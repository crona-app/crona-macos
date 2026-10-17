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
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
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

        await waitForIssueCreator { appState.popups.hardLimitPopupPhase == .decision }

        XCTAssertEqual(appState.popups.hardLimitPopupSessionID, "s1")
    }

    func testHardLimitReachedEventIsIgnoredWhenPopupsDisabled() async throws {
        let (appState, _, connection) = try await appStateWithHardLimitDecision(popupsEnabled: false)
        defer { connection.stop() }

        try await Task.sleep(for: .milliseconds(300))

        XCTAssertNil(appState.popups.hardLimitPopupPhase)
    }

    func testHardLimitExtendSendsRequestAndShowsSuccess() async throws {
        let (appState, transport, connection) = try await appStateWithHardLimitDecision()
        defer { connection.stop() }
        await waitForIssueCreator { appState.popups.hardLimitPopupPhase == .decision }

        appState.popups.chooseHardLimitExtend()
        XCTAssertEqual(appState.popups.hardLimitPopupPhase, .extend)
        appState.popups.confirmHardLimitExtend()
        await waitForIssueCreator { appState.popups.hardLimitPopupPhase == .success }

        XCTAssertEqual(transport.methods.filter { $0 == "timer.extend" }.count, 1)
    }

    func testHardLimitExtendFailureShowsErrorAndStaysInExtend() async throws {
        let (appState, transport, connection) = try await appStateWithHardLimitDecision()
        defer { connection.stop() }
        await waitForIssueCreator { appState.popups.hardLimitPopupPhase == .decision }
        transport.failExtend = true

        appState.popups.chooseHardLimitExtend()
        appState.popups.confirmHardLimitExtend()
        await waitForIssueCreator { appState.popups.hardLimitPopupErrorMessage != nil }

        XCTAssertFalse(appState.popups.isSubmittingHardLimitAction)
        XCTAssertEqual(appState.popups.hardLimitPopupPhase, .extend)
    }

    func testHardLimitChooseEndMovesToEndSessionPhase() async throws {
        let (appState, _, connection) = try await appStateWithHardLimitDecision()
        defer { connection.stop() }
        await waitForIssueCreator { appState.popups.hardLimitPopupPhase == .decision }

        appState.popups.chooseHardLimitEnd()

        XCTAssertEqual(appState.popups.hardLimitPopupPhase, .endSession)
        XCTAssertEqual(appState.endSession.pendingSessionID, "s1")
    }

    func testInactivityReturnToDecisionRestoresDecisionPhase() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.timerStateFixture = runningState
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.preferences.preferences.showInactivityActionPopups = true

        let presented = await appState.popups.presentInactivityPopup(for: try inactivityDelivery())
        XCTAssertTrue(presented)
        XCTAssertEqual(appState.popups.inactivityPopupPhase, .decision)
        appState.popups.chooseInactivityPopupEnd()
        XCTAssertEqual(appState.popups.inactivityPopupPhase, .endSession)
        appState.popups.returnToInactivityDecision()

        XCTAssertEqual(appState.popups.inactivityPopupPhase, .decision)
        XCTAssertNil(appState.endSession.pendingSessionID)
    }
}
