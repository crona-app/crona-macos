import Combine
import Foundation
import OSLog

/// The panes whose tag filter the Mac app shares with the TUI through the `tagFilters` core setting.
enum TagPane: String, CaseIterable {
    case issues
    case habits
}

/// The tag vocabulary and the saved Issues and Habits tag filters.
@MainActor
final class TagsModel: ObservableObject {
    private static let refreshEvents: Set<String> = ["tags.changed", "settings.changed"]

    private let daemonConnection: DaemonConnectionService
    private var eventObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.crona.macos", category: "tags")

    @Published private(set) var tags: [CronaTag] = []
    @Published private(set) var filters: [TagPane: CronaTagFilter] = [:]
    @Published private(set) var errorMessage: String?

    init(daemonConnection: DaemonConnectionService) {
        self.daemonConnection = daemonConnection
        eventObserver = NotificationCenter.default.addObserver(
            forName: .cronaDaemonEventReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.object as? CronaProtocolEvent,
                Self.refreshEvents.contains(event.type)
            else { return }
            Task { await self?.refresh() }
        }
    }

    isolated deinit {
        if let eventObserver {
            NotificationCenter.default.removeObserver(eventObserver)
        }
    }

    var knownNames: Set<String> { Set(tags.map(\.name)) }

    func refresh() async {
        do {
            tags = try await daemonConnection.withClient { try await $0.listTags() }
            errorMessage = nil
        } catch {
            logger.error("Tag list failed: \(error.localizedDescription, privacy: .private)")
            errorMessage = error.localizedDescription
        }
        do {
            let saved = try await daemonConnection.withClient { try await $0.tagFiltersGet() }
            filters = Self.filters(from: saved)
        } catch {
            logger.error("Tag filters failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func filter(for pane: TagPane) -> CronaTagFilter {
        filters[pane] ?? CronaTagFilter()
    }

    func matches(_ itemTags: [String], in pane: TagPane) -> Bool {
        filter(for: pane).matches(itemTags, known: knownNames)
    }

    func color(for name: String) -> String? {
        tags.first { $0.name == name }?.color
    }

    func setFilter(_ filter: CronaTagFilter, for pane: TagPane) async {
        let previous = filters[pane]
        filters[pane] = filter.isEmpty ? nil : filter
        do {
            // Patch over the latest map so the TUI's other panes are kept.
            var saved = try await daemonConnection.withClient { try await $0.tagFiltersGet() }
            saved[pane.rawValue] = filter.isEmpty ? nil : filter.query
            try await daemonConnection.withClient { try await $0.tagFiltersPatch(saved) }
            errorMessage = nil
        } catch {
            logger.error("Saving tag filter failed: \(error.localizedDescription, privacy: .private)")
            filters[pane] = previous
            errorMessage = error.localizedDescription
        }
    }

    private static func filters(from saved: [String: String]) -> [TagPane: CronaTagFilter] {
        var result: [TagPane: CronaTagFilter] = [:]
        for pane in TagPane.allCases {
            let filter = CronaTagFilter(query: saved[pane.rawValue] ?? "")
            if !filter.isEmpty { result[pane] = filter }
        }
        return result
    }
}
