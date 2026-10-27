import Combine
import Foundation
import OSLog

/// Turns pasted lines into issue proposals as the user types, then imports them in one call.
@MainActor
final class IssueCaptureModel: ObservableObject {
    private let daemonConnection: DaemonConnectionService
    private let onImported: () async -> Void
    private let debounce: Duration
    private var parseTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.crona.macos", category: "issueCapture")

    @Published var text = "" {
        didSet {
            guard text != oldValue else { return }
            scheduleParse()
        }
    }
    @Published private(set) var proposals: [CronaCaptureProposal] = []
    @Published private(set) var isParsing = false
    @Published private(set) var isImporting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPresented = false

    init(
        daemonConnection: DaemonConnectionService,
        onImported: @escaping () async -> Void,
        debounce: Duration = .milliseconds(400)
    ) {
        self.daemonConnection = daemonConnection
        self.onImported = onImported
        self.debounce = debounce
    }

    deinit {
        parseTask?.cancel()
    }

    var importableCount: Int { proposals.filter(\.isImportable).count }

    var canImport: Bool {
        !proposals.isEmpty && importableCount == proposals.count && !isImporting
    }

    static func importButtonTitle(count: Int) -> String {
        count == 1 ? "Import 1 Issue" : "Import \(count) Issues"
    }

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
        text = ""
        parseTask?.cancel()
        parseTask = nil
        proposals = []
        isParsing = false
        errorMessage = nil
    }

    func parseNow() async {
        parseTask?.cancel()
        parseTask = nil
        await parse(text)
    }

    func importAll() async -> Bool {
        guard canImport else { return false }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            let proposals = self.proposals
            _ = try await daemonConnection.withClient { try await $0.importCapture(proposals) }
        } catch {
            logger.error("Capture import failed: \(error.localizedDescription, privacy: .private)")
            errorMessage = error.localizedDescription
            return false
        }
        await onImported()
        dismiss()
        return true
    }

    private func scheduleParse() {
        parseTask?.cancel()
        let snapshot = text
        let delay = debounce
        parseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.parse(snapshot)
        }
    }

    private func parse(_ snapshot: String) async {
        guard !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            proposals = []
            isParsing = false
            return
        }
        isParsing = true
        defer { if snapshot == text { isParsing = false } }
        do {
            let parsed = try await daemonConnection.withClient { try await $0.parseCapture(text: snapshot) }
            guard snapshot == text else { return }
            proposals = parsed
            errorMessage = nil
        } catch {
            guard snapshot == text else { return }
            errorMessage = error.localizedDescription
        }
    }
}
