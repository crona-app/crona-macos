import AppKit

/// Native views match the fitted window; the fixed measurement canvas lives inside SwiftUI.
final class StatusPopupCanvas: NSView {
    private let hostingView: NSView
    init(hostingView: NSView, size: NSSize) {
        self.hostingView = hostingView
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.masksToBounds = true
        addSubview(hostingView)
        hostingView.autoresizingMask = []
        layoutCanvas()
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); layoutCanvas() }
    private func layoutCanvas() {
        hostingView.frame = bounds
    }
    static func fittedFrame(_ frame: NSRect, height: CGFloat, centeredIn visibleFrame: NSRect? = nil) -> NSRect {
        let height = min(StatusPopupSizing.viewportHeight, max(StatusPopupSizing.minimumHeight, height.rounded(.up)))
        let size = NSSize(width: frame.width, height: height)
        if let visibleFrame {
            return NSRect(origin: ShortcutPopupPositioner.centeredOrigin(size: size, visibleFrame: visibleFrame), size: size)
        }
        return NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
    }
}
