import XCTest
@testable import crona

@MainActor
final class IssueCreatorModelTests: DaemonTestCase {
    private let fixtureIssue = DailyFocusIssue(id: 42, streamID: 7, title: "Fixture", status: "planned",
        estimateMinutes: nil, workedSeconds: 0, todoForDate: nil)

    func testIssueCreatorDoesNotOpenWhileEndSessionSheetIsPresented() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.isEndSessionSheetPresented = true

        appState.presentIssueCreator()

        XCTAssertFalse(appState.isIssueCreatorPresented)
    }

    func testIssueCreatorDoesNotOpenWhileIssueActionEditorIsPresented() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.issueActionEditor = .delete(issue: fixtureIssue)

        appState.presentIssueCreator()

        XCTAssertFalse(appState.isIssueCreatorPresented)
    }

    func testIssueCreatorIgnoresReopenUntilDismissalCompletes() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)

        appState.presentIssueCreator()
        appState.cancelIssueCreator()
        appState.presentIssueCreator()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(appState.isIssueCreatorPresented)

        appState.presentIssueCreator()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(appState.isIssueCreatorPresented)
        XCTAssertTrue(appState.isIssueCreatorContentVisible)
    }
}
