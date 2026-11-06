import SwiftUI

/// A compact "new version" pill pinned to the bottom of the menu bar popup.
struct UpdateAvailablePill: View {
    let latestVersion: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(PopupVisualTheme.semantic(.info))
                Text(Self.title(latestVersion: latestVersion))
                    .foregroundStyle(PopupVisualTheme.primaryText)
                Text("Update")
                    .foregroundStyle(PopupVisualTheme.semantic(.info))
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(PopupVisualTheme.semantic(.info).opacity(0.14))
                    .overlay(Capsule().strokeBorder(PopupVisualTheme.semantic(.info).opacity(0.35), lineWidth: 0.8))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Self.title(latestVersion: latestVersion) + ", update")
    }

    static func title(latestVersion: String?) -> String {
        guard let version = latestVersion, !version.isEmpty else { return "New version available" }
        return "Crona \(version) available"
    }
}
