import XCTest
@testable import crona

@MainActor
final class DelayPenaltyTests: DaemonTestCase {
    private func planEntryJSON(penalty: String?) -> Data {
        let penaltyField = penalty.map { #","penalty":\#($0)"# } ?? ""
        let json = #"{"id":"e","date":"2026-10-27","issueId":1,"source":"todo_for_date","status":"planned","committedAt":"","baselineDate":"2026-10-25","currentPlannedDate":"2026-10-27","postponeCount":2,"currentDelayedDays":2,"maxDelayedDays":2,"failScore":3.1"#
            + penaltyField + "}"
        return Data(json.utf8)
    }

    func testPlanEntryDecodesPenalty() throws {
        let data = planEntryJSON(
            penalty: #"{"highRisk":true,"highRiskThreshold":2.5,"delayComponent":1.2,"ifPostponedOneDay":{"failScore":3.6,"accountabilityDelta":0.4,"becomesHighRisk":true}}"#)
        let entry = try JSONDecoder().decode(CronaDailyPlanEntry.self, from: data)
        XCTAssertEqual(entry.penalty?.highRisk, true)
        XCTAssertEqual(entry.penalty?.highRiskThreshold, 2.5)
        XCTAssertEqual(entry.penalty?.ifPostponedOneDay?.becomesHighRisk, true)
    }

    func testPlanEntryWithoutPenaltyDecodesNil() throws {
        let missing = try JSONDecoder().decode(CronaDailyPlanEntry.self, from: planEntryJSON(penalty: nil))
        XCTAssertNil(missing.penalty)
        let null = try JSONDecoder().decode(CronaDailyPlanEntry.self, from: planEntryJSON(penalty: "null"))
        XCTAssertNil(null.penalty)
    }

    private func issue(_ id: Int64) -> CronaIssue {
        CronaIssue(id: id, streamID: 10, title: "Issue \(id)", status: "planned", estimateMinutes: nil, workedSeconds: 0, pinnedDaily: false, todoForDate: "2026-10-27", completedAt: nil, abandonedAt: nil)
    }

    private func entry(
        _ issueID: Int64, status: String = "planned", delayedDays: Int = 0,
        penalty: CronaDailyPlanEntryPenalty? = nil
    ) -> CronaDailyPlanEntry {
        CronaDailyPlanEntry(id: "entry-\(issueID)", date: "2026-10-27", issueID: issueID, source: "todo_for_date", status: status, committedAt: "", baselineDate: "2026-10-27", currentPlannedDate: "2026-10-27", postponeCount: 0, currentDelayedDays: delayedDays, maxDelayedDays: delayedDays, failScore: 0, penalty: penalty)
    }

    private func penalty(highRisk: Bool, becomesHighRisk: Bool? = nil) -> CronaDailyPlanEntryPenalty {
        CronaDailyPlanEntryPenalty(
            highRisk: highRisk, highRiskThreshold: 2.5,
            ifPostponedOneDay: becomesHighRisk.map { CronaDailyPlanPenaltyProjection(becomesHighRisk: $0) })
    }

    private func buildIssues(_ issues: [CronaIssue], _ entries: [CronaDailyPlanEntry]) -> [DailyFocusIssue] {
        let summary = CronaDailyIssueSummary(
            date: "2026-10-27", totalIssues: issues.count, issues: issues, totalEstimatedMinutes: 0,
            completedIssues: 0, abandonedIssues: 0, workedSeconds: 0)
        let plan = CronaDailyPlan(id: "plan", date: "2026-10-27", createdAt: "", updatedAt: "", entries: entries)
        return DailyFocusService.buildIssues(summary: summary, plan: plan)
    }

    func testBuildIssuesAttachesPenaltyFromPlannedEntry() {
        let issues = buildIssues([issue(1)], [entry(1, delayedDays: 3, penalty: penalty(highRisk: true))])
        XCTAssertEqual(
            issues.first { $0.id == 1 }?.penalty,
            DailyFocusPenalty(highRisk: true, delayedDays: 3, becomesHighRiskIfPostponed: false))
    }

    func testBuildIssuesLeavesPenaltyNilForSummaryOnlyAndNonPlannedEntries() {
        let issues = buildIssues(
            [issue(2), issue(3)], [entry(3, status: "done", penalty: penalty(highRisk: true))])
        XCTAssertNil(issues.first { $0.id == 2 }?.penalty)
        XCTAssertNil(issues.first { $0.id == 3 }?.penalty)
        XCTAssertEqual(issues.count, 2)
    }

    func testSnapshotHighRiskCountCountsHighRiskIssues() {
        let issues = buildIssues(
            [issue(1), issue(2), issue(3)],
            [entry(1, penalty: penalty(highRisk: true)), entry(2, penalty: penalty(highRisk: false))])
        let snapshot = DailyFocusSnapshot(date: "2026-10-27", issues: issues, isConnected: true)
        XCTAssertEqual(snapshot.highRiskCount, 1)
    }
}
