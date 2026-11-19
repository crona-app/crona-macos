import SwiftUI

struct TimerHUDExpandedView<Actions: View>: View {
    @ObservedObject var state: CompanionAppState
    @ObservedObject var context: ContextService
    @ObservedObject var expansion: TimerHUDExpansionModel
    let presentation: TimerPresentation
    let actions: Actions
    let collapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(state.activeFocusTitle ?? "Quick Session").font(.headline).lineLimit(2)
                Spacer(minLength: 8)
                Button(action: collapse) { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain).help("Collapse timer")
            }
            HStack(spacing: 12) {
                if let repo = context.snapshot.repoName { Label(repo, systemImage: "folder") }
                if let stream = context.snapshot.streamName { Label(stream, systemImage: "arrow.triangle.branch") }
            }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            ScrollView {
                Text(expansion.issueDescription ?? (state.timerService.snapshot.adhoc ? "An unassigned focus session." : "No issue description."))
                    .font(.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(MenuBarTextFormatter.formatClock(seconds: presentation.displaySeconds))
                        .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(presentation.phaseTitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                actions
            }
            if presentation.mode != .stopwatch, let fraction = presentation.progressFraction {
                ReverseProgressBar(progress: fraction).frame(height: 6)
            }
        }
        .task(id: state.timerService.snapshot.issueID) { await expansion.loadDescription(state: state) }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PopoverGlassBackground(cornerRadius: 20, showsShadow: false))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(PopupVisualTheme.surfaceStroke, lineWidth: 0.8))
    }
}
