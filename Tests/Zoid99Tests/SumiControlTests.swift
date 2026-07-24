import SwiftUI
import XCTest
@testable import Zoid99

final class SumiControlTests: XCTestCase {
    func testSelectionCursorMovesWithinMenuBounds() {
        XCTAssertEqual(SumiSelectionCursor.movedIndex(current: 1, count: 3, direction: .down), 2)
        XCTAssertEqual(SumiSelectionCursor.movedIndex(current: 2, count: 3, direction: .down), 2)
        XCTAssertEqual(SumiSelectionCursor.movedIndex(current: 1, count: 3, direction: .up), 0)
        XCTAssertEqual(SumiSelectionCursor.movedIndex(current: 0, count: 3, direction: .up), 0)
    }

    func testSelectionCursorSupportsRTLArrowNavigationWithoutOverflow() {
        XCTAssertEqual(SumiSelectionCursor.movedIndex(current: 1, count: 3, direction: .left), 0)
        XCTAssertEqual(SumiSelectionCursor.movedIndex(current: 1, count: 3, direction: .right), 2)
        XCTAssertEqual(SumiSelectionCursor.movedIndex(current: 0, count: 0, direction: .right), 0)
    }
}
