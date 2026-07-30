import Foundation
import XCTest
@testable import Zoid99

final class ContractCompatibilityTests: XCTestCase {
    func testBootstrapFixtureDecodesExistingMacModels() throws {
        let fixture = try decode(BootstrapFixture.self, named: "bootstrap")

        XCTAssertEqual(fixture.sourceHealth.first?.group, .official)
        XCTAssertEqual(fixture.opportunities.first?.verification, .confirmed)
        XCTAssertEqual(fixture.watchlist.first?.kind, .topic)
        XCTAssertEqual(fixture.notifications.first?.delivery, .digest)
        XCTAssertEqual(fixture.notifications.first?.deliveryState, .awaitingPermission)
    }

    func testIndividualContractFixturesDecode() throws {
        let opportunity = try decode(Opportunity.self, named: "opportunity")
        let watchlist = try decode([WatchlistEntry].self, named: "watchlist")
        let notification = try decode(NotificationRecord.self, named: "notification")
        let sourceHealth = try decode(SourceHealth.self, named: "source-health")
        let connection = try decode(ConnectionFixture.self, named: "connection")

        XCTAssertEqual(opportunity.id.uuidString, "10000000-0000-4000-8000-000000000099")
        XCTAssertEqual(watchlist[0].value, "AI agents")
        XCTAssertFalse(notification.isRead)
        XCTAssertEqual(sourceHealth.dataTruth, .live)
        XCTAssertEqual(connection.provider, "google-trends")
        XCTAssertEqual(connection.state, "Cached")
        XCTAssertNil(connection.retryAt)
    }

    private func decode<T: Decodable>(_ type: T.Type, named name: String) throws -> T {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
}

private struct BootstrapFixture: Decodable {
    let sourceHealth: [SourceHealth]
    let opportunities: [Opportunity]
    let watchlist: [WatchlistEntry]
    let notifications: [NotificationRecord]
}

private struct ConnectionFixture: Decodable {
    let provider: String
    let state: String
    let lastActivity: Date?
    let evidence: String
    let repairAction: String
    let retryAt: Date?
}
