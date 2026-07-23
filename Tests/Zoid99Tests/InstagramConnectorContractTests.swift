import Foundation
import XCTest
@testable import Zoid99

final class InstagramConnectorContractTests: XCTestCase {
    func testSetupRequiredDoesNotMakeNetworkRequest() async {
        let transport = InstagramStubTransport(responses: [])
        let connector = InstagramGraphConnector(
            configuration: configuration(token: nil),
            transport: transport
        )

        let result = await connector.collect()

        guard case .setupRequired = result.state else {
            return XCTFail("Expected an explicit setup-required state.")
        }
        XCTAssertTrue(result.items.isEmpty)
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testDiscoversConnectedProfessionalAccountAndCollectsOwnedMediaCommentsAndReferences() async throws {
        let transport = InstagramStubTransport(responses: [
            .init(statusCode: 200, headers: [:], body: try fixture("instagram-accounts.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("instagram-accounts-page-2.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("instagram-media.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("instagram-comments.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("instagram-comments.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("instagram-reference.json"))
        ])
        let connector = InstagramGraphConnector(
            configuration: configuration(
                references: ["@reference_creator"],
                localeEvidence: [
                    "zoid_research": .init(
                        language: "en",
                        country: "US",
                        evidence: "Account owner confirmed profile locale on 2026-07-23."
                    ),
                    "arabic_viewer": .init(
                        language: "ar",
                        country: "EG",
                        evidence: "User-supplied watchlist evidence."
                    )
                ]
            ),
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_784_812_800) }
        )

        let result = await connector.collect()
        let requests = await transport.requests

        XCTAssertEqual(result.state, .available)
        XCTAssertEqual(result.accounts.count, 1)
        XCTAssertEqual(result.accounts[0].instagramAccountID, "ig-200")
        XCTAssertEqual(result.items.filter { $0.group == .instagram }.count, 3)
        XCTAssertEqual(result.items.filter { $0.group == .comments }.count, 1)
        let reel = try XCTUnwrap(result.items.first { $0.externalID == "media-reel-1" })
        XCTAssertEqual(reel.language, "en")
        XCTAssertEqual(reel.country, "US")
        XCTAssertTrue(reel.summary.contains("product=REELS"))
        XCTAssertTrue(reel.summary.contains("duration=42.5s"))
        XCTAssertEqual(reel.engagement, 14)
        XCTAssertEqual(reel.verification, .confirmed)
        let reference = try XCTUnwrap(result.items.first { $0.externalID == "reference-reel-1" })
        XCTAssertFalse(reference.isOriginalSource)
        XCTAssertEqual(reference.verification, .unverified)
        XCTAssertEqual(reference.language, "und")
        XCTAssertEqual(reference.country, "Unknown")
        XCTAssertTrue(requests.allSatisfy { $0.url.query?.contains("access_token") != true })
        XCTAssertTrue(requests.allSatisfy { $0.headers["Authorization"] == "Bearer test-token" })
        XCTAssertEqual(requests[1].url.queryParameters["after"], "accounts-next")
        XCTAssertFalse(requests[1].url.absoluteString.contains("must-not-be-followed"))
    }

    func testIncrementalCursorExcludesOldMediaAndOldComments() async throws {
        let transport = InstagramStubTransport(responses: [
            .init(statusCode: 200, headers: [:], body: try fixture("instagram-accounts.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("instagram-accounts-page-2.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("instagram-media.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("instagram-comments.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("instagram-comments.json"))
        ])
        let connector = InstagramGraphConnector(
            configuration: configuration(),
            transport: transport
        )
        let result = await connector.collect(
            after: InstagramIncrementalCursor(
                newestMediaTimestamp: Date(timeIntervalSince1970: 1_784_812_800),
                newestCommentTimestampByMediaID: [
                    "media-reel-1": Date(timeIntervalSince1970: 1_784_816_400),
                    "media-carousel-2": Date(timeIntervalSince1970: 1_784_816_400)
                ],
                ownedMediaIDs: ["media-reel-1", "media-carousel-2"],
                ownedMediaPermalinksByID: [
                    "media-reel-1": URL(string: "https://www.instagram.com/reel/example/")!,
                    "media-carousel-2": URL(string: "https://www.instagram.com/p/example/")!
                ]
            )
        )

        XCTAssertEqual(result.state, .available)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.cursor.ownedMediaIDs, ["media-carousel-2", "media-reel-1"])
    }

    func testRateLimitStopsCollectionAndUsesRetryAfterWithoutLeakingToken() async throws {
        let graphError = Data(#"{"error":{"message":"Application request limit reached test-token","code":4}}"#.utf8)
        let connector = InstagramGraphConnector(
            configuration: configuration(),
            transport: InstagramStubTransport(responses: [
                .init(statusCode: 400, headers: ["Retry-After": "120"], body: graphError)
            ])
        )

        let result = await connector.collect()

        XCTAssertEqual(result.state, .rateLimited(retryAfter: 120))
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertFalse(result.evidence.joined().contains("test-token"))
    }

    func testMalformedResponseNeverInventsSourceItems() async {
        let connector = InstagramGraphConnector(
            configuration: configuration(),
            transport: InstagramStubTransport(responses: [
                .init(statusCode: 200, headers: [:], body: Data(#"{"unexpected":true}"#.utf8))
            ])
        )

        let result = await connector.collect()

        guard case .unavailable = result.state else {
            return XCTFail("Expected an explicit unavailable state.")
        }
        XCTAssertTrue(result.items.isEmpty)
    }

    func testUnsupportedNonHTTPSGraphEndpointMakesNoRequest() async {
        let transport = InstagramStubTransport(responses: [])
        let connector = InstagramGraphConnector(
            configuration: configuration(),
            transport: transport,
            graphRoot: URL(string: "http://graph.facebook.com")!
        )

        let result = await connector.collect()

        guard case .unsupported = result.state else {
            return XCTFail("Expected an explicit unsupported state.")
        }
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    private func configuration(
        token: InstagramAccessToken? = InstagramAccessToken("test-token"),
        references: [String] = [],
        localeEvidence: [String: InstagramLocaleEvidence] = [:]
    ) -> InstagramConnectorConfiguration {
        InstagramConnectorConfiguration(
            graphAPIVersion: "v25.0",
            accessToken: token,
            referenceUsernames: references,
            localeEvidenceByUsername: localeEvidence
        )
    }

    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: nil)
        return try Data(contentsOf: XCTUnwrap(url))
    }
}

private actor InstagramStubTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private(set) var requests: [HTTPRequest] = []

    init(responses: [HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }

    func requestCount() -> Int {
        requests.count
    }
}

private extension URL {
    var queryParameters: [String: String] {
        Dictionary(
            uniqueKeysWithValues: (URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .map { ($0.name, $0.value ?? "") }
        )
    }
}
