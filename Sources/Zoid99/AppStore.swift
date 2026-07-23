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

    init(
        persistence: any ResearchPersistence = JSONResearchPersistence.production(),
        sync: any ResearchSyncing = NoopResearchSync(),
        loadDemoDataWhenEmpty: Bool = true
    ) {
        self.persistence = persistence
        self.sync = sync
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
            appendNewNotifications(output.notifications)
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
        persistReportingFailure()
        do {
            let allowed = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            statusMessage = allowed ? "Notifications allowed" : "Notifications not allowed"
        } catch {
            statusMessage = "Notification permission error"
        }
    }

    func sendImmediateDemoNotification() async {
        guard let record = notifications.first(where: { $0.delivery == .immediate }) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Zoid 99 - High-priority opportunity"
        content.body = record.title
        content.sound = .default
        let request = UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            statusMessage = "Demo alert delivered"
        } catch {
            statusMessage = "Notification delivery error"
        }
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
        lastSuccessfulSyncAt = stored.lastSuccessfulSyncAt
        dataTruth = aggregateTruth(sourceHealth.map(\.dataTruth))
    }

    private func applyingStoredDisposition(_ opportunity: Opportunity) -> Opportunity {
        var result = opportunity
        result.disposition = dispositions[opportunity.id] ?? .active
        return result
    }

    private func appendNewNotifications(_ candidates: [NotificationRecord]) {
        let existingOpportunityIDs = Set(notifications.map(\.opportunityID))
        notifications.append(contentsOf: candidates.filter { !existingOpportunityIDs.contains($0.opportunityID) })
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
