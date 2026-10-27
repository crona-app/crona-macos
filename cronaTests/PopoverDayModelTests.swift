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
}
