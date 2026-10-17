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
        appState.endSession.isSheetPresented = true

        appState.issueCreator.presentCreator()

        XCTAssertFalse(appState.issueCreator.isPresented)
    }

    func testIssueCreatorDoesNotOpenWhileIssueActionEditorIsPresented() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.issueActions.editor = .delete(issue: fixtureIssue)

        appState.issueCreator.presentCreator()

        XCTAssertFalse(appState.issueCreator.isPresented)
    }

    func testIssueCreatorIgnoresReopenUntilDismissalCompletes() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)

        appState.issueCreator.presentCreator()
        appState.issueCreator.cancel()
        appState.issueCreator.presentCreator()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(appState.issueCreator.isPresented)

        appState.issueCreator.presentCreator()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(appState.issueCreator.isPresented)
        XCTAssertTrue(appState.issueCreator.isContentVisible)
    }
}
