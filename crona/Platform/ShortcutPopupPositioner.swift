import AppKit

enum ShortcutPopupPositioner {
    static func centeredOrigin(size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(x: max(visibleFrame.minX, visibleFrame.midX - size.width / 2),
                y: max(visibleFrame.minY, visibleFrame.midY - size.height / 2))
    }
}
