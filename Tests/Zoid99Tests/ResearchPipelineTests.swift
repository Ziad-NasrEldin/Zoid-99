import XCTest
@testable import Zoid99

final class ResearchPipelineTests: XCTestCase {
    func testCompleteSixSourceAcceptanceFlow() {
        let output = ResearchPipeline().run(items: ResearchFixtures.allSix, now: ResearchFixtures.now)

        XCTAssertEqual(Set(output.normalizedItems.map(\.group)), Set(SourceGroup.allCases))
        XCTAssertEqual(output.normalizedItems.filter { $0.externalID == "yt-001" }.count, 1)

        let release = try! XCTUnwrap(output.opportunities.first { $0.topicKey == "multimodal-launch" })
        XCTAssertEqual(output.opportunities.filter { $0.topicKey == "multimodal-launch" }.count, 1)
        XCTAssertEqual(release.originalSource?.group, .official)
        XCTAssertEqual(release.originalSource?.url.absoluteString, "https://openai.com/news/model")
        XCTAssertEqual(release.verification, .confirmed)
        XCTAssertEqual(release.earliestPublishedAt, ResearchFixtures.now.addingTimeInterval(-2 * 3600))
        XCTAssertTrue(release.isHighPriority)
        XCTAssertEqual(output.notifications.first { $0.opportunityID == release.id }?.delivery, .immediate)

        let question = try! XCTUnwrap(output.opportunities.first { $0.topicKey == "availability-question" })
        XCTAssertEqual(question.verification, .unverified)
        XCTAssertNil(question.originalSource)
        XCTAssertEqual(output.notifications.first { $0.opportunityID == question.id }?.delivery, .digest)
        XCTAssertEqual(output.comments.first?.count, 2)
    }

    func testFixtureConnectorContractMapsOnlyItsDeclaredSource() async throws {
        let items = ResearchFixtures.allSix.filter { $0.group == .youtube }
        let connector = FixtureConnector(group: .youtube, items: items)
        let mapped = try await connector.collect()
        XCTAssertTrue(mapped.allSatisfy { $0.group == .youtube })
        XCTAssertTrue(mapped.allSatisfy { !$0.externalID.isEmpty && $0.url.scheme == "https" })
    }

