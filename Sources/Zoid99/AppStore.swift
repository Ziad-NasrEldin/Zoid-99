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
    @Published var providerConnections: [ProviderConnection] = []
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
    private let connectionService: any ProviderConnectionServicing

    init(
        persistence: any ResearchPersistence = JSONResearchPersistence.production(),
        sync: any ResearchSyncing = NoopResearchSync(),
        connectionService: any ProviderConnectionServicing = LocalProviderConnectionService(),
        loadDemoDataWhenEmpty: Bool = true
    ) {
        self.persistence = persistence
        self.sync = sync
        self.connectionService = connectionService
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
        let resultByGroup = Dictionary(uniqueKeysWithValues: results.map { ($0.group, $0) })
        sourceHealth = SourceGroup.allCases.compactMap { group in
            guard let result = resultByGroup[group] else { return previousHealth[group] }
            let previous = previousHealth[group]
            let retainedEvidence = previous.flatMap {
                result.items.isEmpty && !$0.evidence.isEmpty ? " Last known evidence: \($0.evidence)" : nil
            } ?? ""
            return SourceHealth(
                group: group,
                state: result.state,
                lastActivity: result.items.map(\.collectedAt).max() ?? previous?.lastActivity,
                evidence: result.evidence + retainedEvidence,
                repairAction: repairAction(for: result.state),
                dataTruth: result.dataTruth
            )
        }
        updateProviderConnectionsFromSourceHealth()
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

    func validateConnection(_ provider: ExternalProvider) async {
        setProviderState(provider, state: .validating, evidence: "Checking provider access without displaying credentials.")
        let result = await connectionService.validate(provider)
        apply(result, to: provider)
    }

    func connect(_ provider: ExternalProvider, credential: String?) async {
        setProviderState(provider, state: .validating, evidence: "Saving authorization and checking its boundary.")
        let result = await connectionService.connect(provider, credential: credential)
        apply(result, to: provider)
    }

    func disconnect(_ provider: ExternalProvider) async {
        setProviderState(provider, state: .validating, evidence: "Removing local authorization. Collected evidence will be retained.")
        let result = await connectionService.disconnect(provider)
        apply(result, to: provider)
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
        providerConnections = defaultProviderConnections()
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
        providerConnections = defaultProviderConnections()
        updateProviderConnectionsFromSourceHealth()
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

    private func defaultProviderConnections() -> [ProviderConnection] {
        ProviderDefinition.catalog.map {
            ProviderConnection(
                provider: $0.provider,
                state: .setupRequired,
                lastActivity: nil,
                evidence: $0.credentialBoundary == .none
                    ? "Public endpoint validation has not run."
                    : "Authorization has not been validated.",
                repairAction: $0.credentialBoundary == .serverSecret ? "Server setup" : "Configure",
                retryAt: nil
            )
        }
    }

    private func updateProviderConnectionsFromSourceHealth() {
        if providerConnections.isEmpty { providerConnections = defaultProviderConnections() }
        for health in sourceHealth {
            guard let provider = ExternalProvider.allCases.first(where: { $0.sourceGroup == health.group }),
                  let index = providerConnections.firstIndex(where: { $0.provider == provider }) else { continue }
            providerConnections[index].state = providerState(for: health)
            providerConnections[index].lastActivity = health.lastActivity
            providerConnections[index].evidence = health.evidence
            providerConnections[index].repairAction = health.repairAction
        }
    }

    private func providerState(for health: SourceHealth) -> ProviderConnectionState {
        if health.dataTruth == .cached { return .cached }
        switch health.state {
        case .connected: return .connected
        case .setupRequired: return .setupRequired
        case .disconnected: return .disconnected
        case .unavailable: return .unavailable
        case .rateLimited: return .rateLimited
        case .delayed: return .delayed
        case .cached: return .cached
        case .unsupported: return .unsupported
        }
    }

    private func apply(_ result: ProviderValidationResult, to provider: ExternalProvider) {
        guard let index = providerConnections.firstIndex(where: { $0.provider == provider }) else { return }
        let previous = providerConnections[index]
        providerConnections[index].state = result.state
        providerConnections[index].lastActivity = result.state == .connected ? result.checkedAt : previous.lastActivity
        providerConnections[index].evidence = result.evidence
        providerConnections[index].repairAction = repairAction(for: result.state)
        providerConnections[index].retryAt = result.retryAt
        statusMessage = "\(provider.rawValue): \(result.state.rawValue)"
        if let group = provider.sourceGroup,
           let healthIndex = sourceHealth.firstIndex(where: { $0.group == group }) {
            sourceHealth[healthIndex].state = connectionState(for: result.state)
            sourceHealth[healthIndex].lastActivity = providerConnections[index].lastActivity
            sourceHealth[healthIndex].evidence = result.evidence
            sourceHealth[healthIndex].repairAction = providerConnections[index].repairAction
        }
        persistReportingFailure()
    }

    private func setProviderState(_ provider: ExternalProvider, state: ProviderConnectionState, evidence: String) {
        guard let index = providerConnections.firstIndex(where: { $0.provider == provider }) else { return }
        providerConnections[index].state = state
        providerConnections[index].evidence = evidence
    }

    private func repairAction(for state: ProviderConnectionState) -> String {
        switch state {
        case .connected: "Review"
        case .setupRequired, .disconnected: "Configure"
        case .rateLimited: "Retry later"
        case .cached, .delayed, .unavailable: "Validate again"
        case .unsupported: "Review support"
        case .validating: "Validating"
        }
    }

    private func repairAction(for state: ConnectionState) -> String {
        switch state {
        case .connected: "Review"
        case .setupRequired, .disconnected: "Configure"
        case .rateLimited: "Retry later"
        case .cached, .delayed, .unavailable: "Validate again"
        case .unsupported: "Review support"
        }
    }

    private func connectionState(for state: ProviderConnectionState) -> ConnectionState {
        switch state {
        case .connected: .connected
        case .setupRequired, .validating: .setupRequired
        case .disconnected: .disconnected
        case .unavailable: .unavailable
        case .delayed: .delayed
        case .rateLimited: .rateLimited
        case .cached: .cached
        case .unsupported: .unsupported
        }
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
