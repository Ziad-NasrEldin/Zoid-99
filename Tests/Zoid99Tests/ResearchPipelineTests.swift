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
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let store = AppStore(defaults: defaults)
        let first = store.visibleOpportunities[0]
        store.updateDisposition(.dismissed, id: first.id)
        XCTAssertFalse(store.visibleOpportunities.contains { $0.id == first.id })

        let second = store.visibleOpportunities[0]
        store.updateDisposition(.muted, id: second.id)
        XCTAssertFalse(store.visibleOpportunities.contains { $0.id == second.id })
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
    }

    func testArabicFixtureRetainsLanguageAndTextDirectionSignal() {
        let arabic = ResearchFixtures.allSix.filter { $0.language.hasPrefix("ar") }
        XCTAssertFalse(arabic.isEmpty)
        XCTAssertTrue(arabic.allSatisfy { $0.country == "EG" })
        XCTAssertTrue(arabic.allSatisfy { $0.title.contains("؟") })
    }
}
