import XCTest
@testable import crona

@MainActor
final class IssueActionEditorModelTests: DaemonTestCase {
    private let fixtureIssue = DailyFocusIssue(id: 42, streamID: 7, title: "Fixture", status: "planned",
        estimateMinutes: nil, workedSeconds: 0, todoForDate: nil)

    func testManualSessionRejectsZeroWorkDuration() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.presentManualSession(for: fixtureIssue)
        appState.manualSessionWorkHours = 0
        appState.manualSessionWorkMinutes = 0

        appState.submitIssueActionEditor()
        await settleAsyncTasks()

        XCTAssertEqual(appState.manualSessionError, "Work duration must be a positive duration.")
        XCTAssertFalse(transport.methods.contains("session.log_manual"))
    }

    func testManualSessionConvertsTwelveHourClockToTwentyFourHour() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.presentManualSession(for: fixtureIssue)
        appState.manualSessionTimesEnabled = true
        appState.manualSessionStartHour = 12
        appState.manualSessionStartMinute = 5
        appState.manualSessionStartPeriod = "AM"
        appState.manualSessionEndHour = 1
        appState.manualSessionEndMinute = 30
        appState.manualSessionEndPeriod = "PM"

        appState.submitIssueActionEditor()
        await waitForIssueCreator { transport.methods.contains("session.log_manual") }

        let log = try XCTUnwrap(transport.requests.first(where: { $0.method == "session.log_manual" }))
        XCTAssertEqual(log.params["startTime"]?.stringValue, "00:05")
        XCTAssertEqual(log.params["endTime"]?.stringValue, "13:30")
    }

    func testStatusChangeRequiringNoteDoesNotSubmitBlankNote() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.requestIssueStatusChange(issue: fixtureIssue, status: .blocked)
        appState.issueActionNote = "   "

        appState.submitIssueActionEditor()
        await settleAsyncTasks()

        XCTAssertEqual(appState.issueActionEditor, .status(issue: fixtureIssue, status: .blocked))
        XCTAssertFalse(transport.methods.contains("issue.change_status"))
    }

    func testDeletingSelectedFocusIssueClearsSelection() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.selectedFocusIssue = fixtureIssue
        appState.presentDeleteIssue(for: fixtureIssue)

        appState.submitIssueActionEditor()
        await waitForIssueCreator { appState.issueActionEditor == nil }

        XCTAssertTrue(transport.methods.contains("issue.delete"))
        XCTAssertNil(appState.selectedFocusIssue)
    }
}
