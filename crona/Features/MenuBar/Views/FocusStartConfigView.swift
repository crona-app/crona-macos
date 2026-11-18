import SwiftUI

struct FocusStartConfigView: View {
    @ObservedObject var appState: CompanionAppState
    let issue: DailyFocusIssue?
    @StateObject private var setup: FocusSetupModel

    init(appState: CompanionAppState, issue: DailyFocusIssue?) {
        self.appState = appState
        self.issue = issue
        _setup = StateObject(wrappedValue: FocusSetupModel(initialState: .defaultState(
            estimateMinutes: issue?.estimateMinutes, workedSeconds: issue?.workedSeconds ?? 0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { appState.dismissStartConfig() } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Text(formattedPopoverDate(appState.dailyFocusService.snapshot.date, appState: appState))
                .font(.caption).foregroundStyle(.secondary)
            Label(issue?.title ?? "Quick Session", systemImage: "record.circle.fill")
                .font(.title3.weight(.semibold)).lineLimit(2)

            SegmentedControl(selection: $setup.mode, title: \.title)

            FocusSetupForm(setup: setup, onSubmit: start)

            Text(setup.validationError ?? appState.focusStartError ?? " ")
                .font(.caption).foregroundStyle(PopupVisualTheme.semantic(.error))
                .lineLimit(2).frame(height: 30, alignment: .topLeading)

            HStack {
                Group {
                    if let config = setup.configuration,
                       let date = TimerEndProjection.startEndDate(config: config) {
                        Label("Ends at \(TimerEndTimeFormatter.string(from: date))", systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(setup.mode == .stopwatch ? "Open-ended" : "Ends at —")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button(appState.isStartingFocus ? "Starting…" : (setup.mode == .timer ? "Start Timer" : "Start Focus")) {
                    start()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(setup.configuration == nil || appState.isStartingFocus)
            }.frame(height: 36)
        }
    }

    private func start() {
        guard !appState.isStartingFocus, let config = setup.configuration else { return }
        appState.startSelectedFocusSession(using: config)
    }
}
