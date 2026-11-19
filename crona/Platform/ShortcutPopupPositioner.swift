import AppKit

enum ShortcutPopupPlacement: String, Codable, CaseIterable {
    case screenCenter
    case menuBar

    var title: String {
        switch self {
        case .screenCenter: return "Screen center"
        case .menuBar: return "Menu bar"
        }
    }
}

enum ShortcutPopupPositioner {
    static func centeredOrigin(size: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(x: max(visibleFrame.minX, visibleFrame.midX - size.width / 2),
                y: max(visibleFrame.minY, visibleFrame.midY - size.height / 2))
    }
}
