import XCTest
@testable import crona

@MainActor
final class IssueCaptureTests: DaemonTestCase {
    func testRepoAndStreamDecodeWithoutSystem() throws {
        let repo = try JSONDecoder().decode(CronaRepo.self, from: Data(#"{"id":3,"name":"Repo"}"#.utf8))
        let stream = try JSONDecoder().decode(CronaStream.self, from: Data(#"{"id":7,"repoId":3,"name":"S"}"#.utf8))
        XCTAssertNil(repo.system)
        XCTAssertNil(stream.system)
    }

    func testVisibleDestinationsDropSystemRepoAndStream() {
        let result = IssueCreationService.visibleDestinations(
            repos: [CronaRepo(id: 3, name: "Repo"), CronaRepo(id: 90, name: "Inbox", system: true)],
            streams: [
                3: [CronaStream(id: 7, repoID: 3, name: "Stream")],
                90: [CronaStream(id: 91, repoID: 90, name: "Inbox", system: true)],
            ])
        XCTAssertEqual(result.destinations.map(\.streamID), [7])
        XCTAssertEqual(result.systemStreamIDs, [91])
    }

    func testVisibleDestinationsDropSystemStreamInRegularRepo() {
        let result = IssueCreationService.visibleDestinations(
            repos: [CronaRepo(id: 3, name: "Repo")],
            streams: [3: [CronaStream(id: 7, repoID: 3, name: "Stream"), CronaStream(id: 8, repoID: 3, name: "Inbox", system: true)]])
        XCTAssertEqual(result.destinations.map(\.streamID), [7])
        XCTAssertEqual(result.systemStreamIDs, [8])
    }

    func testLoadDestinationsHidesInbox() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.provideDestinations = true
        transport.provideInbox = true
        let service = IssueCreationService(daemonConnection: connection)

        await service.loadDestinations()

        XCTAssertEqual(service.destinations.map(\.streamID), [7])
        XCTAssertEqual(service.systemStreamIDs, [91])
    }

    func testSectionTitlesIncludeInboxCount() {
        XCTAssertEqual(DailySectionPicker.title(for: .inbox, sections: DailyIssueSections(inbox: [Self.inboxIssue(1), Self.inboxIssue(2), Self.inboxIssue(3)])), "Inbox (3)")
    }

    static func inboxIssue(_ id: Int64) -> DailyFocusIssue {
        DailyFocusIssue(id: id, streamID: 91, title: "Idea \(id)", status: "backlog", estimateMinutes: 30,
            workedSeconds: 0, todoForDate: "2001-02-04", description: "Notes")
    }

    func testMoveIssueSendsCurrentFieldsAndTargetStream() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        let service = IssueActionsService(daemonConnection: connection, dailyFocusService: DailyFocusService(daemonConnection: connection))

        let moved = await service.moveIssue(
            Self.inboxIssue(5), to: IssueDestination(repoID: 3, repoName: "Repo", streamID: 7, streamName: "Stream"))

        XCTAssertTrue(moved)
        let request = try XCTUnwrap(transport.requests.last { $0.method == "issue.move" })
        XCTAssertEqual(request.params["id"]?.intValue, 5)
        XCTAssertEqual(request.params["streamId"]?.intValue, 7)
        XCTAssertEqual(request.params["title"]?.stringValue, "Idea 5")
        XCTAssertEqual(request.params["estimateMinutes"]?.intValue, 30)
        XCTAssertEqual(request.params["todoForDate"]?.stringValue, "2001-02-04")
        XCTAssertEqual(request.params["description"]?.stringValue, "Notes")
    }

    func testSelectedInboxFallsBackToPlannedWhenEmptied() async throws {
        let (connection, transport) = try await issueCreatorConnection()
        defer { connection.stop() }
        transport.provideInbox = true
        transport.todaySummaryIssuesFixture = [[
            "id": 1, "streamId": 91, "title": "Idea", "status": "backlog", "workedSeconds": 0, "pinnedDaily": false,
        ]]
        let appState = CompanionAppState(daemonConnection: connection, preferences: isolatedPreferences())
        await appState.dailyIssues.refresh()
        XCTAssertEqual(appState.dailyIssues.sections.inbox.map(\.id), [1])
        appState.dailyIssues.section = .inbox

        transport.todaySummaryIssuesFixture = []
        await appState.dailyIssues.refresh()

        XCTAssertEqual(appState.dailyIssues.section, .planned)
    }
}
