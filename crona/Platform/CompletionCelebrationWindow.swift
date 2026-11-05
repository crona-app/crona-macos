import AppKit
import SwiftUI

/// A transparent, click-through window over one screen that plays a completion celebration and closes itself.
@MainActor
final class CompletionCelebrationWindow {
    private var panel: NSPanel?
    private var closeTask: Task<Void, Never>?

    /// Plays `style` on `screen`, aimed at `popupFrame` (screen coordinates). It sits just under the popup.
    func play(_ style: CompletionCelebrationStyle, on screen: NSScreen, popupFrame: NSRect, below level: NSWindow.Level) {
        let resolved = style.resolved(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        guard resolved != .off else { return }
        close()

        let frame = screen.frame
        let target = CGPoint(x: popupFrame.midX - frame.minX, y: frame.maxY - popupFrame.midY)
        let panel = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: level.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: CompletionCelebrationScreenView(style: resolved, target: target)
                .frame(width: frame.width, height: frame.height))
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        self.panel = panel

        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(resolved.duration))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    func close() {
        closeTask?.cancel()
        closeTask = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
