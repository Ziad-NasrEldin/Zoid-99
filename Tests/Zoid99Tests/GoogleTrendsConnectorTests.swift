import Foundation
import XCTest
@testable import Zoid99

final class GoogleTrendsConnectorTests: XCTestCase {
    func testMapsRegionalInterestIntoSourceItemsWithoutLosingQueryMetadata() async throws {
        let provider = FixtureGoogleTrendsProvider(
            pages: [try fixturePage("google-trends-interest.json")]
        )
        let connector = GoogleTrendsConnector(
            access: .configured(provider: provider),
            now: { Date(timeIntervalSince1970: 1_784_851_200) }
        )
        let query = GoogleTrendsQuery(
            terms: [
                .keyword("AI agents"),
                .topic(id: "/m/0mkz", label: "Artificial intelligence")
            ],
            regions: [.egypt, .saudiArabia, .unitedArabEmirates, .oman, .unitedStates],
            timeRange: .init(
                start: Date(timeIntervalSince1970: 1_784_246_400),
                end: Date(timeIntervalSince1970: 1_784_764_800),
                aggregation: .daily
            ),
            language: "ar"
        )

        let result = await connector.collect(query)

        XCTAssertEqual(result.connectionState, .connected)
        XCTAssertEqual(result.collection.state, .available)
        XCTAssertEqual(result.collection.items.count, 3)
        XCTAssertEqual(result.collection.items.map(\.group), [.googleTrends, .googleTrends, .googleTrends])
        XCTAssertEqual(result.collection.items.map(\.country), ["EG", "SA", "US"])
        XCTAssertEqual(result.collection.items.map(\.language), ["ar", "ar", "ar"])
        XCTAssertEqual(result.collection.items[0].externalID, "AI agents|EG|2026-07-22")
        XCTAssertEqual(result.collection.items[0].title, "AI agents search interest in Egypt")
        XCTAssertEqual(result.collection.items[0].engagement, 68)
        XCTAssertEqual(result.collection.items[0].dataTruth, .live)
        XCTAssertEqual(result.collection.items[2].topicKey, "google-trends-topic-_m_0mkz")
        XCTAssertTrue(result.collection.items.allSatisfy { $0.url.host == "trends.google.com" })
        let receivedQueries = await provider.receivedQueries()
        XCTAssertEqual(receivedQueries, [query])
    }

    func testSetupRequiredIsExplicitAndNeverFabricatesLiveItems() async {
        let connector = GoogleTrendsConnector(
            access: .setupRequired,
            now: { Date(timeIntervalSince1970: 1_784_851_200) }
        )

        let result = await connector.collect(query())

        XCTAssertEqual(result.connectionState, .setupRequired)
        XCTAssertEqual(result.collection.state, .unavailable(statusCode: nil))
        XCTAssertTrue(result.collection.items.isEmpty)
        XCTAssertTrue(result.collection.evidence.hasPrefix("Setup required:"))
    }

    func testFollowsProviderPaginationAndMapsEverySupportedComparisonRegion() async {
        let first = GoogleTrendsPage(
            points: regions([.egypt, .saudiArabia, .unitedArabEmirates]),
            nextPageToken: "page-2",
            dataThrough: Date(timeIntervalSince1970: 1_784_678_400)
        )
        let second = GoogleTrendsPage(
            points: regions([.oman, .unitedStates]),
            nextPageToken: nil,
            dataThrough: Date(timeIntervalSince1970: 1_784_678_400)
        )
        let provider = FixtureGoogleTrendsProvider(pages: [first, second])
        let connector = GoogleTrendsConnector(
            access: .configured(provider: provider),
            now: { Date(timeIntervalSince1970: 1_784_851_200) }
        )

        let result = await connector.collect(query())

        XCTAssertEqual(result.connectionState, .connected)
        XCTAssertEqual(result.collection.items.map(\.country), ["EG", "SA", "AE", "OM", "US"])
        let pageTokens = await provider.receivedPageTokens()
        XCTAssertEqual(pageTokens, [nil, "page-2"])
    }

