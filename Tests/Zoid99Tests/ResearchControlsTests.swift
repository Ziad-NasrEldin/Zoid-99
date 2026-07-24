import XCTest
@testable import Zoid99

final class ResearchControlsTests: XCTestCase {
    @MainActor
    func testRadarSupportsEveryRequiredFilter() {
        let persistence = ControlsPersistence(state: fixtureState())
        let store = AppStore(
            persistence: persistence,
            watchlistSync: ControlsWatchlistSync(),
            now: { ResearchFixtures.now },
            loadDemoDataWhenEmpty: false
        )

        store.searchText = "rising in Egypt"
        store.radarSource = .googleTrends
        store.radarTopic = "multimodal-launch"
        store.radarCountry = "EG"
        store.radarLanguage = "en"
        store.radarFreshness = .lastDay
        store.radarVerification = .confirmed

        XCTAssertEqual(store.radarOpportunities.map(\.topicKey), ["multimodal-launch"])
        XCTAssertEqual(
            store.radarOpportunities.first?.originalSource?.url.absoluteString,
            "https://openai.com/news/model"
        )
    }

    @MainActor
    func testTopicResearchRetainsOriginalEvidenceAndDistinguishesTruthfulEmptyStates() {
        let store = AppStore(
            persistence: ControlsPersistence(state: fixtureState()),
            watchlistSync: ControlsWatchlistSync(),
            now: { ResearchFixtures.now },
            loadDemoDataWhenEmpty: false
        )

        let results = store.topicResearch(query: "AI Engineer")
        XCTAssertEqual(results.state, .results)
        XCTAssertEqual(results.evidence.map(\.group), [.x])
        XCTAssertEqual(
            results.evidence.first?.url.absoluteString,
            "https://x.com/example/status/fixture"
        )
        XCTAssertEqual(store.topicResearch(query: "no-such-evidence").state, .noMatches)

        let emptyStore = AppStore(
            persistence: ControlsPersistence(state: .empty),
            watchlistSync: ControlsWatchlistSync(),
            loadDemoDataWhenEmpty: false
        )
        XCTAssertEqual(emptyStore.topicResearch(query: "AI").state, .missingData)
    }

    func testMixedArabicEnglishDirectionKeepsLatinAndArabicEvidenceDistinct() {
        XCTAssertEqual(
            ResearchTextDirection.resolve(text: "OpenAI releases GPT"),
            .leftToRight
        )
        XCTAssertEqual(
            ResearchTextDirection.resolve(text: "OpenAI متاح في مصر؟"),
            .rightToLeft
        )
        XCTAssertEqual(
            ResearchTextDirection.resolve(languageCode: "ar-EG", text: "OpenAI"),
            .rightToLeft
        )
    }

    @MainActor
    func testWatchlistsValidatePersistEditRemoveAndSynchronizeAllKinds() async throws {
        let persistence = ControlsPersistence()
        let sync = ControlsWatchlistSync()
        let researchSync = ControlsResearchSync()
        let store = AppStore(
            persistence: persistence,
            sync: researchSync,
            watchlistSync: sync,
            loadDemoDataWhenEmpty: false
        )

        for kind in WatchlistEntry.Kind.allCases {
            let value = kind == .officialSource ? "https://example.com/feed" : "\(kind.rawValue) value"
            XCTAssertTrue(store.addWatchlist(kind: kind, value: value))
        }
        let company = try XCTUnwrap(store.watchlist.first { $0.kind == .company })
        XCTAssertTrue(
            store.updateWatchlist(
                id: company.id,
                kind: .company,
                value: "Anthropic",
                highPriority: true
            )
        )
        XCTAssertFalse(store.addWatchlist(kind: .company, value: "anthropic"))
        XCTAssertEqual(store.watchlistError, WatchlistValidationError.duplicate.localizedDescription)
        XCTAssertEqual(persistence.state?.watchlist.count, WatchlistEntry.Kind.allCases.count)

        store.removeWatchlist(id: company.id)
        await store.synchronizeWatchlist()
        XCTAssertFalse(store.watchlist.contains { $0.id == company.id })
        XCTAssertFalse(sync.snapshots.isEmpty)

        let fetchedCount = sync.fetchCount
        await store.refresh()
        XCTAssertGreaterThan(sync.fetchCount, fetchedCount)
        XCTAssertEqual(researchSync.watchlists.last, store.watchlist)
    }

