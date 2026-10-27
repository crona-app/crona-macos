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
}
