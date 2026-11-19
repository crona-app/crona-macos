import AppKit
import XCTest
@testable import crona

@MainActor
final class StatusPopupCanvasTests: XCTestCase {
    func testEmptyPreferenceBranchesCannotRestoreTheOldFixedHeight() {
        var height = PopupSurfaceHeightKey.defaultValue
        PopupSurfaceHeightKey.reduce(value: &height, nextValue: { 470 })
        PopupSurfaceHeightKey.reduce(value: &height, nextValue: { PopupSurfaceHeightKey.defaultValue })
        XCTAssertEqual(height, 470)
    }

    func testShortcutPopupStaysCenteredAsContentHeightChanges() {
        let screen = NSRect(x: -1600, y: 100, width: 1600, height: 1000)
        var frame = NSRect(x: 0, y: 0, width: 420, height: 700)
        for height: CGFloat in [250, 600, 180, 480] {
            frame = StatusPopupCanvas.fittedFrame(frame, height: height, centeredIn: screen)
            XCTAssertEqual(frame.midX, screen.midX)
            XCTAssertEqual(frame.midY, screen.midY)
        }
    }

    func testResizeSequencePreservesMenuAnchorAndWidth() {
        var frame = NSRect(x: 1400, y: 200, width: 420, height: 700)
        let top = frame.maxY
        for height: CGFloat in [250, 600, 180, 480, 250] {
            frame = StatusPopupCanvas.fittedFrame(frame, height: height)
            XCTAssertEqual(frame.maxY, top)
            XCTAssertEqual(frame.minX, 1400)
            XCTAssertEqual(frame.width, 420)
        }
    }

    func testContentHeightIsCappedForScrolling() {
        let frame = NSRect(x: 0, y: 0, width: 420, height: 700)
        XCTAssertEqual(StatusPopupCanvas.fittedFrame(frame, height: 1200).height, 700)
        XCTAssertEqual(StatusPopupCanvas.fittedFrame(frame, height: 20).height, 180)
    }

    func testNativeHostingViewMatchesFittedWindowForCapture() {
        let host = NSView()
        let canvas = StatusPopupCanvas(hostingView: host, size: NSSize(width: 420, height: 700))
        for height: CGFloat in [250, 600, 180] {
            canvas.setFrameSize(NSSize(width: 420, height: height))
            canvas.needsLayout = true
            canvas.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.frame.height, height)
            XCTAssertEqual(host.frame.maxY, canvas.bounds.maxY)
        }
    }
}
