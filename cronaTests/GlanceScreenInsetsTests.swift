import AppKit
import SwiftUI
import XCTest
@testable import crona

@MainActor
final class GlanceScreenInsetsTests: XCTestCase {
    func testReservesMenuBarAndBottomDockOnOffsetDisplay() {
        let insets = GlanceWindowController.contentInsets(
            frame: NSRect(x: -1600, y: 100, width: 1600, height: 1000),
            visibleFrame: NSRect(x: -1600, y: 170, width: 1600, height: 906), safeTop: 0)
        XCTAssertEqual(insets.top, 24)
        XCTAssertEqual(insets.bottom, 70)
        XCTAssertEqual(insets.leading, 0)
    }

    func testNotchAndSideDockAreReserved() {
        let insets = GlanceWindowController.contentInsets(
            frame: NSRect(x: 0, y: 0, width: 1500, height: 1000),
            visibleFrame: NSRect(x: 80, y: 0, width: 1420, height: 976), safeTop: 38)
        XCTAssertEqual(insets.top, 38)
        XCTAssertEqual(insets.leading, 80)
    }
}
