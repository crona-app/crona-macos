import SwiftUI

struct PeekLiveSessionStrip: View {
    @ObservedObject var state: CompanionAppState
    @ObservedObject var model: PeekModel
    @ObservedObject var timer: TimerService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let presentation = TimerPresentation.from(timer.snapshot, at: timeline.date)
            HStack(spacing: 14) {
                Image(systemName: presentation.phaseSymbolName).foregroundStyle(PopupVisualTheme.semantic(.focus))
                VStack(alignment: .leading, spacing: 3) {
                    Text(timer.snapshot.issueID.map { state.detailsIssue(id: $0)?.title ?? "Issue #\($0)" } ?? "Quick Session")
                        .font(.headline).lineLimit(1)
                    Text("Live · \(presentation.phaseTitle)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Duration.seconds(presentation.displaySeconds).formatted(.time(pattern: .hourMinuteSecond)))
                    .font(.title2.monospacedDigit())
                if presentation.canPause || presentation.canResume {
                    Button(presentation.canPause ? "Pause" : "Resume") { Task { await model.timerCommand() } }.buttonStyle(PeekButtonStyle())
                }
                if presentation.canAdvance, let title = presentation.advanceTitle {
                    Button(title) { Task { await model.timerCommand(advance: true) } }.buttonStyle(PeekButtonStyle())
                }
                Button("End") {
                    model.dismiss(restoreFocus: false)
                    Task { await state.performGlobalShortcut(.endSession) }
                }.buttonStyle(PeekButtonStyle())
            }.disabled(model.commandInFlight)
        }.padding(12).background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 18))
    }
}
