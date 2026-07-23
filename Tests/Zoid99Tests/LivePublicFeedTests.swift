import XCTest
@testable import Zoid99

final class LivePublicFeedTests: XCTestCase {
    func testVerifiedStarterCatalogCollectsRealPublishedItems() async throws {
        guard ProcessInfo.processInfo.environment["ZOID99_RUN_LIVE_FEEDS"] == "1" else {
            throw XCTSkip("Set ZOID99_RUN_LIVE_FEEDS=1 for credential-free network validation.")
        }

        for source in OfficialAISourceCatalog.starter {
            let connector = PublicFeedConnector(source: source)
            let result = await connector.collect()

            XCTAssertFalse(result.items.isEmpty, "\(source.name): \(result.evidence)")
            XCTAssertTrue(
                result.state == .available || result.state == .delayed,
                "\(source.name): \(result.state)"
            )
            XCTAssertTrue(result.items.allSatisfy { $0.group == .official })
            XCTAssertTrue(result.items.allSatisfy { $0.isOriginalSource })
            print(
                "LIVE_FEED_PROOF source=\(source.name) endpoint=\(source.endpoint.absoluteString) "
                    + "collectedAt=\(result.collectedAt.ISO8601Format()) items=\(result.items.count)"
            )
        }
    }

    func testRealOfficialFeedReachesBackendAndMacOSBootstrap() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ZOID99_RUN_LIVE_SPINE"] == "1" else {
            throw XCTSkip("Set ZOID99_RUN_LIVE_SPINE=1 with ZOID99_API_BASE_URL and ZOID99_API_TOKEN.")
        }
        let baseURL = try XCTUnwrap(environment["ZOID99_API_BASE_URL"].flatMap(URL.init(string:)))
        let token = try XCTUnwrap(environment["ZOID99_API_TOKEN"])
        let sync = BackendResearchSync(baseURL: baseURL, token: token)

        let results = await sync.synchronize()

        let official = try XCTUnwrap(results.first { $0.group == .official })
        XCTAssertEqual(official.state, .connected, official.evidence)
        XCTAssertEqual(official.dataTruth, .live, official.evidence)
        let firstItem = try XCTUnwrap(official.items.first, official.evidence)
        XCTAssertTrue(official.items.allSatisfy { $0.url.scheme == "https" && $0.isOriginalSource })
        print(
            "LIVE_SPINE_PROOF endpoint=\(baseURL.absoluteString) "
                + "items=\(official.items.count) first=\(firstItem.url.absoluteString) "
                + "collectedAt=\(official.collectedAt.ISO8601Format())"
        )
    }
}
