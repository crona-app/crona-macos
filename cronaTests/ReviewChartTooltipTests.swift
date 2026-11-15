import CoreGraphics
import XCTest

@testable import crona

@MainActor
final class ReviewChartTooltipTests: XCTestCase {
    private let plot = CGRect(x: 20, y: 10, width: 500, height: 160)
    private let size = CGSize(width: 210, height: 70)

    func testTooltipSwitchesToLeftAtRightEdge() {
        let pointer = CGPoint(x: 510, y: 90)
        let center = ReviewChartTooltipLayout.center(pointer: pointer, plot: plot, size: size)
        XCTAssertLessThan(center.x, pointer.x)
        XCTAssertLessThanOrEqual(center.x + size.width / 2, plot.maxX)
        XCTAssertGreaterThanOrEqual(center.x - size.width / 2, plot.minX)
    }

    func testTooltipMovesBelowPointerAtTopAndStaysInsidePlot() {
        let pointer = CGPoint(x: 30, y: 12)
        let center = ReviewChartTooltipLayout.center(pointer: pointer, plot: plot, size: size)
        XCTAssertGreaterThan(center.y, pointer.y)
        XCTAssertGreaterThanOrEqual(center.y - size.height / 2, plot.minY)
        XCTAssertLessThanOrEqual(center.y + size.height / 2, plot.maxY)
        XCTAssertGreaterThanOrEqual(center.x - size.width / 2, plot.minX)
    }

    func testTooltipMovesAbovePointerNearBottom() {
        let pointer = CGPoint(x: 200, y: 165)
        let center = ReviewChartTooltipLayout.center(pointer: pointer, plot: plot, size: size)
        XCTAssertLessThan(center.y, pointer.y)
        XCTAssertLessThanOrEqual(center.y + size.height / 2, plot.maxY)
    }
}