    func testRateLimitedDelayedAndUnavailableProviderStatesRemainDistinct() async {
        let rateLimited = GoogleTrendsConnector(
            access: .configured(provider: ThrowingGoogleTrendsProvider(
                error: .rateLimited(retryAfter: 300)
            ))
        )
        let delayed = GoogleTrendsConnector(
            access: .configured(provider: ThrowingGoogleTrendsProvider(error: .delayed))
        )
        let unavailable = GoogleTrendsConnector(
            access: .configured(provider: ThrowingGoogleTrendsProvider(error: .unavailable))
        )

        let rateLimitedResult = await rateLimited.collect(query())
        let delayedResult = await delayed.collect(query())
        let unavailableResult = await unavailable.collect(query())

        XCTAssertEqual(rateLimitedResult.connectionState, .rateLimited)
        XCTAssertEqual(rateLimitedResult.collection.state, .rateLimited(retryAfter: 300))
        XCTAssertEqual(delayedResult.connectionState, .delayed)
        XCTAssertEqual(delayedResult.collection.state, .delayed)
        XCTAssertEqual(unavailableResult.connectionState, .unavailable)
        XCTAssertEqual(unavailableResult.collection.state, .unavailable(statusCode: nil))
        XCTAssertTrue([
            rateLimitedResult, delayedResult, unavailableResult
        ].allSatisfy(\.collection.items.isEmpty))
    }

    func testRejectsRequestsOutsideSupportedFiveYearWindowBeforeCallingProvider() async {
        let provider = FixtureGoogleTrendsProvider(pages: [])
        let connector = GoogleTrendsConnector(
            access: .configured(provider: provider),
            now: { Date(timeIntervalSince1970: 1_784_851_200) }
        )
        let invalid = GoogleTrendsQuery(
            terms: [.keyword("AI agents")],
            regions: [.egypt],
            timeRange: .init(
                start: Date(timeIntervalSince1970: 1_600_000_000),
                end: Date(timeIntervalSince1970: 1_784_764_800),
                aggregation: .monthly
            ),
            language: "en"
        )

        let result = await connector.collect(invalid)

        XCTAssertEqual(result.connectionState, .unavailable)
        XCTAssertTrue(result.collection.items.isEmpty)
        let receivedQueries = await provider.receivedQueries()
        XCTAssertTrue(receivedQueries.isEmpty)
    }

    private func query() -> GoogleTrendsQuery {
        GoogleTrendsQuery(
            terms: [.keyword("AI agents")],
            regions: GoogleTrendsRegion.allCases,
            timeRange: .init(
                start: Date(timeIntervalSince1970: 1_784_246_400),
                end: Date(timeIntervalSince1970: 1_784_764_800),
                aggregation: .daily
            ),
            language: "ar"
        )
    }

    private func regions(_ regions: [GoogleTrendsRegion]) -> [GoogleTrendsInterestPoint] {
        regions.map {
            GoogleTrendsInterestPoint(
                term: .keyword("AI agents"),
                region: $0,
                intervalStart: Date(timeIntervalSince1970: 1_784_678_400),
                intervalEnd: Date(timeIntervalSince1970: 1_784_764_800),
                interest: 50
            )
        }
    }

    private func fixturePage(_ name: String) throws -> GoogleTrendsPage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil))
        return try JSONDecoder.googleTrends.decode(GoogleTrendsPage.self, from: Data(contentsOf: url))
    }
}

private actor FixtureGoogleTrendsProvider: GoogleTrendsProviding {
    private var pages: [GoogleTrendsPage]
    private var queries: [GoogleTrendsQuery] = []
    private var pageTokens: [String?] = []

    init(pages: [GoogleTrendsPage]) {
        self.pages = pages
    }

    func fetch(_ query: GoogleTrendsQuery, pageToken: String?) async throws -> GoogleTrendsPage {
        queries.append(query)
        pageTokens.append(pageToken)
        guard !pages.isEmpty else { throw GoogleTrendsProviderError.unavailable }
        return pages.removeFirst()
    }

    func receivedQueries() -> [GoogleTrendsQuery] {
        queries
    }

    func receivedPageTokens() -> [String?] {
        pageTokens
    }
}

private struct ThrowingGoogleTrendsProvider: GoogleTrendsProviding {
    let error: GoogleTrendsProviderError

    func fetch(_ query: GoogleTrendsQuery, pageToken: String?) async throws -> GoogleTrendsPage {
        throw error
    }
}

private extension JSONDecoder {
    static var googleTrends: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
