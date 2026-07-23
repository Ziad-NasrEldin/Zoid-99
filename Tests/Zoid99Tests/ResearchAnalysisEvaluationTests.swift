import XCTest
@testable import Zoid99

final class ResearchAnalysisEvaluationTests: XCTestCase {
    private let now = ResearchFixtures.now

    func testNearDuplicatesAcrossLanguagesAndSourceGroupsBecomeOneStory() {
        let items = [
            item(.official, "origin", "OpenAI launches GPT-6 model", "Official GPT-6 launch details.", "OpenAI", -3, "en", "US", "launch-origin", true, 1, 100, .confirmed),
            item(.youtube, "creator", "OpenAI GPT 6 launched - first look", "A first look at GPT-6.", "US Creator", -2, "en", "US", "creator-gpt6", false, 0.8, 5_000, .confirmed),
            item(.comments, "arabic", "هل GPT-6 متاح في مصر؟", "سؤال عن إتاحة GPT-6 في مصر", "Viewer", -1, "ar-EG", "EG", "availability-gpt6", false, 0.4, 20, .unverified)
        ]

        let output = ResearchPipeline().run(items: items, now: now)

        XCTAssertEqual(output.opportunities.count, 1)
        XCTAssertEqual(output.opportunities[0].items.count, 3)
        XCTAssertEqual(output.opportunities[0].originalSource?.externalID, "origin")
    }

    func testGenericReleaseWordsDoNotMergeDistinctDevelopments() {
        let items = [
            item(.official, "alpha", "Alpha platform release notes", "Alpha shipped its own update.", "Alpha", -2, "en", "US", "unclustered-alpha", true, 1, 10, .confirmed),
            item(.official, "beta", "Beta platform release notes", "Beta shipped a different update.", "Beta", -1, "en", "US", "unclustered-beta", true, 1, 10, .confirmed)
        ]

        let output = ResearchPipeline().run(items: items, now: now)

        XCTAssertEqual(output.opportunities.count, 2)
        XCTAssertEqual(Set(output.opportunities.map(\.topicKey)), ["unclustered-alpha", "unclustered-beta"])
    }

    func testDifferentSemanticVersionsRemainSeparateDevelopments() {
        let items = [
            item(.official, "v5.4.0", "Release v5.4.0", "Version 5.4.0 release notes.", "Hugging Face", -2, "en", "US", "unclustered-v540", true, 1, 10, .confirmed),
            item(.official, "v5.5.0", "Release v5.5.0", "Version 5.5.0 release notes.", "Hugging Face", -1, "en", "US", "unclustered-v550", true, 1, 10, .confirmed)
        ]

        let output = ResearchPipeline().run(items: items, now: now)

        XCTAssertEqual(output.opportunities.count, 2)
        XCTAssertEqual(Set(output.opportunities.map(\.topicKey)), ["unclustered-v540", "unclustered-v550"])
    }

    func testDifferentPatchVersionsRemainSeparateDevelopments() {
        let items = [
            item(.official, "v5.10.1", "Release v5.10.1", "Version 5.10.1 release notes.", "Hugging Face", -2, "en", "US", "unclustered-v5101", true, 1, 10, .confirmed),
            item(.official, "v5.10.2", "Patch release v5.10.2", "Version 5.10.2 release notes.", "Hugging Face", -1, "en", "US", "unclustered-v5102", true, 1, 10, .confirmed)
        ]

        let output = ResearchPipeline().run(items: items, now: now)

        XCTAssertEqual(output.opportunities.count, 2)
        XCTAssertEqual(Set(output.opportunities.map(\.topicKey)), ["unclustered-v5101", "unclustered-v5102"])
    }

    func testDifferentModelMinorVersionsRemainSeparateDevelopments() {
        let items = [
            item(.official, "gpt-5.6", "GPT-5.6: Frontier intelligence", "GPT-5.6 announcement.", "OpenAI", -3, "en", "US", "unclustered-gpt56", true, 1, 10, .confirmed),
            item(.youtube, "gpt-5-6", "GPT 5 6 first look", "A GPT-5.6 first look.", "Creator", -2, "en", "US", "unclustered-gpt56-video", false, 0.8, 100, .confirmed),
            item(.official, "gpt-5.5", "GPT-5.5 Bio Bug Bounty", "A GPT-5.5 security program.", "OpenAI", -1, "en", "US", "unclustered-gpt55", true, 1, 10, .confirmed)
        ]

        let output = ResearchPipeline().run(items: items, now: now)

        XCTAssertEqual(output.opportunities.count, 2)
        XCTAssertTrue(output.opportunities.contains { $0.items.map(\.externalID).sorted() == ["gpt-5-6", "gpt-5.6"] })
        XCTAssertTrue(output.opportunities.contains { $0.items.map(\.externalID) == ["gpt-5.5"] })
    }

