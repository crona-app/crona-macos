import SwiftUI

/// The mode-specific rows of the focus setup, shared by the menu popover and Peek so both keep one look.
struct FocusSetupForm: View {
    @ObservedObject var setup: FocusSetupModel
    let onSubmit: () -> Void

    var body: some View {
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
    }

    private func durationRow(_ title: String, text: Binding<String>, presets: [Int], enabled: Binding<Bool>? = nil) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
            Spacer(minLength: 4)
            if let enabled {
                Toggle(title, isOn: enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            FocusSetupTextField(title: title, text: text, onSubmit: onSubmit)
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
            FocusSetupTextField(title: title, text: text, isDuration: false, onSubmit: onSubmit)
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
