import XCTest

@testable import crona

@MainActor
final class DetailBrowserTests: DaemonTestCase {
    func testIssueBrowsingStaysInSourceSectionAndStopsAtBoundaries() {
        let model = DetailBrowserModel()
        let first = issue(1)
        let second = issue(2)
        let outside = issue(3)
        model.open(issue: first, section: .planned)
        let sections = DailyIssueSections(planned: [first, second], overdue: [outside])
        let ids = model.ids(issues: sections, habits: [])
        XCTAssertEqual(ids, [1, 2])
        XCTAssertNil(model.neighbor(-1, ids: ids))
        XCTAssertEqual(model.neighbor(1, ids: ids), 2)
        model.select(2)
        XCTAssertNil(model.neighbor(1, ids: ids))
        XCTAssertEqual(model.neighbor(-1, ids: ids), 1)
        XCTAssertNil(model.neighbor(1, ids: [1]))
        XCTAssertEqual(model.issueID, 2)
        XCTAssertEqual(model.source, .issues(.planned))
    }

    func testActivityDetailsDoNotInventAListSource() {
        let model = DetailBrowserModel()
        model.open(issue: issue(7), section: nil)
        XCTAssertEqual(model.source, .activity)
        XCTAssertTrue(model.ids(issues: DailyIssueSections(planned: [issue(1)]), habits: []).isEmpty)
        XCTAssertEqual(model.activityIssue?.id, 7)
    }

    private func issue(_ id: Int64) -> DailyFocusIssue {
        DailyFocusIssue(
            id: id, streamID: 1, title: "Issue", status: "ready", estimateMinutes: nil, workedSeconds: 0,
            todoForDate: nil)
    }
}
