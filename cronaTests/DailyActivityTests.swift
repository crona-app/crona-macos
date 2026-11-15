import XCTest

@testable import crona

@MainActor
final class DailyActivityTests: DaemonTestCase {
    func testOperationsUseTimezoneBoundariesAndLatestSevenIssueUpdates() throws {
        let start = try XCTUnwrap(LibraryDates.timestamp("2026-11-15T00:00:00+05:30"))
        let end = try XCTUnwrap(LibraryDates.timestamp("2026-11-16T00:00:00+05:30"))
        var operations: [CronaIssueOperation] = (0..<10).map {
            CronaIssueOperation(
                id: String($0), entity: "issue", entityID: "1", action: "update", payload: nil,
                timestamp: "2026-11-15T\(String(format: "%02d", $0)):00:00+05:30")
        }
        operations += [
            CronaIssueOperation(
                id: "end", entity: "issue", entityID: "1", action: "delete", payload: nil,
                timestamp: "2026-11-16T00:00:00+05:30"),
            CronaIssueOperation(
                id: "other", entity: "habit", entityID: "1", action: "update", payload: nil,
                timestamp: "2026-11-15T10:00:00+05:30"),
        ]
        let updates = DailyActivityModel.updates(operations, start: start, end: end)
        XCTAssertEqual(updates.map(\.id), ["9", "8", "7", "6", "5", "4", "3"])
        let midnight = DailyActivityModel.updates([operations[0]], start: start, end: end)
        XCTAssertEqual(midnight.count, 1)
    }

    func testDaylightSavingBoundaryUsesAbsoluteInstants() throws {
        let start = try XCTUnwrap(LibraryDates.timestamp("2026-11-01T00:00:00-04:00"))
        let end = try XCTUnwrap(LibraryDates.timestamp("2026-11-02T00:00:00-05:00"))
        let operations = [
            CronaIssueOperation(
                id: "late", entity: "issue", entityID: "2", action: "delete", payload: nil,
                timestamp: "2026-11-01T23:30:00-05:00")
        ]
        XCTAssertEqual(DailyActivityModel.updates(operations, start: start, end: end).count, 1)
    }

    func testActionLabelsAndTitleFallbacks() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let model = DailyActivityModel(connection: connection, day: PopoverDayModel(today: { "2001-02-03" }))
        let op = CronaIssueOperation(
            id: "1", entity: "issue", entityID: "42", action: "update",
            payload: ["from": .string("ready"), "to": .string("done"), "title": .string("Original")], timestamp: "")
        XCTAssertEqual(op.actionLabel, "Ready → Done")
        XCTAssertEqual(model.title(for: op), "Original")
        XCTAssertNil(model.issue(for: op))
        let deletion = CronaIssueOperation(
            id: "2", entity: "issue", entityID: "42", action: "delete", payload: nil, timestamp: "")
        XCTAssertEqual(model.title(for: deletion), "Issue #42")
        XCTAssertEqual(deletion.actionLabel, "Deleted")
    }
}
