import Combine
import XCTest
@testable import crona

@MainActor
final class CompanionAppStateFanInTests: DaemonTestCase {
    func testTimerSessionChangeFinalizesStaleEndSessionSheet() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.timerStateFixture = ["state": "running", "sessionId": "s1", "elapsedSeconds": 60]
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.endSession.begin(source: .menuPopover)
        XCTAssertTrue(appState.endSession.isSheetPresented)

        transport.timerStateFixture = ["state": "running", "sessionId": "s2", "elapsedSeconds": 1]
        await appState.timerService.refresh()
        await waitForIssueCreator { !appState.endSession.isSheetPresented }

        XCTAssertNil(appState.endSession.pendingSessionID)
    }

    func testTimerSnapshotChangeRunsPopupReconcile() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.timerStateFixture = [
            "state": "running", "sessionId": "s1", "elapsedSeconds": 1_500,
            "hardLimitActive": true, "hardLimitExpired": true, "hardLimitKind": "countdown",
        ]
        let appState = CompanionAppState(daemonConnection: connection)
        appState.preferences.preferences.showHardLimitActionPopups = true
        await appState.timerService.refresh()
        try postDaemonEvent(#"{"type":"timer.hard_limit_reached","payload":{"sessionId":"s1"}}"#)
        await waitForIssueCreator { appState.popups.hardLimitPopupPhase == .decision }

        appState.timerService.snapshot = TimerSnapshot(state: "idle")
        await waitForIssueCreator { appState.popups.hardLimitPopupPhase == nil }

        XCTAssertNil(appState.popups.hardLimitPopupSessionID)
    }

    func testUnrelatedServiceChangeDoesNotPublishAppStateChange() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        await settleAsyncTasks()
        var publications = 0
        let cancellable = appState.objectWillChange.sink { publications += 1 }

        appState.diagnosticsService.snapshot = DiagnosticsSnapshot(lastError: "x")
        await settleAsyncTasks()

        XCTAssertEqual(publications, 0)
        withExtendedLifetime(cancellable) {}
    }
}
