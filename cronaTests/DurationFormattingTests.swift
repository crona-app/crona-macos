import XCTest
@testable import crona

@MainActor
final class DurationFormattingTests: XCTestCase {
    func testMinuteValuesUseTheSameHourMinuteNotationAsInputs() throws {
        let cases = [(0, "0m"), (45, "45m"), (59, "59m"), (60, "1h0m"), (75, "1h15m"),
                     (90, "1h30m"), (120, "2h0m"), (1440, "24h0m")]
        for (minutes, expected) in cases {
            let value = MenuBarTextFormatter.formatMinutes(minutes)
            XCTAssertEqual(value, expected)
            XCTAssertEqual(try FlexibleDurationParser.optionalMinutes(value).get(), minutes)
        }
        XCTAssertEqual(MenuBarTextFormatter.formatMinutes(-1), "0m")
    }

    func testDurationDraftsOmitZeroSecondsButPreserveRealSeconds() {
        let cases = [(0, "0m"), (2700, "45m"), (3600, "1h0m"), (5400, "1h30m"),
                     (29, "29s"), (2723, "45m23s"), (4830, "1h20m30s")]
        for (seconds, expected) in cases {
            let draft = HabitDurationFormatter.string(from: seconds)
            XCTAssertEqual(draft, expected)
            XCTAssertEqual(HabitDurationFormatter.seconds(from: draft), seconds)
        }
    }
}
