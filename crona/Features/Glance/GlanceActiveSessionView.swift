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
