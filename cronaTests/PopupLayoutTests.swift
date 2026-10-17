import AppKit
import XCTest
@testable import crona

@MainActor
final class PopupLayoutTests: DaemonTestCase {
    func testTransientPopupCollectionBehaviorSupportsSpacesAndFullScreen() {
        let behavior = WindowService.transientPopupCollectionBehavior

        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behavior.contains(.stationary))
    }

    func testWindowServiceAppliesOnlyDistinctActivationPolicies() {
        var appliedPolicies: [NSApplication.ActivationPolicy] = []
        let service = WindowService { policy in
            appliedPolicies.append(policy)
        }

        service.initializeApplicationActivationPolicy()
        service.initializeApplicationActivationPolicy()
        service.refreshApplicationActivationPolicy()
        service.beginExternalWindowPresentation()
        service.beginExternalWindowPresentation()
        service.endExternalWindowPresentation()
        service.endExternalWindowPresentation()
        service.refreshApplicationActivationPolicy()

        XCTAssertEqual(appliedPolicies, [.accessory, .regular, .accessory])
    }

    func testStatusItemClickIntentUsesSecondaryClickForContextMenu() {
        XCTAssertEqual(
            StatusItemClickIntent.resolve(eventType: .rightMouseUp),
            .showContextMenu
        )
        XCTAssertEqual(
            StatusItemClickIntent.resolve(eventType: .leftMouseUp),
            .togglePopup
        )
        XCTAssertEqual(
            StatusItemClickIntent.resolve(eventType: nil),
            .togglePopup
        )
    }

    func testInactivityPopupPositionerPlacesPanelsAtSelectedScreenAnchor() {
        let frame = NSRect(x: 100, y: 200, width: 1_200, height: 800)
        let panelSize = NSSize(width: 360, height: 320)
        let margin: CGFloat = 72

        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .topLeft, margin: margin),
            NSPoint(x: 172, y: 608)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .topCenter, margin: margin),
            NSPoint(x: 520, y: 608)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .topRight, margin: margin),
            NSPoint(x: 868, y: 608)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .bottomLeft, margin: margin),
            NSPoint(x: 172, y: 272)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .bottomCenter, margin: margin),
            NSPoint(x: 520, y: 272)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(in: frame, panelSize: panelSize, preference: .bottomRight, margin: margin),
            NSPoint(x: 868, y: 272)
        )
    }

    func testInactivityPopupPositionerUsesSharedEdgeInsets() {
        let frame = NSRect(x: 100, y: 200, width: 1_200, height: 800)
        let panelSize = NSSize(width: 380, height: 200)

        XCTAssertEqual(
            InactivityPopupPositioner.origin(
                in: frame,
                panelSize: panelSize,
                preference: .topCenter,
                topMargin: 12,
                bottomMargin: 8,
                horizontalMargin: 8
            ),
            NSPoint(x: 510, y: 788)
        )
        XCTAssertEqual(
            InactivityPopupPositioner.origin(
                in: frame,
                panelSize: panelSize,
                preference: .bottomRight,
                topMargin: 12,
                bottomMargin: 8,
                horizontalMargin: 8
            ),
            NSPoint(x: 912, y: 208)
        )
    }

    func testInactivityPopupPositionerStagesEdgePopupsOffscreen() {
        let visibleFrame = NSRect(x: 100, y: 200, width: 1_200, height: 800)
        let panelFrame = NSRect(x: 510, y: 788, width: 380, height: 200)
        let buffer: CGFloat = 24

        let left = InactivityPopupPositioner.offscreenOrigin(
            for: panelFrame,
            in: visibleFrame,
            preference: .topLeft,
            buffer: buffer
        )
        let right = InactivityPopupPositioner.offscreenOrigin(
            for: panelFrame,
            in: visibleFrame,
            preference: .bottomRight,
            buffer: buffer
        )

        XCTAssertEqual(left.x + panelFrame.width, visibleFrame.minX - buffer)
        XCTAssertEqual(left.y, panelFrame.origin.y)
        XCTAssertEqual(right.x, visibleFrame.maxX + buffer)
        XCTAssertEqual(right.y, panelFrame.origin.y)
    }

    func testInactivityPopupPositionerStagesCenteredPopupsOffscreen() {
        let visibleFrame = NSRect(x: 100, y: 200, width: 1_200, height: 800)
        let panelFrame = NSRect(x: 510, y: 788, width: 380, height: 200)
        let buffer: CGFloat = 24

        let top = InactivityPopupPositioner.offscreenOrigin(
            for: panelFrame,
            in: visibleFrame,
            preference: .topCenter,
            buffer: buffer
        )
        let bottom = InactivityPopupPositioner.offscreenOrigin(
            for: panelFrame,
            in: visibleFrame,
            preference: .bottomCenter,
            buffer: buffer
        )

        XCTAssertEqual(top.x, panelFrame.origin.x)
        XCTAssertEqual(top.y, visibleFrame.maxY + buffer)
        XCTAssertEqual(bottom.x, panelFrame.origin.x)
        XCTAssertEqual(bottom.y + panelFrame.height, visibleFrame.minY - buffer)
    }

    func testInactivityPopupUsesLongerDismissalDuration() {
        XCTAssertEqual(InactivityPopupConfiguration.autoDismissDuration, 60)
        XCTAssertEqual(HardLimitCountdownService.defaultDuration, 30)
    }

    func testPopupDisplayClockStopsWhenDismissed() {
        let clock = PopupDisplayClock()

        XCTAssertFalse(clock.isRunning)
        clock.start()
        XCTAssertTrue(clock.isRunning)
        clock.stop()
        XCTAssertFalse(clock.isRunning)
    }

    func testStatusPopupOriginCentersBelowIcon() {
        let origin = StatusBarService.popupOrigin(
            iconRect: NSRect(x: 850, y: 1050, width: 20, height: 20),
            menuBarBottomY: 1050,
            panelSize: NSSize(width: 420, height: 400),
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1050)
        )

        XCTAssertEqual(origin.x, 650)
        XCTAssertEqual(origin.y, 638)
    }

    func testStatusPopupOriginClampsToVisibleScreenEdges() {
        let leftOrigin = StatusBarService.popupOrigin(
            iconRect: NSRect(x: 10, y: 1050, width: 20, height: 20),
            menuBarBottomY: 1050,
            panelSize: NSSize(width: 420, height: 400),
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1050)
        )
        let rightOrigin = StatusBarService.popupOrigin(
            iconRect: NSRect(x: 1900, y: 1050, width: 20, height: 20),
            menuBarBottomY: 1050,
            panelSize: NSSize(width: 420, height: 400),
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1050)
        )

        XCTAssertEqual(leftOrigin.x, 8)
        XCTAssertEqual(rightOrigin.x, 1492)
    }

    func testStatusPopupOriginUsesSecondaryScreenCoordinates() {
        let origin = StatusBarService.popupOrigin(
            iconRect: NSRect(x: -600, y: 880, width: 20, height: 20),
            menuBarBottomY: 880,
            panelSize: NSSize(width: 420, height: 300),
            visibleFrame: NSRect(x: -1440, y: 0, width: 1440, height: 880)
        )

        XCTAssertEqual(origin.x, -800)
        XCTAssertEqual(origin.y, 568)
    }

    func testStatusPopupUsesFixedViewportDimensions() {
        XCTAssertEqual(StatusPopupSizing.width, 420)
        XCTAssertEqual(StatusPopupSizing.viewportHeight, 700)
    }

    func testPopoverModalMinimumHeightsRemainBounded() {
        XCTAssertEqual(PopoverModalKind.statusNote.minimumHeight, 260)
        XCTAssertEqual(PopoverModalKind.endSession.minimumHeight, 360)
        XCTAssertEqual(PopoverModalKind.dueDate.minimumHeight, 430)
        XCTAssertEqual(PopoverModalKind.issueCreate.minimumHeight, 600)
        XCTAssertLessThan(PopoverModalKind.issueCreate.minimumHeight, StatusPopupSizing.viewportHeight)
        XCTAssertLessThan(PopoverModalKind.dueDate.minimumHeight, StatusPopupSizing.viewportHeight)
    }
}
