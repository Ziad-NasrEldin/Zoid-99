import XCTest
@testable import Zoid99

final class AppWindowMetricsTests: XCTestCase {
    func testMinimumWindowKeepsSidebarAndCompactDetailUsable() {
        XCTAssertEqual(AppWindowMetrics.minimumWidth, 980)
        XCTAssertEqual(AppWindowMetrics.minimumHeight, 680)
        XCTAssertGreaterThanOrEqual(AppWindowMetrics.minimumWidth - 240 - 60, 680)
    }
}