    @MainActor
    func testCanonicalBackendWatchlistIsPulledBeforeCollectionAndPendingLocalChangesWin() async throws {
        let backendEntry = WatchlistEntry(
            id: UUID(),
            kind: .topic,
            value: "Backend canonical topic",
            highPriority: true
        )
        let cleanState = ResearchState.empty
        let cleanPersistence = ControlsPersistence(state: cleanState)
        let canonicalSync = ControlsWatchlistSync(canonicalEntries: [backendEntry])
        let cleanResearchSync = ControlsResearchSync()
        let cleanStore = AppStore(
            persistence: cleanPersistence,
            sync: cleanResearchSync,
            watchlistSync: canonicalSync,
            loadDemoDataWhenEmpty: false
        )

        await cleanStore.refresh()
        XCTAssertEqual(cleanStore.watchlist, [backendEntry])
        XCTAssertEqual(cleanResearchSync.watchlists.last, [backendEntry])
        XCTAssertEqual(canonicalSync.fetchCount, 1)
        XCTAssertTrue(canonicalSync.snapshots.isEmpty)

        let localEntry = WatchlistEntry(
            id: UUID(),
            kind: .company,
            value: "Local offline edit",
            highPriority: false
        )
        var dirtyState = ResearchState.empty
        dirtyState.watchlist = [localEntry]
        dirtyState.watchlistNeedsSync = nil
        let dirtyPersistence = ControlsPersistence(state: dirtyState)
        let dirtySync = ControlsWatchlistSync(canonicalEntries: [backendEntry])
        let dirtyResearchSync = ControlsResearchSync()
        let dirtyStore = AppStore(
            persistence: dirtyPersistence,
            sync: dirtyResearchSync,
            watchlistSync: dirtySync,
            loadDemoDataWhenEmpty: false
        )

        await dirtyStore.refresh()
        XCTAssertEqual(dirtySync.fetchCount, 0)
        XCTAssertEqual(dirtySync.snapshots.last, [localEntry])
        XCTAssertEqual(dirtyResearchSync.watchlists.last, [localEntry])
        XCTAssertEqual(dirtyPersistence.state?.watchlistNeedsSync, false)
    }

