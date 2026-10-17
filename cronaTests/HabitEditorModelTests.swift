import XCTest
@testable import crona

@MainActor
final class HabitEditorModelTests: DaemonTestCase {
    func testHabitCreatorRejectsEmptyName() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.habitEditor.presentCreator()
        appState.habitEditor.name = "   "
        appState.habitEditor.destinationID = 7

        appState.habitEditor.submit()
        await settleAsyncTasks()

        XCTAssertEqual(appState.habitEditor.error, "Enter a habit name.")
        XCTAssertFalse(transport.methods.contains("habit.create"))
    }

    func testHabitCreatorRequiresWeekdayForWeeklySchedule() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.habitEditor.presentCreator()
        appState.habitEditor.name = "Read"
        appState.habitEditor.destinationID = 7
        appState.habitEditor.scheduleType = "weekly"

        appState.habitEditor.submit()

        XCTAssertEqual(appState.habitEditor.error, "Select at least one weekday.")
    }

    func testHabitCreatorRequiresDestination() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.habitEditor.presentCreator()
        appState.habitEditor.name = "Read"
        appState.habitEditor.destinationID = nil

        appState.habitEditor.submit()

        XCTAssertEqual(appState.habitEditor.error, "Choose a repository and stream.")
    }

    func testHabitCreatorSendsCreateRequestAndCloses() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.habitEditor.presentCreator()
        appState.habitEditor.name = "Read"
        appState.habitEditor.target = "30m"
        appState.habitEditor.scheduleType = "weekly"
        appState.habitEditor.weekdays = [3, 1]
        appState.habitEditor.destinationID = 7

        appState.habitEditor.submit()
        await waitForIssueCreator { !appState.habitEditor.isPresented }

        let create = try XCTUnwrap(transport.requests.first(where: { $0.method == "habit.create" }))
        XCTAssertEqual(create.params["weekdays"]?.intArrayValue, [1, 3])
        XCTAssertEqual(create.params["targetMinutes"]?.intValue, 30)
        XCTAssertNil(appState.habitEditor.error)
    }

    func testHabitCreatorDoesNotOpenWhileEndSessionSheetIsPresented() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.endSession.isSheetPresented = true

        appState.habitEditor.presentCreator()

        XCTAssertFalse(appState.habitEditor.isPresented)
    }
}
