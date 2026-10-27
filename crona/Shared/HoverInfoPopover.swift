import SwiftUI

/// Shows a small popover after the pointer rests on a view, so scrolling past rows does not flash popovers.
struct HoverInfoPopover<Info: View>: ViewModifier {
    static var defaultDelay: Duration { .milliseconds(600) }

    let delay: Duration
    @ViewBuilder let info: () -> Info
    @State private var isShown = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onHover { hovering in
                pending?.cancel()
                guard hovering else {
                    isShown = false
                    return
                }
                pending = Task { @MainActor in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                    isShown = true
                }
            }
            .onDisappear { pending?.cancel() }
            .popover(isPresented: $isShown, arrowEdge: .bottom) {
                info().padding(10)
            }
    }
}

extension View {
    func hoverInfo<Info: View>(
        delay: Duration = HoverInfoPopover<Info>.defaultDelay, @ViewBuilder _ info: @escaping () -> Info
    ) -> some View {
        modifier(HoverInfoPopover(delay: delay, info: info))
    }
}

/// Plain lines for a hover popover, with an optional highlighted line color.
struct HoverInfoLines: View {
    let lines: [(text: String, color: Color?)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(.callout)
                    .foregroundStyle(line.color ?? PopupVisualTheme.primaryText)
                    .fixedSize()
            }
        }
    }
}
