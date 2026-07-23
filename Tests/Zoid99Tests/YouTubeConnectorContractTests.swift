import Foundation
import XCTest
@testable import Zoid99

final class YouTubeConnectorContractTests: XCTestCase {
    func testReferenceChannelCollectsRecentUploadsAcrossBoundedPages() async throws {
        let transport = YouTubeStubTransport(responses: [
            .init(statusCode: 200, headers: [:], body: try fixture("youtube-channel.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("youtube-playlist-page-1.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("youtube-playlist-page-2.json"))
        ])
        let connector = YouTubeDataConnector(
            credentialProvider: StaticYouTubeCredentialProvider(.apiKey("secret-api-key")),
            transport: transport,
            limits: .init(maxPagesPerRequest: 2, maxItemsPerPage: 25, maxQuotaUnitsPerRun: 10),
            now: { Date(timeIntervalSince1970: 1_784_813_400) }
        )

        let result = await connector.collectRecentVideos(
            channel: .reference(id: "UC_REFERENCE", language: "en", country: "US")
        )
        let requests = await transport.requests

        XCTAssertEqual(result.state, .available)
        XCTAssertEqual(result.items.map(\.externalID), ["video-1", "video-2"])
        XCTAssertEqual(result.items.first?.group, .youtube)
        XCTAssertEqual(result.items.first?.author, "Reference AI")
        XCTAssertEqual(result.items.first?.language, "en")
        XCTAssertEqual(result.items.first?.country, "US")
        XCTAssertEqual(result.items.first?.url.absoluteString, "https://www.youtube.com/watch?v=video-1")
        XCTAssertEqual(result.quotaUnitsUsed, 3)
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy { $0.url.absoluteString.contains("secret-api-key") })
        XCTAssertFalse(result.evidence.contains("secret-api-key"))
        XCTAssertTrue(requests[2].url.absoluteString.contains("pageToken=PAGE_2"))
    }

    func testSearchUsesCountryLanguageAndMapsCanonicalVideoMetadata() async throws {
        let transport = YouTubeStubTransport(responses: [
            .init(statusCode: 200, headers: [:], body: try fixture("youtube-search.json"))
        ])
        let connector = YouTubeDataConnector(
            credentialProvider: StaticYouTubeCredentialProvider(.apiKey("key")),
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_784_813_400) }
        )

        let result = await connector.search(
            .init(query: "open model", language: "ar", country: "EG", publishedAfter: nil)
        )
        let searchRequests = await transport.requests
        let request = try XCTUnwrap(searchRequests.first)

        XCTAssertEqual(result.items.first?.externalID, "search-video")
        XCTAssertEqual(result.items.first?.language, "ar")
        XCTAssertEqual(result.items.first?.country, "EG")
        XCTAssertTrue(request.url.absoluteString.contains("relevanceLanguage=ar"))
        XCTAssertTrue(request.url.absoluteString.contains("regionCode=EG"))
        XCTAssertEqual(result.quotaUnitsUsed, 1)
    }

    func testPublicCommentsFromOwnedOrReferenceVideosAcceptAPIKeyAndMapMetadata() async throws {
        let transport = YouTubeStubTransport(responses: [
            .init(statusCode: 200, headers: [:], body: try fixture("youtube-comments.json"))
        ])
        let connector = YouTubeDataConnector(
            credentialProvider: StaticYouTubeCredentialProvider(.apiKey("public-key")),
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_784_813_400) }
        )

        let result = await connector.collectComments(
            video: .init(
                id: "video-1",
                channelKind: .owned,
                channelTitle: "My Channel",
                language: "ar",
                country: "EG"
            )
        )
        let commentRequests = await transport.requests
        let request = try XCTUnwrap(commentRequests.first)

        XCTAssertNil(request.headers["Authorization"])
        XCTAssertTrue(request.url.absoluteString.contains("public-key"))
        XCTAssertEqual(result.items.first?.group, .comments)
        XCTAssertEqual(result.items.first?.externalID, "comment-1")
        XCTAssertEqual(result.items.first?.title, "هل يعمل هذا النموذج باللغة العربية؟")
        XCTAssertEqual(result.items.first?.engagement, 9)
        XCTAssertEqual(result.items.first?.language, "ar")
        XCTAssertEqual(result.items.first?.country, "EG")
        XCTAssertEqual(
            result.items.first?.url.absoluteString,
            "https://www.youtube.com/watch?v=video-1&lc=comment-1"
        )
    }

    func testMissingCredentialAndQuotaErrorsAreExplicitAndNeverMakeRequests() async {
        let missingTransport = YouTubeStubTransport(responses: [])
        let missing = YouTubeDataConnector(
            credentialProvider: StaticYouTubeCredentialProvider(nil),
            transport: missingTransport
        )

        let missingResult = await missing.search(.init(query: "AI", language: "en", country: "US"))

        XCTAssertEqual(missingResult.state, .setupRequired)
        XCTAssertTrue(missingResult.items.isEmpty)
        let missingRequests = await missingTransport.requests
        XCTAssertEqual(missingRequests.count, 0)
        XCTAssertEqual(missingResult.evidence, "YouTube Data API credentials are required.")

        let quotaTransport = YouTubeStubTransport(responses: [
            .init(
                statusCode: 403,
                headers: [:],
                body: Data(#"{"error":{"errors":[{"reason":"quotaExceeded"}],"message":"Quota exceeded"}}"#.utf8)
            )
        ])
        let quota = YouTubeDataConnector(
            credentialProvider: StaticYouTubeCredentialProvider(.apiKey("private")),
            transport: quotaTransport
        )

        let quotaResult = await quota.search(.init(query: "AI", language: "en", country: "US"))

        XCTAssertEqual(quotaResult.state, .rateLimited(retryAfter: nil))
        XCTAssertFalse(quotaResult.evidence.contains("private"))

        let ownedTransport = YouTubeStubTransport(responses: [])
        let owned = YouTubeDataConnector(
            credentialProvider: StaticYouTubeCredentialProvider(.apiKey("public")),
            transport: ownedTransport
        )
        let ownedResult = await owned.collectRecentVideos(channel: .owned(language: "ar", country: "EG"))
        XCTAssertEqual(ownedResult.state, .setupRequired)
        XCTAssertEqual(ownedResult.evidence, "OAuth authorization is required for the owned YouTube channel.")
        let ownedRequestCount = await ownedTransport.requestCount()
        XCTAssertEqual(ownedRequestCount, 0)
    }

    func testQuotaBudgetStopsPaginationBeforeAnotherRequest() async throws {
        let transport = YouTubeStubTransport(responses: [
            .init(statusCode: 200, headers: [:], body: try fixture("youtube-channel.json")),
            .init(statusCode: 200, headers: [:], body: try fixture("youtube-playlist-page-1.json"))
        ])
        let connector = YouTubeDataConnector(
            credentialProvider: StaticYouTubeCredentialProvider(.apiKey("key")),
            transport: transport,
            limits: .init(maxPagesPerRequest: 4, maxItemsPerPage: 25, maxQuotaUnitsPerRun: 2)
        )

        let result = await connector.collectRecentVideos(
            channel: .reference(id: "UC_REFERENCE", language: "en", country: "US")
        )

        XCTAssertEqual(result.state, .rateLimited(retryAfter: nil))
        XCTAssertEqual(result.items.map(\.externalID), ["video-1"])
        XCTAssertEqual(result.quotaUnitsUsed, 2)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil)))
    }
}

private actor YouTubeStubTransport: HTTPTransport {
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
