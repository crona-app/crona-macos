import AppKit
import SwiftUI

/// Shared dimensions keep the miniature and the live widget columns in proportion.
enum GlanceLayoutMetrics {
    static func sideWidth(_ width: CGFloat) -> CGFloat { max(340, width * 0.34) }
    static func height(_ widget: GlanceWidget, availableHeight: CGFloat) -> CGFloat {
        switch widget {
        case .issues: return max(320, (availableHeight - 20) / 2)
        case .habits: return max(300, (availableHeight - 20) / 2)
        case .selection: return 260
        case .calendar: return availableHeight < 820 ? 160 : 390
        case .summary: return 250
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
        let width = min(1800, size.width) - 48
        let height = max(300, size.height - 160)
        let visible = preferences.normalizedOrder.filter(preferences.visible)
        let main = visible.filter { $0 == .issues || $0 == .habits }
        let side = visible.filter { $0 != .issues && $0 != .habits }
        let columnHeight: ([GlanceWidget]) -> CGFloat = { widgets in
            widgets.reduce(0) { $0 + GlanceLayoutMetrics.height($1, availableHeight: height) } + CGFloat(max(0, widgets.count - 1)) * 20
        }
        let contentHeight = width >= 800 ? max(columnHeight(main), columnHeight(side)) : columnHeight(main + side)
        let canvasHeight = max(height, contentHeight) + 96
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
                    if visible.isEmpty {
                        Text("Choose widgets to make Glance yours.")
                            .frame(maxWidth: .infinity, minHeight: height)
                    } else if width >= 800 {
                        HStack(alignment: .top, spacing: 20) {
                            if !main.isEmpty { column(main, height: height) }
                            if !side.isEmpty {
                                column(side, height: height)
                                    .frame(width: main.isEmpty ? width : GlanceLayoutMetrics.sideWidth(width))
                            }
                        }
                    } else { column(main + side, height: height) }
                    Spacer(minLength: 0)
                }
                .padding(24)
                .frame(width: width + 48, height: canvasHeight, alignment: .top)
                .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 24))
                .scaleEffect(scale, anchor: .topLeading)
            }
            .aspectRatio((width + 48) / canvasHeight, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Glance layout preview: " + visible.map(\.title).joined(separator: ", "))
            Text("Proportions reflect your display. Sample content illustrates each widget.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func column(_ widgets: [GlanceWidget], height: CGFloat) -> some View {
        VStack(spacing: 20) {
            ForEach(widgets) { widget in
                VStack(alignment: .leading, spacing: 16) {
                    Text(widget.title).font(.headline)
                    illustration(widget)
                    Spacer(minLength: 0)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .frame(height: GlanceLayoutMetrics.height(widget, availableHeight: height))
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.secondary.opacity(0.2)))
                .clipped()
            }
        }.frame(maxWidth: .infinity)
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
            Text("‹                   This month                   ›").font(.subheadline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 14) {
                ForEach(1..<(screenSize.height - 160 < 820 ? 8 : 36), id: \.self) { day in
                    Text("\((day - 1) % 31 + 1)").font(.caption)
                        .frame(width: 24, height: 24)
                        .background(day == 4 ? Color.accentColor : .clear, in: Circle())
                }
            }
        case .selection:
            Text("Selected issue or habit").font(.title3.weight(.semibold))
            Text("Description, tags, progress, and actions appear here.").foregroundStyle(.secondary)
            Label("Start focus", systemImage: "play.fill").padding(10).background(.secondary.opacity(0.12), in: Capsule())
        case .summary:
            HStack {
                ForEach(["Score", "Worked", "Issues", "Habits"], id: \.self) { title in
                    VStack(spacing: 10) {
                        Circle().trim(from: 0, to: 0.7).stroke(.green, lineWidth: 5).frame(width: 42, height: 42)
                        Text(title).font(.caption)
                    }.frame(maxWidth: .infinity)
                }
            }
            Divider()
            Text("Sessions                  Average                  Breaks").font(.caption).foregroundStyle(.secondary)
        }
    }
}