    func testBridgeItemCannotTransitivelyMergeUnrelatedDevelopments() {
        let items = [
            item(.official, "orion", "Acme Orion launch", "The Orion development.", "Acme", -3, "en", "US", "unclustered-orion", true, 1, 10, .confirmed),
            item(.youtube, "bridge", "Acme Orion meets Beta Nova", "A comparison of two developments.", "Creator", -2, "en", "US", "unclustered-comparison", false, 0.7, 100, .unverified),
            item(.official, "nova", "Beta Nova launch", "The separate Nova development.", "Beta", -1, "en", "US", "unclustered-nova", true, 1, 10, .confirmed)
        ]

        let output = ResearchPipeline().run(items: items, now: now)

        XCTAssertEqual(output.opportunities.count, 2)
        XCTAssertTrue(output.opportunities.contains { $0.items.map(\.externalID).sorted() == ["bridge", "orion"] })
        XCTAssertTrue(output.opportunities.contains { $0.items.map(\.externalID) == ["nova"] })
    }

    func testUnverifiedClaimsCannotBecomeConfirmedWithoutCredibleOriginalEvidence() {
        let items = [
            item(.x, "rumor-1", "Company X secretly released Model Z", "Anonymous launch claim.", "Anonymous", -2, "en", "US", "model-z", true, 0.95, 50_000, .confirmed),
            item(.youtube, "rumor-2", "Model Z is here", "Repeats the anonymous claim.", "Creator", -1, "en", "US", "model-z", false, 0.7, 80_000, .confirmed)
        ]

        let opportunity = ResearchPipeline().run(items: items, now: now).opportunities[0]

        XCTAssertEqual(opportunity.verification, .unverified)
        XCTAssertNil(opportunity.originalSource)
        XCTAssertFalse(opportunity.isHighPriority)
    }

    func testCredibleContradictionMakesStoryDisputed() {
        let items = [
            item(.official, "claim", "Model Z launches today", "Official launch claim.", "Company", -3, "en", "US", "model-z", true, 0.95, 100, .confirmed),
            item(.official, "correction", "Model Z launch report is false", "Official correction disputes the launch.", "Regulator", -1, "en", "US", "model-z", true, 0.95, 200, .disputed)
        ]

        XCTAssertEqual(ResearchPipeline().run(items: items, now: now).opportunities[0].verification, .disputed)
    }

    func testBriefAlwaysRetainsCitationsAndNamesUnknownOrigin() {
        let items = [
            item(.instagram, "missing-origin", "A new AI wearable is rumored", "A creator reports a possible wearable.", "Creator", -2, "en", "AE", "wearable", false, 0.55, 2_000, .unverified)
        ]

        let opportunity = ResearchPipeline().run(items: items, now: now).opportunities[0]

        XCTAssertFalse(opportunity.researchBrief.citations.isEmpty)
        XCTAssertEqual(opportunity.researchBrief.citations.map(\.sourceID), ["Instagram:missing-origin"])
        XCTAssertTrue(opportunity.researchBrief.originStatement.contains("unknown"))
        XCTAssertTrue(opportunity.researchBrief.summary.contains("[1]"))
    }

    func testFreshnessMomentumArabicGapAndRegionalEvidenceAreExplainable() {
        let items = [
            item(.official, "origin", "Open model launches", "Official launch.", "Lab", -10, "en", "US", "open-model", true, 1, 100, .confirmed),
            item(.googleTrends, "eg-old", "Open model Egypt trend", "Egypt interest.", "Trends", -8, "en", "EG", "open-model", false, 0.8, 100, .confirmed),
            item(.googleTrends, "sa-new", "Open model Saudi trend", "Saudi interest.", "Trends", -1, "en", "SA", "open-model", false, 0.8, 2_000, .confirmed),
            item(.instagram, "uae", "Open model UAE demo", "UAE creator demo.", "Creator", -0.5, "en", "AE", "open-model", false, 0.6, 1_000, .unverified),
            item(.comments, "oman", "هل يعمل النموذج في عمان؟", "طلب من عمان.", "Viewer", -0.25, "ar-OM", "OM", "open-model", false, 0.5, 30, .unverified)
        ]

        let opportunity = ResearchPipeline().run(items: items, now: now).opportunities[0]

        XCTAssertGreaterThan(opportunity.score.momentum, 0)
        XCTAssertTrue(opportunity.momentumEvidence.contains("recent"))
        XCTAssertTrue(opportunity.coverageExplanation.contains("1 Arabic"))
        XCTAssertEqual(opportunity.regionalEvidence.map(\.countryCode), ["AE", "EG", "OM", "SA"])
    }

