import SwiftUI

enum CronaCarryPresentation {
    static let carriedChipText = "Carried"
    static let carriedIcon = "arrow.uturn.right"
    static let stalledIcon = "exclamationmark.arrow.circlepath"

    static var carriedColor: Color { PopupVisualTheme.semantic(.carried) }

    static func undoMessage(title: String) -> String {
        "Carried \u{201C}\(title)\u{201D} to tomorrow"
    }

    static func badgeText(for carry: DailyFocusCarry?) -> String? {
        guard let carry else { return nil }
        if carry.stalled { return "Stalled" }
        return carry.count > 0 ? "Carried ×\(carry.count)" : nil
    }

    static func badgeIcon(for carry: DailyFocusCarry) -> String {
        carry.stalled ? stalledIcon : carriedIcon
    }

    static func badgeColor(for carry: DailyFocusCarry) -> Color {
        carry.stalled ? CronaPenaltyPresentation.colorKey.color : carriedColor
    }
}

struct CarryBadge: View {
    let carry: DailyFocusCarry?

    var body: some View {
        if let carry, let text = CronaCarryPresentation.badgeText(for: carry) {
            HStack(spacing: 4) {
                Image(systemName: CronaCarryPresentation.badgeIcon(for: carry))
                Text(text)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(CronaCarryPresentation.badgeColor(for: carry))
        }
    }
}
