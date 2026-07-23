import Foundation
import UserNotifications

@MainActor
final class AppStore: ObservableObject {
    @Published var selectedDestination: AppDestination = .today
    @Published var selectedOpportunityID: UUID?
    @Published var opportunities: [Opportunity] = []
    @Published var comments: [CommentCluster] = []
    @Published var notifications: [NotificationRecord] = []
    @Published var sourceHealth: [SourceHealth] = []
    @Published var sourceHealthHistory: [SourceHealthRecord] = []
    @Published var watchlist: [WatchlistEntry] = []
    @Published var radarSource: SourceGroup?
    @Published var radarVerification: VerificationState?
    @Published var searchText = ""
    @Published var setupComplete = false
    @Published var refreshMinutes = 15
    @Published var notificationsEnabled = false
    @Published var notificationPermission: NotificationPermissionState = .notDetermined
    @Published var quietHoursEnabled = true
    @Published var quietStartHour = 22
    @Published var quietEndHour = 8
    @Published var digestHour = 18
    @Published var statusMessage = "Ready"
    @Published var isRefreshing = false
    @Published private(set) var dataTruth: DataTruth = .missing

    private var sourceItems: [SourceItem] = []
    private var dispositions: [UUID: OpportunityDisposition] = [:]
    private var settings = AppSettings.defaults
    private var lastSuccessfulSyncAt: Date?
    private let pipeline = ResearchPipeline()
    private let persistence: any ResearchPersistence
    private let sync: any ResearchSyncing
    private let notificationDelivery: any NotificationDelivering

    init(
        persistence: any ResearchPersistence = JSONResearchPersistence.production(),
        sync: any ResearchSyncing = NoopResearchSync(),
        notificationDelivery: any NotificationDelivering = UnavailableNotificationDelivery(),
        loadDemoDataWhenEmpty: Bool = true
    ) {
        self.persistence = persistence
        self.sync = sync
        self.notificationDelivery = notificationDelivery
        do {
            if let stored = try persistence.load() {
                applyStoredState(stored)
                statusMessage = "Offline cache loaded"
            } else if loadDemoDataWhenEmpty {
                applyDemoState()
                statusMessage = "Demo data loaded"
                do {
                    try persist()
                } catch {
                    statusMessage = "Demo data loaded - changes cannot be saved"
                }
            } else {
                applyStoredState(.empty)
                statusMessage = "No cached or live data"
            }
        } catch {
            applyStoredState(.empty)
            statusMessage = "Local data unavailable"
        }
    }

    var selectedOpportunity: Opportunity? {
        opportunities.first { $0.id == selectedOpportunityID }
    }

    var visibleOpportunities: [Opportunity] {
        opportunities.filter { opportunity in
            guard opportunity.disposition != .dismissed, opportunity.disposition != .muted else { return false }
            let sourceMatch = radarSource.map { source in opportunity.items.contains { $0.group == source } } ?? true
            let verificationMatch = radarVerification.map { $0 == opportunity.verification } ?? true
            let searchMatch = searchText.isEmpty
                || opportunity.title.localizedCaseInsensitiveContains(searchText)
                || opportunity.items.contains { $0.summary.localizedCaseInsensitiveContains(searchText) }
            return sourceMatch && verificationMatch && searchMatch
        }
    }

    func refresh() async {
        isRefreshing = true
        statusMessage = "Synchronizing"
        let results = await sync.synchronize()
        let liveItems = results.flatMap { result in
            result.items.map {
                var item = $0
                item.dataTruth = result.dataTruth
                return item
            }
        }

        if !liveItems.isEmpty {
            sourceItems = liveItems
            let output = pipeline.run(items: liveItems)
            opportunities = output.opportunities.map(applyingStoredDisposition)
            comments = output.comments
            await processNotifications(output.notifications)
            lastSuccessfulSyncAt = results.map(\.collectedAt).max()
        }

        let previousHealth = Dictionary(uniqueKeysWithValues: sourceHealth.map { ($0.group, $0) })
        sourceHealth = results.map {
            SourceHealth(
                group: $0.group,
                state: $0.state,
                lastActivity: $0.items.map(\.collectedAt).max() ?? previousHealth[$0.group]?.lastActivity,
                evidence: $0.evidence,
                repairAction: $0.state == .connected ? "Review" : "Configure",
                dataTruth: $0.dataTruth
            )
        }.sorted { sourceOrder($0.group) < sourceOrder($1.group) }
        recordSourceHealth(results)
        dataTruth = liveItems.isEmpty
            ? aggregateTruth(sourceItems.map(\.dataTruth))
            : aggregateTruth(sourceHealth.map(\.dataTruth))
        statusMessage = liveItems.isEmpty ? "No live data received - offline data retained" : "Live sync complete"
        persistReportingFailure()
        isRefreshing = false
    }

    func updateDisposition(_ disposition: OpportunityDisposition, id: UUID) {
        guard let index = opportunities.firstIndex(where: { $0.id == id }) else { return }
        opportunities[index].disposition = disposition
        dispositions[id] = disposition
        statusMessage = disposition == .dismissed ? "Opportunity dismissed" : "Opportunity \(disposition.rawValue)"
        persistReportingFailure()
    }

