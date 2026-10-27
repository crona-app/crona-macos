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

    // MARK: - Filter

    func testFilterParsesTUIQuery() {
        let filter = CronaTagFilter(query: "+work +home -someday")
        XCTAssertEqual(filter.any, ["work", "home"])
        XCTAssertEqual(filter.none, ["someday"])
        XCTAssertEqual(filter.query, "+work +home -someday")
        XCTAssertTrue(CronaTagFilter(query: "  ").isEmpty)
    }

    func testFilterMatchesAnyAndNone() {
        let known: Set<String> = ["work", "home", "someday"]
        let filter = CronaTagFilter(query: "+work +home -someday")
        XCTAssertTrue(filter.matches(["work"], known: known))
        XCTAssertTrue(filter.matches(["home", "x"], known: known))
        XCTAssertFalse(filter.matches(["work", "someday"], known: known))
        XCTAssertFalse(filter.matches([], known: known))
    }

    func testUntaggedMatchesOnlyItemsWithoutTags() {
        XCTAssertTrue(CronaTagFilter(query: "+untagged").matches([], known: []))
        XCTAssertFalse(CronaTagFilter(query: "+untagged").matches(["a"], known: ["a"]))
        XCTAssertFalse(CronaTagFilter(query: "-untagged").matches([], known: []))
    }

    func testUnknownTagInSavedFilterIsIgnored() {
        XCTAssertTrue(CronaTagFilter(query: "+gone").matches(["work"], known: ["work"]))
        XCTAssertTrue(CronaTagFilter(query: "-gone").matches(["work"], known: ["work"]))
    }

    func testToggleShowAndHide() {
        var filter = CronaTagFilter(query: "-work")
        filter.toggleShow("work")
        XCTAssertEqual(filter.query, "+work")
        filter.toggleShow("work")
        XCTAssertTrue(filter.isEmpty)
        filter.toggleHide("home")
        XCTAssertEqual(filter.query, "-home")
    }

    // MARK: - TagsModel

    private func makeTags() async throws -> (TagsModel, IssueCreatorTestTransport) {
        let (connection, transport) = try await issueCreatorConnection()
        addTeardownBlock { connection.stop() }
        transport.tagsFixture = [
            ["name": "work", "color": "blue", "system": false, "issueCount": 1, "habitCount": 0],
            ["name": "home", "system": false, "issueCount": 0, "habitCount": 1],
        ]
        return (TagsModel(daemonConnection: connection), transport)
    }

    func testRefreshLoadsTagsAndFilters() async throws {
        let (model, transport) = try await makeTags()
        transport.tagFiltersFixture = ["issues": "+work", "habits": "-home"]
        await model.refresh()
        XCTAssertEqual(model.tags.map(\.name), ["work", "home"])
        XCTAssertEqual(model.color(for: "work"), "blue")
        XCTAssertEqual(model.filter(for: .issues).query, "+work")
        XCTAssertEqual(model.filter(for: .habits).query, "-home")
        XCTAssertTrue(model.matches(["work"], in: .issues))
        XCTAssertFalse(model.matches(["home"], in: .issues))
    }

    func testSetFilterKeepsOtherPanes() async throws {
        let (model, transport) = try await makeTags()
        transport.tagFiltersFixture = ["issues": "+work", "sessions": "+x"]
        await model.refresh()

        await model.setFilter(CronaTagFilter(query: "+home"), for: .habits)
        XCTAssertEqual(transport.tagFiltersFixture, ["issues": "+work", "sessions": "+x", "habits": "+home"])

        await model.setFilter(CronaTagFilter(query: ""), for: .issues)
        XCTAssertEqual(transport.tagFiltersFixture, ["sessions": "+x", "habits": "+home"])
        XCTAssertTrue(model.filter(for: .issues).isEmpty)
    }

    func testTagListFailureKeepsTabsUnfiltered() async throws {
        let (model, transport) = try await makeTags()
        transport.failTagList = true
        transport.tagFiltersFixture = ["issues": "+work"]
        await model.refresh()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.matches(["home"], in: .issues))
    }

    func testTagsChangedEventReloads() async throws {
        let (model, transport) = try await makeTags()
        await model.refresh()
        transport.tagsFixture.append(["name": "new", "system": false, "issueCount": 0, "habitCount": 0])
        try postDaemonEvent(#"{"type":"tags.changed","payload":{}}"#)
        await waitForIssueCreator { model.tags.count == 3 }
        XCTAssertEqual(model.tags.count, 3)
    }

    func testSettingsChangedEventReloadsFilters() async throws {
        let (model, transport) = try await makeTags()
        await model.refresh()
        transport.tagFiltersFixture = ["issues": "+work"]
        try postDaemonEvent(#"{"type":"settings.changed","payload":{}}"#)
        await waitForIssueCreator { !model.filter(for: .issues).isEmpty }
        XCTAssertEqual(model.filter(for: .issues).query, "+work")
    }

    // MARK: - Chips

    func testChipOverflow() {
        XCTAssertEqual(TagChipLayout.split([]).shown, [])
        XCTAssertEqual(TagChipLayout.split([]).overflow, 0)
        XCTAssertNil(TagChipLayout.overflowLabel(0))
        XCTAssertEqual(TagChipLayout.split(["a", "b"]).shown, ["a", "b"])
        XCTAssertEqual(TagChipLayout.split(["a", "b"]).overflow, 0)
        let split = TagChipLayout.split(["a", "b", "c", "d"])
        XCTAssertEqual(split.shown, ["a", "b"])
        XCTAssertEqual(split.overflow, 2)
        XCTAssertEqual(TagChipLayout.overflowLabel(split.overflow), "+2")
    }

    func testSectionsCarryIssueTags() {
        var issue = CronaIssue(
            id: 1, streamID: 7, title: "T", status: "ready", estimateMinutes: nil, workedSeconds: 0,
            pinnedDaily: false, todoForDate: "2001-02-03")
        issue.tags = ["work"]
        let sections = DailyIssueSections.build(issues: [issue], plan: nil, date: "2001-02-03")
        XCTAssertEqual(sections.planned.first?.tags, ["work"])
    }

    func testHabitRowCarriesTags() throws {
        let json = #"{"id":1,"streamId":2,"name":"H","scheduleType":"daily","weekdays":[],"active":true,"repoId":3,"repoName":"R","streamName":"S","tags":["health"],"status":"pending","completed":false}"#
        let item = try JSONDecoder().decode(CronaHabitDailyItem.self, from: Data(json.utf8))
        XCTAssertEqual(HabitsService.project(item).tags, ["health"])
    }
}
