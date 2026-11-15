import XCTest

@testable import crona

@MainActor
final class HabitHistoryTests: DaemonTestCase {
    func testHitRatesUseRecordedDaysAndInclusiveHistoricalWindow() throws {
        let records = try JSONDecoder().decode(
            [CronaHabitCompletion].self,
            from: Data(
                #"[{"id":1,"habitId":2,"date":"2026-11-09","status":"completed","durationMinutes":10},{"id":2,"habitId":2,"date":"2026-11-09","status":"failed","durationMinutes":5},{"id":3,"habitId":2,"date":"2026-11-15","status":"failed"},{"id":4,"habitId":2,"date":"2026-11-08","status":"completed"},{"id":5,"habitId":2,"date":"2026-11-16","status":"completed"},{"id":6,"habitId":3,"date":"2026-11-15","status":"completed"}]"#
                    .utf8))
        let outcomes = HabitHistoryModel.outcomes(records, habitID: 2, through: "2026-11-15")
        XCTAssertEqual(outcomes.count, 3)
        XCTAssertEqual(outcomes.first { $0.date == "2026-11-09" }?.minutes, 15)
        XCTAssertEqual(HabitHistoryModel.hitRate(outcomes, through: "2026-11-15", days: 7), 0.5)
        XCTAssertEqual(HabitHistoryModel.hitRate(outcomes, through: "2026-11-15", days: 30), 2.0 / 3)
        XCTAssertNil(HabitHistoryModel.hitRate([], through: "2026-11-15", days: 7))
    }

    func testVisibleHistoryRefreshesAfterHabitMutation() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.libraryFixtures["habit.history"] = [
            ["id": 1, "habitId": 2, "date": transport.logicalDate, "status": "failed"]
        ]
        let model = HabitHistoryModel(connection: connection)
        await model.refresh()
        XCTAssertEqual(model.records.first?.status, "failed")
        model.setVisible(true)
        transport.libraryFixtures["habit.history"] = [
            ["id": 1, "habitId": 2, "date": transport.logicalDate, "status": "completed"]
        ]
        try postDaemonEvent(#"{"type":"habit.completed","payload":{}}"#)
        await waitForIssueCreator { model.records.first?.status == "completed" }
    }
}
