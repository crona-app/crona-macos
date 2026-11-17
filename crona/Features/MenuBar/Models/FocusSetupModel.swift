import Combine
import Foundation

@MainActor
final class FocusSetupModel: ObservableObject {
    @Published var mode: FocusSessionMode
    @Published var focus: String
    @Published var shortBreak: String
    @Published var longBreak: String
    @Published var countdown: String
    @Published var breaksEnabled: Bool
    @Published var longBreakEnabled: Bool
    @Published var cycles: String
    @Published var longBreakAfter: String

    init(initialState: FocusStartConfigState) {
        mode = initialState.mode
        focus = MenuBarTextFormatter.formatMinutes(initialState.resolvedFocusMinutes)
        shortBreak = MenuBarTextFormatter.formatMinutes(max(1, initialState.resolvedBreakMinutes))
        longBreak = MenuBarTextFormatter.formatMinutes(max(1, initialState.resolvedLongBreakMinutes))
        countdown = MenuBarTextFormatter.formatMinutes(initialState.resolvedCountdownMinutes)
        breaksEnabled = initialState.breaksEnabled
        longBreakEnabled = initialState.longBreakEnabled
        cycles = String(initialState.pomodoroCycles)
        longBreakAfter = String(max(1, initialState.pomodoroCyclesBeforeLongBreak))
    }

    var validationError: String? {
        switch mode {
        case .stopwatch: return nil
        case .timer:
            return duration(countdown) == nil ? "Enter a positive duration, such as 1h12m." : nil
        case .pomodoro:
            if duration(focus) == nil { return "Enter a positive focus duration, such as 47m." }
            if breaksEnabled {
                if duration(shortBreak) == nil { return "Enter a positive short break duration." }
                if count(cycles) == nil { return "Enter 1 to 12 cycles." }
                if longBreakEnabled {
                    if duration(longBreak) == nil { return "Enter a positive long break duration." }
                    if count(longBreakAfter) == nil { return "Long break frequency must be from 1 to 12 cycles." }
                }
            }
            return nil
        }
    }

    var configuration: FocusStartConfigState? {
        guard validationError == nil else { return nil }
        return FocusStartConfigState(
            mode: mode, focusChoice: .custom,
            breakChoice: breaksEnabled ? .custom : .noBreak,
            longBreakChoice: longBreakEnabled ? .custom : .noBreak,
            countdownChoice: .custom,
            customFocusMinutes: duration(focus) ?? 25,
            customBreakMinutes: duration(shortBreak) ?? 5,
            customLongBreakMinutes: duration(longBreak) ?? 15,
            customCountdownMinutes: duration(countdown) ?? 25,
            pomodoroCycles: count(cycles) ?? 4,
            pomodoroCyclesBeforeLongBreak: count(longBreakAfter) ?? 4)
    }

    private func duration(_ text: String) -> Int? {
        guard let minutes = DurationInput.minutes(text, maximum: 1_440), minutes > 0 else { return nil }
        return minutes
    }

    private func count(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...12).contains(value) else { return nil }
        return value
    }
}
