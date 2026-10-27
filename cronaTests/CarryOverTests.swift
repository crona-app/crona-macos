import AppKit
import SwiftUI
import XCTest
@testable import crona

@MainActor
final class CarryOverTests: DaemonTestCase {
    func testCarriedSemanticColorIsLavender() throws {
        let color = try XCTUnwrap(NSColor(PopupVisualTheme.semantic(.carried)).usingColorSpace(.sRGB))
        XCTAssertEqual(color.redComponent, 0.686, accuracy: 0.01)
        XCTAssertEqual(color.greenComponent, 0.529, accuracy: 0.01)
        XCTAssertEqual(color.blueComponent, 1.0, accuracy: 0.01)
    }

    func testBadgeText() {
        XCTAssertNil(CronaCarryPresentation.badgeText(for: nil))
        XCTAssertEqual(CronaCarryPresentation.badgeText(for: DailyFocusCarry(count: 1, stalled: false, fromDate: nil)), "Carried ×1")
        XCTAssertEqual(CronaCarryPresentation.badgeText(for: DailyFocusCarry(count: 3, stalled: false, fromDate: nil)), "Carried ×3")
        XCTAssertEqual(CronaCarryPresentation.badgeText(for: DailyFocusCarry(count: 2, stalled: true, fromDate: nil)), "Stalled")
        XCTAssertEqual(CronaCarryPresentation.badgeText(for: DailyFocusCarry(count: 0, stalled: true, fromDate: nil)), "Stalled")
    }
}
