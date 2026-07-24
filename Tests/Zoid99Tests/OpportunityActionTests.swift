import XCTest
@testable import Zoid99

@MainActor
final class OpportunityActionTests: XCTestCase {
    func testSaveIsIndependentReachableAndPersistsAcrossRelaunch() {
        let persistence = ActionTestPersistence(state: state())
        let first = store(persistence)
        let id = first.opportunities[0].id

        XCTAssertTrue(first.toggleSavedOpportunity(id: id))
        XCTAssertEqual(first.savedOpportunities.map(\.id), [id])
        XCTAssertTrue(first.isOpportunitySaved(id))

        let relaunched = store(persistence)
        XCTAssertEqual(relaunched.savedOpportunities.map(\.id), [id])
        XCTAssertTrue(relaunched.toggleSavedOpportunity(id: id))
        XCTAssertTrue(relaunched.savedOpportunities.isEmpty)
    }

    func testWatchUsesExistingWatchlistAndPreventsDuplicates() {
        let persistence = ActionTestPersistence(state: state())
        let appStore = store(persistence)
        let opportunity = appStore.opportunities[0]

        XCTAssertTrue(appStore.watchOpportunity(id: opportunity.id))
        XCTAssertTrue(appStore.isOpportunityWatched(opportunity.id))
        XCTAssertEqual(appStore.watchlist.count, 1)
        XCTAssertEqual(appStore.watchlist[0].kind, .topic)
        XCTAssertEqual(appStore.watchlist[0].value, opportunity.title)
        XCTAssertFalse(appStore.watchOpportunity(id: opportunity.id))

        let relaunched = store(persistence)
        XCTAssertTrue(relaunched.isOpportunityWatched(opportunity.id))
        XCTAssertTrue(relaunched.stopWatchingOpportunity(id: opportunity.id))
        XCTAssertFalse(relaunched.isOpportunityWatched(opportunity.id))
    }

    func testDismissCanBeRestoredAndPersists() {
        let persistence = ActionTestPersistence(state: state())
        let first = store(persistence)
        let id = first.opportunities[0].id

        XCTAssertTrue(first.dismissOpportunity(id: id))
        XCTAssertTrue(first.visibleOpportunities.isEmpty)
        XCTAssertEqual(first.dismissedOpportunities.map(\.id), [id])

        let relaunched = store(persistence)
        XCTAssertEqual(relaunched.dismissedOpportunities.map(\.id), [id])
        XCTAssertTrue(relaunched.restoreDismissedOpportunity(id: id))
        XCTAssertEqual(relaunched.visibleOpportunities.map(\.id), [id])
    }

    func testMuteSuppressesSameTopicAndCanBeManagedAfterRelaunch() {
        let original = opportunity(id: 1, topicKey: "agent-research")
        let futureMatch = opportunity(id: 2, topicKey: "agent-research")
        let unrelated = opportunity(id: 3, topicKey: "video-models")
        let persistence = ActionTestPersistence(
            state: state(opportunities: [original, futureMatch, unrelated])
        )
        let first = store(persistence)

        XCTAssertTrue(first.muteOpportunityTopic(id: original.id))
        XCTAssertEqual(first.visibleOpportunities.map(\.id), [unrelated.id])
        XCTAssertEqual(first.muteRules.count, 1)
        XCTAssertFalse(first.muteOpportunityTopic(id: futureMatch.id))

        let relaunched = store(persistence)
        XCTAssertEqual(relaunched.visibleOpportunities.map(\.id), [unrelated.id])
        XCTAssertTrue(relaunched.unmuteRule(id: relaunched.muteRules[0].id))
        XCTAssertEqual(
            Set(relaunched.visibleOpportunities.map(\.id)),
            Set([original.id, futureMatch.id, unrelated.id])
        )
    }

    func testActionsRemainIndependentAndMissingIDsReturnErrors() {
        let persistence = ActionTestPersistence(state: state())
        let appStore = store(persistence)
        let id = appStore.opportunities[0].id

        XCTAssertTrue(appStore.toggleSavedOpportunity(id: id))
        XCTAssertTrue(appStore.watchOpportunity(id: id))
        XCTAssertTrue(appStore.dismissOpportunity(id: id))
        XCTAssertTrue(appStore.isOpportunitySaved(id))
        XCTAssertTrue(appStore.isOpportunityWatched(id))
        XCTAssertEqual(appStore.dismissedOpportunities.map(\.id), [id])

        XCTAssertFalse(appStore.toggleSavedOpportunity(id: UUID()))
        XCTAssertEqual(appStore.statusMessage, "Opportunity unavailable - no changes made")
    }

    func testPersistenceFailureIsReportedWithoutClaimingDurability() {
        let persistence = ActionTestPersistence(state: state())
        persistence.shouldFailSave = true
        let appStore = store(persistence)

        XCTAssertTrue(appStore.toggleSavedOpportunity(id: appStore.opportunities[0].id))
        XCTAssertEqual(appStore.statusMessage, "Changes could not be saved")
    }

    private func store(_ persistence: ActionTestPersistence) -> AppStore {
        AppStore(
            persistence: persistence,
            dispositionSync: NoopOpportunityDispositionSync(),
            watchlistSync: ActionTestWatchlistSync(),
            loadDemoDataWhenEmpty: false
        )
    }

    private func state(opportunities: [Opportunity]? = nil) -> ResearchState {
        var value = ResearchState.empty
        value.opportunities = opportunities ?? [opportunity(id: 1, topicKey: "agent-research")]
        return value
    }

    private func opportunity(id: UInt8, topicKey: String) -> Opportunity {
        Opportunity(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id)),
            topicKey: topicKey,
            title: "Opportunity \(id)",
            brief: "Verified research",
            verification: .confirmed,
            earliestPublishedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(id)),
            originalSource: nil,
            items: [],
            score: ScoreBreakdown(
                freshness: 15,
                credibility: 20,
                momentum: 15,
                creatorActivity: 10,
                arabicCoverageGap: 10,
                regionalRelevance: 10
            ),
            regionalExplanation: "Relevant",
            coverageExplanation: "Gap",
            disposition: .active
        )
    }
}

private final class ActionTestPersistence: ResearchPersistence, @unchecked Sendable {
    private var state: ResearchState
    var shouldFailSave = false

    init(state: ResearchState) {
        self.state = state
    }

    func load() throws -> ResearchState? { state }
    func save(_ state: ResearchState) throws {
        if shouldFailSave { throw ActionTestPersistenceError.saveFailed }
        self.state = state
    }
}

private enum ActionTestPersistenceError: Error {
    case saveFailed
}

private struct ActionTestWatchlistSync: WatchlistSyncing {
    func fetchCanonical() async -> WatchlistSyncResult {
        WatchlistSyncResult(synchronizedEntries: [], errorMessage: "Offline in test")
    }

    func reconcile(_ entries: [WatchlistEntry]) async -> WatchlistSyncResult {
        WatchlistSyncResult(synchronizedEntries: entries, errorMessage: nil)
    }
}
