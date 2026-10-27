import Combine
import Foundation
import OSLog

enum TagEditorTarget: Equatable {
    case issue(id: Int64, title: String)
    case habit(id: Int64, name: String)

    var name: String {
        switch self {
        case .issue(_, let title): title
        case .habit(_, let name): name
        }
    }
}

/// Replaces one issue's or habit's tags from the row menu.
@MainActor
final class TagEditorModel: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private let onSaved: () async -> Void
    private let logger = Logger(subsystem: "com.crona.macos", category: "tagEditor")

    @Published private(set) var target: TagEditorTarget?
    @Published var tags: [String] = []
    @Published var draft = ""
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    init(daemonConnection: DaemonConnectionService, onSaved: @escaping () async -> Void) {
        self.daemonConnection = daemonConnection
        self.onSaved = onSaved
    }

    var isPresented: Bool { target != nil }

    func present(_ target: TagEditorTarget, tags: [String]) {
        guard !isSaving else { return }
        self.target = target
        self.tags = tags
        draft = ""
        errorMessage = nil
    }

    func dismiss() {
        guard !isSaving else { return }
        target = nil
        tags = []
        draft = ""
        errorMessage = nil
    }

    func save() async -> Bool {
        guard let target, !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        self.tags = TagInput.committing(draft, into: self.tags)
        draft = ""
        let tags = self.tags
        do {
            switch target {
            case .issue(let id, _):
                _ = try await daemonConnection.withClient { try await $0.setIssueTags(issueID: id, tags: tags) }
            case .habit(let id, _):
                _ = try await daemonConnection.withClient { try await $0.setHabitTags(habitID: id, tags: tags) }
            }
        } catch {
            isSaving = false
            logger.error("Saving tags failed: \(error.localizedDescription, privacy: .private)")
            errorMessage = error.localizedDescription
            return false
        }
        isSaving = false
        await onSaved()
        dismiss()
        return true
    }
}
