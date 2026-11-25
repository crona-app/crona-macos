import SwiftUI

/// Keeps pane identity stable when the display changes the number of panes per row.
struct GlancePaneGridLayout: Layout {
    let layout: GlanceLayout
    static let spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 800
        let rows = measure(subviews, width: width)
        return CGSize(width: width, height: Self.totalHeight(rows.map(\.height)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var index = 0
        for row in measure(subviews, width: bounds.width) {
            var x = bounds.minX
            for _ in 0..<row.count {
                subviews[index].place(
                    at: CGPoint(x: x, y: y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: row.paneWidth, height: row.height)
                )
                x += row.paneWidth + Self.spacing
                index += 1
            }
            y += row.height + Self.spacing
        }
    }

    static func rowCounts(paneCount: Int, width: CGFloat, layout: GlanceLayout) -> [Int] {
        guard paneCount > 0 else { return [] }
        let minimumPaneWidth: CGFloat = 360
        let capacity = layout == .singleColumn
            ? 1 : min(3, max(1, Int((width + spacing) / (minimumPaneWidth + spacing))))
        let rowCount = (paneCount + capacity - 1) / capacity
        let panesPerRow = paneCount / rowCount
        let largerRows = paneCount % rowCount
        return Array(repeating: panesPerRow, count: rowCount - largerRows)
            + Array(repeating: panesPerRow + 1, count: largerRows)
    }

    static func totalHeight(_ heights: [CGFloat]) -> CGFloat {
        heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * spacing
    }

    private struct Row {
        let paneWidth: CGFloat
        let count: Int
        let height: CGFloat
    }

    private func measure(_ subviews: Subviews, width: CGFloat) -> [Row] {
        let counts = Self.rowCounts(paneCount: subviews.count, width: width, layout: layout)
        var start = 0
        return counts.map { count in
            let paneWidth = max(0, width - CGFloat(count - 1) * Self.spacing) / CGFloat(count)
            let height = subviews[start..<(start + count)].map {
                $0.sizeThatFits(ProposedViewSize(width: paneWidth, height: nil)).height
            }.max() ?? 0
            start += count
            return Row(paneWidth: paneWidth, count: count, height: height)
        }
    }
}
