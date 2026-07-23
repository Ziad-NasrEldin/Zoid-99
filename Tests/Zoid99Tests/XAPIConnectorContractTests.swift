import Foundation
import XCTest
@testable import Zoid99

final class XAPIConnectorContractTests: XCTestCase {
    func testRecentSearchMapsPostsReferencesEngagementPaginationAndCheckpoint() async throws {
        let transport = XStubTransport(responses: [
            response(body: try fixture("x-recent-search-page-1.json"), remaining: "19"),
            response(body: try fixture("x-recent-search-page-2.json"), remaining: "18")
        ])
        let checkpoints = XSinceIDStore()
        let connector = XAPIConnector(
            configuration: XAPIConfiguration(
                authentication: .bearerToken("test-token"),
                recentSearchQueries: ["agent evaluation"]
            ),
            transport: transport,
            checkpoints: checkpoints,
            maximumPagesPerTarget: 2,
            now: { ISO8601DateFormatter().date(from: "2026-07-23T11:00:00Z")! }
        )

        let report = await connector.collectReport()
        let requests = await transport.recordedRequests()

        XCTAssertEqual(report.state, .available)
        XCTAssertEqual(report.collection.items.map(\.externalID), [
            "1900000000000000100",
            "1900000000000000090",
            "1900000000000000001"
        ])
        XCTAssertEqual(report.collection.items[0].author, "@example_ai")
        XCTAssertEqual(report.collection.items[0].url.absoluteString, "https://x.com/example_ai/status/1900000000000000100")
        XCTAssertEqual(report.collection.items[0].engagement, 62)
        XCTAssertEqual(report.engagement["1900000000000000100"]?.impressions, 900)
        XCTAssertEqual(report.references["1900000000000000100"]?.first?.type, .quoted)
        XCTAssertEqual(report.references["1900000000000000100"]?.first?.postID, "1900000000000000001")
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests[0].url.absoluteString.contains("query=agent%20evaluation"))
        XCTAssertTrue(requests[1].url.absoluteString.contains("next_token=page-two-token"))
        XCTAssertEqual(requests[0].headers["Authorization"], "Bearer test-token")
        XCTAssertFalse(report.collection.evidence.contains("test-token"))
        XCTAssertEqual(report.rateLimit?.remaining, 18)
        let savedSinceID = await checkpoints.sinceID(for: "search:agent evaluation")
        XCTAssertEqual(savedSinceID, "1900000000000000100")

