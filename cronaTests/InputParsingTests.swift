import XCTest
@testable import crona

@MainActor
final class InputParsingTests: DaemonTestCase {
    func testFlexibleDurationParserMatchesManualLogInputs() {
        XCTAssertEqual(try? FlexibleDurationParser.optionalMinutes("90").get(), 90)
        XCTAssertEqual(try? FlexibleDurationParser.optionalMinutes("90m").get(), 90)
        XCTAssertEqual(try? FlexibleDurationParser.optionalMinutes("1h30m").get(), 90)
        XCTAssertEqual(try? FlexibleDurationParser.optionalMinutes("1.5h").get(), 90)
        XCTAssertEqual(try? FlexibleDurationParser.optionalMinutes("-1m").get(), nil)
    }

    func testIssueStatusPresentationMatchesTUIStatusSemantics() {
        XCTAssertEqual(CronaIssueStatusPresentation.status(for: "todo"), .backlog)
        XCTAssertEqual(CronaIssueStatusPresentation.status(for: "active"), .inProgress)
        XCTAssertEqual(CronaIssueStatusPresentation.icon(for: "blocked"), "exclamationmark.octagon")
        XCTAssertEqual(CronaIssueStatusPresentation.icon(for: "done"), "checkmark.circle.fill")
        XCTAssertEqual(CronaIssueStatusPresentation.colorKey(for: "planned"), .blue)
        XCTAssertEqual(CronaIssueStatusPresentation.colorKey(for: "in_progress"), .yellow)
        XCTAssertEqual(CronaIssueStatusPresentation.colorKey(for: "in_review"), .magenta)
        XCTAssertEqual(CronaIssueStatusPresentation.colorKey(for: "abandoned"), .red)
        XCTAssertEqual(CronaIssueStatusPresentation.colorKey(for: "unknown"), .subtle)
    }

    func testFlexibleEstimateParserMatchesTUIInputs() throws {
        let cases: [(String, Int?)] = [
            ("", nil),
            ("90", 90),
            ("90m", 90),
            ("1h30m", 90),
            ("1.5h", 90),
            ("1H34M23S", 94),
            (" 45m ", 45)
        ]
        for (input, expected) in cases {
            let result = FlexibleDurationParser.optionalMinutes(input)
            XCTAssertEqual(try result.get(), expected, "Unexpected parse for \(input)")
        }
    }

    func testFlexibleEstimateParserRejectsMalformedAndNegativeInputs() {
        for input in ["-1", "tomorrow", "1h30", "1:30"] {
            if case .success = FlexibleDurationParser.optionalMinutes(input) {
                XCTFail("Expected \(input) to be rejected")
            }
        }
    }
}
