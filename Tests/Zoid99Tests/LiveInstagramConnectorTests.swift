import XCTest
@testable import Zoid99

final class LiveInstagramConnectorTests: XCTestCase {
    func testAuthorizedProfessionalAccountConnection() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ZOID99_RUN_LIVE_INSTAGRAM"] == "1" else {
            throw XCTSkip("Set ZOID99_RUN_LIVE_INSTAGRAM=1 for opt-in live validation.")
        }
        guard let token = environment["ZOID99_INSTAGRAM_ACCESS_TOKEN"],
              let version = environment["ZOID99_INSTAGRAM_GRAPH_VERSION"] else {
            throw XCTSkip(
                "Set ZOID99_INSTAGRAM_ACCESS_TOKEN and ZOID99_INSTAGRAM_GRAPH_VERSION in secure process configuration."
            )
        }

        let connector = InstagramGraphConnector(
            configuration: InstagramConnectorConfiguration(
                graphAPIVersion: version,
                accessToken: InstagramAccessToken(token),
                selectedProfessionalAccountID: environment["ZOID99_INSTAGRAM_ACCOUNT_ID"]
            )
        )
        let result = await connector.collect()

        XCTAssertEqual(result.state, .available, result.evidence.joined(separator: " "))
        XCTAssertFalse(result.accounts.isEmpty)
        XCTAssertTrue(result.items.allSatisfy { $0.dataTruth == .live })
        XCTAssertTrue(result.items.allSatisfy { $0.url.scheme == "https" })
        print(
            "LIVE_INSTAGRAM_PROOF accounts=\(result.accounts.count) "
                + "items=\(result.items.count) collectedAt=\(result.collectedAt.ISO8601Format())"
        )
    }
}
