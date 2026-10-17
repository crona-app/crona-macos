import XCTest
@testable import crona

@MainActor
final class FocusStartConfigTests: DaemonTestCase {
    func testFocusStartConfigBuildsStopwatchRequest() {
        let issue = DailyFocusIssue(id: 33, streamID: 22, title: "Issue", status: "planned", estimateMinutes: nil, workedSeconds: 0, todoForDate: nil)
        let state = FocusStartConfigState(mode: .stopwatch)

        let request = state.startRequest(for: issue)

        XCTAssertEqual(request.streamID, 22)
        XCTAssertEqual(request.issueID, 33)
        XCTAssertNil(request.hardLimitKind)
        XCTAssertNil(request.hardLimitTotalSeconds)
        XCTAssertNil(request.hardLimitWorkSeconds)
    }

    func testFocusStartConfigBuildsPomodoroRequest() {
        let issue = DailyFocusIssue(id: 33, streamID: 22, title: "Issue", status: "planned", estimateMinutes: nil, workedSeconds: 0, todoForDate: nil)
        let state = FocusStartConfigState(
            mode: .pomodoro,
            focusChoice: .preset25,
            breakChoice: .preset5,
            longBreakChoice: .preset15,
            countdownChoice: .preset25,
            pomodoroCycles: 4,
            pomodoroCyclesBeforeLongBreak: 4,
            extendMinutes: 25,
            extendSessions: 1
        )

        let request = state.startRequest(for: issue)

        XCTAssertEqual(request.hardLimitKind, .pomodoro)
        XCTAssertEqual(request.hardLimitTotalSeconds, 7800)
        XCTAssertEqual(request.hardLimitWorkSeconds, 1500)
        XCTAssertEqual(request.hardLimitBreakSeconds, 300)
        XCTAssertEqual(request.hardLimitLongBreakSeconds, 900)
        XCTAssertEqual(request.hardLimitCyclesBeforeLongBreak, 4)
    }

    func testFocusStartConfigUsesRemainingEstimateForTimerDefault() {
        let state = FocusStartConfigState.defaultState(estimateMinutes: 60, workedSeconds: 15 * 60)
        let issue = DailyFocusIssue(id: 33, streamID: 22, title: "Issue", status: "planned", estimateMinutes: 60, workedSeconds: 15 * 60, todoForDate: nil)
        var timerState = state
        timerState.mode = .timer

        let request = timerState.startRequest(for: issue)

        XCTAssertEqual(state.customCountdownMinutes, 45)
        XCTAssertEqual(state.countdownChoice, .custom)
        XCTAssertEqual(request.hardLimitKind, .countdown)
        XCTAssertEqual(request.hardLimitTotalSeconds, 45 * 60)
        XCTAssertNil(request.hardLimitWorkSeconds)
        XCTAssertNil(request.hardLimitBreakSeconds)
        XCTAssertNil(request.hardLimitLongBreakSeconds)
        XCTAssertNil(request.hardLimitCyclesBeforeLongBreak)
    }

    func testFocusStartConfigDisablesDependentPomodoroFieldsWhenNoBreakSelected() {
        let state = FocusStartConfigState(
            mode: .pomodoro,
            focusChoice: .preset25,
            breakChoice: .noBreak,
            longBreakChoice: .preset15,
            countdownChoice: .preset25,
            pomodoroCycles: 4,
            pomodoroCyclesBeforeLongBreak: 4
        )

        XCTAssertFalse(state.breaksEnabled)
        XCTAssertFalse(state.showsLongBreakControls)
        XCTAssertFalse(state.showsCycleControls)
        XCTAssertFalse(state.showsLongBreakAfterControls)
        XCTAssertEqual(state.pomodoroValues.breakSeconds, 0)
        XCTAssertEqual(state.pomodoroValues.longBreakSeconds, 0)
        XCTAssertEqual(state.pomodoroValues.cyclesBeforeLongBreak, 0)
        XCTAssertEqual(state.pomodoroValues.totalSeconds, 25 * 60)
    }

    func testFocusStartConfigDisablesLongBreakAfterWhenLongBreakDisabled() {
        let state = FocusStartConfigState(
            mode: .pomodoro,
            focusChoice: .preset25,
            breakChoice: .preset5,
            longBreakChoice: .noBreak,
            countdownChoice: .preset25,
            pomodoroCycles: 4,
            pomodoroCyclesBeforeLongBreak: 4
        )

        XCTAssertTrue(state.breaksEnabled)
        XCTAssertFalse(state.longBreakEnabled)
        XCTAssertTrue(state.showsCycleControls)
        XCTAssertFalse(state.showsLongBreakAfterControls)
        XCTAssertEqual(state.pomodoroValues.longBreakSeconds, 0)
        XCTAssertEqual(state.pomodoroValues.cyclesBeforeLongBreak, 0)
    }

    func testFocusStartConfigClampsCustomDurations() {
        let state = FocusStartConfigState(
            mode: .pomodoro,
            focusChoice: .custom,
            breakChoice: .custom,
            longBreakChoice: .custom,
            countdownChoice: .custom,
            customFocusMinutes: 0,
            customBreakMinutes: -5,
            customLongBreakMinutes: -10,
            customCountdownMinutes: 0
        )
        var timerState = state
        timerState.mode = .timer

        XCTAssertEqual(state.resolvedFocusMinutes, 1)
        XCTAssertEqual(state.resolvedBreakMinutes, 0)
        XCTAssertEqual(state.resolvedLongBreakMinutes, 0)
        XCTAssertEqual(timerState.resolvedCountdownMinutes, 1)
    }
}
