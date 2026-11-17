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
            Label(issue?.title ?? "Ad Hoc Focus", systemImage: "record.circle.fill")
                .font(.title3.weight(.semibold)).lineLimit(2)

            SegmentedControl(selection: $setup.mode, title: \.title)

            VStack(spacing: 0) {
                switch setup.mode {
                case .stopwatch:
                    MetricStripCard(icon: "play.fill", tint: PopupVisualTheme.semantic(.success),
                        title: "Open-ended focus", value: "No hard limit")
                case .pomodoro:
                    durationRow("Focus", text: $setup.focus, presets: [25, 50, 90])
                    durationRow("Short break", text: $setup.shortBreak, presets: [5, 10, 15], enabled: $setup.breaksEnabled)
                    durationRow("Long break", text: $setup.longBreak, presets: [15, 20, 30], enabled: $setup.longBreakEnabled)
                        .disabled(!setup.breaksEnabled)
                    numberRow("Cycles", text: $setup.cycles)
                        .disabled(!setup.breaksEnabled)
                    numberRow("Long break every", text: $setup.longBreakAfter, suffix: "cycles")
                        .disabled(!setup.breaksEnabled || !setup.longBreakEnabled)
                case .timer:
                    durationRow("Duration", text: $setup.countdown, presets: [])
                    HStack(spacing: 8) {
                        Text("Quick picks").font(.caption).foregroundStyle(.secondary)
                        ForEach([25, 45, 90], id: \.self) { minutes in
                            Button(MenuBarTextFormatter.formatMinutes(minutes)) {
                                setup.countdown = MenuBarTextFormatter.formatMinutes(minutes)
                            }.buttonStyle(.bordered).controlSize(.small)
                        }
                        Spacer(minLength: 0)
                    }.padding(12)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 270, alignment: .top)

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

    private func durationRow(_ title: String, text: Binding<String>, presets: [Int], enabled: Binding<Bool>? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
            Spacer(minLength: 4)
            if let enabled {
                Toggle(title, isOn: enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            FocusSetupTextField(title: title, text: text, onSubmit: start)
                .frame(width: 78, height: 20).padding(7).popupInputSurface(cornerRadius: 8)
                .disabled(enabled?.wrappedValue == false)
            if !presets.isEmpty {
                Menu {
                    ForEach(presets, id: \.self) { minutes in
                        Button(MenuBarTextFormatter.formatMinutes(minutes)) {
                            text.wrappedValue = MenuBarTextFormatter.formatMinutes(minutes)
                        }
                    }
                } label: { Text("") }
                .menuStyle(.borderlessButton).menuIndicator(.visible).fixedSize()
                .accessibilityLabel("\(title) presets")
                .disabled(enabled?.wrappedValue == false)
            }
        }
        .padding(.horizontal, 12).frame(height: 50)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 12) }
    }

    private func numberRow(_ title: String, text: Binding<String>, suffix: String = "") -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            FocusSetupTextField(title: title, text: text, isDuration: false, onSubmit: start)
                .frame(width: 30, height: 20).padding(7).popupInputSurface(cornerRadius: 8)
                .accessibilityLabel(title)
            Stepper(title, value: Binding(
                get: { Int(text.wrappedValue) ?? 4 },
                set: { text.wrappedValue = String($0) }), in: 1...12)
                .labelsHidden().fixedSize()
            if !suffix.isEmpty { Text(suffix).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12).frame(height: 50)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 12) }
    }
}
