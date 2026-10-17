import XCTest
@testable import crona

@MainActor
final class EndSessionModelTests: DaemonTestCase {
    private let expiredCountdownState: [String: Any] = [
        "state": "running", "sessionId": "s1", "elapsedSeconds": 1_500,
        "hardLimitActive": true, "hardLimitExpired": true, "hardLimitKind": "countdown",
    ]

    func testSessionEndedEventFinalizesPendingEndSessionAndHardLimitPopup() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.timerStateFixture = expiredCountdownState
        let appState = CompanionAppState(daemonConnection: connection)
        appState.preferences.preferences.showHardLimitActionPopups = true
        await appState.timerService.refresh()
        try postDaemonEvent(#"{"type":"timer.hard_limit_reached","payload":{"sessionId":"s1"}}"#)
        await waitForIssueCreator { appState.popups.hardLimitPopupPhase == .decision }
        appState.popups.chooseHardLimitEnd()
        XCTAssertEqual(appState.endSession.pendingSessionID, "s1")

        try postDaemonEvent(#"{"type":"session.ended","payload":{"sessionId":"s1"}}"#)
        await waitForIssueCreator { appState.popups.hardLimitPopupPhase == nil }

        XCTAssertNil(appState.endSession.pendingSessionID)
        XCTAssertNil(appState.popups.hardLimitPopupSessionID)
    }

    func testConfirmEndSessionRequiresSummaryForAdhocSessions() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.hasAdhocSession = true
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.endSession.begin(source: .menuPopover)

        appState.endSession.confirm()

        XCTAssertEqual(appState.endSession.errorMessage, "A session summary is required.")
        XCTAssertFalse(transport.methods.contains("timer.end"))
    }

    func testCancelEndSessionPreservesAdhocDraft() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.hasAdhocSession = true
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.endSession.begin(source: .menuPopover)
        appState.endSession.commitMessage = "draft"

        appState.endSession.cancel()
        appState.endSession.begin(source: .menuPopover)

        XCTAssertEqual(appState.endSession.commitMessage, "draft")
    }
}