    func testImmediateRequiresConfirmedRecentHighPriorityStoryOtherwiseDigest() {
        let confirmed = ResearchPipeline().run(items: ResearchFixtures.allSix, now: now)
        let release = try! XCTUnwrap(confirmed.opportunities.first { $0.verification == .confirmed })
        XCTAssertEqual(confirmed.notifications.first { $0.opportunityID == release.id }?.delivery, .immediate)

        let stale = [
            item(.official, "old", "Old confirmed release", "Old release.", "Lab", -240, "en", "US", "old-release", true, 1, 500_000, .confirmed)
        ]
        let staleOutput = ResearchPipeline().run(items: stale, now: now)
        XCTAssertEqual(staleOutput.notifications[0].delivery, .digest)
    }

    func testProviderUnavailableFallsBackDeterministically() async {
        let policy = AIAnalysisPolicy(maxAttempts: 2, maxInputItems: 10, maxOutputCharacters: 2_000)
        let output = await ResearchPipeline().run(
            items: ResearchFixtures.allSix,
            now: now,
            provider: UnavailableAIAnalysisProvider(),
            policy: policy
        )

        XCTAssertEqual(output.aiStatus, .unavailableFallback)
        XCTAssertEqual(output.opportunities, ResearchPipeline().run(items: ResearchFixtures.allSix, now: now).opportunities)
    }

    func testInvalidAIOutputIsRejectedWithBoundedRetriesAndCannotChangeVerification() async {
        let provider = InvalidThenValidProvider()
        let output = await ResearchPipeline().run(
            items: ResearchFixtures.allSix,
            now: now,
            provider: provider,
            policy: AIAnalysisPolicy(maxAttempts: 2, maxInputItems: 10, maxOutputCharacters: 2_000)
        )

        let attemptCount = await provider.attemptCount
        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(output.aiStatus, .applied)
        XCTAssertTrue(output.aiInterpretations.allSatisfy { !$0.citedSourceIDs.isEmpty })
        XCTAssertEqual(output.opportunities.first { $0.topicKey == "availability-question" }?.verification, .unverified)
    }

    private func item(
        _ group: SourceGroup,
        _ externalID: String,
        _ title: String,
        _ summary: String,
        _ author: String,
        _ hours: Double,
        _ language: String,
        _ country: String,
        _ topic: String,
        _ original: Bool,
        _ credibility: Double,
        _ engagement: Int,
        _ verification: VerificationState
    ) -> SourceItem {
        SourceItem(
            id: UUID(),
            group: group,
            externalID: externalID,
            title: title,
            summary: summary,
            author: author,
            url: URL(string: "https://example.com/\(externalID)")!,
            publishedAt: now.addingTimeInterval(hours * 3_600),
            collectedAt: now,
            language: language,
            country: country,
            topicKey: topic,
            isOriginalSource: original,
            credibility: credibility,
            engagement: engagement,
            verification: verification
        )
    }
}

private actor InvalidThenValidProvider: AIAnalysisProvider {
    private(set) var attemptCount = 0

    func analyze(_ request: AIAnalysisRequest) async throws -> AIAnalysisResponse {
        attemptCount += 1
        let cluster = request.clusters[0]
        if attemptCount == 1 {
            return AIAnalysisResponse(
                schemaVersion: 1,
                interpretations: [
                    AIClusterInterpretation(
                        clusterID: cluster.clusterID,
                        conciseSummary: String(repeating: "x", count: 3_000),
                        regionalInterpretation: "Unsupported.",
                        citedSourceIDs: []
                    )
                ]
            )
        }
        return AIAnalysisResponse(
            schemaVersion: 1,
            interpretations: [
                AIClusterInterpretation(
                    clusterID: cluster.clusterID,
                    conciseSummary: "Interpretation based only on cited evidence.",
                    regionalInterpretation: "Regional meaning requires editorial review.",
                    citedSourceIDs: [cluster.sources[0].sourceID]
                )
            ]
        )
    }
}
