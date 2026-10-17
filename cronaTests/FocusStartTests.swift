import XCTest
@testable import crona

@MainActor
final class FocusStartTests: DaemonTestCase {
    private let issue = DailyFocusIssue(id: 42, streamID: 7, title: "Fixture", status: "planned",
        estimateMinutes: nil, workedSeconds: 0, todoForDate: nil)
    private let config = FocusStartConfigState.defaultState(estimateMinutes: nil, workedSeconds: 0)

    func testFocusStartSendsTimerStartAndClearsSelectionOnSuccess() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.selectFocusIssue(issue)

        appState.startSelectedFocusSession(using: config)
        XCTAssertTrue(appState.isStartingFocus)
        await waitForIssueCreator { !appState.isStartingFocus }

        let start = try XCTUnwrap(transport.requests.first(where: { $0.method == "timer.start" }))
        XCTAssertEqual(start.params["issueId"]?.intValue, 42)
        XCTAssertEqual(start.params["streamId"]?.intValue, 7)
        XCTAssertNil(appState.selectedFocusIssue)
        XCTAssertNil(appState.focusStartError)
    }

    func testAdhocFocusStartSendsAdhocRequest() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.beginAdhocStart()

        appState.startSelectedFocusSession(using: config)
        await waitForIssueCreator { !appState.isStartingFocus }

        let start = try XCTUnwrap(transport.requests.first(where: { $0.method == "timer.start" }))
        XCTAssertEqual(start.params["adhoc"]?.boolValue, true)
        XCTAssertNil(start.params["issueId"]?.intValue)
        XCTAssertFalse(appState.isAdhocStartSelected)
    }

    func testFocusStartFailureKeepsSelectionAndReportsError() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.failStart = true
        let appState = CompanionAppState(daemonConnection: connection)
        appState.selectFocusIssue(issue)

        appState.startSelectedFocusSession(using: config)
        await waitForIssueCreator { appState.focusStartError != nil }

        XCTAssertEqual(appState.selectedFocusIssue?.id, 42)
        XCTAssertFalse(appState.isStartingFocus)
    }

    func testFocusStartDismissIsIgnoredWhileStarting() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.suspendStart = true
        let appState = CompanionAppState(daemonConnection: connection)
        appState.selectFocusIssue(issue)
        appState.startSelectedFocusSession(using: config)
        await waitForIssueCreator { transport.methods.contains("timer.start") }

        appState.dismissStartConfig()
        appState.startSelectedFocusSession(using: config)

        XCTAssertEqual(appState.selectedFocusIssue?.id, 42)
        XCTAssertTrue(appState.isStartingFocus)
        transport.resumeStart()
        await waitForIssueCreator { !appState.isStartingFocus }
        XCTAssertEqual(transport.methods.filter { $0 == "timer.start" }.count, 1)
    }

    func testFocusStartIsIgnoredWithoutSelection() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)

        appState.startSelectedFocusSession(using: config)
        await settleAsyncTasks()

        XCTAssertFalse(appState.isStartingFocus)
        XCTAssertFalse(transport.methods.contains("timer.start"))
    }

    func testFocusStartIsIgnoredDuringActiveSession() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.timerStateFixture = ["state": "running", "sessionId": "s1", "elapsedSeconds": 60]
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.timerService.refresh()
        appState.selectFocusIssue(issue)

        appState.startSelectedFocusSession(using: config)
        await settleAsyncTasks()

        XCTAssertFalse(transport.methods.contains("timer.start"))
    }

    func testAdhocStartOpensWhenConnectedAndNotAway() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.selectFocusIssue(issue)

        appState.beginAdhocStart()

        XCTAssertTrue(appState.isAdhocStartSelected)
        XCTAssertNil(appState.selectedFocusIssue)
    }

    func testAdhocStartIsBlockedWhenAway() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.awayModeEnabled = true
        let appState = CompanionAppState(daemonConnection: connection)
        await appState.coreSettingsService.refresh()
        XCTAssertTrue(appState.todayIsAway)

        appState.beginAdhocStart()

        XCTAssertFalse(appState.isAdhocStartSelected)
    }

    func testAdhocStartIsBlockedWhenDisconnected() async throws {
        let (connection, _) = try await issueCreatorConnection()
        let appState = CompanionAppState(daemonConnection: connection)
        connection.stop()
        connection.connectionState = .disconnected

        appState.beginAdhocStart()

        XCTAssertFalse(appState.isAdhocStartSelected)
    }
}
