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

    // MARK: - Filtering

    private static func tagged(_ id: Int64, _ tags: [String], streamID: Int64 = 7) -> DailyFocusIssue {
        DailyFocusIssue(
            id: id, streamID: streamID, title: "I\(id)", status: "ready", estimateMinutes: nil, workedSeconds: 0,
            todoForDate: nil, tags: tags)
    }

    func testSectionsFilteredByTag() {
        let sections = DailyIssueSections(
            planned: [Self.tagged(1, ["work"]), Self.tagged(2, [])],
            overdue: [Self.tagged(3, ["home"])],
            upcoming: [Self.tagged(4, ["work"])],
            inbox: [Self.tagged(5, ["home"])])
        let filtered = sections.filtered { $0.tags.contains("work") }
        XCTAssertEqual(filtered.planned.map(\.id), [1])
        XCTAssertEqual(filtered.overdue, [])
        XCTAssertEqual(filtered.upcoming.map(\.id), [4])
        XCTAssertEqual(filtered.inbox, [])
    }

    private func inboxAppState() async throws -> (CompanionAppState, IssueCreatorTestTransport) {
        let (connection, transport) = try await issueCreatorConnection()
        addTeardownBlock { connection.stop() }
        transport.provideInbox = true
        transport.tagsFixture = [
            ["name": "work", "system": false, "issueCount": 1, "habitCount": 0],
            ["name": "home", "system": false, "issueCount": 1, "habitCount": 0],
        ]
        transport.todaySummaryIssuesFixture = [
            ["id": 1, "streamId": 91, "title": "A", "status": "backlog", "workedSeconds": 0, "pinnedDaily": false,
                "tags": ["home"]],
            ["id": 2, "streamId": 91, "title": "B", "status": "backlog", "workedSeconds": 0, "pinnedDaily": false,
                "tags": ["work"]],
        ]
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        await appState.tags.refresh()
        await appState.dailyIssues.refresh()
        return (appState, transport)
    }

    func testInboxCountReflectsFilter() async throws {
        let (appState, _) = try await inboxAppState()
        XCTAssertEqual(appState.dailyIssues.sections.inbox.count, 2)
        await appState.tags.setFilter(CronaTagFilter(query: "+work"), for: .issues)
        await waitForIssueCreator { appState.dailyIssues.sections.inbox.count == 1 }
        XCTAssertEqual(appState.dailyIssues.sections.inbox.map(\.id), [2])
    }

    func testFilteredOutInboxFallsBackToPlanned() async throws {
        let (appState, _) = try await inboxAppState()
        appState.dailyIssues.section = .inbox
        await appState.tags.setFilter(CronaTagFilter(query: "-work -home"), for: .issues)
        await waitForIssueCreator { appState.dailyIssues.section == .planned }
        XCTAssertEqual(appState.dailyIssues.section, .planned)
    }

    func testHabitRowsFilteredByTag() {
        let rows = [
            HabitRowModel(id: 1, name: "A", repoName: "R", streamName: "S", status: "pending", completed: false,
                durationMinutes: nil, targetMinutes: nil, tags: ["health"]),
            HabitRowModel(id: 2, name: "B", repoName: "R", streamName: "S", status: "pending", completed: false,
                durationMinutes: nil, targetMinutes: nil),
        ]
        let snapshot = HabitsSnapshot(items: rows)
        let filtered = snapshot.filtered(by: CronaTagFilter(query: "+health"), known: ["health"])
        XCTAssertEqual(filtered.items.map(\.id), [1])
        XCTAssertEqual(snapshot.filtered(by: CronaTagFilter(), known: []).items.count, 2)
    }

    // MARK: - Input

    func testTagInputNormalizes() {
        XCTAssertEqual(TagInput.normalize("Deep Work"), "deep-work")
        XCTAssertEqual(TagInput.normalize(" +Urgent "), "urgent")
        XCTAssertEqual(TagInput.normalize("team/api_v2"), "team/api_v2")
        XCTAssertNil(TagInput.normalize(""))
        XCTAssertNil(TagInput.normalize("untagged"))
        XCTAssertNil(TagInput.normalize("-x"))
        XCTAssertNil(TagInput.normalize("a!"))
        XCTAssertNil(TagInput.normalize(String(repeating: "a", count: 33)))
        XCTAssertEqual(TagInput.normalize(String(repeating: "a", count: 32))?.count, 32)
    }

    func testTagInputAddsWithoutDuplicates() {
        XCTAssertEqual(TagInput.adding("Work", to: ["work"]), ["work"])
        XCTAssertEqual(TagInput.adding("home", to: ["work"]), ["work", "home"])
        XCTAssertEqual(TagInput.adding("!!", to: ["work"]), ["work"])
    }

    // MARK: - Editor

    private func makeEditor(onSaved: (() -> Void)? = nil) async throws -> (TagEditorModel, IssueCreatorTestTransport) {
        let (connection, transport) = try await issueCreatorConnection()
        addTeardownBlock { connection.stop() }
        return (TagEditorModel(daemonConnection: connection, onSaved: { onSaved?() }), transport)
    }

    func testTagEditorSavesIssueTags() async throws {
        var saved = 0
        let (editor, transport) = try await makeEditor { saved += 1 }
        editor.present(.issue(id: 5, title: "Fix"), tags: ["work"])
        editor.tags.append("urgent")

        let ok = await editor.save()

        XCTAssertTrue(ok)
        let request = try XCTUnwrap(transport.requests.last { $0.method == "issue.tags.set" })
        XCTAssertEqual(request.params["id"]?.intValue, 5)
        XCTAssertEqual(request.params["tags"]?.stringArrayValue, ["work", "urgent"])
        XCTAssertEqual(saved, 1)
        XCTAssertNil(editor.target)
    }

    func testTagEditorSavesHabitTags() async throws {
        let (editor, transport) = try await makeEditor()
        editor.present(.habit(id: 8, name: "Walk"), tags: [])
        editor.tags = ["health"]

        let ok = await editor.save()

        XCTAssertTrue(ok)
        let request = try XCTUnwrap(transport.requests.last { $0.method == "habit.tags.set" })
        XCTAssertEqual(request.params["id"]?.intValue, 8)
        XCTAssertEqual(request.params["tags"]?.stringArrayValue, ["health"])
    }

    func testTagEditorFailureKeepsEdit() async throws {
        let (editor, transport) = try await makeEditor()
        transport.failTagSet = true
        editor.present(.issue(id: 5, title: "Fix"), tags: [])
        editor.tags = ["work"]

        let ok = await editor.save()

        XCTAssertFalse(ok)
        XCTAssertEqual(editor.target, .issue(id: 5, title: "Fix"))
        XCTAssertEqual(editor.tags, ["work"])
        XCTAssertNotNil(editor.errorMessage)
    }

    func testTagEditorCountsAsPopoverModal() async throws {
        let (connection, _) = try await issueCreatorConnection()
        defer { connection.stop() }
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        appState.tagEditor.present(.issue(id: 1, title: "T"), tags: [])
        XCTAssertTrue(appState.isPopoverModalPresented)
        XCTAssertTrue(appState.isUpdatePresentationBlocked)
    }

    // MARK: - Focus by tag

    private static func row(_ key: String, _ seconds: Int) -> [String: Any] {
        ["key": key, "label": key, "workedSeconds": seconds, "percent": 0.0]
    }

    func testTagFocusKeepsTopFiveByTime() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.distributionRowsFixture = [
            Self.row("a", 10), Self.row("b", 60), Self.row("c", 30), Self.row("d", 50), Self.row("e", 20),
            Self.row("f", 40),
        ]
        let model = TagFocusModel(daemonConnection: connection)

        await model.refresh(date: "2026-10-28")

        XCTAssertEqual(model.today.map(\.key), ["b", "d", "f", "c", "e"])
        XCTAssertEqual(model.week.map(\.key), ["b", "d", "f", "c", "e"])
    }

    func testTagFocusRequestsTodayAndWeek() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let model = TagFocusModel(daemonConnection: connection)

        // 2026-10-28 is a Wednesday; the week starts Monday 2026-10-26.
        await model.refresh(date: "2026-10-28")

        let requests = transport.requests.filter { $0.method == "dashboard.distribution" }
        XCTAssertEqual(requests.map { $0.params["groupBy"]?.stringValue }, ["tag", "tag"])
        let ranges = Set(requests.map { "\($0.params["start"]?.stringValue ?? "")..\($0.params["end"]?.stringValue ?? "")" })
        XCTAssertEqual(ranges, ["2026-10-28..2026-10-28", "2026-10-26..2026-10-28"])
    }

    func testTagFocusWeekStartsMondayOnSunday() {
        XCTAssertEqual(TagFocusModel.weekStart(for: "2026-11-01"), "2026-10-26")
        XCTAssertEqual(TagFocusModel.weekStart(for: "2026-10-26"), "2026-10-26")
    }

    func testTagFocusDropsZeroRows() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.distributionRowsFixture = [Self.row("a", 0), Self.row("b", 5)]
        let model = TagFocusModel(daemonConnection: connection)

        await model.refresh(date: "2026-10-28")

        XCTAssertEqual(model.today.map(\.key), ["b"])
    }

    func testTagEditorSaveIncludesPendingDraft() async throws {
        let (editor, transport) = try await makeEditor()
        editor.present(.issue(id: 5, title: "Fix"), tags: ["work"])
        editor.draft = "Deep Work"

        _ = await editor.save()

        let request = try XCTUnwrap(transport.requests.last { $0.method == "issue.tags.set" })
        XCTAssertEqual(request.params["tags"]?.stringArrayValue, ["work", "deep-work"])
        XCTAssertEqual(editor.draft, "")
    }

    func testTagInputCommitsCommaSeparatedDraft() {
        XCTAssertEqual(TagInput.committing("a, b,a", into: ["x"]), ["x", "a", "b"])
        XCTAssertEqual(TagInput.committing("  ", into: ["x"]), ["x"])
    }

    func testTagSuggestionsMatchAndOfferNew() {
        let existing = ["work", "workout", "home", "deep-work"]
        XCTAssertEqual(
            TagSuggestions.make(draft: "wo", existing: existing, selected: ["work"]),
            [.existing("workout"), .existing("deep-work"), .create("wo")])
        XCTAssertEqual(
            TagSuggestions.make(draft: "Home", existing: existing, selected: []), [.existing("home")])
        XCTAssertEqual(TagSuggestions.make(draft: "", existing: existing, selected: ["home"]).count, 3)
        XCTAssertEqual(TagSuggestions.make(draft: "!!", existing: existing, selected: []), [])
        XCTAssertEqual(TagSuggestions.make(draft: "work", existing: existing, selected: ["work"]), [.existing("workout"), .existing("deep-work")])
    }
}
