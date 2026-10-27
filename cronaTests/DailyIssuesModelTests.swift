import XCTest
@testable import crona

@MainActor
final class DailyIssuesModelTests: DaemonTestCase {
    private func issueJSON(_ id: Int, due: String) -> [String: Any] {
        ["id": id, "streamId": 7, "title": "Issue \(id)", "status": "planned", "workedSeconds": 0,
         "pinnedDaily": false, "todoForDate": due]
    }

    private func planDates(_ transport: IssueCreatorTestTransport) -> [String] {
        transport.requests.filter { $0.method == "daily_plan.get" }.compactMap { $0.params["date"]?.stringValue }
    }

    func testRefreshBuildsSectionsForSelectedDay() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let yesterday = CronaCalendarDate.adding(days: -1, to: transport.logicalDate)!
        transport.todaySummaryIssuesFixture = [issueJSON(1, due: transport.logicalDate), issueJSON(2, due: yesterday)]
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())

        await appState.dailyIssues.refresh()

        XCTAssertEqual(appState.dailyIssues.sections.planned.map(\.id), [1])
        XCTAssertEqual(appState.dailyIssues.sections.overdue.map(\.id), [2])
    }

    func testRefreshRequestsPlanForSelectedDay() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        _ = appState.dailyIssues
        appState.day.showPreviousDay()
        let previous = appState.day.selectedDate

        await waitForIssueCreator { self.planDates(transport).last == previous }
        XCTAssertNotEqual(previous, transport.logicalDate)
    }

    func testIssueEventRefreshKeepsSelectedDay() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        _ = appState.dailyIssues
        appState.day.showPreviousDay()
        let previous = appState.day.selectedDate
        await waitForIssueCreator { self.planDates(transport).last == previous }
        await settleAsyncTasks()
        // DailyFocusService also loads today's plan on issue events, so count requests for the selected day.
        let before = planDates(transport).filter { $0 == previous }.count

        try postDaemonEvent(#"{"type":"issue.updated","payload":{}}"#)

        await waitForIssueCreator { self.planDates(transport).filter { $0 == previous }.count > before }
        XCTAssertEqual(appState.day.selectedDate, previous)
    }

    func testSectionTitlesAndEmptyText() {
        XCTAssertEqual(DailySectionPicker.title(for: .overdue, overdueCount: 0), "Overdue")
        XCTAssertEqual(DailySectionPicker.title(for: .overdue, overdueCount: 3), "Overdue (3)")
        XCTAssertEqual(DailySectionPicker.title(for: .planned, overdueCount: 3), "Planned")
        XCTAssertEqual(DailySectionPicker.emptyText(for: .upcoming), "Nothing in the next 7 days")
        XCTAssertEqual(DailySectionPicker.emptyText(for: .overdue), "Nothing overdue")
    }
}
