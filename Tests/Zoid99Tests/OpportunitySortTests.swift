import Foundation
import XCTest
@testable import Zoid99

final class OpportunitySortTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testTotalScoreSortsDescendingWithStableTieBreakers() {
        let lower = opportunity(id: 3, totalBase: 10, publishedOffset: 300)
        let tiedOlder = opportunity(id: 2, totalBase: 20, publishedOffset: 100)
        let tiedNewerHigherID = opportunity(id: 4, totalBase: 20, publishedOffset: 200)
        let tiedNewerLowerID = opportunity(id: 1, totalBase: 20, publishedOffset: 200)

        XCTAssertEqual(
            OpportunitySort.totalScore.sorted([
                lower,
                tiedNewerHigherID,
                tiedOlder,
                tiedNewerLowerID,
            ]).map(\.id),
            [tiedNewerLowerID.id, tiedNewerHigherID.id, tiedOlder.id, lower.id]
        )
    }

    func testNewestUsesLatestEvidenceTimestampThenTotalScore() {
        let older = opportunity(id: 1, totalBase: 30, publishedOffset: 100)
        let newerLowerScore = opportunity(id: 2, totalBase: 10, publishedOffset: 300)
        let newerHigherScore = opportunity(id: 3, totalBase: 20, publishedOffset: 300)

        XCTAssertEqual(
            OpportunitySort.newest.sorted([older, newerLowerScore, newerHigherScore]).map(\.id),
            [newerHigherScore.id, newerLowerScore.id, older.id]
        )
    }

    func testHighPrioritySortsPriorityFirstThenTotalScore() {
        let highPriority = opportunity(
            id: 1,
            totalBase: 12,
            freshness: 15,
            credibility: 20,
            momentum: 15,
            creatorActivity: 10,
            arabicGap: 10,
            regional: 10
        )
        let higherTotalNotPriority = opportunity(
            id: 2,
            totalBase: 0,
            freshness: 13,
            credibility: 25,
            momentum: 20,
            creatorActivity: 15,
            arabicGap: 10,
            regional: 10
        )

        XCTAssertTrue(highPriority.isHighPriority)
        XCTAssertFalse(higherTotalNotPriority.isHighPriority)
        XCTAssertEqual(
            OpportunitySort.highPriority.sorted([higherTotalNotPriority, highPriority]).map(\.id),
            [highPriority.id, higherTotalNotPriority.id]
        )
    }

    func testRegionalRelevanceSortsDescendingThenTotalScore() {
        let lowerRegional = opportunity(id: 1, totalBase: 30, regional: 3)
        let higherRegionalLowerTotal = opportunity(id: 2, totalBase: 10, regional: 12)
        let higherRegionalHigherTotal = opportunity(id: 3, totalBase: 20, regional: 12)

        XCTAssertEqual(
            OpportunitySort.regionalRelevance.sorted([
                lowerRegional,
                higherRegionalLowerTotal,
                higherRegionalHigherTotal,
            ]).map(\.id),
            [higherRegionalHigherTotal.id, higherRegionalLowerTotal.id, lowerRegional.id]
        )
    }

    func testArabicCoverageGapSortsDescendingThenTotalScore() {
        let lowerGap = opportunity(id: 1, totalBase: 30, arabicGap: 3)
        let higherGapLowerTotal = opportunity(id: 2, totalBase: 10, arabicGap: 15)
        let higherGapHigherTotal = opportunity(id: 3, totalBase: 20, arabicGap: 15)

        XCTAssertEqual(
            OpportunitySort.arabicCoverageGap.sorted([
                lowerGap,
                higherGapLowerTotal,
                higherGapHigherTotal,
            ]).map(\.id),
            [higherGapHigherTotal.id, higherGapLowerTotal.id, lowerGap.id]
        )
    }

    func testPickerLabelsAreStableAndComplete() {
        XCTAssertEqual(
            OpportunitySort.allCases.map(\.title),
            [
                "Total Score",
                "Newest",
                "High Priority",
                "Regional Relevance",
                "Arabic Coverage Gap",
            ]
        )
    }

    @MainActor
    func testSortPersistsAcrossStoresAndResetPersistsTotalScore() {
        let defaults = makeDefaults()
        let first = makeStore(defaults: defaults)

        first.setRadarSort(.regionalRelevance)
        XCTAssertEqual(
            defaults.string(forKey: OpportunitySort.storageKey),
            OpportunitySort.regionalRelevance.rawValue
        )

        let relaunched = makeStore(defaults: defaults)
        XCTAssertEqual(relaunched.radarSort, .regionalRelevance)

        relaunched.resetRadarSort()
        XCTAssertEqual(relaunched.radarSort, .totalScore)
        XCTAssertEqual(
            defaults.string(forKey: OpportunitySort.storageKey),
            OpportunitySort.totalScore.rawValue
        )
    }

    @MainActor
    func testInvalidStoredSortFallsBackToTotalScore() {
        let defaults = makeDefaults()
        defaults.set("removed-sort", forKey: OpportunitySort.storageKey)

        XCTAssertEqual(makeStore(defaults: defaults).radarSort, .totalScore)
    }

    @MainActor
    func testExistingFiltersApplyBeforeSelectedSort() {
        let store = makeStore(defaults: makeDefaults())
        let arabicLower = opportunity(id: 1, totalBase: 10, language: "ar", regional: 3)
        let englishHigher = opportunity(id: 2, totalBase: 40, language: "en", regional: 15)
        let arabicHigher = opportunity(id: 3, totalBase: 20, language: "ar", regional: 12)
        store.opportunities = [arabicLower, englishHigher, arabicHigher]
        store.radarLanguage = "ar"
        store.setRadarSort(.regionalRelevance)

        XCTAssertEqual(store.radarOpportunities.map(\.id), [arabicHigher.id, arabicLower.id])
    }

    @MainActor
    func testLargeRadarProjectionKeepsStableIdentityAndFastFilteringAndSorting() {
        let store = makeStore(defaults: makeDefaults())
        store.opportunities = (1...100).map {
            opportunity(
                id: UInt8($0),
                totalBase: $0,
                publishedOffset: TimeInterval($0),
                language: $0.isMultiple(of: 2) ? "ar" : "en",
                regional: $0 % 16
            )
        }
        store.radarLanguage = "ar"
        store.setRadarSort(.regionalRelevance)

        let startedAt = ContinuousClock.now
        let firstProjection = store.radarOpportunities
        let secondProjection = store.radarOpportunities
        let elapsed = startedAt.duration(to: .now)

        XCTAssertEqual(firstProjection.count, 50)
        XCTAssertEqual(firstProjection.map(\.id), secondProjection.map(\.id))
        XCTAssertLessThan(elapsed, .milliseconds(100))
    }

    private func opportunity(
        id: UInt8,
        totalBase: Int,
        publishedOffset: TimeInterval = 0,
        language: String = "en",
        freshness: Int? = nil,
        credibility: Int = 0,
        momentum: Int = 0,
        creatorActivity: Int = 0,
        arabicGap: Int = 0,
        regional: Int = 0
    ) -> Opportunity {
        let identifier = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id))
        let publishedAt = baseDate.addingTimeInterval(publishedOffset)
        let item = SourceItem(
            id: identifier,
            group: .official,
            externalID: "\(id)",
            title: "Evidence \(id)",
            summary: "Summary",
            author: "Official",
            url: URL(string: "https://example.com/\(id)")!,
            publishedAt: publishedAt,
            collectedAt: publishedAt,
            language: language,
            country: "US",
            topicKey: "topic-\(id)",
            isOriginalSource: true,
            credibility: 1,
            engagement: 0,
            verification: .confirmed
        )
        return Opportunity(
            id: identifier,
            topicKey: item.topicKey,
            title: item.title,
            brief: item.summary,
            verification: .confirmed,
            earliestPublishedAt: publishedAt,
            originalSource: item,
            items: [item],
            score: ScoreBreakdown(
                freshness: freshness ?? totalBase,
                credibility: credibility,
                momentum: momentum,
                creatorActivity: creatorActivity,
                arabicCoverageGap: arabicGap,
                regionalRelevance: regional
            ),
            regionalExplanation: "Regional evidence",
            coverageExplanation: "Coverage evidence",
            disposition: .active
        )
    }

    @MainActor
    private func makeStore(defaults: UserDefaults) -> AppStore {
        AppStore(
            persistence: SortTestPersistence(),
            sortDefaults: defaults,
            loadDemoDataWhenEmpty: false
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "OpportunitySortTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class SortTestPersistence: ResearchPersistence, @unchecked Sendable {
    func load() throws -> ResearchState? { .empty }
    func save(_ state: ResearchState) throws {}
}
