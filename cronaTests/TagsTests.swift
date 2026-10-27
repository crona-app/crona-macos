import XCTest
@testable import crona

@MainActor
final class TagsTests: DaemonTestCase {
    func testIssueAndHabitDecodeWithAndWithoutTags() throws {
        let issue = #"{"id":1,"streamId":2,"title":"T","status":"ready","workedSeconds":0,"pinnedDaily":false"#
        XCTAssertNil(try JSONDecoder().decode(CronaIssue.self, from: Data((issue + "}").utf8)).tags)
        XCTAssertEqual(
            try JSONDecoder().decode(CronaIssue.self, from: Data((issue + #","tags":["work"]}"#).utf8)).tags, ["work"])

        let habit = #"{"id":1,"streamId":2,"name":"H","scheduleType":"daily","weekdays":[],"active":true,"repoId":3,"repoName":"R","streamName":"S""#
        XCTAssertNil(try JSONDecoder().decode(CronaHabitWithMeta.self, from: Data((habit + "}").utf8)).tags)
        XCTAssertEqual(
            try JSONDecoder().decode(CronaHabitWithMeta.self, from: Data((habit + #","tags":["a","b"]}"#).utf8)).tags,
            ["a", "b"])
    }

    func testTagDecodesWithoutColor() throws {
        let tag = try JSONDecoder().decode(
            CronaTag.self, from: Data(#"{"name":"urgent","system":true,"issueCount":2,"habitCount":0}"#.utf8))
        XCTAssertEqual(tag, CronaTag(name: "urgent", color: nil, system: true, issueCount: 2, habitCount: 0))
        XCTAssertEqual(tag.id, "urgent")
    }

    func testCreateIssueRequestEncodesTagsOnlyWhenPresent() throws {
        let without = CronaCreateIssueRequest(
            streamID: 1, title: "T", description: nil, estimateMinutes: nil, todoForDate: nil, tags: nil)
        let with = CronaCreateIssueRequest(
            streamID: 1, title: "T", description: nil, estimateMinutes: nil, todoForDate: nil, tags: ["work"])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(without), as: UTF8.self).contains("tags"))
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(with), as: UTF8.self).contains(#""tags":["work"]"#))
    }

    func testTagFiltersGetDefaultsToEmpty() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let filters = try await connection.withClient { try await $0.tagFiltersGet() }
        XCTAssertEqual(filters, [:])
    }

    func testTagFiltersPatchSendsObject() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        try await connection.withClient { try await $0.tagFiltersPatch(["issues": "+work"]) }
        XCTAssertEqual(transport.tagFiltersFixture, ["issues": "+work"])
        let filters = try await connection.withClient { try await $0.tagFiltersGet() }
        XCTAssertEqual(filters, ["issues": "+work"])
    }

    func testDistributionDecodesWithoutRows() throws {
        let summary = try JSONDecoder().decode(
            CronaTimeDistributionSummary.self,
            from: Data(#"{"startDate":"a","endDate":"b","groupBy":"tag","totalSeconds":0}"#.utf8))
        XCTAssertEqual(summary.rows, [])
    }
}
