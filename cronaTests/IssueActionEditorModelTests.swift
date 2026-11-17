import XCTest
@testable import crona

@MainActor
final class IssueActionEditorModelTests: DaemonTestCase {
    private let fixtureIssue = DailyFocusIssue(id: 42, streamID: 7, title: "Fixture", status: "planned",
        estimateMinutes: nil, workedSeconds: 0, todoForDate: nil)

    func testManualSessionRejectsZeroWorkDuration() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.issueActions.presentManualSession(for: fixtureIssue)
        appState.issueActions.manualSession.workDuration = "0m"

        appState.issueActions.submit()
        await settleAsyncTasks()

        XCTAssertEqual(appState.issueActions.manualSessionError, "Work duration must be a positive duration.")
        XCTAssertFalse(transport.methods.contains("session.log_manual"))
    }

    func testManualSessionAcceptsMinutePrecisionClockInputs() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.issueActions.presentManualSession(for: fixtureIssue)
        appState.issueActions.manualSession.timesEnabled = true
        appState.issueActions.manualSession.startTime = "00:05"
        appState.issueActions.manualSession.endTime = "13:30"

        appState.issueActions.submit()
        await waitForIssueCreator { transport.methods.contains("session.log_manual") }

        let log = try XCTUnwrap(transport.requests.first(where: { $0.method == "session.log_manual" }))
        XCTAssertEqual(log.params["startTime"]?.stringValue, "00:05")
        XCTAssertEqual(log.params["endTime"]?.stringValue, "13:30")
    }

    func testManualSessionAllowsStartWithoutEnd() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.issueActions.presentManualSession(for: fixtureIssue)
        appState.issueActions.manualSession.timesEnabled = true
        appState.issueActions.manualSession.startTime = "09:07"
        appState.issueActions.submit()
        await waitForIssueCreator { transport.methods.contains("session.log_manual") }
        let log = try XCTUnwrap(transport.requests.first { $0.method == "session.log_manual" })
        XCTAssertEqual(log.params["startTime"]?.stringValue, "09:07")
        XCTAssertNil(log.params["endTime"]?.stringValue)
    }

    func testManualSessionLogsIndividualMinutes() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.issueActions.presentManualSession(for: fixtureIssue)
        appState.issueActions.manualSession.workDuration = "1h07m"
        appState.issueActions.manualSession.breakDuration = "13m"
        appState.issueActions.submit()
        await waitForIssueCreator { transport.methods.contains("session.log_manual") }

        let log = try XCTUnwrap(transport.requests.first { $0.method == "session.log_manual" })
        XCTAssertEqual(log.params["workDurationSeconds"]?.intValue, 4_020)
        XCTAssertEqual(log.params["breakDurationSeconds"]?.intValue, 780)
    }

    func testManualSessionRejectsInvalidDurationBeforeSending() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.issueActions.presentManualSession(for: fixtureIssue)
        for (work, rest) in [("bad", "0m"), ("1h", "bad"), ("1h", "-3m"), ("", "0m")] {
            appState.issueActions.manualSession.workDuration = work
            appState.issueActions.manualSession.breakDuration = rest
            appState.issueActions.submit()
            await settleAsyncTasks()
            XCTAssertNotNil(appState.issueActions.manualSessionError)
        }
        XCTAssertFalse(transport.methods.contains("session.log_manual"))
    }

    func testStatusChangeRequiringNoteDoesNotSubmitBlankNote() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.issueActions.requestStatusChange(issue: fixtureIssue, status: .blocked)
        appState.issueActions.note = "   "

        appState.issueActions.submit()
        await settleAsyncTasks()

        XCTAssertEqual(appState.issueActions.editor, .status(issue: fixtureIssue, status: .blocked))
        XCTAssertFalse(transport.methods.contains("issue.change_status"))
    }

    func testDeletingSelectedFocusIssueClearsSelection() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.selectedFocusIssue = fixtureIssue
        appState.issueActions.presentDelete(for: fixtureIssue)

        appState.issueActions.submit()
        await waitForIssueCreator { appState.issueActions.editor == nil }

        XCTAssertTrue(transport.methods.contains("issue.delete"))
        XCTAssertNil(appState.selectedFocusIssue)
    }
}
