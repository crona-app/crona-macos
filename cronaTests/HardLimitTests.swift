import XCTest
@testable import crona

@MainActor
final class HardLimitTests: DaemonTestCase {
    func testHardLimitExtendChoiceMapsTimerValues() {
        XCTAssertEqual(HardLimitExtendChoice.minutes1.secondsValue, 60)
        XCTAssertEqual(HardLimitExtendChoice.minutes5.secondsValue, 300)
        XCTAssertEqual(HardLimitExtendChoice.minutes15.secondsValue, 900)
        XCTAssertNil(HardLimitExtendChoice.minutes15.sessionValue)
    }

    func testHardLimitExtendChoiceMapsPomodoroValues() {
        XCTAssertEqual(HardLimitExtendChoice.session1.sessionValue, 1)
        XCTAssertEqual(HardLimitExtendChoice.session2.sessionValue, 2)
        XCTAssertNil(HardLimitExtendChoice.session1.secondsValue)
    }

    func testHardLimitCountdownAdvancesAndExpiresOnce() {
        var state = HardLimitCountdownState(duration: 30)

        XCTAssertFalse(state.advance(by: 12))
        XCTAssertEqual(state.remaining, 18)
        XCTAssertEqual(state.progress, 0.6, accuracy: 0.001)
        XCTAssertEqual(state.displayedSeconds, 18)

        XCTAssertTrue(state.advance(by: 18))
        XCTAssertEqual(state.remaining, 0)
        XCTAssertFalse(state.isRunning)
        XCTAssertFalse(state.advance(by: 1))
    }

    func testHardLimitCountdownPausePreservesRemainingTime() {
        var state = HardLimitCountdownState(duration: 30)
        state.isPaused = true

        XCTAssertFalse(state.advance(by: 3))
        XCTAssertEqual(state.remaining, 30)

        state.isPaused = false
        XCTAssertFalse(state.advance(by: 2.5))
        XCTAssertEqual(state.remaining, 27.5)
        XCTAssertEqual(state.displayedSeconds, 28)
    }

    func testHardLimitCountdownClampsProjection() {
        let state = HardLimitCountdownState(duration: 30, remaining: 40)

        XCTAssertEqual(state.remaining, 30)
        XCTAssertEqual(state.progress, 1)
    }

    func testHardLimitCountdownWaitsForAllPauseReasonsToClear() {
        let service = HardLimitCountdownService()
        service.start {}
        XCTAssertEqual(service.state.duration, 30)

        service.setPaused(true, reason: .hoverEnd)
        service.setPaused(true, reason: .keyboardFocus)
        XCTAssertTrue(service.state.isPaused)

        service.setPaused(false, reason: .hoverEnd)
        XCTAssertTrue(service.state.isPaused)

        service.setPaused(false, reason: .keyboardFocus)
        XCTAssertFalse(service.state.isPaused)
        service.cancel()
    }

    func testHardLimitSessionTimeSummaryUsesConsumedLimitTime() {
        let summary = HardLimitSessionTimeSummary.from(
            TimerSnapshot(
                state: "expired",
                sessionID: "session-1",
                hardLimitActive: true,
                hardLimitExpired: true,
                hardLimitTotalSeconds: 1_800,
                hardLimitRemainingSeconds: 0,
                isConnected: true
            )
        )

        XCTAssertEqual(summary.spentSeconds, 1_800)
        XCTAssertEqual(summary.limitSeconds, 1_800)
        XCTAssertEqual(summary.spentText, "30:00")
    }

    func testHardLimitSessionTimeSummaryClampsRemainingTime() {
        let overLimit = HardLimitSessionTimeSummary.from(
            TimerSnapshot(
                hardLimitActive: true,
                hardLimitTotalSeconds: 600,
                hardLimitRemainingSeconds: 900
            )
        )
        let negativeRemaining = HardLimitSessionTimeSummary.from(
            TimerSnapshot(
                hardLimitActive: true,
                hardLimitTotalSeconds: 600,
                hardLimitRemainingSeconds: -10
            )
        )

        XCTAssertEqual(overLimit.spentSeconds, 0)
        XCTAssertEqual(negativeRemaining.spentSeconds, 600)
    }

    func testHardLimitSessionTimeSummaryFallsBackToStopwatchElapsedTime() {
        let summary = HardLimitSessionTimeSummary.from(
            TimerSnapshot(state: "running", elapsedSeconds: 125, isConnected: true)
        )

        XCTAssertEqual(summary.spentSeconds, 125)
        XCTAssertEqual(summary.limitSeconds, 0)
    }
}
