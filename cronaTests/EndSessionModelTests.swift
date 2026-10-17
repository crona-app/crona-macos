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
        await waitForIssueCreator { appState.hardLimitPopupPhase == .decision }
        appState.chooseHardLimitEnd()
        XCTAssertEqual(appState.pendingEndSessionID, "s1")

        try postDaemonEvent(#"{"type":"session.ended","payload":{"sessionId":"s1"}}"#)
        await waitForIssueCreator { appState.hardLimitPopupPhase == nil }

        XCTAssertNil(appState.pendingEndSessionID)
        XCTAssertNil(appState.hardLimitPopupSessionID)
    }

    func testConfirmEndSessionRequiresSummaryForAdhocSessions() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.hasAdhocSession = true
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.beginEndSession(source: .menuPopover)

        appState.confirmEndSession()

        XCTAssertEqual(appState.endSessionErrorMessage, "A session summary is required.")
        XCTAssertFalse(transport.methods.contains("timer.end"))
    }

    func testCancelEndSessionPreservesAdhocDraft() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.hasAdhocSession = true
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.beginEndSession(source: .menuPopover)
        appState.endSessionCommitMessage = "draft"

        appState.cancelEndSession()
        appState.beginEndSession(source: .menuPopover)

        XCTAssertEqual(appState.endSessionCommitMessage, "draft")
    }
}