    func addWatchlist(kind: WatchlistEntry.Kind, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        watchlist.append(WatchlistEntry(id: UUID(), kind: kind, value: trimmed, highPriority: false))
        statusMessage = "Watchlist added"
        persistReportingFailure()
    }

    func removeWatchlist(at offsets: IndexSet) {
        watchlist.remove(atOffsets: offsets)
        statusMessage = "Watchlist removed"
        persistReportingFailure()
    }

    func setWatchlistPriority(id: UUID, highPriority: Bool) {
        guard let index = watchlist.firstIndex(where: { $0.id == id }) else { return }
        watchlist[index].highPriority = highPriority
        statusMessage = "Watchlist updated"
        persistReportingFailure()
    }

    func setRefreshMinutes(_ minutes: Int) {
        refreshMinutes = min(60, max(5, minutes))
        settings.refreshMinutes = refreshMinutes
        persistReportingFailure()
    }

    func completeSetup() {
        setupComplete = true
        settings.setupComplete = true
        statusMessage = "Setup complete"
        persistReportingFailure()
    }

    func requestNotifications() async {
        settings.notificationPermissionRequested = true
        do {
            notificationPermission = try await notificationDelivery.requestPermission()
            notificationsEnabled = notificationPermission == .authorized || notificationPermission == .provisional
            settings.notificationPermission = notificationPermission
            settings.notificationsEnabled = notificationsEnabled
            statusMessage = notificationPermission == .authorized || notificationPermission == .provisional
                ? "Notifications allowed"
                : "Notifications blocked by macOS"
            if notificationsEnabled {
                let eligible = notifications.filter { record in
                    opportunities.first(where: { $0.id == record.opportunityID })?.dataTruth != .fixture
                }
                await processNotifications(eligible)
            }
        } catch {
            notificationPermission = .unavailable
            settings.notificationPermission = .unavailable
            statusMessage = "macOS notification permission is unavailable"
        }
        persistReportingFailure()
    }

