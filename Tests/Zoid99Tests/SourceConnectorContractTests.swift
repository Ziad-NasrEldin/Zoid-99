import Foundation
import XCTest
@testable import Zoid99

final class SourceConnectorContractTests: XCTestCase {
    func testBackendDispositionSyncUsesAuthenticatedPatchAndPullsCanonicalState() async throws {
        let opportunityID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        let mutationID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
        let changedAt = Date(timeIntervalSince1970: 1_785_000_000)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let applied = OpportunityDispositionState(
            opportunityID: opportunityID,
            disposition: .dismissed,
            changedAt: changedAt,
            mutationID: mutationID,
            outcome: .applied
        )
        let canonical = """
        [{
          "id":"\(opportunityID.uuidString)",
          "disposition":"dismissed",
          "dispositionUpdatedAt":"\(ISO8601DateFormatter().string(from: changedAt))",
          "dispositionMutationID":"\(mutationID.uuidString)"
        }]
        """.data(using: .utf8)!
        let transport = StubHTTPTransport(responses: [
            .response(status: 200, headers: [:], body: try encoder.encode(applied)),
            .response(status: 200, headers: [:], body: canonical),
        ])
        let sync = BackendOpportunityDispositionSync(
            baseURL: URL(string: "https://zoid99.example")!,
            apiToken: String(repeating: "a", count: 32),
            transport: transport
        )

        let result = await sync.reconcile([
            OpportunityDispositionMutation(
                id: mutationID,
                opportunityID: opportunityID,
                disposition: .dismissed,
                changedAt: changedAt
            )
        ])

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.acknowledgedMutationIDs, [mutationID])
        XCTAssertEqual(result.states.last?.disposition, .dismissed)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map(\.method), ["PATCH", "GET"])
        XCTAssertEqual(requests[0].headers["Authorization"], "Bearer \(String(repeating: "a", count: 32))")
        XCTAssertTrue(try XCTUnwrap(String(data: XCTUnwrap(requests[0].body), encoding: .utf8))
            .contains("\"mutationID\":\"\(mutationID.uuidString)\""))
    }

    func testRSS20MapsIntoNormalizedSourceItems() async throws {
        let transport = StubHTTPTransport(
            responses: [.response(status: 200, headers: [
                "ETag": "\"rss-v1\"",
                "Last-Modified": "Tue, 21 Jul 2026 15:00:00 GMT"
            ], body: try fixture("rss20.xml"))]
        )
        let connector = PublicFeedConnector(
            source: OfficialSource(
                id: "example-product",
                name: "Example Product",
                kind: .rss,
                endpoint: URL(string: "https://example.com/rss.xml")!,
                homepage: URL(string: "https://example.com")!,
                language: "en",
                country: "US"
            ),
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_784_768_400) }
        )

        let result = await connector.collect()

        XCTAssertEqual(result.state, .available)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].group, .official)
        XCTAssertEqual(result.items[0].externalID, "release-42")
        XCTAssertEqual(result.items[0].title, "Model 42 is available")
        XCTAssertEqual(result.items[0].summary, "Availability and safety details.")
        XCTAssertEqual(result.items[0].author, "Research Team")
        XCTAssertEqual(result.items[0].url.absoluteString, "https://example.com/news/model-42")
        XCTAssertEqual(result.items[0].publishedAt, Date(timeIntervalSince1970: 1_784_644_200))
        XCTAssertEqual(result.items[0].language, "en-US")
        XCTAssertEqual(result.items[0].country, "US")
        XCTAssertTrue(result.items[0].topicKey.hasPrefix("unclustered-"))
        XCTAssertTrue(result.items[0].isOriginalSource)
        XCTAssertEqual(result.validators?.etag, "\"rss-v1\"")
        let pipeline = ResearchPipeline().run(
            items: result.items,
            now: Date(timeIntervalSince1970: 1_784_768_400)
        )
        XCTAssertEqual(pipeline.normalizedItems, result.items)
        XCTAssertEqual(pipeline.opportunities.first?.originalSource, result.items[0])
    }

    func testAtomMapsOriginalAuthorTimestampAndMetadata() async throws {
        let connector = connector(
            kind: .atom,
            body: try fixture("atom.xml"),
            now: Date(timeIntervalSince1970: 1_784_764_800)
        )

        let result = await connector.collect()

        XCTAssertEqual(result.state, .available)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].externalID, "tag:example.org,2026:paper-7")
        XCTAssertEqual(result.items[0].author, "Example Research, Second Author")
        XCTAssertEqual(result.items[0].url.absoluteString, "https://research.example.org/papers/agent-evaluation")
        XCTAssertEqual(result.items[0].publishedAt, Date(timeIntervalSince1970: 1_784_708_130))
        XCTAssertEqual(result.items[0].language, "en")
        XCTAssertEqual(result.items[0].country, "US")
    }

    func testGitHubReleasesUsesPublicAPIAndExcludesDrafts() async throws {
        let connector = connector(
            kind: .githubReleases,
            body: try fixture("github-releases.json"),
            now: Date(timeIntervalSince1970: 1_784_764_800)
        )

        let result = await connector.collect()

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items[0].externalID, "91002")
        XCTAssertEqual(result.items[0].title, "Version 2.1.0")
        XCTAssertEqual(
            result.items[0].summary,
            """
            ## What's changed

            - Added a supported inference endpoint.
            - Fixed source formatting for release notes.
            """
        )
        XCTAssertEqual(result.items[0].author, "example-ai")
        XCTAssertEqual(result.items[0].url.absoluteString, "https://github.com/example/ai-runtime/releases/tag/v2.1.0")
        XCTAssertEqual(result.items[0].publishedAt, Date(timeIntervalSince1970: 1_784_546_553))
    }

    func testConditionalRequestUsesCachedPayloadOnNotModified() async throws {
        let transport = StubHTTPTransport(responses: [
            .response(status: 200, headers: [
                "ETag": "\"rss-v1\"",
                "Last-Modified": "Tue, 21 Jul 2026 15:00:00 GMT"
            ], body: try fixture("rss20.xml")),
            .response(status: 304, headers: [:], body: Data())
        ])
        let connector = makeConnector(kind: .rss, transport: transport)

        let first = await connector.collect()
        let second = await connector.collect()
        let requests = await transport.recordedRequests()

        XCTAssertEqual(first.state, .available)
        XCTAssertEqual(second.state, .notModified)
        XCTAssertEqual(second.items, first.items)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].headers["If-None-Match"], "\"rss-v1\"")
        XCTAssertEqual(requests[1].headers["If-Modified-Since"], "Tue, 21 Jul 2026 15:00:00 GMT")
        XCTAssertEqual(requests[1].timeout, 15)
    }

    func testRateLimitUnavailableAndDelayedStatesAreExplicit() async throws {
        let rateLimited = makeConnector(
            kind: .rss,
            transport: StubHTTPTransport(responses: [
                .response(status: 429, headers: ["Retry-After": "120"], body: Data())
            ])
        )
        let unavailable = makeConnector(
            kind: .rss,
            transport: StubHTTPTransport(responses: [
                .response(status: 503, headers: [:], body: Data())
            ])
        )
        let githubRateLimited = makeConnector(
            kind: .githubReleases,
            transport: StubHTTPTransport(responses: [
                .response(status: 403, headers: [
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": "1784768520"
                ], body: Data())
            ]),
            now: Date(timeIntervalSince1970: 1_784_768_400)
        )
        let delayed = PublicFeedConnector(
            source: source(kind: .rss),
            transport: StubHTTPTransport(responses: [
                .response(status: 200, headers: [:], body: try fixture("rss20.xml"))
            ]),
            delayedAfter: 60,
            now: { Date(timeIntervalSince1970: 1_784_768_400) }
        )

        let rateLimitedResult = await rateLimited.collect()
        let unavailableResult = await unavailable.collect()
        let githubRateLimitedResult = await githubRateLimited.collect()
        let delayedResult = await delayed.collect()
        XCTAssertEqual(rateLimitedResult.state, .rateLimited(retryAfter: 120))
        XCTAssertEqual(unavailableResult.state, .unavailable(statusCode: 503))
        XCTAssertEqual(githubRateLimitedResult.state, .rateLimited(retryAfter: 120))
        XCTAssertEqual(delayedResult.state, .delayed)
    }

    func testRetryPolicyIsBoundedAndRetriesOnlyTransientFailures() async throws {
        let recoveringBase = StubHTTPTransport(responses: [
            .failure(URLError(.timedOut)),
            .response(status: 200, headers: [:], body: try fixture("rss20.xml"))
        ])
        let recovering = RetryingHTTPTransport(
            base: recoveringBase,
            maximumAttempts: 3,
            sleeper: { _ in }
        )

        let recovered = try await recovering.send(HTTPRequest(url: source(kind: .rss).endpoint))
        let recoveringCount = await recoveringBase.requestCount()

        XCTAssertEqual(recovered.statusCode, 200)
        XCTAssertEqual(recoveringCount, 2)

        let failingBase = StubHTTPTransport(responses: [
            .failure(URLError(.timedOut)),
            .failure(URLError(.networkConnectionLost)),
            .failure(URLError(.cannotConnectToHost))
        ])
        let bounded = RetryingHTTPTransport(base: failingBase, maximumAttempts: 9, sleeper: { _ in })
        do {
            _ = try await bounded.send(HTTPRequest(url: source(kind: .rss).endpoint))
            XCTFail("Expected the bounded retry policy to surface the final failure.")
        } catch {
            let failingCount = await failingBase.requestCount()
            XCTAssertEqual(failingCount, 3)
        }
    }

    func testMalformedResponseNeverInventsItems() async {
        let connector = connector(kind: .rss, body: Data("<rss><broken>".utf8))

        let result = await connector.collect()

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.state, .unavailable(statusCode: nil))
    }

    func testOfficialFeedCollectionIsBoundedToThirtyNewestItems() async {
        let records = (1...35).map { index in
            """
            <item><guid>\(index)</guid><title>Release \(index)</title>
            <link>https://example.com/releases/\(index)</link>
            <pubDate>Thu, \(String(format: "%02d", min(index, 28))) Jul 2026 08:00:00 GMT</pubDate></item>
            """
        }.joined()
        let xml = Data("<rss><channel>\(records)</channel></rss>".utf8)

        let result = await connector(kind: .rss, body: xml).collect()

        XCTAssertEqual(result.items.count, 30)
        XCTAssertTrue(result.items.allSatisfy { !["1", "2", "3", "4", "5"].contains($0.externalID) })
    }

    func testStarterCatalogIncludesCredentialFreeOfficialAISources() {
        let sources = Dictionary(uniqueKeysWithValues: OfficialAISourceCatalog.starter.map { ($0.id, $0) })

        XCTAssertEqual(Set(sources.keys), [
            "openai-news",
            "huggingface-transformers-releases",
            "arxiv-cs-ai",
            "google-ai-news",
            "google-gemini-cli-releases",
            "anthropic-claude-code-releases",
        ])
        XCTAssertTrue(sources.values.allSatisfy { $0.endpoint.scheme == "https" })
        XCTAssertEqual(sources["google-ai-news"]?.kind, .rss)
        XCTAssertEqual(sources["google-gemini-cli-releases"]?.kind, .githubReleases)
        XCTAssertEqual(sources["anthropic-claude-code-releases"]?.kind, .githubReleases)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: nil)
        return try Data(contentsOf: XCTUnwrap(url))
    }

    private func connector(
        kind: OfficialSourceKind,
        body: Data,
        now: Date = Date(timeIntervalSince1970: 1_784_768_400)
    ) -> PublicFeedConnector {
        makeConnector(
            kind: kind,
            transport: StubHTTPTransport(responses: [
                .response(status: 200, headers: [:], body: body)
            ]),
            now: now
        )
    }

    private func makeConnector(
        kind: OfficialSourceKind,
        transport: any HTTPTransport,
        now: Date = Date(timeIntervalSince1970: 1_784_768_400)
    ) -> PublicFeedConnector {
        PublicFeedConnector(
            source: source(kind: kind),
            transport: transport,
            now: { now }
        )
    }

    private func source(kind: OfficialSourceKind) -> OfficialSource {
        OfficialSource(
            id: "example",
            name: "Example Official Source",
            kind: kind,
            endpoint: URL(string: kind == .githubReleases
                ? "https://api.github.com/repos/example/ai-runtime/releases"
                : "https://example.com/feed")!,
            homepage: URL(string: "https://example.com")!,
            language: "en",
            country: "US"
        )
    }
}

private actor StubHTTPTransport: HTTPTransport {
    enum Stub {
        case response(status: Int, headers: [String: String], body: Data)
        case failure(Error)
    }

    private var responses: [Stub]
    private(set) var requests: [HTTPRequest] = []

    init(responses: [Stub]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        switch responses.removeFirst() {
        case let .response(status, headers, body):
            return HTTPResponse(statusCode: status, headers: headers, body: body)
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [HTTPRequest] {
        requests
    }

    func requestCount() -> Int {
        requests.count
    }
}
