import SwiftUI
import XCTest
@testable import Zoid99

final class SumiControlTests: XCTestCase {
    func testOpportunityQuickActionsExposeCanonicalDispositionsAndAccessibilityMetadata() {
        XCTAssertEqual(OpportunityQuickAction.save.symbolName, "bookmark")
        XCTAssertEqual(OpportunityQuickAction.watch.symbolName, "eye")
        XCTAssertEqual(OpportunityQuickAction.dismiss.symbolName, "xmark")
        XCTAssertEqual(OpportunityQuickAction.mute.symbolName, "speaker.slash")
        XCTAssertEqual(OpportunityQuickAction.save.accessibilityLabel, "Save opportunity")
        XCTAssertEqual(OpportunityQuickAction.watch.accessibilityLabel, "Watch opportunity")
        XCTAssertEqual(OpportunityQuickAction.dismiss.accessibilityLabel, "Dismiss opportunity")
        XCTAssertEqual(OpportunityQuickAction.mute.accessibilityLabel, "Mute opportunity")
        XCTAssertTrue(OpportunityQuickAction.allCases.allSatisfy { !$0.helpText.isEmpty })
    }

    func testOpportunityQuickActionSelectionTracksDurableActionState() {
        XCTAssertTrue(OpportunityQuickAction.save.isSelected(isSaved: true, isWatched: false))
        XCTAssertTrue(OpportunityQuickAction.watch.isSelected(isSaved: false, isWatched: true))
        XCTAssertFalse(OpportunityQuickAction.save.isSelected(isSaved: false, isWatched: true))
        XCTAssertFalse(OpportunityQuickAction.watch.isSelected(isSaved: true, isWatched: false))
        XCTAssertFalse(OpportunityQuickAction.dismiss.isSelected(isSaved: true, isWatched: true))
        XCTAssertFalse(OpportunityQuickAction.mute.isSelected(isSaved: true, isWatched: true))
    }

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