    func testConnectorUnavailableAndRateLimitStatesRemainExplicit() async {
        for expected in [ConnectorError.setupRequired, .rateLimited, .unavailable] {
            let connector = FixtureConnector(group: .x, items: [], error: expected)
            do {
                _ = try await connector.collect()
                XCTFail("Expected \(expected)")
            } catch let error as ConnectorError {
                XCTAssertEqual(error, expected)
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    @MainActor
    func testDismissAndMuteRemoveOpportunitiesFromVisibleProjection() {
        let store = AppStore(persistence: MemoryPersistence())
        let first = store.visibleOpportunities[0]
        store.updateDisposition(.dismissed, id: first.id)
        XCTAssertFalse(store.visibleOpportunities.contains { $0.id == first.id })

        let second = store.visibleOpportunities[0]
        store.updateDisposition(.muted, id: second.id)
        XCTAssertFalse(store.visibleOpportunities.contains { $0.id == second.id })
    }

    @MainActor
    func testOfflineDispositionSurvivesRestartAndSynchronizesCanonicalState() async {
        let persistence = MemoryPersistence()
        let actionTime = Date(timeIntervalSince1970: 1_785_000_000)
        let firstLaunch = AppStore(
            persistence: persistence,
            dispositionSync: NoopOpportunityDispositionSync(),
            now: { actionTime }
        )
        let opportunity = firstLaunch.visibleOpportunities[0]

        firstLaunch.updateDisposition(.saved, id: opportunity.id)
        await firstLaunch.synchronizePendingDispositions()
        XCTAssertEqual(
            firstLaunch.opportunities.first { $0.id == opportunity.id }?.disposition,
            .saved
        )
        XCTAssertTrue(firstLaunch.statusMessage.contains("queued for sync"))

        let sync = StubDispositionSync { pending in
            let mutation = try! XCTUnwrap(pending.first)
            return DispositionSyncResult(
                states: [
                    OpportunityDispositionState(
                        opportunityID: mutation.opportunityID,
                        disposition: mutation.disposition,
                        changedAt: mutation.changedAt,
                        mutationID: mutation.id,
                        outcome: .applied
                    )
                ],
                acknowledgedMutationIDs: [mutation.id],
                errorMessage: nil
            )
        }
        let restarted = AppStore(
            persistence: persistence,
            dispositionSync: sync,
            loadDemoDataWhenEmpty: false
        )
        await restarted.synchronizePendingDispositions()

        XCTAssertEqual(restarted.opportunities.first { $0.id == opportunity.id }?.disposition, .saved)
        XCTAssertEqual(restarted.statusMessage, "Opportunity saved - synced")
        let finalRestart = AppStore(persistence: persistence, loadDemoDataWhenEmpty: false)
        XCTAssertEqual(finalRestart.opportunities.first { $0.id == opportunity.id }?.disposition, .saved)
    }

    @MainActor
    func testNewerServerDispositionSupersedesStaleOfflineActionAndHidesFutureResults() async {
        let actionTime = Date(timeIntervalSince1970: 1_785_000_000)
        let serverTime = actionTime.addingTimeInterval(60)
        let serverMutationID = UUID(uuidString: "60000000-0000-4000-8000-000000000001")!
        let sync = StubDispositionSync { pending in
            DispositionSyncResult(
                states: [
                    OpportunityDispositionState(
                        opportunityID: pending[0].opportunityID,
                        disposition: .muted,
                        changedAt: serverTime,
                        mutationID: serverMutationID,
                        outcome: .superseded
                    )
                ],
                acknowledgedMutationIDs: [pending[0].id],
                errorMessage: nil
            )
        }
        let store = AppStore(
            persistence: MemoryPersistence(),
            dispositionSync: sync,
            now: { actionTime }
        )
        let opportunity = store.visibleOpportunities[0]

        store.updateDisposition(.watched, id: opportunity.id)
        await store.synchronizePendingDispositions()

        XCTAssertEqual(store.opportunities.first { $0.id == opportunity.id }?.disposition, .muted)
        XCTAssertFalse(store.visibleOpportunities.contains { $0.id == opportunity.id })
        XCTAssertEqual(
            store.opportunities.first { $0.id == opportunity.id }?.originalSource?.url,
            opportunity.originalSource?.url
        )
        XCTAssertEqual(
            store.opportunities.first { $0.id == opportunity.id }?.earliestPublishedAt,
            opportunity.earliestPublishedAt
        )
    }

    func testThemeAndMotionPolicyConstants() {
        XCTAssertEqual(SumiMotion.pressDuration, 0.15)
        XCTAssertEqual(SumiMotion.hoverDuration, 0.18)
        XCTAssertEqual(SumiMotion.disclosureDuration, 0.16)
        XCTAssertEqual(SumiMotion.standardDuration, 0.20)
        XCTAssertEqual(SumiMotion(reduceMotion: true).pressScale, 1)
        XCTAssertEqual(SumiMotion(reduceMotion: false).pressScale, 0.98)
        XCTAssertNil(SumiMotion(reduceMotion: true).standardAnimation)
    }

    func testEveryStateHasWrittenText() {
        XCTAssertEqual(Set(VerificationState.allCases.map(\.rawValue)), ["Confirmed", "Disputed", "Unverified"])
        XCTAssertEqual(Set(SourceGroup.allCases.map(\.rawValue)).count, 6)
        XCTAssertFalse(ConnectionState.setupRequired.rawValue.isEmpty)
        XCTAssertFalse(ConnectionState.unavailable.rawValue.isEmpty)
        XCTAssertFalse(ConnectionState.rateLimited.rawValue.isEmpty)
        XCTAssertFalse(ConnectionState.delayed.rawValue.isEmpty)
        XCTAssertEqual(
            Set(DataTruth.allCases.map(\.rawValue)),
            ["Fixture", "Cached", "Live", "Missing", "Delayed", "Unavailable", "Rate limited"]
        )
    }

    func testArabicFixtureRetainsLanguageAndTextDirectionSignal() {
        let arabic = ResearchFixtures.allSix.filter { $0.language.hasPrefix("ar") }
        XCTAssertFalse(arabic.isEmpty)
        XCTAssertTrue(arabic.allSatisfy { $0.country == "EG" })
        XCTAssertTrue(arabic.allSatisfy { $0.title.contains("؟") })
    }

    @MainActor
    func testDurableRestartRestoresDispositionWatchlistSettingsAndHistory() async {
        let persistence = MemoryPersistence()
        let firstLaunch = AppStore(persistence: persistence)
        let opportunity = firstLaunch.visibleOpportunities[0]
        firstLaunch.updateDisposition(.saved, id: opportunity.id)
        firstLaunch.addWatchlist(kind: .keyword, value: "local inference")
        firstLaunch.setRefreshMinutes(30)
        await firstLaunch.refresh()

        let restarted = AppStore(persistence: persistence, loadDemoDataWhenEmpty: false)

        XCTAssertEqual(restarted.opportunities.first { $0.id == opportunity.id }?.disposition, .saved)
        XCTAssertTrue(restarted.watchlist.contains { $0.value == "local inference" })
        XCTAssertEqual(restarted.refreshMinutes, 30)
        XCTAssertEqual(restarted.sourceHealthHistory.count, SourceGroup.allCases.count)
        XCTAssertEqual(restarted.statusMessage, "Offline cache loaded")
    }

    func testJSONPersistenceRoundTripAndV1Migration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let persistence = JSONResearchPersistence(fileURL: url)
        let pipeline = ResearchPipeline().run(items: ResearchFixtures.allSix, now: ResearchFixtures.now)
        let state = ResearchState(
            sourceItems: pipeline.normalizedItems,
            opportunities: pipeline.opportunities,
            comments: pipeline.comments,
            dispositions: [pipeline.opportunities[0].id: .watched],
            watchlist: DemoFixtures.watchlist,
            settings: AppSettings(setupComplete: true, refreshMinutes: 25, notificationPermissionRequested: true),
            notificationHistory: pipeline.notifications,
            sourceHealth: [],
            sourceHealthHistory: [],
            lastSuccessfulSyncAt: ResearchFixtures.now
        )

        try persistence.save(state)
        XCTAssertEqual(try persistence.load(), state)

        let v1 = PersistenceDocumentV1(
            schemaVersion: 1,
            sourceItems: state.sourceItems,
            opportunities: state.opportunities,
            comments: state.comments,
            dispositions: state.dispositions,
            watchlist: state.watchlist,
            settings: state.settings,
            notificationHistory: state.notificationHistory,
            sourceHealth: state.sourceHealth
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(v1).write(to: url, options: .atomic)

        let migrated = try XCTUnwrap(persistence.load())
        XCTAssertEqual(migrated.sourceHealthHistory, [])
        XCTAssertNil(migrated.lastSuccessfulSyncAt)
        XCTAssertEqual(migrated.dispositions, state.dispositions)
    }

    @MainActor
    func testLiveSyncBecomesCachedAfterRestartAndRetainsOfflineReads() async {
        let persistence = MemoryPersistence()
        let sync = StubSync(results: SourceGroup.allCases.map { group in
            let items = ResearchFixtures.allSix.filter { $0.group == group }.map {
                var item = $0
                item.dataTruth = .live
                return item
            }
            return SourceSyncResult(
                group: group,
                collectedAt: ResearchFixtures.now,
                items: items,
                state: .connected,
                dataTruth: .live,
                evidence: "\(items.count) live items received."
            )
        })
        let firstLaunch = AppStore(
            persistence: persistence,
            sync: sync,
            loadDemoDataWhenEmpty: false
        )

        await firstLaunch.refresh()
        XCTAssertEqual(firstLaunch.dataTruth, .live)
        XCTAssertFalse(firstLaunch.opportunities.isEmpty)
        XCTAssertTrue(firstLaunch.sourceHealth.allSatisfy { $0.dataTruth == .live })

        let restarted = AppStore(persistence: persistence, loadDemoDataWhenEmpty: false)
        XCTAssertEqual(restarted.dataTruth, .cached)
        XCTAssertEqual(restarted.opportunities.count, firstLaunch.opportunities.count)
        XCTAssertTrue(restarted.opportunities.allSatisfy { $0.dataTruth == .cached })
        XCTAssertTrue(restarted.sourceHealth.allSatisfy { $0.dataTruth == .cached })
    }

    @MainActor
    func testSyncBoundaryPreservesExplicitMissingDelayedUnavailableAndRateLimitedTruth() async {
        let truths: [DataTruth] = [.missing, .delayed, .unavailable, .rateLimited, .cached, .fixture]
        let states: [ConnectionState] = [.setupRequired, .delayed, .unavailable, .rateLimited, .delayed, .setupRequired]
        let results = zip(SourceGroup.allCases, zip(truths, states)).map { group, pair in
            SourceSyncResult(
                group: group,
                collectedAt: ResearchFixtures.now,
                items: [],
                state: pair.1,
                dataTruth: pair.0,
                evidence: "\(pair.0.rawValue) test state."
            )
        }
        let store = AppStore(
            persistence: MemoryPersistence(),
            sync: StubSync(results: results),
            loadDemoDataWhenEmpty: false
        )

        await store.refresh()

        XCTAssertEqual(store.sourceHealth.map(\.dataTruth), truths)
        XCTAssertEqual(store.sourceHealth.map(\.state), states)
        XCTAssertEqual(store.sourceHealthHistory.map(\.dataTruth), truths)
        XCTAssertEqual(store.dataTruth, .missing)
        XCTAssertEqual(store.statusMessage, "No live data received - offline data retained")
    }
}

private final class MemoryPersistence: ResearchPersistence, @unchecked Sendable {
    private var state: ResearchState?
    private let lock = NSLock()

    func load() throws -> ResearchState? {
        lock.withLock { state }
    }

    func save(_ state: ResearchState) throws {
        lock.withLock { self.state = state }
    }
}

private struct StubSync: ResearchSyncing {
    let results: [SourceSyncResult]

    func synchronize() async -> [SourceSyncResult] {
        results
    }
}

private struct StubDispositionSync: OpportunityDispositionSyncing {
    let handler: @Sendable ([OpportunityDispositionMutation]) -> DispositionSyncResult

    func reconcile(_ pending: [OpportunityDispositionMutation]) async -> DispositionSyncResult {
        handler(pending)
    }
}
