import XCTest
@testable import crona

@MainActor
final class PopupCoordinatorTests: DaemonTestCase {
    private let expiredCountdownState: [String: Any] = [
        "state": "running", "sessionId": "s1", "elapsedSeconds": 1_500,
        "hardLimitActive": true, "hardLimitExpired": true, "hardLimitKind": "countdown",
    ]
    private let runningState: [String: Any] = ["state": "running", "sessionId": "s1", "elapsedSeconds": 100]

    private func appStateWithHardLimitDecision(
        popupsEnabled: Bool = true
    ) async throws -> (CompanionAppState, IssueCreatorTestTransport, DaemonConnectionService) {
        let (connection, transport) = try await issueCreatorConnection()
        transport.timerStateFixture = expiredCountdownState
        let appState = CompanionAppState(daemonConnection: connection)
        appState.preferences.preferences.showHardLimitActionPopups = popupsEnabled
        await appState.timerService.refresh()
        try postDaemonEvent(#"{"type":"timer.hard_limit_reached","payload":{"sessionId":"s1"}}"#)
        return (appState, transport, connection)
    }

    private func inactivityDelivery() throws -> CronaAlertDelivery {
        let event = try JSONDecoder().decode(CronaProtocolEvent.self, from: Data(#"""
            {"type":"alert.delivery","payload":{"id":"alert-9",
              "alert":{"kind":"timer.inactivity","title":"Still there?","body":"","urgency":"normal",
                "iconEnabled":true,"playSound":false},
              "deliverNotification":true,"playSound":false}}
            """#.utf8))
        return try event.decodePayload(CronaAlertDelivery.self)
    }

    func testHardLimitReachedEventPresentsDecisionPhase() async throws {
        let (appState, _, connection) = try await appStateWithHardLimitDecision()
        defer { connection.stop() }

        await waitForIssueCreator { appState.hardLimitPopupPhase == .decision }

        XCTAssertEqual(appState.hardLimitPopupSessionID, "s1")
    }

    func testHardLimitReachedEventIsIgnoredWhenPopupsDisabled() async throws {
        let (appState, _, connection) = try await appStateWithHardLimitDecision(popupsEnabled: false)
        defer { connection.stop() }

        try await Task.sleep(for: .milliseconds(300))

        XCTAssertNil(appState.hardLimitPopupPhase)
    }

    func testHardLimitExtendSendsRequestAndShowsSuccess() async throws {
        let (appState, transport, connection) = try await appStateWithHardLimitDecision()
        defer { connection.stop() }
        await waitForIssueCreator { appState.hardLimitPopupPhase == .decision }

        appState.chooseHardLimitExtend()
        XCTAssertEqual(appState.hardLimitPopupPhase, .extend)
        appState.confirmHardLimitExtend()
        await waitForIssueCreator { appState.hardLimitPopupPhase == .success }

        XCTAssertEqual(transport.methods.filter { $0 == "timer.extend" }.count, 1)
    }

    func testHardLimitExtendFailureShowsErrorAndStaysInExtend() async throws {
        let (appState, transport, connection) = try await appStateWithHardLimitDecision()
        defer { connection.stop() }
        await waitForIssueCreator { appState.hardLimitPopupPhase == .decision }
        transport.failExtend = true

        appState.chooseHardLimitExtend()
        appState.confirmHardLimitExtend()
        await waitForIssueCreator { appState.hardLimitPopupErrorMessage != nil }

        XCTAssertFalse(appState.isSubmittingHardLimitAction)
        XCTAssertEqual(appState.hardLimitPopupPhase, .extend)
    }

    func testHardLimitChooseEndMovesToEndSessionPhase() async throws {
        let (appState, _, connection) = try await appStateWithHardLimitDecision()
        defer { connection.stop() }
        await waitForIssueCreator { appState.hardLimitPopupPhase == .decision }

        appState.chooseHardLimitEnd()

        XCTAssertEqual(appState.hardLimitPopupPhase, .endSession)
        XCTAssertEqual(appState.endSession.pendingSessionID, "s1")
    }

    func testInactivityReturnToDecisionRestoresDecisionPhase() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.timerStateFixture = runningState
        let appState = CompanionAppState(daemonConnection: connection)
        appState.preferences.preferences.showInactivityActionPopups = true

        let presented = await appState.presentInactivityPopup(for: try inactivityDelivery())
        XCTAssertTrue(presented)
        XCTAssertEqual(appState.inactivityPopupPhase, .decision)
        appState.chooseInactivityPopupEnd()
        XCTAssertEqual(appState.inactivityPopupPhase, .endSession)
        appState.returnToInactivityDecision()

        XCTAssertEqual(appState.inactivityPopupPhase, .decision)
        XCTAssertNil(appState.endSession.pendingSessionID)
    }
}
