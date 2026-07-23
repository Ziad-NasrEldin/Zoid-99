import Foundation
import XCTest
@testable import Zoid99

final class LiveYouTubeDataTests: XCTestCase {
    func testConfiguredReferenceChannelReturnsRealRecentVideos() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ZOID99_RUN_LIVE_YOUTUBE"] == "1" else {
            throw XCTSkip("Set ZOID99_RUN_LIVE_YOUTUBE=1 for opt-in YouTube validation.")
        }
        guard let apiKey = environment["ZOID99_YOUTUBE_API_KEY"], !apiKey.isEmpty,
              let channelID = environment["ZOID99_YOUTUBE_CHANNEL_ID"], !channelID.isEmpty else {
            let connector = YouTubeDataConnector(
                credentialProvider: StaticYouTubeCredentialProvider(nil)
            )
            let result = await connector.collectRecentVideos(
                channel: .reference(id: "setup-required", language: "en", country: "US")
            )
            XCTAssertEqual(result.state, .setupRequired)
            throw XCTSkip("Setup required: provide API key and reference channel ID environment variables.")
        }

        let language = environment["ZOID99_YOUTUBE_LANGUAGE"] ?? "en"
        let country = environment["ZOID99_YOUTUBE_COUNTRY"] ?? "US"
        let connector = YouTubeDataConnector(
            credentialProvider: StaticYouTubeCredentialProvider(.apiKey(apiKey)),
            limits: .init(maxPagesPerRequest: 1, maxItemsPerPage: 5, maxQuotaUnitsPerRun: 2)
        )
        let result = await connector.collectRecentVideos(
            channel: .reference(id: channelID, language: language, country: country)
        )

        XCTAssertEqual(result.state, .available, result.evidence)
        XCTAssertFalse(result.items.isEmpty, result.evidence)
        XCTAssertTrue(result.items.allSatisfy { $0.dataTruth == .live })
        XCTAssertTrue(result.items.allSatisfy { $0.url.host == "www.youtube.com" })
        print(
            "LIVE_YOUTUBE_PROOF channelConfigured=true items=\(result.items.count) "
                + "quotaUnits=\(result.quotaUnitsUsed) collectedAt=\(result.collectedAt.ISO8601Format())"
        )
    }
}
