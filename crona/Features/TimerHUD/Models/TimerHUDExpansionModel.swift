import AppKit
import Combine

@MainActor
final class TimerHUDExpansionModel: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var issueDescription: String?
    private weak var panel: NSPanel?
    private var compactFrame: NSRect?

    static func expandedFrame(from frame: NSRect, in visible: NSRect) -> NSRect {
        let size = NSSize(width: min(396, visible.width), height: min(348, visible.height))
        return NSRect(x: min(max(visible.minX, frame.midX - size.width / 2), visible.maxX - size.width),
                      y: min(max(visible.minY, frame.minY), visible.maxY - size.height),
                      width: size.width, height: size.height)
    }

    func loadDescription(state: CompanionAppState) async {
        issueDescription = nil
        guard let id = state.timerService.snapshot.issueID else { return }
        if let issue = state.detailsIssue(id: id) {
            issueDescription = issue.description
            return
        }
        guard let streamID = state.contextService.snapshot.streamID,
              let client = state.daemonConnection.client else { return }
        if let issues = try? await client.listIssues(streamID: streamID), !Task.isCancelled,
           state.timerService.snapshot.issueID == id {
            issueDescription = issues.first { $0.id == id }?.description
        }
    }

    func expand(panel: NSPanel) {
        guard !isExpanded, let screen = panel.screen ?? NSScreen.main else { return }
        self.panel = panel
        compactFrame = panel.frame
        isExpanded = true
        resize(Self.expandedFrame(from: panel.frame, in: screen.visibleFrame), animated: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Transfer the saved resting frame to the completion form without resizing first.
    func beginCompletion() -> NSRect? {
        guard isExpanded else { return nil }
        isExpanded = false
        let restingFrame = compactFrame
        compactFrame = nil
        return restingFrame
    }

    func collapse(animated: Bool = true) {
        guard isExpanded else { return }
        isExpanded = false
        if let compactFrame { resize(compactFrame, animated: animated) }
        compactFrame = nil
    }

    func lostFocus(_ window: NSWindow?) {
        if window === panel { collapse() }
    }

    private func resize(_ frame: NSRect, animated: Bool) {
        guard let panel else { return }
        if !animated || SystemGlassSettings.shared.reduceMotion {
            panel.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().setFrame(frame, display: true)
            }
        }
    }
}
