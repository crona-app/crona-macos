import XCTest
@testable import crona

@MainActor
final class CaptureAutocompleteTests: XCTestCase {
    private let destinations = [
        IssueDestination(repoID: 1, repoName: "crona", streamID: 10, streamName: "macos"),
        IssueDestination(repoID: 1, repoName: "crona", streamID: 11, streamName: "core"),
        IssueDestination(repoID: 2, repoName: "Side Projects", streamID: 20, streamName: "Blog Posts"),
    ]

    private func token(_ text: String) -> CaptureToken? {
        CaptureAutocomplete.token(in: text, caret: (text as NSString).length)
    }

    func testTokenFoundOnlyAtWordStart() {
        XCTAssertEqual(token("- Fix bug #cr")?.trigger, .target)
        XCTAssertEqual(token("- Fix bug #cr")?.query, "cr")
        XCTAssertEqual(token("- Fix ~")?.trigger, .estimate)
        XCTAssertEqual(token("- Fix @to")?.trigger, .date)
        XCTAssertEqual(token("- Fix +do")?.trigger, .tag)
        XCTAssertNil(token("- email a@b"))
        XCTAssertNil(token("- Fix bug #cr "))
        XCTAssertNil(token("- c++"))
    }

    func testTokenRangeCoversTriggerAndQuery() {
        let text = "- Fix #cr"
        XCTAssertEqual(token(text)?.range, NSRange(location: 6, length: 3))
    }

    func testTargetSuggestionsMatchRepoOrStream() {
        let found = CaptureAutocomplete.suggestions(
            for: CaptureToken(trigger: .target, query: "mac", range: NSRange()), destinations: destinations, tags: [])
        XCTAssertEqual(found.map(\.insertion), ["#crona/macos"])
        XCTAssertEqual(found.first?.label, "crona / macos")
    }

    func testTargetInsertionUsesFirstWordOfNamesWithSpaces() {
        let found = CaptureAutocomplete.suggestions(
            for: CaptureToken(trigger: .target, query: "blog", range: NSRange()), destinations: destinations, tags: [])
        XCTAssertEqual(found.map(\.insertion), ["#side/blog"])
    }

    func testEstimateDateAndTagSuggestionsFilterByPrefix() {
        XCTAssertEqual(
            CaptureAutocomplete.suggestions(
                for: CaptureToken(trigger: .estimate, query: "1", range: NSRange()), destinations: [], tags: []
            ).map(\.insertion),
            ["~15m", "~1h", "~1h30m"])
        XCTAssertEqual(
            CaptureAutocomplete.suggestions(
                for: CaptureToken(trigger: .date, query: "t", range: NSRange()), destinations: [], tags: []
            ).map(\.insertion),
            ["@today", "@tomorrow", "@tuesday", "@thursday"])
        XCTAssertEqual(
            CaptureAutocomplete.suggestions(
                for: CaptureToken(trigger: .tag, query: "do", range: NSRange()), destinations: [],
                tags: ["docs", "release", "done"]
            ).map(\.insertion),
            ["+docs", "+done"])
    }

    func testApplyReplacesTokenAndAddsSpace() {
        let text = "- Fix #cr later"
        let caret = 9
        let found = try! XCTUnwrap(CaptureAutocomplete.token(in: text, caret: caret))
        let result = CaptureAutocomplete.apply(
            CaptureSuggestion(label: "", detail: nil, insertion: "#crona/macos"), to: text, replacing: found)
        XCTAssertEqual(result.text, "- Fix #crona/macos later")
        XCTAssertEqual(result.caret, 19)
        let end = CaptureAutocomplete.apply(
            CaptureSuggestion(label: "", detail: nil, insertion: "+docs"), to: "- A +d",
            replacing: try! XCTUnwrap(token("- A +d")))
        XCTAssertEqual(end.text, "- A +docs ")
    }
}
