import XCTest
@testable import crona

@MainActor
final class BreakDeferralNoticeTests: DaemonTestCase {
    func testConfirmedDeferralProjectsTheNewBreakDeadlineUntilTheSegmentChanges() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let now = Date()
        let segmentStart = now.addingTimeInterval(-1495)
        let start = ISO8601DateFormatter().string(from: segmentStart)
        transport.timerStateFixture = [
            "state": "running", "sessionId": "session", "segmentType": "work",
            "segmentStartTime": start, "nextSegmentType": "short_break",
            "hardLimitActive": true, "hardLimitKind": "pomodoro", "hardLimitWorkSeconds": 1500,
            "hardLimitBreakSeconds": 300, "hardLimitTotalSeconds": 3600
        ]
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        let timer = appState.timerService
        await timer.refresh()
        try postDaemonEvent(#"{"type":"timer.break_deferred","payload":{"sessionId":"other"}}"#)
        await settleAsyncTasks()
        XCTAssertNil(timer.snapshot.breakDeferral)

        transport.timerStateFixture?["hardLimitTotalSeconds"] = 3660
        try postDaemonEvent(#"{"type":"timer.break_deferred","payload":{"sessionId":"session"}}"#)
        await waitForIssueCreator {
            timer.snapshot.breakDeferral?.additionalSeconds == 60
                && appState.popups.hardLimitWarningIndicatorModel?.kind == .breakDeferred
        }
        let snapshot = timer.snapshot
        let parsedStart = try XCTUnwrap(snapshot.segmentStartTime)
        let deadline = parsedStart.addingTimeInterval(1560)
        let presentation = TimerPresentation.from(snapshot, at: deadline.addingTimeInterval(-45))
        XCTAssertTrue(presentation.isBreakDeferred)
        XCTAssertEqual(presentation.displaySeconds, 45)
        XCTAssertGreaterThan(presentation.progressFraction ?? 0, 0)
        XCTAssertLessThan(presentation.progressFraction ?? 1, 1)
        var preferences = CompanionPreferences()
        preferences.menuBarDisplayMode = .iconAndText
        preferences.menuBarTimeFormat = .clock
        XCTAssertEqual(MenuBarTextFormatter.statusItemTitle(
            preferences: preferences, connectionState: .connected,
            timerSnapshot: snapshot, now: deadline.addingTimeInterval(-45)
        ), "00:45")
        XCTAssertEqual(TimerEndProjection.activeEndDate(snapshot: snapshot, now: deadline.addingTimeInterval(-45)), deadline)
        XCTAssertEqual(TimerPresentation.projectedDisplaySeconds(for: snapshot, at: deadline.addingTimeInterval(1)), 0)
        let deferral = try XCTUnwrap(snapshot.breakDeferral)
        XCTAssertTrue(deferral.showsConfirmation(at: deferral.confirmedAt))
        XCTAssertFalse(deferral.showsConfirmation(at: deferral.confirmedAt.addingTimeInterval(5)))

        await timer.refresh()
        XCTAssertEqual(timer.snapshot.breakDeferral, snapshot.breakDeferral)

        transport.timerStateFixture?["segmentType"] = "short_break"
        transport.timerStateFixture?["nextSegmentType"] = "work"
        await timer.refresh()
        XCTAssertNil(timer.snapshot.breakDeferral)
        XCTAssertFalse(TimerPresentation.from(timer.snapshot).isBreakDeferred)
    }

    func testDeferralCanBeConfirmedAfterARefreshHasAlreadySeenTheExtension() {
        let now = Date(timeIntervalSince1970: 10_000)
        let original = TimerSnapshot(
            state: "running", sessionID: "session", segmentType: "work",
            segmentStartTime: now.addingTimeInterval(-1495), hardLimitActive: true,
            hardLimitKind: .pomodoro, hardLimitTotalSeconds: 3600, hardLimitWorkSeconds: 1500,
            snapshotAppliedAt: now
        )
        var updated = original
        updated.hardLimitTotalSeconds = 3630
        var tracker = TimerBreakDeferralTracker()
        XCTAssertNil(tracker.reconcile(next: original))
        XCTAssertNil(tracker.reconcile(next: updated))
        let confirmed = tracker.confirm(sessionID: "session", snapshot: updated, at: now)
        XCTAssertEqual(confirmed?.additionalSeconds, 30)
        XCTAssertEqual(confirmed?.remainingSeconds(for: updated, at: now), 35)
    }
}
