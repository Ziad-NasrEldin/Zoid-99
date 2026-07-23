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
}
