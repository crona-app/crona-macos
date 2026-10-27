import SwiftUI

struct SegmentedControl<T: Hashable & CaseIterable & Identifiable>: View
where T.AllCases: RandomAccessCollection {

    @Binding var selection: T
    let title: (T) -> String
    var icon: ((T) -> String?)? = nil
    var fitsContent = false
    /// The segments to show; every case when nil.
    var items: [T]? = nil

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items ?? Array(T.allCases)) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(SystemGlassSettings.shared.reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.9)) {
                        selection = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let iconName = icon?(item) {
                            Image(systemName: iconName)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(title(item))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                        ? PopupVisualTheme.primaryText
                        : PopupVisualTheme.secondaryText
                    )
                    .frame(maxWidth: fitsContent ? nil : .infinity)
                    .padding(.horizontal, fitsContent ? 12 : 0)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .background {
                    segmentBackground(isSelected: isSelected)
                }
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(PopupVisualTheme.controlBackground)
                .overlay {
                    Capsule()
                        .strokeBorder(PopupVisualTheme.border.opacity(0.85), lineWidth: 0.8)
                }
        }
    }

    @ViewBuilder
    private func segmentBackground(isSelected: Bool) -> some View {
        if isSelected {
            Capsule()
                .fill(PopupVisualTheme.elevatedBackground)
                .overlay {
                    Capsule()
                        .strokeBorder(PopupVisualTheme.highlightedBorder, lineWidth: 0.8)
                }
        } else {
            Capsule()
                .fill(Color.clear)
        }
    }
}
