import Combine
import Foundation
import OSLog

struct CarryUndoOffer: Equatable {
    let issueID: Int64
    let title: String
}

/// Carries issues to the next working day and offers a short undo.
@MainActor
final class CarryOverModel: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private let onChanged: () async -> Void
    private let undoWindow: Duration
    private var expiryTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.crona.macos", category: "carryOver")

    @Published private(set) var inFlightIssueID: Int64?
    @Published private(set) var undoOffer: CarryUndoOffer?
    @Published private(set) var errorMessage: String?

    init(
        daemonConnection: DaemonConnectionService,
        onChanged: @escaping () async -> Void,
        undoWindow: Duration = .seconds(5)
    ) {
        self.daemonConnection = daemonConnection
        self.onChanged = onChanged
        self.undoWindow = undoWindow
    }

    deinit {
        expiryTask?.cancel()
    }

    func carry(_ issue: DailyFocusIssue) async {
        let succeeded = await perform(issueID: issue.id) {
            _ = try await $0.carryIssue(issueID: issue.id)
        }
        guard succeeded else { return }
        offerUndo(CarryUndoOffer(issueID: issue.id, title: issue.title))
    }

    func undo() async {
        guard let offer = undoOffer else { return }
        dismissUndo()
        await undoCarry(issueID: offer.issueID)
    }

    func undoCarry(issueID: Int64) async {
        _ = await perform(issueID: issueID) {
            _ = try await $0.undoCarry(issueID: issueID)
        }
    }

    func dismissUndo() {
        expiryTask?.cancel()
        expiryTask = nil
        undoOffer = nil
    }

    func clearError() {
        errorMessage = nil
    }

    private func offerUndo(_ offer: CarryUndoOffer) {
        expiryTask?.cancel()
        undoOffer = offer
        let window = undoWindow
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled, self?.undoOffer == offer else { return }
            self?.undoOffer = nil
        }
    }

    private func perform(
        issueID: Int64,
        operation: @escaping (CronaDaemonClient) async throws -> Void
    ) async -> Bool {
        guard inFlightIssueID == nil else { return false }
        inFlightIssueID = issueID
        errorMessage = nil
        defer { inFlightIssueID = nil }
        do {
            try await daemonConnection.withClient { try await operation($0) }
            await onChanged()
            return true
        } catch {
            logger.error("Carry action failed: \(error.localizedDescription, privacy: .private)")
            errorMessage = error.localizedDescription
            return false
        }
    }
}