    func sendImmediateDemoNotification() async {
        guard let record = notifications.first(where: { $0.delivery == .immediate }) else { return }
        guard notificationsEnabled else {
            statusMessage = "Turn on notifications before sending a native test"
            return
        }
        let request = NativeNotificationRequest(
            identifier: "manual-\(UUID().uuidString)",
            title: "Zoid 99 - Native test",
            body: record.title,
            scheduledAt: .now,
            deepLink: URL(string: "zoid99://opportunity/\(record.opportunityID.uuidString)")!
        )
        do {
            try await notificationDelivery.schedule(request)
            statusMessage = "Native test scheduled - click it to verify the deep link"
        } catch {
            statusMessage = "macOS could not schedule the native test"
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled && (notificationPermission == .authorized || notificationPermission == .provisional)
        settings.notificationsEnabled = notificationsEnabled
        statusMessage = notificationsEnabled
            ? "Notifications enabled"
            : enabled ? "Allow notifications in macOS first" : "Notifications disabled"
        persistReportingFailure()
    }

    func setQuietHoursEnabled(_ enabled: Bool) {
        quietHoursEnabled = enabled
        settings.quietHoursEnabled = enabled
        persistReportingFailure()
    }

    func setQuietStartHour(_ hour: Int) {
        quietStartHour = min(23, max(0, hour))
        settings.quietStartHour = quietStartHour
        persistReportingFailure()
    }

    func setQuietEndHour(_ hour: Int) {
        quietEndHour = min(23, max(0, hour))
        settings.quietEndHour = quietEndHour
        persistReportingFailure()
    }

    func setDigestHour(_ hour: Int) {
        digestHour = min(23, max(0, hour))
        settings.digestHour = digestHour
        persistReportingFailure()
    }

    func openNotificationDeepLink(_ url: URL) {
        guard url.scheme == "zoid99",
              url.host == "opportunity",
              let id = UUID(uuidString: url.lastPathComponent),
              opportunities.contains(where: { $0.id == id })
        else {
            statusMessage = "Notification destination is no longer available"
            return
        }
        selectedOpportunityID = id
        selectedDestination = .today
        if let index = notifications.firstIndex(where: { $0.opportunityID == id }) {
            notifications[index].isRead = true
            notifications[index].deliveredAt = .now
            notifications[index].deliveryState = .delivered
            notifications[index].statusDetail = "Opened in Opportunity Detail."
        }
        statusMessage = "Opened notification opportunity"
        persistReportingFailure()
    }

    private func applyDemoState() {
        let output = pipeline.run(items: ResearchFixtures.allSix, now: ResearchFixtures.now)
        sourceItems = output.normalizedItems
        opportunities = output.opportunities
        comments = output.comments
        notifications = output.notifications
        watchlist = DemoFixtures.watchlist
        settings = .defaults
        setupComplete = settings.setupComplete
        refreshMinutes = settings.refreshMinutes
        applyNotificationSettings()
        sourceHealth = SourceGroup.allCases.map { group in
            let count = output.normalizedItems.filter { $0.group == group }.count
            return SourceHealth(
                group: group,
                state: .setupRequired,
                lastActivity: count > 0 ? ResearchFixtures.now : nil,
                evidence: "\(count) labeled demo \(count == 1 ? "item" : "items") available. Live access is not configured.",
                repairAction: "Configure",
                dataTruth: .fixture
            )
        }
        dataTruth = .fixture
    }

    private func applyStoredState(_ stored: ResearchState) {
        sourceItems = stored.sourceItems.map {
            var item = $0
            if item.dataTruth == .live { item.dataTruth = .cached }
            return item
        }
        dispositions = stored.dispositions
        opportunities = stored.opportunities.map { opportunity in
            var cached = opportunity
            cached.disposition = stored.dispositions[opportunity.id] ?? opportunity.disposition
            cached = cached.replacingItems(cached.items.map(markingLiveAsCached))
            return cached
        }
        comments = stored.comments.map { cluster in
            CommentCluster(
                id: cluster.id,
                question: cluster.question,
                count: cluster.count,
                demand: cluster.demand,
                language: cluster.language,
                sourceItems: cluster.sourceItems.map(markingLiveAsCached)
            )
        }
        notifications = stored.notificationHistory
        sourceHealth = stored.sourceHealth.map {
            var health = $0
            if health.dataTruth == .live { health.dataTruth = .cached }
            return health
        }
        sourceHealthHistory = stored.sourceHealthHistory
        watchlist = stored.watchlist
        settings = stored.settings
        setupComplete = settings.setupComplete
        refreshMinutes = settings.refreshMinutes
        applyNotificationSettings()
        lastSuccessfulSyncAt = stored.lastSuccessfulSyncAt
        dataTruth = aggregateTruth(sourceHealth.map(\.dataTruth))
    }

    private func applyingStoredDisposition(_ opportunity: Opportunity) -> Opportunity {
        var result = opportunity
        result.disposition = dispositions[opportunity.id] ?? .active
        return result
    }

    private func processNotifications(_ candidates: [NotificationRecord]) async {
        let result = await NotificationCoordinator(delivery: notificationDelivery).process(
            candidates: candidates,
            existing: notifications,
            settings: settings
        )
        notifications = result.records
        notificationPermission = result.permission
        settings.notificationPermission = result.permission
    }

    private func applyNotificationSettings() {
        notificationsEnabled = settings.notificationsEnabled
        notificationPermission = settings.notificationPermission
        quietHoursEnabled = settings.quietHoursEnabled
        quietStartHour = settings.quietStartHour
        quietEndHour = settings.quietEndHour
        digestHour = settings.digestHour
    }

    private func recordSourceHealth(_ results: [SourceSyncResult]) {
        sourceHealthHistory.append(contentsOf: results.map {
            SourceHealthRecord(
                id: UUID(),
                group: $0.group,
                state: $0.state,
                dataTruth: $0.dataTruth,
                recordedAt: $0.collectedAt,
                evidence: $0.evidence
            )
        })
        sourceHealthHistory = Array(sourceHealthHistory.suffix(600))
    }

    private func aggregateTruth(_ truths: [DataTruth]) -> DataTruth {
        if truths.contains(.live) { return .live }
        if truths.contains(.cached) { return .cached }
        if truths.contains(.fixture) { return .fixture }
        if truths.contains(.rateLimited) { return .rateLimited }
        if truths.contains(.delayed) { return .delayed }
        if truths.contains(.unavailable) { return .unavailable }
        return .missing
    }

    private func sourceOrder(_ group: SourceGroup) -> Int {
        SourceGroup.allCases.firstIndex(of: group) ?? SourceGroup.allCases.count
    }

    private func markingLiveAsCached(_ item: SourceItem) -> SourceItem {
        var result = item
        if result.dataTruth == .live { result.dataTruth = .cached }
        return result
    }

    private func persistReportingFailure() {
        do {
            try persist()
        } catch {
            statusMessage = "Changes could not be saved"
        }
    }

    private func persist() throws {
        settings.setupComplete = setupComplete
        settings.refreshMinutes = refreshMinutes
        settings.notificationsEnabled = notificationsEnabled
        settings.notificationPermission = notificationPermission
        settings.quietHoursEnabled = quietHoursEnabled
        settings.quietStartHour = quietStartHour
        settings.quietEndHour = quietEndHour
        settings.digestHour = digestHour
        try persistence.save(
            ResearchState(
                sourceItems: sourceItems,
                opportunities: opportunities,
                comments: comments,
                dispositions: dispositions,
                watchlist: watchlist,
                settings: settings,
                notificationHistory: notifications,
                sourceHealth: sourceHealth,
                sourceHealthHistory: sourceHealthHistory,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt
            )
        )
    }
}

enum DemoFixtures {
    static let watchlist = [
        WatchlistEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, kind: .topic, value: "AI agents", highPriority: true),
        WatchlistEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, kind: .country, value: "Egypt", highPriority: true),
        WatchlistEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!, kind: .country, value: "Saudi Arabia", highPriority: false),
        WatchlistEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!, kind: .language, value: "Arabic", highPriority: true)
    ]
}
