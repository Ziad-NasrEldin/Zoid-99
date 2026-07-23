import Foundation
import XCTest
@testable import Zoid99

final class LiveXAPIConnectorTests: XCTestCase {
    func testOptInOfficialXAPIConnection() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ZOID99_RUN_LIVE_X"] == "1" else {
            throw XCTSkip("Set ZOID99_RUN_LIVE_X=1 to enable official X API validation.")
        }
        guard let query = environment["ZOID99_X_LIVE_QUERY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            throw XCTSkip("Set ZOID99_X_LIVE_QUERY to a deliberate, low-volume recent-search query.")
        }

        let configuration = XAPIConfiguration.fromEnvironment(
            environment,
            recentSearchQueries: [query]
        )
        let connector = XAPIConnector(
            configuration: configuration,
            maximumPagesPerTarget: 1
        )

        let report = await connector.collectReport()

        guard report.state != .setupRequired else {
            XCTFail("Set ZOID99_X_BEARER_TOKEN or ZOID99_X_OAUTH2_ACCESS_TOKEN.")
            return
        }
        XCTAssertTrue(
            report.state == .available || report.state == .delayed,
            "X API validation state: \(report.state). \(report.collection.evidence)"
        )
        XCTAssertFalse(report.collection.items.isEmpty, report.collection.evidence)
        XCTAssertTrue(report.collection.items.allSatisfy { $0.group == .x })
        XCTAssertTrue(report.collection.items.allSatisfy { $0.dataTruth == .live })
        print(
            "LIVE_X_PROOF endpoint=https://api.x.com/2/tweets/search/recent "
                + "collectedAt=\(report.collection.collectedAt.ISO8601Format()) "
                + "items=\(report.collection.items.count) state=\(report.state)"
        )
    }
}
