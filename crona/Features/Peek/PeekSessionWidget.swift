import SwiftUI

/// Focus setup card for Peek; the rows come from the shared `FocusSetupForm` so it matches the popover.
struct PeekSessionWidget: View {
    @ObservedObject var state: CompanionAppState
    @ObservedObject var model: PeekModel
    @ObservedObject var setup: FocusSetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { model.showsSetup = false } label: { Label("Back", systemImage: "chevron.left") }
                .buttonStyle(.plain)
            if state.todayIsAway {
                Label("Away today", systemImage: "figure.walk").font(.title3.weight(.semibold))
                Text("Turn off Away Mode in Crona to start focus.").foregroundStyle(.secondary)
            } else {
                Label(model.selectedIssue?.title ?? "Quick Session", systemImage: "record.circle.fill")
                    .font(.title3.weight(.semibold)).lineLimit(2)
                SegmentedControl(selection: $setup.mode, title: \.title)
                FocusSetupForm(setup: setup, onSubmit: { Task { await model.start() } })
                Text(setup.validationError ?? model.error ?? " ")
                    .font(.caption).foregroundStyle(PopupVisualTheme.semantic(.error))
                    .lineLimit(2).frame(height: 30, alignment: .topLeading)
                HStack {
                    endsAt
                    Spacer(minLength: 8)
                    if model.error?.contains("open Crona flow") == true {
                        Button("Continue in Crona") {
                            model.dismiss(restoreFocus: false)
                            state.statusBarService.showPopupFromShortcut()
                        }.buttonStyle(PeekButtonStyle())
                    }
                    Button(model.isStarting ? "Starting…" : (setup.mode == .timer ? "Start Timer" : "Start Focus")) {
                        Task { await model.start() }
                    }
                    .buttonStyle(PeekButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(setup.configuration == nil || model.isStarting)
                }.frame(height: 36)
            }
        }
        .padding(20).frame(width: 460)
        .disabled(model.isStarting)
    }

    @ViewBuilder private var endsAt: some View {
        if let config = setup.configuration, let date = TimerEndProjection.startEndDate(config: config) {
            Label("Ends at \(TimerEndTimeFormatter.string(from: date))", systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text(setup.mode == .stopwatch ? "Open-ended" : "Ends at —").font(.caption).foregroundStyle(.secondary)
        }
    }
}
