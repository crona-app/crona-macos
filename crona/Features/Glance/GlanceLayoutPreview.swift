import AppKit
import SwiftUI

enum GlanceLayoutMetrics {
    static let workspaceWidth: CGFloat = 1520

    static func previewHeight(_ widget: GlanceWidget) -> CGFloat {
        switch widget {
        case .issues, .habits: 260
        case .calendar: 132
        case .wellbeing: 108
        case .summary: 232
        case .selection: 0
        }
    }
}

struct GlanceLayoutPreview: View {
    let preferences: GlancePreferences
    private var screenSize: CGSize {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        return screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
    }

    var body: some View {
        let size = screenSize
        let width = min(GlanceLayoutMetrics.workspaceWidth, size.width - 48)
        let groups = [preferences.overviewWidgets, preferences.workWidgets].filter { !$0.isEmpty }
        let contentHeight = groups.map { height(of: $0, width: width) }.reduce(0, +)
            + CGFloat(max(0, groups.count - 1)) * 20
        let canvasHeight = max(100, contentHeight) + 108
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Layout Preview").font(.body.weight(.medium))
                Spacer()
                Text("\(Int(size.width)) × \(Int(size.height)) display").font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let scale = geometry.size.width / (width + 48)
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Glance").font(.title2.bold())
                        Spacer()
                        Text("Today").font(.body)
                        Spacer()
                        Image(systemName: "plus")
                        Image(systemName: "xmark")
                    }.frame(height: 40)
                    if groups.isEmpty {
                        Text("Choose Panes").frame(maxWidth: .infinity)
                    } else {
                        ForEach(groups, id: \.self) { widgets in
                            GlancePaneGridLayout(layout: preferences.layout) {
                                ForEach(widgets) { widget in
                                    previewPane(widget)
                                }
                            }
                        }
                    }
                }
                .padding(24)
                .frame(width: width + 48, height: canvasHeight, alignment: .top)
                .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 24))
                .scaleEffect(scale, anchor: .topLeading)
            }
            .aspectRatio((width + 48) / canvasHeight, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Glance layout preview: " + groups.flatMap { $0 }.map(\.title).joined(separator: ", "))
        }
    }

    private func height(of widgets: [GlanceWidget], width: CGFloat) -> CGFloat {
        let counts = GlancePaneGridLayout.rowCounts(paneCount: widgets.count, width: width, layout: preferences.layout)
        var index = 0
        let heights = counts.map { count in
            defer { index += count }
            return widgets[index..<(index + count)].map(GlanceLayoutMetrics.previewHeight).max() ?? 0
        }
        return GlancePaneGridLayout.totalHeight(heights)
    }

    private func previewPane(_ widget: GlanceWidget) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(widget.title).font(.headline)
            illustration(widget)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: GlanceLayoutMetrics.previewHeight(widget))
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        .clipped()
    }

    @ViewBuilder private func illustration(_ widget: GlanceWidget) -> some View {
        switch widget {
        case .issues, .habits:
            if widget == .issues { Text("Planned     Overdue     Upcoming").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(0..<3) { index in
                HStack(spacing: 12) {
                    Image(systemName: widget == .habits ? "circle" : "circle.dotted").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.3)).frame(width: CGFloat(130 + index * 35), height: 10)
                        RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.2)).frame(width: 100, height: 7)
                    }
                    Spacer()
                    Image(systemName: widget == .habits ? "checkmark.circle" : "play.circle").foregroundStyle(.green)
                }.padding(14).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        case .calendar:
            Text("November 2026").font(.subheadline)
            HStack {
                ForEach(22...28, id: \.self) { day in
                    Text("\(day)").font(.caption)
                        .frame(maxWidth: .infinity)
                }
            }
        case .selection:
            EmptyView()
        case .wellbeing:
            Text("No check-in yet").foregroundStyle(.secondary)
        case .summary:
            HStack {
                ForEach(["Score", "Worked", "Issues", "Habits"], id: \.self) { title in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            Circle().trim(from: 0.5, to: 1)
                                .stroke(.secondary.opacity(0.35), lineWidth: 4)
                                .frame(width: 48, height: 48)
                            Text("0").font(.headline)
                        }
                        Text(title).font(.caption)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }
}
