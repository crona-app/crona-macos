import XCTest
@testable import crona

@MainActor
final class DailyIssueSectionsTests: XCTestCase {
    private let day = "2026-10-27"

    private func issue(
        _ id: Int64, status: String = "planned", due: String? = nil, pinned: Bool = false
    ) -> CronaIssue {
        CronaIssue(id: id, streamID: 1, title: "Issue \(id)", status: status, estimateMinutes: nil, workedSeconds: 0, pinnedDaily: pinned, todoForDate: due, completedAt: nil, abandonedAt: nil)
    }

    private func plan(date: String? = nil, _ entries: [CronaDailyPlanEntry]) -> CronaDailyPlan {
        CronaDailyPlan(id: "plan", date: date ?? day, createdAt: "", updatedAt: "", entries: entries)
    }

    private func entry(_ issueID: Int64, delayed: Int = 0, highRisk: Bool = false) -> CronaDailyPlanEntry {
        CronaDailyPlanEntry(id: "e\(issueID)", date: day, issueID: issueID, source: "todo_for_date", status: "planned", committedAt: "", baselineDate: day, currentPlannedDate: day, postponeCount: 0, currentDelayedDays: delayed, maxDelayedDays: delayed, failScore: 0, penalty: CronaDailyPlanEntryPenalty(highRisk: highRisk, highRiskThreshold: 2.5, ifPostponedOneDay: nil))
    }

    private func build(_ issues: [CronaIssue], _ plan: CronaDailyPlan? = nil) -> DailyIssueSections {
        DailyIssueSections.build(issues: issues, plan: plan, date: day)
    }

    func testPlannedPutsOpenPinnedFirstThenDueToday() {
        let sections = build([issue(1, due: day), issue(2, due: "2026-11-30", pinned: true), issue(3, due: "2026-10-28")])
        XCTAssertEqual(sections.planned.map(\.id), [2, 1])
    }

    func testPlannedExcludesClosedPinnedButKeepsClosedDueThatDay() {
        let sections = build([
            issue(1, status: "done", pinned: true), issue(2, status: "abandoned", due: day),
            issue(3, status: "done", due: day),
        ])
        XCTAssertEqual(sections.planned.map(\.id), [2, 3])
    }

    func testOverdueIncludesOpenIssuesDueBeforeDay() {
        let sections = build([issue(1, due: "2026-10-20"), issue(2, status: "done", due: "2026-10-20"), issue(3, due: day)])
        XCTAssertEqual(sections.overdue.map(\.id), [1])
    }

    func testOverdueExcludesPinnedWithoutDueDate() {
        XCTAssertEqual(build([issue(1, pinned: true)]).overdue.map(\.id), [])
    }

    func testPinnedWithPastDueAppearsInPlannedAndOverdue() {
        let sections = build([issue(1, due: "2026-10-20", pinned: true)])
        XCTAssertEqual(sections.planned.map(\.id), [1])
        XCTAssertEqual(sections.overdue.map(\.id), [1])
    }

    func testUpcomingWithinSevenDaysSortedByDate() {
        let sections = build([
            issue(1, due: "2026-11-03"), issue(2, due: "2026-10-28"), issue(3, due: "2026-11-04"),
            issue(4, due: day), issue(5, status: "done", due: "2026-10-29"),
        ])
        XCTAssertEqual(sections.upcoming.map(\.id), [2, 1])
    }

    func testPlannedEntryAttachesPenalty() {
        let sections = build([issue(1, due: day)], plan([entry(1, delayed: 2, highRisk: true)]))
        XCTAssertEqual(sections.planned.first?.penalty,
            DailyFocusPenalty(highRisk: true, delayedDays: 2, becomesHighRiskIfPostponed: false))
    }

    func testPlanForOtherDateIsIgnored() {
        let sections = build([issue(1, due: day)], plan(date: "2026-10-26", [entry(1, highRisk: true)]))
        XCTAssertNil(sections.planned.first?.penalty)
    }

    func testIssuesInSectionMatchesProperties() {
        let sections = build([issue(1, due: day), issue(2, due: "2026-10-20"), issue(3, due: "2026-10-29")])
        XCTAssertEqual(sections.issues(in: .planned).map(\.id), [1])
        XCTAssertEqual(sections.issues(in: .overdue).map(\.id), [2])
        XCTAssertEqual(sections.issues(in: .upcoming).map(\.id), [3])
    }

    private func planEntryJSON(_ extra: String) -> Data {
        Data((#"{"id":"e","date":"2026-10-27","issueId":1,"source":"todo_for_date","status":"planned","committedAt":"","baselineDate":"2026-10-27","currentPlannedDate":"2026-10-27","postponeCount":0,"currentDelayedDays":0,"maxDelayedDays":0,"failScore":0"# + extra + "}").utf8)
    }

    func testPlanEntryDecodesCarryFields() throws {
        let entry = try JSONDecoder().decode(CronaDailyPlanEntry.self,
            from: planEntryJSON(#","carryCount":2,"stalled":true,"carriedFromDate":"2026-10-26""#))
        XCTAssertEqual(entry.carryCount, 2)
        XCTAssertEqual(entry.stalled, true)
        XCTAssertEqual(entry.carriedFromDate, "2026-10-26")
        XCTAssertEqual(DailyFocusCarry.from(entry), DailyFocusCarry(count: 2, stalled: true, fromDate: "2026-10-26"))
    }

    func testPlanEntryWithoutCarryFieldsDecodes() throws {
        let entry = try JSONDecoder().decode(CronaDailyPlanEntry.self, from: planEntryJSON(""))
        XCTAssertNil(entry.carryCount)
        XCTAssertNil(DailyFocusCarry.from(entry))
    }

    private func carriedEntry(_ issueID: Int64) -> CronaDailyPlanEntry {
        CronaDailyPlanEntry(id: "c\(issueID)", date: day, issueID: issueID, source: "todo_for_date", status: "carried", committedAt: "", baselineDate: day, currentPlannedDate: "2026-10-28", postponeCount: 0, currentDelayedDays: 0, maxDelayedDays: 0, failScore: 0)
    }

    func testPlannedIncludesCarriedAwayIssuesNotDueThatDay() {
        let sections = build(
            [issue(1, due: day), issue(2, due: "2026-10-28"), issue(3, due: "2026-10-28", pinned: true)],
            plan([carriedEntry(2), carriedEntry(3)]))
        XCTAssertEqual(sections.planned.map(\.id), [3, 1, 2])
        XCTAssertEqual(sections.planned.first { $0.id == 2 }?.carriedAway, true)
        XCTAssertEqual(sections.planned.first { $0.id == 1 }?.carriedAway, false)
        XCTAssertEqual(sections.upcoming.map(\.id), [2, 3])
    }

    func testPlannedEntryAttachesCarry() {
        var planned = entry(1)
        planned.carryCount = 1
        planned.carriedFromDate = "2026-10-26"
        let sections = build([issue(1, due: day)], plan([planned]))
        XCTAssertEqual(sections.planned.first?.carry, DailyFocusCarry(count: 1, stalled: false, fromDate: "2026-10-26"))
    }
}
