import Combine
import Foundation
import OSLog

struct IssueDestination: Equatable, Identifiable {
    let repoID: Int64
    let repoName: String
    let streamID: Int64
    let streamName: String

    var id: Int64 { streamID }
    var label: String { "\(repoName) / \(streamName)" }
}

@MainActor
final class IssueCreationService: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private let logger = Logger(subsystem: "com.crona.macos", category: "issueCreation")

    @Published private(set) var destinations: [IssueDestination] = []
    /// Streams Crona made itself (the Inbox), kept out of `destinations`.
    @Published private(set) var systemStreamIDs: Set<Int64> = []
    @Published private(set) var isLoadingDestinations = false
    @Published private(set) var isCreating = false
    @Published private(set) var lastErrorMessage: String?

    init(daemonConnection: DaemonConnectionService) {
        self.daemonConnection = daemonConnection
    }

    func loadDestinations() async {
        guard !isLoadingDestinations else { return }
        isLoadingDestinations = true
        lastErrorMessage = nil
        defer { isLoadingDestinations = false }
        do {
            let repos = try await daemonConnection.withClient { try await $0.listRepos() }
            var streams: [Int64: [CronaStream]] = [:]
            for repo in repos {
                streams[repo.id] = try await daemonConnection.withClient { try await $0.listStreams(repoID: repo.id) }
            }
            let visible = Self.visibleDestinations(repos: repos, streams: streams)
            destinations = visible.destinations
            systemStreamIDs = visible.systemStreamIDs
        } catch {
            logger.error("Loading issue destinations failed: \(error.localizedDescription, privacy: .private)")
            lastErrorMessage = error.localizedDescription
        }
    }

    func create(_ request: CronaCreateIssueRequest) async -> CronaIssue? {
        guard !isCreating else { return nil }
        isCreating = true
        lastErrorMessage = nil
        defer { isCreating = false }
        do {
            return try await daemonConnection.withClient { try await $0.createIssue(request) }
        } catch {
            logger.error("Creating issue failed: \(error.localizedDescription, privacy: .private)")
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    func clearError() { lastErrorMessage = nil }

    /// Destinations a user may pick: every stream except the ones Crona made itself.
    static func visibleDestinations(repos: [CronaRepo], streams: [Int64: [CronaStream]])
        -> (destinations: [IssueDestination], systemStreamIDs: Set<Int64>)
    {
        var destinations: [IssueDestination] = []
        var systemStreamIDs = Set<Int64>()
        for repo in repos {
            for stream in streams[repo.id] ?? [] {
                if repo.system == true || stream.system == true {
                    systemStreamIDs.insert(stream.id)
                    continue
                }
                destinations.append(
                    IssueDestination(repoID: repo.id, repoName: repo.name, streamID: stream.id, streamName: stream.name))
            }
        }
        destinations.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        return (destinations, systemStreamIDs)
    }
}