        let nextTransport = XStubTransport(responses: [
            response(body: Data(#"{"meta":{"result_count":0}}"#.utf8), remaining: "17")
        ])
        let nextConnector = XAPIConnector(
            configuration: XAPIConfiguration(
                authentication: .bearerToken("test-token"),
                recentSearchQueries: ["agent evaluation"]
            ),
            transport: nextTransport,
            checkpoints: checkpoints
        )
        _ = await nextConnector.collectReport()
        let nextRequests = await nextTransport.recordedRequests()
        let nextRequest = try XCTUnwrap(nextRequests.first)
        XCTAssertTrue(nextRequest.url.absoluteString.contains("since_id=1900000000000000100"))
    }

    func testAccountsAndListsUseOfficialEndpointsAndBoundedPagination() async throws {
        let transport = XStubTransport(responses: [
            response(body: Data(#"{"data":[{"id":"1001","name":"Example AI","username":"example_ai"}]}"#.utf8)),
            response(body: Data(#"{"meta":{"result_count":0,"newest_id":"1900000000000000200"}}"#.utf8)),
            response(body: Data(#"{"meta":{"result_count":0,"next_token":"ignored-third-page"}}"#.utf8)),
            response(body: Data(#"{"meta":{"result_count":0,"next_token":"also-ignored"}}"#.utf8))
        ])
        let connector = XAPIConnector(
            configuration: XAPIConfiguration(
                authentication: .oauth2AccessToken("user-token"),
                monitoredUsernames: ["example_ai"],
                listIDs: ["1146654567674912769"]
            ),
            transport: transport,
            maximumPagesPerTarget: 1
        )

        _ = await connector.collectReport()
        let requests = await transport.recordedRequests()

        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests[0].url.path.contains("/2/users/by"))
        XCTAssertTrue(requests[1].url.path.contains("/2/users/1001/tweets"))
        XCTAssertTrue(requests[2].url.path.contains("/2/lists/1146654567674912769/tweets"))
        XCTAssertTrue(requests[1].url.query?.contains("tweet.fields=") == true)
        XCTAssertTrue(requests[2].url.query?.contains("expansions=author_id") == true)
        XCTAssertFalse(requests[2].url.query?.contains("referenced_tweets.id") == true)
    }

    func testPageLimitDoesNotAdvanceCheckpointPastUnseenPosts() async throws {
        let checkpoints = XSinceIDStore()
        let transport = XStubTransport(responses: [
            response(body: try fixture("x-recent-search-page-1.json"))
        ])
        let connector = XAPIConnector(
            configuration: XAPIConfiguration(
                authentication: .bearerToken("test-token"),
                recentSearchQueries: ["agent evaluation"]
            ),
            transport: transport,
            checkpoints: checkpoints,
            maximumPagesPerTarget: 1,
            now: { ISO8601DateFormatter().date(from: "2026-07-23T11:00:00Z")! }
        )

        let report = await connector.collectReport()
        let savedSinceID = await checkpoints.sinceID(for: "search:agent evaluation")
        let requestCount = await transport.requestCount()

        XCTAssertEqual(report.state, .delayed)
        XCTAssertNil(savedSinceID)
        XCTAssertEqual(requestCount, 1)
    }

    func testSetupRateLimitDelayedAndUnavailableStatesAreExplicitAndSecretSafe() async throws {
        let missing = XAPIConnector(configuration: XAPIConfiguration(authentication: nil))
        let missingReport = await missing.collectReport()
        XCTAssertEqual(missingReport.state, .setupRequired)
        XCTAssertEqual(missingReport.collection.state, .unavailable(statusCode: nil))

        let limited = XAPIConnector(
            configuration: XAPIConfiguration(
                authentication: .bearerToken("never-print-me"),
                recentSearchQueries: ["AI"]
            ),
            transport: XStubTransport(responses: [
                HTTPResponse(
                    statusCode: 429,
                    headers: [
                        "x-rate-limit-limit": "10",
                        "x-rate-limit-remaining": "0",
                        "x-rate-limit-reset": "1785000600"
                    ],
                    body: Data()
                )
            ]),
            now: { Date(timeIntervalSince1970: 1_785_000_000) }
        )
        let limitedReport = await limited.collectReport()
        XCTAssertEqual(limitedReport.state, .rateLimited(retryAfter: 600))
        XCTAssertFalse(limitedReport.collection.evidence.contains("never-print-me"))

        let unavailable = XAPIConnector(
            configuration: XAPIConfiguration(
                authentication: .bearerToken("never-print-me"),
                recentSearchQueries: ["AI"]
            ),
            transport: XStubTransport(responses: [
                HTTPResponse(statusCode: 402, headers: [:], body: Data())
            ])
        )
        let unavailableReport = await unavailable.collectReport()
        XCTAssertEqual(unavailableReport.state, .unavailable(statusCode: 402))

        let semanticError = XAPIConnector(
            configuration: XAPIConfiguration(
                authentication: .bearerToken("never-print-me"),
                recentSearchQueries: ["invalid operator"]
            ),
            transport: XStubTransport(responses: [
                response(body: Data(#"{"errors":[{"title":"Invalid Request","detail":"The query is invalid."}],"meta":{"result_count":0}}"#.utf8))
            ])
        )
        let semanticErrorReport = await semanticError.collectReport()
        XCTAssertEqual(semanticErrorReport.state, .unavailable(statusCode: nil))
        XCTAssertFalse(semanticErrorReport.collection.evidence.contains("The query is invalid."))

        let delayedBody = Data(#"{"data":[{"id":"1800000000000000000","text":"Old post","author_id":"1","created_at":"2026-07-01T00:00:00.000Z","lang":"en","public_metrics":{"retweet_count":0,"reply_count":0,"like_count":0,"quote_count":0}}],"includes":{"users":[{"id":"1","username":"old_source","name":"Old Source"}]},"meta":{"newest_id":"1800000000000000000","result_count":1}}"#.utf8)
        let delayed = XAPIConnector(
            configuration: XAPIConfiguration(
                authentication: .bearerToken("token"),
                recentSearchQueries: ["AI"]
            ),
            transport: XStubTransport(responses: [response(body: delayedBody)]),
            delayedAfter: 60,
            now: { ISO8601DateFormatter().date(from: "2026-07-24T00:00:00Z")! }
        )
        let delayedReport = await delayed.collectReport()
        XCTAssertEqual(delayedReport.state, .delayed)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil)))
    }

    private func response(body: Data, remaining: String = "20") -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: [
                "x-rate-limit-limit": "30",
                "x-rate-limit-remaining": remaining,
                "x-rate-limit-reset": "1785000600"
            ],
            body: body
        )
    }
}

private actor XStubTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private var requests: [HTTPRequest] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }

    func recordedRequests() -> [HTTPRequest] {
        requests
    }

    func requestCount() -> Int {
        requests.count
    }
}
