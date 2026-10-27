import XCTest
@testable import crona

@MainActor
final class PopoverDayModelTests: DaemonTestCase {
    private var today = "2026-10-27"

    private func makeDay() -> PopoverDayModel {
        PopoverDayModel(today: { [unowned self] in today })
    }

    func testStartsOnToday() {
        let day = makeDay()
        XCTAssertEqual(day.selectedDate, "2026-10-27")
        XCTAssertTrue(day.isToday)
        XCTAssertFalse(day.canShowNextDay)
    }

    func testPreviousThenNextReturnsToToday() {
        let day = makeDay()
        day.showPreviousDay()
        XCTAssertEqual(day.selectedDate, "2026-10-26")
        XCTAssertFalse(day.isToday)
        XCTAssertTrue(day.canShowNextDay)
        day.showNextDay()
        XCTAssertEqual(day.selectedDate, "2026-10-27")
    }

    func testNextDayStopsAtToday() {
        let day = makeDay()
        var changes: [String] = []
        day.onChange = { changes.append($0) }
        day.showNextDay()
        XCTAssertEqual(day.selectedDate, "2026-10-27")
        XCTAssertEqual(changes, [])
    }

    func testSelectFutureDateClampsToToday() {
        let day = makeDay()
        day.showPreviousDay()
        day.select("2026-11-02")
        XCTAssertEqual(day.selectedDate, "2026-10-27")
    }

    func testOnChangeFiresOncePerChange() {
        let day = makeDay()
        var changes: [String] = []
        day.onChange = { changes.append($0) }
        day.select("2026-10-20")
        day.select("2026-10-20")
        day.showToday()
        day.showToday()
        XCTAssertEqual(changes, ["2026-10-20", "2026-10-27"])
    }

    func testDayStartMovesViewerOfOldToday() {
        let day = makeDay()
        today = "2026-10-28"
        day.handleDayStart(date: "2026-10-28", previousDate: "2026-10-27")
        XCTAssertEqual(day.selectedDate, "2026-10-28")
    }

    func testDayStartKeepsEarlierDay() {
        let day = makeDay()
        day.select("2026-10-25")
        today = "2026-10-28"
        day.handleDayStart(date: "2026-10-28", previousDate: "2026-10-27")
        XCTAssertEqual(day.selectedDate, "2026-10-25")
    }

    private func dates(_ transport: IssueCreatorTestTransport, _ method: String) -> [String] {
        transport.requests.filter { $0.method == method }.compactMap { $0.params["date"]?.stringValue }
    }

    private func appStateOnPreviousDay() async throws -> (CompanionAppState, IssueCreatorTestTransport, String) {
        let (connection, transport) = try await issueCreatorConnection()
        addTeardownBlock { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        await settleAsyncTasks()
        appState.day.showPreviousDay()
        let previous = appState.day.selectedDate
        await waitForIssueCreator { self.dates(transport, "habit.list_due").last == previous }
        return (appState, transport, previous)
    }

    func testChangingDayRefreshesHabitsAndWellbeingForThatDay() async throws {
        let (_, transport, previous) = try await appStateOnPreviousDay()
        XCTAssertEqual(previous, CronaCalendarDate.adding(days: -1, to: transport.logicalDate))
        await waitForIssueCreator { self.dates(transport, "checkin.get").last == previous }
    }

    func testChangingDaySelectsStatsDay() async throws {
        let (appState, _, previous) = try await appStateOnPreviousDay()
        XCTAssertEqual(appState.popoverStatsService.functionalDate, previous)
    }

    func testHabitEventOnPastDayKeepsPastDay() async throws {
        let (appState, transport, previous) = try await appStateOnPreviousDay()
        await appState.habitsService.refresh()
        await appState.wellbeingService.refresh()
        XCTAssertEqual(dates(transport, "habit.list_due").last, previous)
        XCTAssertEqual(dates(transport, "checkin.get").last, previous)
    }

    func testHabitCompleteOnPastDayUsesPastDay() async throws {
        let (appState, transport, previous) = try await appStateOnPreviousDay()
        let habit = HabitRowModel(id: 5, name: "Read", repoName: "R", streamName: "S", status: "pending",
            completed: false, durationMinutes: nil, targetMinutes: nil)
        await appState.habitsService.complete(habit)
        XCTAssertEqual(dates(transport, "habit.complete").last, previous)
        XCTAssertEqual(dates(transport, "habit.list_due").last, previous)
    }

    func testPopoverOpenReturnsToToday() async throws {
        let (appState, transport, _) = try await appStateOnPreviousDay()
        await appState.reconcileFunctionalDateOnPopoverOpen()
        XCTAssertEqual(appState.day.selectedDate, transport.logicalDate)
        XCTAssertEqual(dates(transport, "habit.list_due").last, transport.logicalDate)
    }

    func testWellbeingDropsPreviousDayCheckInWhenDayChanges() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.checkInByDate[transport.logicalDate] = ["date": transport.logicalDate, "mood": 4, "energy": 3]
        let wellbeing = WellbeingService(daemonConnection: connection)
        await wellbeing.refresh()
        XCTAssertEqual(wellbeing.snapshot.checkIn?.mood, 4)

        transport.failCheckIn = true
        await wellbeing.refresh(date: CronaCalendarDate.adding(days: -1, to: transport.logicalDate))

        XCTAssertNil(wellbeing.snapshot.checkIn)
    }
}
