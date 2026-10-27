import SwiftUI

/// How many tag chips a row shows before collapsing the rest into `+N`.
enum TagChipLayout {
    static func split(_ tags: [String], limit: Int = 2) -> (shown: [String], overflow: Int) {
        (Array(tags.prefix(limit)), max(0, tags.count - limit))
    }

    static func overflowLabel(_ overflow: Int) -> String? {
        overflow > 0 ? "+\(overflow)" : nil
    }
}

enum TagPresentation {
    static let icon = "tag"

    static func label(for name: String) -> String {
        name == CronaTagFilter.untagged ? "Untagged" : "#\(name)"
    }

    /// Maps the core's palette names; a tag without a color reads as neutral.
    static func color(named name: String?) -> Color {
        switch name {
        case "blue": .blue
        case "cyan": .cyan
        case "green": .green
        case "magenta": .pink
        case "yellow": .yellow
        case "red": .red
        case "orange": .orange
        case "lavender": PopupVisualTheme.semantic(.carried)
        default: PopupVisualTheme.secondaryText
        }
    }
}