    func testWatchlistPlanFeedsEverySupportedOfficialConnectorInput() {
        let entries = [
            WatchlistEntry(id: UUID(), kind: .creator, value: "@arab_creator", highPriority: true),
            WatchlistEntry(id: UUID(), kind: .officialSource, value: "https://example.com/feed", highPriority: false),
            WatchlistEntry(id: UUID(), kind: .company, value: "OpenAI", highPriority: false),
            WatchlistEntry(id: UUID(), kind: .keyword, value: "agents", highPriority: false),
            WatchlistEntry(id: UUID(), kind: .topic, value: "AI safety", highPriority: false),
            WatchlistEntry(id: UUID(), kind: .country, value: "Egypt", highPriority: false),
            WatchlistEntry(id: UUID(), kind: .country, value: "Saudi Arabia", highPriority: false),
            WatchlistEntry(id: UUID(), kind: .language, value: "Arabic", highPriority: false),
            WatchlistEntry(id: UUID(), kind: .language, value: "English", highPriority: false),
        ]
        let plan = WatchlistConnectorPlan(entries: entries)
        let connectorGroups = WatchlistConnectorFactory.connectors(for: entries, environment: [:]).map(\.group)

        XCTAssertEqual(plan.creators, ["@arab_creator"])
        XCTAssertEqual(plan.officialSourceURLs.map(\.absoluteString), ["https://example.com/feed"])
        XCTAssertEqual(Set(plan.searchTerms), Set(["OpenAI", "agents", "AI safety"]))
        XCTAssertEqual(plan.countryCodes, ["EG", "SA"])
        XCTAssertEqual(plan.languageCodes, ["ar", "en"])
        XCTAssertTrue(plan.youtubeSearches.contains {
            $0.query == "OpenAI" && $0.country == "EG" && $0.language == "ar"
        })
        XCTAssertTrue(plan.youtubeSearches.contains {
            $0.query == "OpenAI" && $0.country == "SA" && $0.language == "en"
        })
        XCTAssertTrue(plan.xQueries.contains { $0 == "agents lang:ar" })
        XCTAssertTrue(plan.xQueries.contains { $0 == "agents lang:en" })
        XCTAssertEqual(plan.trendLanguages, ["ar", "en"])
        XCTAssertEqual(Set(connectorGroups), Set([.youtube, .googleTrends, .instagram, .official, .x]))
        XCTAssertEqual(
            WatchlistEntry.Kind.country.connectorSupport.first { $0.group == .x }?.level,
            .collectedEvidence
        )
    }

    @MainActor
    func testTopicResearchQueriesConnectedSourcesAndMergesOriginalEvidence() async {
        let state = fixtureState()
        let xItem = state.sourceItems.first { $0.group == .x }!
        let researchSync = ControlsResearchSync(
            topicResults: [
                SourceSyncResult(
                    group: .x,
                    collectedAt: xItem.collectedAt,
                    items: [xItem],
                    state: .connected,
                    dataTruth: .live,
                    evidence: "Queried the configured X connector"
                )
            ]
        )
        let store = AppStore(
            persistence: ControlsPersistence(state: state),
            sync: researchSync,
            watchlistSync: ControlsWatchlistSync(canonicalEntries: state.watchlist),
            loadDemoDataWhenEmpty: false
        )

        await store.researchTopicAcrossConnectedSources(xItem.author)

        XCTAssertEqual(researchSync.topics, [xItem.author])
        let result = store.topicResearch(query: xItem.author)
        XCTAssertEqual(result.state, .results)
        XCTAssertTrue(result.evidence.contains { $0.id == xItem.id && $0.url == xItem.url })
    }

    func testBackendWatchlistSyncPullsCanonicalBeforeAtomicReplacement() async throws {
        let entry = WatchlistEntry(
            id: UUID(),
            kind: .keyword,
            value: "agents",
            highPriority: true
        )
        let body = try JSONEncoder().encode([entry])
        let transport = ControlsHTTPTransport(
            responses: [
                HTTPResponse(statusCode: 200, headers: [:], body: body),
                HTTPResponse(statusCode: 200, headers: [:], body: body),
            ]
        )
        let sync = BackendWatchlistSync(
            baseURL: URL(string: "https://backend.example")!,
            apiToken: String(repeating: "t", count: 32),
            transport: transport
        )

        let canonical = await sync.fetchCanonical()
        let replaced = await sync.reconcile([entry])
        let requests = await transport.requests

        XCTAssertEqual(canonical.synchronizedEntries, [entry])
        XCTAssertEqual(replaced.synchronizedEntries, [entry])
        XCTAssertEqual(requests.map(\.method), ["GET", "PUT"])
        let replacement = try XCTUnwrap(requests.last?.body)
        XCTAssertTrue(String(decoding: replacement, as: UTF8.self).contains("\"entries\""))
    }

