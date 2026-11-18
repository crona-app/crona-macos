import AppKit
import XCTest
@testable import crona

@MainActor
final class ShortcutPopupPositionerTests: XCTestCase {
    func testCentersOnSecondaryScreenWithinVisibleFrame() {
        XCTAssertEqual(ShortcutPopupPositioner.centeredOrigin(size: NSSize(width: 400, height: 600),
            visibleFrame: NSRect(x: -1600, y: 100, width: 1600, height: 1000)), NSPoint(x: -1000, y: 300))
    }

    func testOversizedPopupStartsAtVisibleFrameOrigin() {
        XCTAssertEqual(ShortcutPopupPositioner.centeredOrigin(size: NSSize(width: 800, height: 900),
            visibleFrame: NSRect(x: 200, y: 100, width: 400, height: 500)), NSPoint(x: 200, y: 100))
    }
}
