import XCTest
@testable import crona

@MainActor
final class TimerPresentationTests: DaemonTestCase {
    func testHUDProgressProjectsFractionalTimeAndFreezesWhenPaused() {
        let now = Date(timeIntervalSince1970: 10_000)
        var snapshot = TimerSnapshot(
            state: "running", hardLimitActive: true, hardLimitKind: .countdown,
            hardLimitTotalSeconds: 100, hardLimitRemainingSeconds: 75, snapshotAppliedAt: now
        )
        XCTAssertEqual(TimerPresentation.elapsedProgressFraction(for: snapshot, at: now.addingTimeInterval(0.5)) ?? -1, 0.255, accuracy: 0.0001)
        snapshot.state = "paused"
        XCTAssertEqual(TimerPresentation.elapsedProgressFraction(for: snapshot, at: now.addingTimeInterval(30)) ?? -1, 0.25, accuracy: 0.0001)
        snapshot.hardLimitActive = false
        XCTAssertNil(TimerPresentation.elapsedProgressFraction(for: snapshot, at: now))
    }

    func testHUDProgressUsesPomodoroSegmentAndReadyState() {
        let now = Date(timeIntervalSince1970: 10_000)
        var snapshot = TimerSnapshot(
            state: "running", segmentType: "short_break", nextSegmentType: "work",
            segmentStartTime: now.addingTimeInterval(-15.5), segmentElapsedOffsetSeconds: 5,
            hardLimitActive: true, hardLimitKind: .pomodoro, hardLimitWorkSeconds: 100,
            hardLimitBreakSeconds: 50
        )
        XCTAssertEqual(TimerPresentation.elapsedProgressFraction(for: snapshot, at: now) ?? -1, 0.41, accuracy: 0.0001)
        XCTAssertEqual(TimerPresentation.elapsedProgressFraction(for: snapshot, at: now.addingTimeInterval(100)), 1)
        snapshot.state = "ready"
        XCTAssertEqual(TimerPresentation.elapsedProgressFraction(for: snapshot, at: now), 0)
        snapshot.hardLimitExpired = true
        XCTAssertEqual(TimerPresentation.elapsedProgressFraction(for: snapshot, at: now), 1)
    }

    func testTimerHUDVisibilityRequiresEnabledActiveTimerWithoutMenuPopover() {
        XCTAssertTrue(WindowService.timerHUDShouldBeVisible(
            preferencesEnabled: true,
            activeTimer: true,
            menuBarPopoverPresented: false
        ))
        XCTAssertFalse(WindowService.timerHUDShouldBeVisible(
            preferencesEnabled: true,
            activeTimer: true,
            menuBarPopoverPresented: true
        ))
        XCTAssertFalse(WindowService.timerHUDShouldBeVisible(
            preferencesEnabled: false,
            activeTimer: true,
            menuBarPopoverPresented: false
        ))
        XCTAssertFalse(WindowService.timerHUDShouldBeVisible(
            preferencesEnabled: true,
            activeTimer: false,
            menuBarPopoverPresented: false
        ))
        XCTAssertFalse(WindowService.timerHUDShouldBeVisible(
            preferencesEnabled: true,
            activeTimer: true,
            menuBarPopoverPresented: false,
            hardLimitPopupPresented: true
        ))
        XCTAssertTrue(WindowService.timerHUDShouldBeVisible(
            preferencesEnabled: true,
            activeTimer: true,
            menuBarPopoverPresented: false,
            hardLimitPopupPresented: false
        ))
    }

    func testTimerSnapshotAppliesRunningState() {
        let state = CronaTimerState(
            state: "running",
            sessionID: "session-1",
            sessionStartTime: "2026-06-09T00:00:00Z",
            issueID: 10,
            segmentType: "work",
            segmentStartTime: "2026-06-09T00:00:30Z",
            segmentElapsedOffsetSeconds: nil,
            readySegmentType: nil,
            nextSegmentType: "rest",
            elapsedSeconds: 90,
            hardLimitActive: false,
            hardLimitExpired: false,
            hardLimitTotalSeconds: 0,
            hardLimitRemainingSeconds: 0,
            hardLimitWorkSeconds: 0,
            hardLimitBreakSeconds: 0,
            hardLimitLongBreakSeconds: 0,
            hardLimitCyclesBeforeLongBreak: 0
        )

        let snapshot = TimerSnapshot.from(state)
        XCTAssertEqual(snapshot.state, "running")
        XCTAssertEqual(snapshot.sessionID, "session-1")
        XCTAssertEqual(snapshot.issueID, 10)
        XCTAssertEqual(snapshot.segmentType, "work")
        XCTAssertEqual(snapshot.elapsedSeconds, 90)
        XCTAssertTrue(snapshot.isConnected)
    }

