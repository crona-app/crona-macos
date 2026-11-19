import SwiftUI

/// Shares the menu popup's timer, progress, context, and session controls.
struct GlanceActiveSessionView: View {
    @ObservedObject var state: CompanionAppState
    @StateObject private var clock = PopupDisplayClock()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                ActiveTimerView(appState: state, displayClock: clock)
                    .frame(maxWidth: 560)
                    .padding(32)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height, alignment: .center)
            }
        }
        .background(SheetGlassBackground())
        .onAppear { clock.start() }
        .onDisappear { clock.stop() }
    }
}

/// The supporting cards determine the row height, rather than the full-screen proposal.
struct GlanceSessionRowLayout: Layout {
    let sideWidth: CGFloat
    let availableHeight: CGFloat
    private let spacing: CGFloat = 20

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 1000
        let height = subviews.count > 1
            ? subviews[1].sizeThatFits(ProposedViewSize(width: sideWidth, height: nil)).height
            : min(640, availableHeight)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let timer = subviews.first else { return }
        let timerWidth = subviews.count > 1 ? bounds.width - sideWidth - spacing : bounds.width
        timer.place(at: bounds.origin, anchor: .topLeading,
                    proposal: ProposedViewSize(width: timerWidth, height: bounds.height))
        if subviews.count > 1 {
            subviews[1].place(at: CGPoint(x: bounds.maxX - sideWidth, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: sideWidth, height: bounds.height))
        }
    }
}
