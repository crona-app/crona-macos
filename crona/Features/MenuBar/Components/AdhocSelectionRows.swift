import SwiftUI

struct AdhocChoiceRow: View {
    let resolution: CronaAdhocResolution
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PopupVisualTheme.semantic(.focus))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(PopupVisualTheme.semantic(.focus).opacity(0.10)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(resolution.title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(PopupVisualTheme.secondaryText)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PopupVisualTheme.tertiaryText)
            }
            .foregroundStyle(PopupVisualTheme.primaryText)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 16))
            .background(RoundedRectangle(cornerRadius: 16).fill(hovered ? PopupVisualTheme.controlBackground : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(GlassPressButtonStyle())
        .onHover { hovered = $0 }
    }

    private var symbol: String {
        switch resolution {
        case .attach: "link"
        case .create: "plus"
        case .keep: "timer"
        }
    }
    private var subtitle: String {
        switch resolution {
        case .attach: "Add this work to an existing issue."
        case .create: "Turn this session into a new issue."
        case .keep: "Save it without choosing an issue."
        }
    }
}

struct AdhocIssueRow: View {
    let issue: CronaIssue
    let selected: Bool
    let dateLabel: String?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? PopupVisualTheme.semantic(.focus) : PopupVisualTheme.tertiaryText)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(issue.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text([issue.repoName, issue.streamName].compactMap { $0 }.joined(separator: " / "))
                        .font(.caption).foregroundStyle(PopupVisualTheme.secondaryText).lineLimit(1)
                    if let dateLabel {
                        Label(dateLabel, systemImage: "calendar")
                            .font(.caption2).foregroundStyle(PopupVisualTheme.tertiaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(PopupVisualTheme.primaryText)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(selected ? PopupVisualTheme.emphasizedSurfaceFill : PopupVisualTheme.surfaceFill))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? PopupVisualTheme.highlightedBorder : PopupVisualTheme.border, lineWidth: 0.8))
            .background(RoundedRectangle(cornerRadius: 14).fill(hovered ? PopupVisualTheme.controlBackground : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(GlassPressButtonStyle())
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
