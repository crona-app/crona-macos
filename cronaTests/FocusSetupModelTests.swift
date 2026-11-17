import XCTest
@testable import crona

@MainActor
final class FocusSetupModelTests: XCTestCase {
    func testDefaultsPreserveRemainingEstimate() throws {
        let model = FocusSetupModel(initialState: .defaultState(estimateMinutes: 90, workedSeconds: 23 * 60))
        model.mode = .timer
        XCTAssertEqual(model.countdown, "1h7m")
        let config = try XCTUnwrap(model.configuration)
        XCTAssertEqual(config.startRequest(for: nil).hardLimitTotalSeconds, 4_020)
    }

    func testTypedPomodoroDurationsProduceExactRequest() throws {
        let model = FocusSetupModel(initialState: FocusStartConfigState(mode: .pomodoro))
        model.focus = "47m"
        model.shortBreak = "7m"
        model.longBreak = "19m"
        model.cycles = "3"
        model.longBreakAfter = "2"
        let request = try XCTUnwrap(model.configuration).startRequest(for: nil)
        XCTAssertEqual(request.hardLimitWorkSeconds, 2_820)
        XCTAssertEqual(request.hardLimitBreakSeconds, 420)
        XCTAssertEqual(request.hardLimitLongBreakSeconds, 1_140)
        XCTAssertEqual(request.hardLimitCyclesBeforeLongBreak, 2)
    }

    func testDisablingBreaksPreservesDraftAndIgnoresDisabledFields() throws {
        let model = FocusSetupModel(initialState: FocusStartConfigState(mode: .pomodoro))
        model.shortBreak = "7m"
        model.cycles = "6"
        model.breaksEnabled = false
        let request = try XCTUnwrap(model.configuration).startRequest(for: nil)
        XCTAssertEqual(request.hardLimitBreakSeconds, 0)
        XCTAssertEqual(request.hardLimitTotalSeconds, 1_500)
        model.breaksEnabled = true
        XCTAssertEqual(model.shortBreak, "7m")
        XCTAssertEqual(model.cycles, "6")
        model.longBreakEnabled = false
        model.longBreak = "invalid"
        model.longBreakAfter = "invalid"
        XCTAssertNotNil(model.configuration)
        model.longBreakEnabled = true
        XCTAssertNil(model.configuration)
    }

    func testInvalidActiveFieldsBlockStartingWithoutClamping() {
        let model = FocusSetupModel(initialState: FocusStartConfigState(mode: .timer))
        for text in ["", "bad", "0m", "-1m", "25h"] {
            model.countdown = text
            XCTAssertNil(model.configuration, text)
            XCTAssertNotNil(model.validationError, text)
        }
        model.mode = .pomodoro
        model.cycles = "13"
        XCTAssertNil(model.configuration)
        model.cycles = "4"
        model.focus = ""
        XCTAssertNil(model.configuration)
        model.mode = .stopwatch
        XCTAssertNotNil(model.configuration)
    }

    func testSwitchingModesRetainsCustomValues() {
        let model = FocusSetupModel(initialState: FocusStartConfigState(mode: .timer))
        model.countdown = "1h12m"
        model.mode = .pomodoro
        model.focus = "37m"
        model.mode = .timer
        XCTAssertEqual(model.configuration?.resolvedCountdownMinutes, 72)
        model.mode = .pomodoro
        XCTAssertEqual(model.configuration?.resolvedFocusMinutes, 37)
    }
}
