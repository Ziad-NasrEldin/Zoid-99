import AppKit
import XCTest
@testable import Zoid99

@MainActor
final class WindowFramePersistenceTests: XCTestCase {
    func testMainWindowUsesStableNativeFrameAutosaveName() {
        UserDefaults.standard.removeObject(forKey: MainWindowFramePersistence.frameDefaultsKey)
        defer {
            UserDefaults.standard.removeObject(forKey: MainWindowFramePersistence.frameDefaultsKey)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 140, width: 1080, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(window.setFrameAutosaveName("SwiftUI.Generated.Window"))
        XCTAssertTrue(MainWindowFramePersistence.configure(window))
        XCTAssertEqual(window.frameAutosaveName, MainWindowFramePersistence.autosaveName)

        MainWindowFramePersistence.save(window)
        let restoredWindow = NSWindow(
            contentRect: NSRect(x: 40, y: 40, width: 980, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(MainWindowFramePersistence.restore(restoredWindow))
        XCTAssertEqual(restoredWindow.frame, window.frame)
    }
}
