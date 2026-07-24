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
        XCTAssertEqual(OpportunityQuickAction.save.visualRole, .selectable)
        XCTAssertEqual(OpportunityQuickAction.watch.visualRole, .selectable)
        XCTAssertEqual(OpportunityQuickAction.dismiss.visualRole, .caution)
        XCTAssertEqual(OpportunityQuickAction.mute.visualRole, .destructive)
        XCTAssertTrue(OpportunityQuickAction.mute.accessibilityHint.contains("topic"))
        XCTAssertTrue(OpportunityQuickAction.dismiss.accessibilityHint.contains("restore"))
        XCTAssertTrue(OpportunityQuickAction.allCases.allSatisfy { !$0.helpText.isEmpty })
    }

    func testOpportunityQuickActionSelectionTracksDurableActionState() {
        XCTAssertTrue(OpportunityQuickAction.save.isSelected(isSaved: true, isWatched: false))
        XCTAssertTrue(OpportunityQuickAction.watch.isSelected(isSaved: false, isWatched: true))
        XCTAssertFalse(OpportunityQuickAction.save.isSelected(isSaved: false, isWatched: true))
        XCTAssertFalse(OpportunityQuickAction.watch.isSelected(isSaved: true, isWatched: false))
        XCTAssertFalse(OpportunityQuickAction.dismiss.isSelected(isSaved: true, isWatched: true))
        XCTAssertFalse(OpportunityQuickAction.mute.isSelected(isSaved: true, isWatched: true))
        XCTAssertEqual(
            OpportunityQuickAction.save.accessibilityValue(selected: true),
            "Selected, saved"
        )
        XCTAssertEqual(
            OpportunityQuickAction.watch.accessibilityValue(selected: true),
            "Selected, watching"
        )
        XCTAssertEqual(
            OpportunityQuickAction.mute.accessibilityValue(selected: false),
            "Not selected, suppresses this topic"
        )
    }

    func testOpportunityQuickActionsUseIntegratedRowLayoutAtEverySupportedWidth() {
        XCTAssertEqual(OpportunityQuickActionLayout.placement, .integratedTrailingRow)
        XCTAssertEqual(OpportunityQuickActionLayout.minimumTargetSize, 34)
        XCTAssertLessThanOrEqual(
            OpportunityQuickActionLayout.requiredWidth,
            AppWindowMetrics.minimumWidth
        )
        XCTAssertEqual(
            OpportunityQuickAction.allCases,
            [.save, .watch, .dismiss, .mute]
        )
    }

    func testTodayLedgerBoundsQuickActionNodesToMaterializedRows() {
        XCTAssertEqual(
            TodayLedgerMaterialization.quickActionNodeCount(materializedRowCount: 8),
            32
        )
        XCTAssertLessThan(
            TodayLedgerMaterialization.quickActionNodeCount(materializedRowCount: 8),
            TodayLedgerMaterialization.quickActionNodeCount(materializedRowCount: 70)
        )
    }

    func testRadarQuickActionsUseInlinePlacementWithoutRegressingTodayRedesign() {
        XCTAssertEqual(OpportunityQuickActionPlacement.today, .integratedTrailingRow)
        XCTAssertEqual(OpportunityQuickActionPlacement.radar, .inlineRow)
        XCTAssertEqual(OpportunityQuickActionLayout.minimumTargetSize, 34)
    }

    func testQuickActionHierarchyDistinguishesRecoverableAndSuppressiveActions() {
        XCTAssertEqual(OpportunityQuickAction.save.tone, .standard)
        XCTAssertEqual(OpportunityQuickAction.watch.tone, .standard)
        XCTAssertEqual(OpportunityQuickAction.dismiss.tone, .caution)
        XCTAssertEqual(OpportunityQuickAction.mute.tone, .destructive)
        XCTAssertTrue(OpportunityQuickAction.allCases.allSatisfy { !$0.accessibilityHint.isEmpty })
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
