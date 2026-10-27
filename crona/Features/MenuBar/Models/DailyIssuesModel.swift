import Combine
import Foundation
import OSLog

/// Planned, Overdue and Upcoming issues for the shared popover day.
@MainActor
final class DailyIssuesModel: ObservableObject {
    private static let refreshEvents: Set<String> = [
        "session.history_changed", "session.started", "session.stopped", "session.ended",
        "context.issue.changed", "issue.updated", "issue.created", "issue.deleted",
    ]

    private let daemonConnection: DaemonConnectionService
    private let day: PopoverDayModel
    private let issueCreationService: IssueCreationService
    private let tags: TagsModel
    private var eventObserver: NSObjectProtocol?
    private var tagFilterSubscription: AnyCancellable?
    /// Every section before the Issues tag filter applies.
    private var unfilteredSections = DailyIssueSections()
    private let logger = Logger(subsystem: "com.crona.macos", category: "dailyIssues")

    /// The sections after the Issues tag filter.
    @Published private(set) var sections = DailyIssueSections()
    @Published var section: DailySection = .planned
    @Published private(set) var isLoading = false

    init(
        daemonConnection: DaemonConnectionService, day: PopoverDayModel,
        issueCreationService: IssueCreationService, tags: TagsModel
    ) {
        self.daemonConnection = daemonConnection
        self.day = day
        self.issueCreationService = issueCreationService
        self.tags = tags
        // @Published emits before the change lands, so filter with the emitted values.
        tagFilterSubscription = tags.$filters.combineLatest(tags.$tags)
            .dropFirst()
            .sink { [weak self] filters, list in
                self?.applyFilter(filters[.issues] ?? CronaTagFilter(), known: Set(list.map(\.name)))
            }
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

    var allIssues: [DailyFocusIssue] {
        sections.planned + sections.overdue + sections.upcoming + sections.inbox
    }

    func refresh() async {
        let date = day.selectedDate
        isLoading = true
        defer { isLoading = false }
        // The Inbox is recognised by its system stream, which comes with the destinations list.
        if issueCreationService.destinations.isEmpty && issueCreationService.systemStreamIDs.isEmpty {
            await issueCreationService.loadDestinations()
        }
        do {
            async let issues = daemonConnection.withClient { try await $0.listAllIssues() }
            async let plan = daemonConnection.withClient { try await $0.dailyPlanGet(date: date) }
            let fetchedIssues = try await issues
            // A stream we have not seen (such as an Inbox created by capture) means the destinations are stale.
            let knownStreamIDs = Set(issueCreationService.destinations.map(\.streamID))
                .union(issueCreationService.systemStreamIDs)
            if fetchedIssues.contains(where: { !knownStreamIDs.contains($0.streamID) }) {
                await issueCreationService.loadDestinations()
            }
            let built = DailyIssueSections.build(
                issues: fetchedIssues, plan: try await plan, date: date,
                systemStreamIDs: issueCreationService.systemStreamIDs)
            // A newer day may have been picked while this one loaded.
            guard date == day.selectedDate else { return }
            unfilteredSections = built
            applyFilter(tags.filter(for: .issues), known: tags.knownNames)
        } catch {
            logger.error("Daily issues refresh failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func applyFilter(_ filter: CronaTagFilter, known: Set<String>) {
        let filtered = filter.isEmpty
            ? unfilteredSections : unfilteredSections.filtered { filter.matches($0.tags, known: known) }
        sections = filtered
        if !filtered.visibleSections.contains(section) {
            section = .planned
        }
    }
}
