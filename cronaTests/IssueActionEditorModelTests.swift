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
        appState.issueActions.presentManualSession(for: fixtureIssue)
        appState.issueActions.manualSession.workHours = 0
        appState.issueActions.manualSession.workMinutes = 0

        appState.issueActions.submit()
        await settleAsyncTasks()

        XCTAssertEqual(appState.issueActions.manualSessionError, "Work duration must be a positive duration.")
        XCTAssertFalse(transport.methods.contains("session.log_manual"))
    }

    func testManualSessionConvertsTwelveHourClockToTwentyFourHour() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.issueActions.presentManualSession(for: fixtureIssue)
        appState.issueActions.manualSession.timesEnabled = true
        appState.issueActions.manualSession.startHour = 12
        appState.issueActions.manualSession.startMinute = 5
        appState.issueActions.manualSession.startPeriod = "AM"
        appState.issueActions.manualSession.endHour = 1
        appState.issueActions.manualSession.endMinute = 30
        appState.issueActions.manualSession.endPeriod = "PM"

        appState.issueActions.submit()
        await waitForIssueCreator { transport.methods.contains("session.log_manual") }

        let log = try XCTUnwrap(transport.requests.first(where: { $0.method == "session.log_manual" }))
        XCTAssertEqual(log.params["startTime"]?.stringValue, "00:05")
        XCTAssertEqual(log.params["endTime"]?.stringValue, "13:30")
    }

    func testStatusChangeRequiringNoteDoesNotSubmitBlankNote() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
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
        let appState = CompanionAppState(daemonConnection: connection)
        appState.selectedFocusIssue = fixtureIssue
        appState.issueActions.presentDelete(for: fixtureIssue)

        appState.issueActions.submit()
        await waitForIssueCreator { appState.issueActions.editor == nil }

        XCTAssertTrue(transport.methods.contains("issue.delete"))
        XCTAssertNil(appState.selectedFocusIssue)
    }
}
