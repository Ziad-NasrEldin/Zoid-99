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
    @Published var radarTopic = ""
    @Published var radarCountry: String?
    @Published var radarLanguage: String?
    @Published var radarFreshness: RadarFreshness = .any
    @Published private(set) var radarSort: OpportunitySort
    @Published var searchText = ""
    @Published var searchFocusRequest = 0
    @Published var setupComplete = false
    @Published var refreshMinutes = 15
    @Published var notificationsEnabled = false
    @Published var notificationPermission: NotificationPermissionState = .notDetermined
    @Published var quietHoursEnabled = true
    @Published var quietStartHour = 22
    @Published var quietEndHour = 8
    @Published var digestHour = 18
    @Published var discordEnabled = false
    @Published var discordHighPriorityEnabled = true
    @Published private(set) var discordConfigured = false
    @Published private(set) var discordStatus: DiscordDeliveryStatus = .notConfigured
    @Published var statusMessage = "Ready"
    @Published var isRefreshing = false
    @Published var isResearchingTopic = false
    @Published var watchlistError: String?
    @Published private(set) var watchlistSyncState = "Saved locally"
    @Published private(set) var dataTruth: DataTruth = .missing

    private var sourceItems: [SourceItem] = []
    private var dispositions: [UUID: OpportunityDisposition] = [:]
    private var pendingDispositionMutations: [OpportunityDispositionMutation] = []
    private var isSyncingDispositions = false
    private var settings = AppSettings.defaults
    private var lastSuccessfulSyncAt: Date?
    private let pipeline = ResearchPipeline()
    private let persistence: any ResearchPersistence
    private let sync: any ResearchSyncing
    private let dispositionSync: any OpportunityDispositionSyncing
    private let watchlistSync: any WatchlistSyncing
    private let now: @Sendable () -> Date
    private let connectionService: any ProviderConnectionServicing
    private let notificationDelivery: any NotificationDelivering
    private let discordService: any DiscordNotificationServicing
    private let sortDefaults: UserDefaults
    private var scheduledRefreshTask: Task<Void, Never>?
    private var isSyncingWatchlist = false
    private var watchlistNeedsSync = false

    init(
        persistence: any ResearchPersistence = JSONResearchPersistence.production(),
        sync: any ResearchSyncing = ProductionResearchSync(),
        dispositionSync: any OpportunityDispositionSyncing = OpportunityDispositionSyncFactory.production(),
        watchlistSync: any WatchlistSyncing = WatchlistSyncFactory.production(),
        now: @escaping @Sendable () -> Date = { .now },
        connectionService: any ProviderConnectionServicing = LocalProviderConnectionService(),
        notificationDelivery: any NotificationDelivering = UnavailableNotificationDelivery(),
        discordService: any DiscordNotificationServicing = DiscordNotificationService(),
        sortDefaults: UserDefaults = .standard,
        loadDemoDataWhenEmpty: Bool = true
    ) {
        self.persistence = persistence
        self.sync = sync
        self.dispositionSync = dispositionSync
        self.watchlistSync = watchlistSync
        self.now = now
        self.connectionService = connectionService
        self.notificationDelivery = notificationDelivery
        self.discordService = discordService
        self.sortDefaults = sortDefaults
        self.radarSort = OpportunitySort(
            rawValue: sortDefaults.string(forKey: OpportunitySort.storageKey) ?? ""
        ) ?? .totalScore
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

    func startScheduledRefresh() {
        guard scheduledRefreshTask == nil else { return }
        scheduledRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                let interval = UInt64(self.refreshMinutes) * 60
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    var selectedOpportunity: Opportunity? {
        opportunities.first { $0.id == selectedOpportunityID }
    }

    var lastRefreshAt: Date? {
        lastSuccessfulSyncAt
    }

    var connectedSourceCount: Int {
        sourceHealth.filter { $0.state == .connected }.count
    }

    var activeOpportunities: [Opportunity] {
        opportunities.filter {
            $0.disposition != .dismissed && $0.disposition != .muted
        }
    }

    var visibleOpportunities: [Opportunity] {
        activeOpportunities
    }

    var radarOpportunities: [Opportunity] {
        radarSort.sorted(activeOpportunities.filter { opportunity in
            guard opportunity.disposition != .dismissed, opportunity.disposition != .muted else { return false }
            let sourceMatch = radarSource.map { source in opportunity.items.contains { $0.group == source } } ?? true
            let verificationMatch = radarVerification.map { $0 == opportunity.verification } ?? true
            let topicMatch = radarTopic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || opportunity.matchesResearchQuery(radarTopic)
            let countryMatch = radarCountry.map { country in
                opportunity.items.contains { $0.country.caseInsensitiveCompare(country) == .orderedSame }
            } ?? true
            let languageMatch = radarLanguage.map { language in
                opportunity.items.contains { $0.language.caseInsensitiveCompare(language) == .orderedSame }
            } ?? true
            let latestPublishedAt = opportunity.items.map(\.publishedAt).max() ?? opportunity.earliestPublishedAt
            let freshnessMatch = radarFreshness.includes(latestPublishedAt, now: now())
            let searchMatch = searchText.isEmpty
                || opportunity.title.localizedCaseInsensitiveContains(searchText)
                || opportunity.items.contains {
                    $0.title.localizedCaseInsensitiveContains(searchText)
                        || $0.summary.localizedCaseInsensitiveContains(searchText)
                        || $0.author.localizedCaseInsensitiveContains(searchText)
                }
            return sourceMatch && verificationMatch && topicMatch && countryMatch
                && languageMatch && freshnessMatch && searchMatch
        })
    }

    var radarCountries: [String] {
        metadataValues(\.country)
    }

    var radarLanguages: [String] {
        metadataValues(\.language)
    }

    func clearRadarFilters() {
        searchText = ""
        radarSource = nil
        radarVerification = nil
        radarTopic = ""
        radarCountry = nil
        radarLanguage = nil
        radarFreshness = .any
        statusMessage = "Radar filters cleared"
    }

    func setRadarSort(_ sort: OpportunitySort) {
        radarSort = sort
        sortDefaults.set(sort.rawValue, forKey: OpportunitySort.storageKey)
    }

    func resetRadarSort() {
        setRadarSort(.totalScore)
    }

    func requestSearchFocus() {
        searchFocusRequest += 1
    }

    func topicResearch(query: String) -> TopicResearchResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let healthByGroup = Dictionary(uniqueKeysWithValues: sourceHealth.map { ($0.group, $0) })
        guard !trimmed.isEmpty else {
            return TopicResearchResult(
                query: "",
                state: .prompt,
                evidence: [],
                opportunities: [],
                sourceCoverage: topicCoverage(evidence: [], healthByGroup: healthByGroup)
            )
        }
        guard !sourceItems.isEmpty else {
            return TopicResearchResult(
                query: trimmed,
                state: .missingData,
                evidence: [],
                opportunities: [],
                sourceCoverage: topicCoverage(evidence: [], healthByGroup: healthByGroup)
            )
        }
        let directEvidence = sourceItems.filter { $0.matchesResearchQuery(trimmed) }
        let matchingOpportunities = activeOpportunities.filter { opportunity in
            opportunity.matchesResearchQuery(trimmed)
                || opportunity.items.contains { item in directEvidence.contains { $0.id == item.id } }
        }
        var evidenceByID: [UUID: SourceItem] = [:]
        let evidenceCandidates = directEvidence.isEmpty
            ? matchingOpportunities.flatMap(\.items)
            : directEvidence
        for item in evidenceCandidates {
            evidenceByID[item.id] = item
        }
        let evidence = evidenceByID.values.sorted {
            if $0.publishedAt == $1.publishedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.publishedAt > $1.publishedAt
        }
        return TopicResearchResult(
            query: trimmed,
            state: evidence.isEmpty ? .noMatches : .results,
            evidence: evidence,
            opportunities: matchingOpportunities,
            sourceCoverage: topicCoverage(evidence: evidence, healthByGroup: healthByGroup)
        )
    }

    func refresh() async {
        isRefreshing = true
        statusMessage = "Synchronizing"
        await synchronizeWatchlist()
        let results = await sync.synchronize(watchlist: watchlist)
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
            await processDiscordNotifications()
            lastSuccessfulSyncAt = results.map(\.collectedAt).max()
        }

        let previousHealth = Dictionary(uniqueKeysWithValues: sourceHealth.map { ($0.group, $0) })
        let resultByGroup = Dictionary(uniqueKeysWithValues: results.map { ($0.group, $0) })
        sourceHealth = SourceGroup.allCases.compactMap { group -> SourceHealth? in
            guard let result = resultByGroup[group] else { return previousHealth[group] }
            let previous = previousHealth[group]
            let previousEvidenceSuffix = previous.flatMap {
                result.items.isEmpty ? retainedEvidence(from: $0.evidence, current: result.evidence) : nil
            } ?? ""
            return SourceHealth(
                group: group,
                state: result.state,
                lastActivity: result.items.map(\.collectedAt).max() ?? previous?.lastActivity,
                evidence: result.evidence + previousEvidenceSuffix,
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
        await synchronizePendingDispositions()
        isRefreshing = false
    }

    func researchTopicAcrossConnectedSources(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResearchingTopic else { return }
        isResearchingTopic = true
        statusMessage = "Researching topic across connected sources"
        await synchronizeWatchlist()
        let results = await sync.researchTopic(trimmed, watchlist: watchlist)
        mergeResearchResults(results)
        statusMessage = results.flatMap(\.items).isEmpty
            ? "Topic research complete - no new evidence"
            : "Topic research complete"
        persistReportingFailure()
        isResearchingTopic = false
    }

    func updateDisposition(_ disposition: OpportunityDisposition, id: UUID) {
        guard let index = opportunities.firstIndex(where: { $0.id == id }) else { return }
        let mutation = OpportunityDispositionMutation(
            id: UUID(),
            opportunityID: id,
            disposition: disposition,
            changedAt: now()
        )
        opportunities[index].disposition = disposition
        opportunities[index].dispositionUpdatedAt = mutation.changedAt
        opportunities[index].dispositionMutationID = mutation.id
        dispositions[id] = disposition
        pendingDispositionMutations.removeAll { $0.opportunityID == id }
        pendingDispositionMutations.append(mutation)
        statusMessage = "Opportunity \(disposition.writtenState) - syncing"
        persistReportingFailure()
        Task { await synchronizePendingDispositions() }
    }

    func synchronizePendingDispositions() async {
        guard !isSyncingDispositions else { return }
        isSyncingDispositions = true
        defer { isSyncingDispositions = false }
        var latestSynchronizedMutation: OpportunityDispositionMutation?
        var shouldPullCanonicalState = true
        repeat {
            let pending = pendingDispositionMutations
            let result = await dispositionSync.reconcile(pending)
            pendingDispositionMutations.removeAll { result.acknowledgedMutationIDs.contains($0.id) }
            for state in result.states {
                let newerPending = pendingDispositionMutations.contains {
                    $0.opportunityID == state.opportunityID
                        && ($0.changedAt > state.changedAt
                            || ($0.changedAt == state.changedAt && $0.id.uuidString > state.mutationID.uuidString))
                }
                guard !newerPending,
                      let index = opportunities.firstIndex(where: { $0.id == state.opportunityID }) else { continue }
                opportunities[index].disposition = state.disposition
                opportunities[index].dispositionUpdatedAt = state.changedAt
                opportunities[index].dispositionMutationID = state.mutationID
                dispositions[state.opportunityID] = state.disposition
            }
            latestSynchronizedMutation = pending
                .filter { result.acknowledgedMutationIDs.contains($0.id) }
                .max(by: mutationOrder) ?? latestSynchronizedMutation
            persistReportingFailure()

            if result.errorMessage != nil {
                if !pendingDispositionMutations.isEmpty {
                    statusMessage = "\(latestPendingWrittenState) - queued for sync"
                }
                break
            }
            if !pending.isEmpty && result.acknowledgedMutationIDs.isEmpty {
                statusMessage = "\(latestPendingWrittenState) - queued for sync"
                break
            }
            shouldPullCanonicalState = false
        } while !pendingDispositionMutations.isEmpty || shouldPullCanonicalState

        if pendingDispositionMutations.isEmpty, let latestSynchronizedMutation {
            statusMessage = "Opportunity \(latestSynchronizedMutation.disposition.writtenState) - synced"
        }
        persistReportingFailure()
    }

    @discardableResult
    func addWatchlist(kind: WatchlistEntry.Kind, value: String) -> Bool {
        do {
            let validated = try WatchlistValidator.validatedValue(
                kind: kind,
                value: value,
                existing: watchlist
            )
            watchlist.append(
                WatchlistEntry(id: UUID(), kind: kind, value: validated, highPriority: false)
            )
            watchlistError = nil
            finishWatchlistChange(message: "Watchlist added")
            return true
        } catch {
            watchlistError = error.localizedDescription
            statusMessage = "Watchlist not changed"
            return false
        }
    }

    func removeWatchlist(at offsets: IndexSet) {
        watchlist.remove(atOffsets: offsets)
        watchlistNeedsSync = true
        statusMessage = "Watchlist removed - saved locally"
        persistReportingFailure()
        Task { await synchronizeWatchlist() }
    }

    func removeWatchlist(id: UUID) {
        guard let index = watchlist.firstIndex(where: { $0.id == id }) else { return }
        watchlist.remove(at: index)
        watchlistNeedsSync = true
        statusMessage = "Watchlist removed - saved locally"
        persistReportingFailure()
        Task { await synchronizeWatchlist() }
    }

    @discardableResult
    func updateWatchlist(
        id: UUID,
        kind: WatchlistEntry.Kind,
        value: String,
        highPriority: Bool
    ) -> Bool {
        guard let index = watchlist.firstIndex(where: { $0.id == id }) else { return false }
        do {
            let validated = try WatchlistValidator.validatedValue(
                kind: kind,
                value: value,
                existing: watchlist,
                excludingID: id
            )
            watchlist[index] = WatchlistEntry(
                id: id,
                kind: kind,
                value: validated,
                highPriority: highPriority
            )
            watchlistError = nil
            finishWatchlistChange(message: "Watchlist updated")
            return true
        } catch {
            watchlistError = error.localizedDescription
            statusMessage = "Watchlist not changed"
            return false
        }
    }

    func setWatchlistPriority(id: UUID, highPriority: Bool) {
        guard let index = watchlist.firstIndex(where: { $0.id == id }) else { return }
        watchlist[index].highPriority = highPriority
        watchlistNeedsSync = true
        statusMessage = "Watchlist priority updated - saved locally"
        persistReportingFailure()
        Task { await synchronizeWatchlist() }
    }

    func synchronizeWatchlist() async {
        guard !isSyncingWatchlist else { return }
        isSyncingWatchlist = true
        defer { isSyncingWatchlist = false }
        if !watchlistNeedsSync {
            let localSnapshot = watchlist
            watchlistSyncState = "Checking backend watchlist"
            let result = await watchlistSync.fetchCanonical()
            guard result.errorMessage == nil else {
                watchlistSyncState = watchlistNeedsSync
                    ? "Saved locally - backend sync pending"
                    : "Saved locally - backend unavailable"
                return
            }
            if !watchlistNeedsSync, watchlist == localSnapshot {
                watchlist = result.synchronizedEntries
                watchlistSyncState = "Saved locally and synchronized"
                persistReportingFailure()
                return
            }
        }
        repeat {
            let snapshot = watchlist
            watchlistSyncState = "Saved locally - synchronizing"
            let result = await watchlistSync.reconcile(snapshot)
            if result.errorMessage != nil {
                watchlistSyncState = "Saved locally - backend sync pending"
                return
            }
            if watchlist == snapshot {
                watchlist = result.synchronizedEntries
                watchlistNeedsSync = false
                watchlistSyncState = "Saved locally and synchronized"
                persistReportingFailure()
                return
            }
        } while true
    }

    private func finishWatchlistChange(message: String) {
        watchlistNeedsSync = true
        statusMessage = "\(message) - saved locally"
        watchlistSyncState = "Saved locally - backend sync pending"
        persistReportingFailure()
        Task { await synchronizeWatchlist() }
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
        startScheduledRefresh()
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

    func refreshDiscordConfigurationStatus() async {
        discordConfigured = await discordService.isConfigured()
        discordStatus = discordConfigured
            ? (discordEnabled ? .ready : .disabled)
            : .notConfigured
    }

    func configureDiscordWebhook(_ value: String) async {
        discordStatus = .validating
        do {
            try await discordService.configure(value)
            discordConfigured = true
            discordStatus = discordEnabled ? .ready : .disabled
            statusMessage = "Discord webhook validated and saved in macOS Keychain"
        } catch {
            discordConfigured = await discordService.isConfigured()
            discordStatus = .failed(
                (error as? LocalizedError)?.errorDescription
                    ?? "Discord validation failed safely."
            )
            statusMessage = "Discord webhook was not saved"
        }
    }

    func removeDiscordWebhook() async {
        do {
            try await discordService.remove()
            discordConfigured = false
            discordEnabled = false
            settings.discordEnabled = false
            discordStatus = .notConfigured
            statusMessage = "Discord webhook removed from macOS Keychain"
            persistReportingFailure()
        } catch {
            discordStatus = .failed("The Discord webhook could not be removed from macOS Keychain.")
        }
    }

    func setDiscordEnabled(_ enabled: Bool) {
        discordEnabled = enabled && discordConfigured
        settings.discordEnabled = discordEnabled
        discordStatus = discordConfigured
            ? (discordEnabled ? .ready : .disabled)
            : .notConfigured
        statusMessage = enabled && !discordConfigured
            ? "Save and validate a Discord webhook first"
            : discordEnabled ? "Discord delivery enabled" : "Discord delivery disabled"
        persistReportingFailure()
    }

    func setDiscordHighPriorityEnabled(_ enabled: Bool) {
        discordHighPriorityEnabled = enabled
        settings.discordHighPriorityEnabled = enabled
        persistReportingFailure()
    }

    func sendDiscordTest() async {
        guard discordConfigured else {
            discordStatus = .notConfigured
            return
        }
        do {
            try await discordService.send(.test)
            discordStatus = .delivered(now())
            statusMessage = "Discord test delivered"
        } catch {
            discordStatus = .failed(
                (error as? LocalizedError)?.errorDescription
                    ?? "Discord test failed safely."
            )
            statusMessage = "Discord test was not delivered"
        }
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
        pendingDispositionMutations = stored.pendingDispositionMutations ?? []
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
        watchlistNeedsSync = stored.watchlistNeedsSync ?? !stored.watchlist.isEmpty
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
        discordEnabled = settings.discordEnabled
        discordHighPriorityEnabled = settings.discordHighPriorityEnabled
    }

    private func processDiscordNotifications() async {
        let result = await DiscordNotificationCoordinator(service: discordService).process(
            opportunities: discordHighPriorityEnabled ? opportunities : [],
            enabled: discordEnabled,
            deliveredOpportunityIDs: settings.discordDeliveredOpportunityIDs,
            now: now()
        )
        settings.discordDeliveredOpportunityIDs =
            Set(result.deliveredOpportunityIDs.sorted { $0.uuidString < $1.uuidString }.suffix(1_000))
        discordStatus = result.status
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

    private func metadataValues(_ keyPath: KeyPath<SourceItem, String>) -> [String] {
        Array(Set(sourceItems.map { $0[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func mergeResearchResults(_ results: [SourceSyncResult]) {
        let collectedItems = results.flatMap { result in
            result.items.map {
                var item = $0
                item.dataTruth = result.dataTruth
                return item
            }
        }
        if !collectedItems.isEmpty {
            var itemByKey: [String: SourceItem] = [:]
            for item in sourceItems {
                itemByKey["\(item.group.rawValue):\(item.externalID)"] = item
            }
            for item in collectedItems {
                itemByKey["\(item.group.rawValue):\(item.externalID)"] = item
            }
            sourceItems = itemByKey.values.sorted {
                if $0.publishedAt == $1.publishedAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.publishedAt > $1.publishedAt
            }
            let output = pipeline.run(items: sourceItems)
            opportunities = output.opportunities.map(applyingStoredDisposition)
            comments = output.comments
            lastSuccessfulSyncAt = results.map(\.collectedAt).max()
        }
        let healthByGroup = Dictionary(uniqueKeysWithValues: results.map { ($0.group, $0) })
        sourceHealth = SourceGroup.allCases.map { group in
            guard let result = healthByGroup[group] else {
                return sourceHealth.first(where: { $0.group == group }) ?? SourceHealth(
                    group: group,
                    state: .setupRequired,
                    lastActivity: nil,
                    evidence: "This source is not configured.",
                    repairAction: "Configure",
                    dataTruth: .missing
                )
            }
            return SourceHealth(
                group: group,
                state: result.state,
                lastActivity: result.collectedAt,
                evidence: result.evidence,
                repairAction: repairAction(for: result.state),
                dataTruth: result.dataTruth
            )
        }
        updateProviderConnectionsFromSourceHealth()
        recordSourceHealth(results)
        dataTruth = aggregateTruth(sourceHealth.map(\.dataTruth))
    }

    private func topicCoverage(
        evidence: [SourceItem],
        healthByGroup: [SourceGroup: SourceHealth]
    ) -> [TopicSourceCoverage] {
        SourceGroup.allCases.map { group in
            let health = healthByGroup[group]
            return TopicSourceCoverage(
                group: group,
                matchingEvidenceCount: evidence.filter { $0.group == group }.count,
                state: health?.state ?? .setupRequired,
                dataTruth: health?.dataTruth ?? .missing
            )
        }
    }

    private func retainedEvidence(from previous: String, current: String) -> String? {
        let marker = " Last known evidence: "
        let evidence = previous.range(of: marker, options: .backwards)
            .map { String(previous[$0.upperBound...]) } ?? previous
        guard !evidence.isEmpty, evidence != current else { return nil }
        return marker + evidence
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
        settings.notificationsEnabled = notificationsEnabled
        settings.notificationPermission = notificationPermission
        settings.quietHoursEnabled = quietHoursEnabled
        settings.quietStartHour = quietStartHour
        settings.quietEndHour = quietEndHour
        settings.digestHour = digestHour
        settings.discordEnabled = discordEnabled
        settings.discordHighPriorityEnabled = discordHighPriorityEnabled
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
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                pendingDispositionMutations: pendingDispositionMutations,
                watchlistNeedsSync: watchlistNeedsSync
            )
        )
    }

    private var latestPendingWrittenState: String {
        guard let latest = pendingDispositionMutations.max(by: mutationOrder) else { return "Disposition" }
        return "Opportunity \(latest.disposition.writtenState)"
    }

    private func mutationOrder(
        _ left: OpportunityDispositionMutation,
        _ right: OpportunityDispositionMutation
    ) -> Bool {
        if left.changedAt != right.changedAt { return left.changedAt < right.changedAt }
        return left.id.uuidString < right.id.uuidString
    }
}

private extension SourceItem {
    func matchesResearchQuery(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || summary.localizedCaseInsensitiveContains(query)
            || author.localizedCaseInsensitiveContains(query)
            || topicKey.localizedCaseInsensitiveContains(query)
    }
}

private extension Opportunity {
    func matchesResearchQuery(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || brief.localizedCaseInsensitiveContains(query)
            || topicKey.localizedCaseInsensitiveContains(query)
            || items.contains { $0.matchesResearchQuery(query) }
    }
}

private extension OpportunityDisposition {
    var writtenState: String {
        switch self {
        case .active: "active"
        case .saved: "saved"
        case .watched: "watched"
        case .dismissed: "dismissed"
        case .muted: "muted"
        }
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
