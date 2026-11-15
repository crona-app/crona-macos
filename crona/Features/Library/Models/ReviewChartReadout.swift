import CoreGraphics
import Foundation

struct ReviewChartReadout {
    struct Value {
        let label: String
        let text: String
        let plotValue: Double?
    }

    let date: String
    let isAway: Bool
    let values: [Value]
}

/// Keeps the floating readout inside its own plot, switching sides near the edges.
enum ReviewChartTooltipLayout {
    static func center(pointer: CGPoint, plot: CGRect, size: CGSize) -> CGPoint {
        let gap: CGFloat = 12
        let proposedX = pointer.x + gap + size.width / 2
        let x =
            proposedX + size.width / 2 <= plot.maxX
            ? proposedX : pointer.x - gap - size.width / 2
        let proposedY = pointer.y - gap - size.height / 2
        let y =
            proposedY - size.height / 2 >= plot.minY
            ? proposedY : pointer.y + gap + size.height / 2
        return CGPoint(
            x: clamp(x, minimum: plot.minX + size.width / 2, maximum: plot.maxX - size.width / 2),
            y: clamp(y, minimum: plot.minY + size.height / 2, maximum: plot.maxY - size.height / 2)
        )
    }

    private static func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard minimum <= maximum else { return (minimum + maximum) / 2 }
        return min(maximum, max(minimum, value))
    }
}
