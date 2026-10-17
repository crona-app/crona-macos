import XCTest
@testable import crona

@MainActor
final class HabitsTests: DaemonTestCase {
    func testHabitsServiceRefreshesForHabitCompletionEvents() {
        XCTAssertTrue(HabitsService.shouldRefresh(for: "habit.completed"))
        XCTAssertTrue(HabitsService.shouldRefresh(for: "habit.uncompleted"))
        XCTAssertFalse(HabitsService.shouldRefresh(for: "timer.state"))
    }

    func testHabitRowActionSwitchesByCompletionState() {
        let pending = HabitRowModel(
            id: 1,
            name: "Stretch",
            repoName: "Crona",
            streamName: "Health",
            status: "completed",
            completed: false,
            durationMinutes: nil,
            targetMinutes: 15
        )
        let completed = HabitRowModel(
            id: 2,
            name: "Walk",
            repoName: "Crona",
            streamName: "Health",
            status: "completed",
            completed: true,
            durationMinutes: 12,
            targetMinutes: 15
        )
        let failed = HabitRowModel(
            id: 3,
            name: "Sleep",
            repoName: "Crona",
            streamName: "Health",
            status: "failed",
            completed: false,
            durationMinutes: nil,
            targetMinutes: nil
        )

        XCTAssertFalse(pending.supportsClearAction)
        XCTAssertTrue(completed.supportsClearAction)
        XCTAssertTrue(failed.supportsClearAction)
    }

    func testHabitDurationFormatterSupportsHoursMinutesAndSeconds() {
        XCTAssertEqual(HabitDurationFormatter.seconds(from: "1h20m30s"), 4_830)
        XCTAssertEqual(HabitDurationFormatter.seconds(from: "01:20:30"), 4_830)
        XCTAssertEqual(HabitDurationFormatter.string(from: 4_830), "1h20m30s")
        XCTAssertNil(HabitDurationFormatter.seconds(from: "1h75m"))
    }
}