    func testTimerPresentationClassifiesStructuredTimer() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            issueID: 10,
            segmentType: "work",
            nextSegmentType: nil,
            readySegmentType: nil,
            elapsedSeconds: 600,
            sessionStartTime: nil,
            segmentStartTime: nil,
            hardLimitActive: true,
            hardLimitKind: .countdown,
            hardLimitExpired: false,
            hardLimitTotalSeconds: 1800,
            hardLimitRemainingSeconds: 1200,
            hardLimitWorkSeconds: 1800,
            hardLimitBreakSeconds: 0,
            hardLimitLongBreakSeconds: 0,
            hardLimitCyclesBeforeLongBreak: 0,
            snapshotAppliedAt: now,
            isConnected: true
        )

        let presentation = TimerPresentation.from(snapshot, at: now)

        XCTAssertEqual(presentation.mode, .timer)
        XCTAssertTrue(presentation.countsDown)
        XCTAssertEqual(presentation.displaySeconds, 1200)
        XCTAssertEqual(presentation.progressFraction ?? 0, 2.0 / 3.0, accuracy: 0.001)
        XCTAssertFalse(presentation.canPause)
        XCTAssertFalse(presentation.canResume)
        XCTAssertEqual(presentation.phaseTitle, "Timer ends in")
    }

    func testTimerPresentationClassifiesPomodoroBreak() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            issueID: 10,
            segmentType: "rest",
            nextSegmentType: "work",
            readySegmentType: nil,
            elapsedSeconds: 1500,
            sessionStartTime: nil,
            segmentStartTime: nil,
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitExpired: false,
            hardLimitTotalSeconds: 1800,
            hardLimitRemainingSeconds: 300,
            hardLimitWorkSeconds: 1500,
            hardLimitBreakSeconds: 300,
            hardLimitLongBreakSeconds: 900,
            hardLimitCyclesBeforeLongBreak: 4,
            snapshotAppliedAt: now,
            isConnected: true
        )

        let presentation = TimerPresentation.from(snapshot, at: now)

        XCTAssertEqual(presentation.mode, .pomodoro)
        XCTAssertEqual(presentation.phaseTitle, "Break ends in")
        XCTAssertEqual(presentation.displaySeconds, 300)
        XCTAssertEqual(presentation.upcomingSegment?.kind, .work)
        XCTAssertEqual(presentation.upcomingSegment?.durationSeconds, 1500)
        XCTAssertFalse(presentation.canPause)
        XCTAssertFalse(presentation.canResume)
    }

    func testBreakScreenProjectionStartsPreparedPomodoroBreak() {
        let snapshot = TimerSnapshot(
            state: "ready",
            sessionID: "session-1",
            nextSegmentType: "short_break",
            readySegmentType: "short_break",
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitBreakSeconds: 300,
            isConnected: true
        )

        let projection = BreakScreenProjection.resolve(
            snapshot: snapshot,
            enabled: true,
            managedSessionID: nil
        )

        XCTAssertTrue(projection.shouldPresent)
        XCTAssertEqual(projection.transition, .startBreak)
        XCTAssertEqual(projection.segment, .shortBreak)
    }

    func testBreakScreenProjectionResumesWorkOnlyForManagedBreak() {
        let snapshot = TimerSnapshot(
            state: "ready",
            sessionID: "session-1",
            nextSegmentType: "work",
            readySegmentType: "work",
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            isConnected: true
        )

        let managed = BreakScreenProjection.resolve(
            snapshot: snapshot,
            enabled: false,
            managedSessionID: "session-1"
        )
        let unmanaged = BreakScreenProjection.resolve(
            snapshot: snapshot,
            enabled: true,
            managedSessionID: nil
        )

        XCTAssertEqual(managed.transition, .resumeWork)
        XCTAssertFalse(managed.shouldPresent)
        XCTAssertEqual(unmanaged.transition, .none)
    }

    func testBreakScreenProjectionIgnoresCountdownAndStopwatchStates() {
        let countdown = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            segmentType: "short_break",
            hardLimitActive: true,
            hardLimitKind: .countdown,
            isConnected: true
        )
        let stopwatch = TimerSnapshot(
            state: "paused",
            sessionID: "session-2",
            segmentType: "short_break",
            hardLimitActive: false,
            isConnected: true
        )

        XCTAssertFalse(
            BreakScreenProjection.resolve(
                snapshot: countdown,
                enabled: true,
                managedSessionID: nil
            ).shouldPresent
        )
        XCTAssertFalse(
            BreakScreenProjection.resolve(
                snapshot: stopwatch,
                enabled: true,
                managedSessionID: nil
            ).shouldPresent
        )
    }

    func testBreakScreenStrictDelayUsesAuthoritativeRemainingTime() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            segmentType: "short_break",
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitRemainingSeconds: 290,
            hardLimitBreakSeconds: 300,
            snapshotAppliedAt: now,
            isConnected: true
        )

        XCTAssertEqual(
            BreakScreenService.strictDelayRemaining(
                snapshot: snapshot,
                segment: .shortBreak,
                delaySeconds: 15,
                now: now
            ),
            5
        )

        XCTAssertEqual(
            BreakScreenService.strictDelayRemaining(
                snapshot: snapshot,
                segment: .shortBreak,
                delaySeconds: 15,
                now: now.addingTimeInterval(10)
            ),
            0
        )
    }

    func testTimerPresentationKeepsNoBreakPomodoroAsPomodoro() {
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            segmentType: "work",
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitTotalSeconds: 1500,
            hardLimitRemainingSeconds: 1200,
            hardLimitWorkSeconds: 1500,
            isConnected: true
        )

        let presentation = TimerPresentation.from(snapshot)

        XCTAssertEqual(presentation.mode, .pomodoro)
        XCTAssertEqual(presentation.phaseTitle, "Focus ends in")
        XCTAssertNil(presentation.upcomingSegment)
    }

    func testPomodoroWorkProjectionUsesCurrentSegmentDuration() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            segmentType: "work",
            nextSegmentType: "short_break",
            elapsedSeconds: 10,
            segmentStartTime: now.addingTimeInterval(-10),
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitTotalSeconds: 120,
            hardLimitRemainingSeconds: 110,
            hardLimitWorkSeconds: 60,
            hardLimitBreakSeconds: 60,
            snapshotAppliedAt: now,
            isConnected: true
        )
        let presentation = TimerPresentation.from(snapshot, at: now)

        XCTAssertEqual(presentation.displaySeconds, 50)
        XCTAssertEqual(presentation.progressFraction ?? 0, 5.0 / 6.0, accuracy: 0.001)
        XCTAssertEqual(presentation.phaseTitle, "Break starts in")
        XCTAssertEqual(presentation.upcomingSegment?.kind, .shortBreak)
        XCTAssertEqual(presentation.upcomingSegment?.durationSeconds, 60)
    }

    func testPomodoroBreakProjectionUsesBreakDurationAndUpcomingFocus() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            segmentType: "short_break",
            nextSegmentType: "work",
            elapsedSeconds: 15,
            segmentStartTime: now.addingTimeInterval(-15),
            hardLimitActive: true,
            hardLimitKind: .pomodoro,
            hardLimitTotalSeconds: 120,
            hardLimitRemainingSeconds: 45,
            hardLimitWorkSeconds: 60,
            hardLimitBreakSeconds: 60,
            snapshotAppliedAt: now,
            isConnected: true
        )
        let presentation = TimerPresentation.from(snapshot, at: now)

        XCTAssertEqual(presentation.displaySeconds, 45)
        XCTAssertEqual(presentation.progressFraction ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(presentation.phaseTitle, "Break ends in")
        XCTAssertEqual(presentation.upcomingSegment?.kind, .work)
        XCTAssertEqual(presentation.upcomingSegment?.durationSeconds, 60)
    }

    func testTimerPresentationAllowsPauseAndResumeOnlyForStopwatch() {
        let running = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            elapsedSeconds: 90,
            isConnected: true
        )
        let paused = TimerSnapshot(
            state: "paused",
            sessionID: "session-1",
            elapsedSeconds: 90,
            isConnected: true
        )

        let runningPresentation = TimerPresentation.from(running)
        let pausedPresentation = TimerPresentation.from(paused)

        XCTAssertEqual(runningPresentation.mode, .stopwatch)
        XCTAssertTrue(runningPresentation.canPause)
        XCTAssertFalse(runningPresentation.canResume)
        XCTAssertFalse(pausedPresentation.canPause)
        XCTAssertTrue(pausedPresentation.canResume)
    }

    func testTimerStartEndProjectionUsesConfiguredCountdown() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = FocusStartConfigState(
            mode: .timer,
            countdownChoice: .custom,
            customCountdownMinutes: 45
        )

        let endDate = try XCTUnwrap(TimerEndProjection.startEndDate(config: state, now: now))

        XCTAssertEqual(endDate, now.addingTimeInterval(45 * 60))
    }

    func testPomodoroStartEndProjectionUsesCompletePlan() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = FocusStartConfigState(
            mode: .pomodoro,
            focusChoice: .preset25,
            breakChoice: .preset5,
            longBreakChoice: .preset15,
            countdownChoice: .preset25,
            pomodoroCycles: 4,
            pomodoroCyclesBeforeLongBreak: 4
        )

        let endDate = try XCTUnwrap(TimerEndProjection.startEndDate(config: state, now: now))

        XCTAssertEqual(endDate, now.addingTimeInterval(7_800))
    }

    func testStopwatchHasNoProjectedEndDate() {
        let state = FocusStartConfigState(mode: .stopwatch)

        XCTAssertNil(TimerEndProjection.startEndDate(config: state))
    }

    func testActiveEndProjectionUsesAuthoritativeRemainingTime() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: true,
            hardLimitRemainingSeconds: 600,
            snapshotAppliedAt: now,
            isConnected: true
        )

        let endDate = try XCTUnwrap(TimerEndProjection.activeEndDate(snapshot: snapshot, now: now))

        XCTAssertEqual(endDate, now.addingTimeInterval(600))
    }

    func testActiveEndProjectionDisappearsAfterAuthoritativeExpiry() {
        let snapshot = TimerSnapshot(
            state: "expired",
            sessionID: "session-1",
            hardLimitActive: true,
            hardLimitExpired: true,
            hardLimitRemainingSeconds: 0,
            isConnected: true
        )

        XCTAssertNil(TimerEndProjection.activeEndDate(snapshot: snapshot))
    }

    func testTimerProjectionAdvancesWithoutMutatingAuthoritativeSnapshot() {
        let appliedAt = Date(timeIntervalSince1970: 10_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            elapsedSeconds: 90,
            snapshotAppliedAt: appliedAt,
            isConnected: true
        )

        XCTAssertEqual(
            TimerPresentation.projectedDisplaySeconds(
                for: snapshot,
                at: appliedAt.addingTimeInterval(14_400)
            ),
            14_490
        )
        XCTAssertEqual(snapshot.elapsedSeconds, 90)
    }

    func testTimerExtensionEndProjectionIncludesRemainingTime() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = TimerSnapshot(
            state: "running",
            sessionID: "session-1",
            hardLimitActive: true,
            hardLimitRemainingSeconds: 120,
            snapshotAppliedAt: now,
            isConnected: true
        )
        let request = CronaTimerExtendRequest(
            additionalSeconds: 300,
            additionalSessions: 1,
            hardLimitTotalSeconds: nil,
            hardLimitWorkSeconds: nil,
            hardLimitBreakSeconds: nil,
            hardLimitLongBreakSeconds: nil,
            hardLimitCyclesBeforeLongBreak: nil
        )

        let endDate = try XCTUnwrap(
            TimerEndProjection.extensionEndDate(snapshot: snapshot, request: request, now: now)
        )

        XCTAssertEqual(endDate, now.addingTimeInterval(420))
    }

    func testConfiguredExtensionEndProjectionUsesSessionCount() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = TimerSnapshot(
            state: "expired",
            sessionID: "session-1",
            hardLimitActive: true,
            hardLimitExpired: true,
            isConnected: true
        )
        let request = CronaTimerExtendRequest(
            additionalSeconds: 0,
            additionalSessions: 2,
            hardLimitTotalSeconds: 1_800,
            hardLimitWorkSeconds: 1_500,
            hardLimitBreakSeconds: 300,
            hardLimitLongBreakSeconds: 0,
            hardLimitCyclesBeforeLongBreak: 0
        )

        let endDate = try XCTUnwrap(
            TimerEndProjection.extensionEndDate(snapshot: snapshot, request: request, now: now)
        )

        XCTAssertEqual(endDate, now.addingTimeInterval(3_600))
    }
}
