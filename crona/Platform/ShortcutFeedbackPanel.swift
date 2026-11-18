import AppKit
import SwiftUI

@MainActor
final class ShortcutFeedbackPanel {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(_ message: String) {
        dismissal?.cancel()
        let panel = panel ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 90),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.panel = panel
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            Text(message).font(.callout).multilineTextAlignment(.center)
                .padding(16).frame(width: 360, height: 90)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)))
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - 180, y: frame.minY + 48))
        }
        panel.orderFrontRegardless()
        dismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }
}
