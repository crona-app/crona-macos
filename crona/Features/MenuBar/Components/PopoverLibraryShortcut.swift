import SwiftUI

/// Library entry points share the date toolbar instead of occupying a content row.
struct PopoverLibraryShortcut: View {
    let destination: LibraryDestination
    let open: () -> Void

    private var title: String { destination == .checkIns ? "Check-in history" : "Review" }
    private var icon: String { destination == .checkIns ? "clock.arrow.circlepath" : "chart.xyaxis.line" }

    var body: some View {
        Button(action: open) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.78))
        .background(Circle().fill(PopupVisualTheme.primaryText.opacity(0.08)))
        .help("Open \(title.lowercased()) in Library")
        .accessibilityLabel(title)
    }
}
