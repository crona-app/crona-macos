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
}