    @MainActor
    func testLocalEditDuringCanonicalPullIsNeverOverwritten() async {
        let remote = WatchlistEntry(
            id: UUID(),
            kind: .topic,
            value: "Remote",
            highPriority: false
        )
        let sync = DelayedCanonicalWatchlistSync(canonicalEntries: [remote])
        let store = AppStore(
            persistence: ControlsPersistence(state: .empty),
            sync: ControlsResearchSync(),
            watchlistSync: sync,
            loadDemoDataWhenEmpty: false
        )

        let pull = Task { await store.synchronizeWatchlist() }
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(store.addWatchlist(kind: .company, value: "Local during pull"))
        await pull.value

        XCTAssertEqual(store.watchlist.map(\.value), ["Local during pull"])
        XCTAssertEqual(sync.snapshots.last?.map(\.value), ["Local during pull"])
    }

    private func fixtureState() -> ResearchState {
        let output = ResearchPipeline().run(
            items: ResearchFixtures.allSix,
            now: ResearchFixtures.now
        )
        var state = ResearchState.empty
        state.sourceItems = output.normalizedItems
        state.opportunities = output.opportunities
        state.comments = output.comments
        state.sourceHealth = SourceGroup.allCases.map {
            SourceHealth(
                group: $0,
                state: .connected,
                lastActivity: ResearchFixtures.now,
                evidence: "Fixture evidence",
                repairAction: "None",
                dataTruth: .cached
            )
        }
        return state
    }
}

private final class ControlsPersistence: ResearchPersistence, @unchecked Sendable {
    var state: ResearchState?

    init(state: ResearchState? = nil) {
        self.state = state
    }

    func load() throws -> ResearchState? { state }
    func save(_ state: ResearchState) throws { self.state = state }
}

private final class ControlsWatchlistSync: WatchlistSyncing, @unchecked Sendable {
    private(set) var snapshots: [[WatchlistEntry]] = []
    private(set) var fetchCount = 0
    private var canonicalEntries: [WatchlistEntry]

    init(canonicalEntries: [WatchlistEntry] = []) {
        self.canonicalEntries = canonicalEntries
    }

    func fetchCanonical() async -> WatchlistSyncResult {
        fetchCount += 1
        return WatchlistSyncResult(synchronizedEntries: canonicalEntries, errorMessage: nil)
    }

    func reconcile(_ entries: [WatchlistEntry]) async -> WatchlistSyncResult {
        snapshots.append(entries)
        canonicalEntries = entries
        return WatchlistSyncResult(synchronizedEntries: entries, errorMessage: nil)
    }
}

private final class ControlsResearchSync: ResearchSyncing, @unchecked Sendable {
    private(set) var watchlists: [[WatchlistEntry]] = []
    private(set) var topics: [String] = []
    private let topicResults: [SourceSyncResult]

    init(topicResults: [SourceSyncResult] = []) {
        self.topicResults = topicResults
    }

    func synchronize() async -> [SourceSyncResult] { [] }

    func synchronize(watchlist: [WatchlistEntry]) async -> [SourceSyncResult] {
        watchlists.append(watchlist)
        return []
    }

    func researchTopic(_ query: String, watchlist: [WatchlistEntry]) async -> [SourceSyncResult] {
        topics.append(query)
        watchlists.append(watchlist)
        return topicResults
    }
}

private actor ControlsHTTPTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private(set) var requests: [HTTPRequest] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return responses.removeFirst()
    }
}

private final class DelayedCanonicalWatchlistSync: WatchlistSyncing, @unchecked Sendable {
    let canonicalEntries: [WatchlistEntry]
    private(set) var snapshots: [[WatchlistEntry]] = []

    init(canonicalEntries: [WatchlistEntry]) {
        self.canonicalEntries = canonicalEntries
    }

    func fetchCanonical() async -> WatchlistSyncResult {
        try? await Task.sleep(for: .milliseconds(50))
        return WatchlistSyncResult(synchronizedEntries: canonicalEntries, errorMessage: nil)
    }

    func reconcile(_ entries: [WatchlistEntry]) async -> WatchlistSyncResult {
        snapshots.append(entries)
        return WatchlistSyncResult(synchronizedEntries: entries, errorMessage: nil)
    }
}
