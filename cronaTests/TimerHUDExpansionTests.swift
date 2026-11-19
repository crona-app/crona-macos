import AppKit
import XCTest
@testable import crona

@MainActor
final class TimerHUDExpansionTests: XCTestCase {
    func testCompletionTransfersCompactFrameWithoutIntermediateResize() {
        let compact = NSRect(x: 500, y: 40, width: 308, height: 88)
        let panel = NSPanel(contentRect: compact, styleMask: [.borderless], backing: .buffered, defer: false)
        let model = TimerHUDExpansionModel()
        model.expand(panel: panel)
        let expanded = NSRect(x: 456, y: 40, width: 396, height: 348)
        panel.setFrame(expanded, display: false)
        XCTAssertEqual(model.beginCompletion(), compact)
        XCTAssertFalse(model.isExpanded)
        XCTAssertEqual(panel.frame, expanded)
        model.lostFocus(panel)
        XCTAssertEqual(panel.frame, expanded)
        XCTAssertNil(model.beginCompletion())
        panel.orderOut(nil)
    }

    func testExpansionPreservesBottomAndHorizontalCenter() {
        let compact = NSRect(x: 500, y: 40, width: 308, height: 88)
        let expanded = TimerHUDExpansionModel.expandedFrame(from: compact, in: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(expanded.minY, compact.minY)
        XCTAssertEqual(expanded.midX, compact.midX)
        XCTAssertEqual(expanded.size, NSSize(width: 396, height: 348))
    }

    func testExpansionStaysInsideOffsetScreenAtTopRight() {
        let screen = NSRect(x: -1600, y: 100, width: 1600, height: 900)
        let frame = TimerHUDExpansionModel.expandedFrame(from: NSRect(x: -240, y: 900, width: 220, height: 64), in: screen)
        XCTAssertTrue(screen.contains(frame))
    }

    func testUnrelatedBlurIsIgnoredAndCollapseRestoresCompactFrame() {
        let frame = NSRect(x: 500, y: 40, width: 308, height: 88)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        let model = TimerHUDExpansionModel()
        model.expand(panel: panel)
        XCTAssertTrue(model.isExpanded)
        model.lostFocus(NSWindow())
        XCTAssertTrue(model.isExpanded)
        model.collapse(animated: false)
        XCTAssertFalse(model.isExpanded)
        XCTAssertEqual(panel.frame, frame)
        panel.orderOut(nil)
    }
}
