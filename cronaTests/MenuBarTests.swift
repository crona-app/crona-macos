import AppKit
import XCTest
@testable import crona

@MainActor
final class MenuBarTests: DaemonTestCase {
    func testMenuBarFormatterClockOmitsZeroHours() {
        XCTAssertEqual(MenuBarTextFormatter.formatClock(seconds: 247), "04:07")
        XCTAssertEqual(MenuBarTextFormatter.formatClock(seconds: 3_847), "1:04:07")
    }

    func testMenuBarIconStateFollowsConnectionAndTimerProjection() {
        var activeSnapshot = TimerSnapshot()
        activeSnapshot.sessionID = "session-1"
        activeSnapshot.state = "running"

        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .disconnected, timerSnapshot: activeSnapshot),
            .offline
        )
        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .connected, timerSnapshot: TimerSnapshot()),
            .idle
        )
        if case .focus(let progress) = MenuBarIconState.resolve(
            connectionState: .connected,
            timerSnapshot: activeSnapshot
        ) {
            XCTAssertGreaterThanOrEqual(progress, 0)
            XCTAssertLessThanOrEqual(progress, 1)
        } else {
            XCTFail("Expected focus icon state")
        }

        activeSnapshot.state = "paused"
        if case .paused = MenuBarIconState.resolve(
            connectionState: .connected,
            timerSnapshot: activeSnapshot
        ) {
        } else {
            XCTFail("Expected paused icon state")
        }

        activeSnapshot.state = "running"
        activeSnapshot.segmentType = "short_break"
        if case .breakTime = MenuBarIconState.resolve(
            connectionState: .connected,
            timerSnapshot: activeSnapshot
        ) {
        } else {
            XCTFail("Expected break icon state")
        }

        activeSnapshot.hardLimitExpired = true
        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .connected, timerSnapshot: activeSnapshot),
            .completed
        )
    }

    func testMenuBarIconStateClampsProgressAndMapsConnectingAndErrors() {
        XCTAssertEqual(
            MenuBarIconState.clamp(-1),
            0
        )
        XCTAssertEqual(
            MenuBarIconState.clamp(2),
            1
        )

        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .connecting, timerSnapshot: TimerSnapshot()),
            .connecting
        )
        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .error, timerSnapshot: TimerSnapshot()),
            .error
        )
        XCTAssertEqual(
            MenuBarIconState.resolve(connectionState: .incompatible, timerSnapshot: TimerSnapshot()),
            .error
        )
    }

    func testMenuBarIconRendererReturnsTemplateImagesForAllStates() {
        let renderer = CronaMenuBarIconRenderer()
        let states: [MenuBarIconState] = [
            .idle,
            .focus(progress: 0.5),
            .paused(progress: 0.5),
            .breakTime(progress: 0.5),
            .connecting,
            .offline,
            .error,
            .completed,
            .updateAvailable
        ]

        for state in states {
            let image = renderer.image(for: state, connectingPhase: 0.25)
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            XCTAssertTrue(image.isTemplate)
        }
    }

    func testMenuBarFormatterAdaptiveUsesContextualUnits() {
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 0), "0s")
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 59), "59s")
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 60), "1m")
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 3_599), "59m")
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 3_600), "1h")
        XCTAssertEqual(MenuBarTextFormatter.formatAdaptive(seconds: 3_847), "1h4m")
    }

    func testMenuBarFormatterFormatsMinutes() {
        XCTAssertEqual(MenuBarTextFormatter.formatMinutes(75), "1h15m")
    }

    func testMenuBarFormatterUsesIdleForConnectedWithoutTimer() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .iconAndText
        preferences.menuBarTimeFormat = .clock
        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences,
            connectionState: .connected,
            timerSnapshot: TimerSnapshot()
        )
        XCTAssertEqual(title, "Idle")
    }

    func testAdaptiveRefreshIntervalsFollowVisibleBoundaries() {
        XCTAssertEqual(
            MenuBarTextFormatter.nextRefreshInterval(
                seconds: 125,
                style: .adaptive,
                countsDown: true
            ),
            6
        )
        XCTAssertEqual(
            MenuBarTextFormatter.nextRefreshInterval(
                seconds: 125,
                style: .adaptive,
                countsDown: false
            ),
            55
        )
        XCTAssertEqual(
            MenuBarTextFormatter.nextRefreshInterval(
                seconds: 59,
                style: .adaptive,
                countsDown: true
            ),
            1
        )
        XCTAssertEqual(
            MenuBarTextFormatter.nextRefreshInterval(
                seconds: 3_600,
                style: .clock,
                countsDown: true
            ),
            1
        )
    }

    func testMenuBarFormatterUsesTodayFocusWhenIdle() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .textOnly
        preferences.menuBarIdleTextMode = .focusToday

        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences,
            connectionState: .connected,
            timerSnapshot: TimerSnapshot(),
            todayWorkedSeconds: 5_520
        )

        XCTAssertEqual(title, "1h32m")
    }

    func testMenuBarFormatterOmitsZeroHoursFromTodayFocus() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .textOnly
        preferences.menuBarIdleTextMode = .focusToday

        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences,
            connectionState: .connected,
            timerSnapshot: TimerSnapshot(),
            todayWorkedSeconds: 1_920
        )

        XCTAssertEqual(title, "32m")
    }

    func testMenuBarFormatterFallsBackToIdleWithoutTodayMetrics() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .iconAndText
        preferences.menuBarIdleTextMode = .focusToday

        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences,
            connectionState: .connected,
            timerSnapshot: TimerSnapshot()
        )

        XCTAssertEqual(title, "Idle")
    }

    func testMenuBarFormatterSupportsIssueBreakdownWhenIdle() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .textOnly
        preferences.menuBarIdleTextMode = .issueBreakdown
        let metrics = CronaDailyMetricsDay(
            date: "2026-08-09", workedSeconds: 3_600, restSeconds: 600,
            sessionCount: 2, totalIssues: 5, completedIssues: 2, abandonedIssues: 0,
            totalEstimatedMinutes: 120, habitDueCount: 0, habitCompletedCount: 0, habitFailedCount: 0
        )

        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences, connectionState: .connected,
            timerSnapshot: TimerSnapshot(), todayMetrics: metrics
        )

        XCTAssertEqual(title, "2/5")
    }

    func testMenuBarFormatterSupportsTotalTimeWhenIdle() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .textOnly
        preferences.menuBarIdleTextMode = .totalTime
        let metrics = CronaDailyMetricsDay(
            date: "2026-08-09", workedSeconds: 3_600, restSeconds: 600,
            sessionCount: 2, totalIssues: 0, completedIssues: 0, abandonedIssues: 0,
            totalEstimatedMinutes: 0, habitDueCount: 0, habitCompletedCount: 0, habitFailedCount: 0
        )

        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences, connectionState: .connected,
            timerSnapshot: TimerSnapshot(), todayMetrics: metrics
        )

        XCTAssertEqual(title, "1h10m")
    }

    func testMenuBarFormatterSupportsFocusScoreWhenIdle() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .textOnly
        preferences.menuBarIdleTextMode = .focusScore
        let score = CronaFocusScoreSummary(
            startDate: "2026-08-09", endDate: "2026-08-09", score: 87,
            level: "strong", workedSeconds: 3_600, restSeconds: 600,
            sessionCount: 2, focusDays: 1, days: 1, targetWorkedSeconds: 7_200
        )

        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences, connectionState: .connected,
            timerSnapshot: TimerSnapshot(), todayFocusScore: score
        )

        XCTAssertEqual(title, "87")
    }

    func testMenuBarFormatterKeepsTextOnlyItemReachableWhenDisconnected() {
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .textOnly

        let title = MenuBarTextFormatter.statusItemTitle(
            preferences: preferences,
            connectionState: .disconnected,
            timerSnapshot: TimerSnapshot()
        )

        XCTAssertEqual(title, "Offline")
    }
}
