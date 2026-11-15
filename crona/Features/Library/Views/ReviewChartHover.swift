import Charts
import SwiftUI

extension View {
    func reviewChartHover(dates: [String], readout: @escaping (String) -> ReviewChartReadout) -> some View {
        self.chartXScale(domain: dates)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let frame = proxy.plotFrame {
                        ReviewChartHoverOverlay(proxy: proxy, plot: geometry[frame], dates: dates, readout: readout)
                    }
                }
            }
    }
}

private struct ReviewChartHoverOverlay: View {
    let proxy: ChartProxy
    let plot: CGRect
    let dates: [String]
    let readout: (String) -> ReviewChartReadout
    @State private var hoveredDate: String?
    @State private var pointer = CGPoint.zero
    @State private var tooltipSize = CGSize(width: 210, height: 90)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
            if let date = hoveredDate, let position = proxy.position(forX: date) {
                let x = plot.minX + position
                let info = readout(date)
                Rectangle()
                    .fill(.primary.opacity(0.06))
                    .frame(width: plot.width / CGFloat(max(1, dates.count)), height: plot.height)
                    .position(x: x, y: plot.midY)
                Path { path in
                    path.move(to: CGPoint(x: x, y: plot.minY))
                    path.addLine(to: CGPoint(x: x, y: plot.maxY))
                }
                .stroke(.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(Array(info.values.enumerated()), id: \.offset) { _, value in
                    if let value = value.plotValue, let y = proxy.position(forY: value) {
                        Circle().fill(.background)
                            .overlay(Circle().stroke(.primary, lineWidth: 2))
                            .frame(width: 8, height: 8)
                            .position(x: x, y: plot.minY + y)
                    }
                }
                tooltip(info)
                    .frame(width: min(210, plot.width))
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: ReviewTooltipSizeKey.self, value: geometry.size)
                        }
                    }
                    .position(ReviewChartTooltipLayout.center(pointer: pointer, plot: plot, size: tooltipSize))
            }
        }
        .allowsHitTesting(true)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                guard plot.contains(location),
                    let date = proxy.value(atX: location.x - plot.minX, as: String.self), dates.contains(date)
                else {
                    hoveredDate = nil
                    return
                }
                pointer = location
                hoveredDate = date
            case .ended:
                hoveredDate = nil
            }
        }
        .onPreferenceChange(ReviewTooltipSizeKey.self) { tooltipSize = $0 }
        .onChange(of: dates) { _, _ in hoveredDate = nil }
        .onDisappear { hoveredDate = nil }
        .accessibilityHidden(true)
    }

    private func tooltip(_ info: ReviewChartReadout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(info.date).font(.caption.weight(.semibold)).lineLimit(1)
            if info.isAway {
                Label("Away day", systemImage: "leaf").foregroundStyle(.green).font(.caption2)
            }
            ForEach(Array(info.values.enumerated()), id: \.offset) { _, value in
                HStack(spacing: 12) {
                    Text(value.label).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(value.text).monospacedDigit()
                }.font(.caption).lineLimit(1)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        .allowsHitTesting(false)
    }
}

private struct ReviewTooltipSizeKey: PreferenceKey {
    static let defaultValue = CGSize(width: 210, height: 90)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
