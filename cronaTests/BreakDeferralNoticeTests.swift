import XCTest
@testable import crona

@MainActor
final class BreakDeferralNoticeTests: DaemonTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)
    private var snapshot: TimerSnapshot {
        TimerSnapshot(state: "running", sessionID: "session", segmentType: "work",
            segmentStartTime: now.addingTimeInterval(-1_500), hardLimitActive: true)
    }

    func testDaemonDeferralEventRecordsNoticeForCurrentSession() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.timerStateFixture = ["state": "running", "sessionId": "session", "segmentType": "work",
            "segmentStartTime": "2026-11-17T09:00:00Z", "hardLimitActive": true,
            "hardLimitKind": "pomodoro", "hardLimitWorkSeconds": 1500]
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        await appState.timerService.refresh()
        try postDaemonEvent(#"{"type":"timer.break_deferred","payload":{"sessionId":"session"}}"#)
        await waitForIssueCreator {
            appState.breakDeferralNotice.suppressesWarning(for: appState.timerService.snapshot)
        }
        XCTAssertEqual(appState.breakDeferralNotice.indicator(for: appState.timerService.snapshot)?.kind, .breakDeferred)
    }

    func testConfirmedDeferralShowsNoticeThenSuppressesOldCountdown() {
        let model = BreakDeferralNoticeModel()
        model.record(sessionID: "session", snapshot: snapshot, now: now)
        XCTAssertEqual(model.indicator(for: snapshot, now: now)?.title, "Break deferred")
        XCTAssertEqual(model.indicator(for: snapshot, now: now)?.kind, .breakDeferred)
        XCTAssertNil(model.indicator(for: snapshot, now: now.addingTimeInterval(5)))
        XCTAssertTrue(model.suppressesWarning(for: snapshot))
    }

    func testOtherSessionEventsAreIgnored() {
        let model = BreakDeferralNoticeModel()
        model.record(sessionID: "other", snapshot: snapshot, now: now)
        XCTAssertFalse(model.suppressesWarning(for: snapshot))
    }

    func testNewSegmentRestoresWarnings() {
        let model = BreakDeferralNoticeModel()
        model.record(sessionID: "session", snapshot: snapshot, now: now)
        var next = snapshot
        next.segmentStartTime = now
        XCTAssertFalse(model.suppressesWarning(for: next))
        XCTAssertNil(model.indicator(for: next, now: now))
    }

    func testLeavingWorkClearsDeferral() {
        let model = BreakDeferralNoticeModel()
        model.record(sessionID: "session", snapshot: snapshot, now: now)
        var next = snapshot
        next.segmentType = "short_break"
        XCTAssertFalse(model.suppressesWarning(for: next))
    }
}
