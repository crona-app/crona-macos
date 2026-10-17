import XCTest
@testable import crona

@MainActor
final class HabitEditorModelTests: DaemonTestCase {
    func testHabitCreatorRejectsEmptyName() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.presentHabitCreator()
        appState.habitCreateName = "   "
        appState.habitCreateDestinationID = 7

        appState.submitHabitCreator()
        await settleAsyncTasks()

        XCTAssertEqual(appState.habitCreateError, "Enter a habit name.")
        XCTAssertFalse(transport.methods.contains("habit.create"))
    }

    func testHabitCreatorRequiresWeekdayForWeeklySchedule() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.presentHabitCreator()
        appState.habitCreateName = "Read"
        appState.habitCreateDestinationID = 7
        appState.habitCreateScheduleType = "weekly"

        appState.submitHabitCreator()

        XCTAssertEqual(appState.habitCreateError, "Select at least one weekday.")
    }

    func testHabitCreatorRequiresDestination() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.presentHabitCreator()
        appState.habitCreateName = "Read"
        appState.habitCreateDestinationID = nil

        appState.submitHabitCreator()

        XCTAssertEqual(appState.habitCreateError, "Choose a repository and stream.")
    }

    func testHabitCreatorSendsCreateRequestAndCloses() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.presentHabitCreator()
        appState.habitCreateName = "Read"
        appState.habitCreateTarget = "30m"
        appState.habitCreateScheduleType = "weekly"
        appState.habitCreateWeekdays = [3, 1]
        appState.habitCreateDestinationID = 7

        appState.submitHabitCreator()
        await waitForIssueCreator { !appState.isHabitCreatorPresented }

        let create = try XCTUnwrap(transport.requests.first(where: { $0.method == "habit.create" }))
        XCTAssertEqual(create.params["weekdays"]?.intArrayValue, [1, 3])
        XCTAssertEqual(create.params["targetMinutes"]?.intValue, 30)
        XCTAssertNil(appState.habitCreateError)
    }

    func testHabitCreatorDoesNotOpenWhileEndSessionSheetIsPresented() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection)
        appState.endSession.isSheetPresented = true

        appState.presentHabitCreator()

        XCTAssertFalse(appState.isHabitCreatorPresented)
    }
}
