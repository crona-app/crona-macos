import SwiftUI

/// Tag chips in each tag's color. With a limit (rows), tags collapse into overlapping color dots
/// that show the full list on hover, so they never crowd the title.
struct TagChipsView: View {
    let tags: [String]
    @ObservedObject var tagsModel: TagsModel
    var limit: Int? = 3

    var body: some View {
        if !tags.isEmpty {
            if let limit {
                TagDots(tags: tags, limit: limit, tagsModel: tagsModel)
            } else {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.self) { name in
                        TagChip(name: name, color: TagPresentation.color(named: tagsModel.color(for: name)))
                    }
                }
                .fixedSize()
            }
        }
    }
}

private struct TagDots: View {
    let tags: [String]
    let limit: Int
    let tagsModel: TagsModel

    var body: some View {
        let split = TagChipLayout.split(tags, limit: limit)
        HStack(spacing: 3) {
            HStack(spacing: -4) {
                ForEach(split.shown, id: \.self) { name in
                    Circle()
                        .fill(TagPresentation.color(named: tagsModel.color(for: name)))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(PopupVisualTheme.surfaceFill, lineWidth: 1.5))
                }
            }
            if let overflow = TagChipLayout.overflowLabel(split.overflow) {
                Text(overflow)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.secondaryText)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .fixedSize()
        .hoverInfo {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(tags, id: \.self) { name in
                    TagChip(name: name, color: TagPresentation.color(named: tagsModel.color(for: name)))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tags: " + tags.map(TagPresentation.label(for:)).joined(separator: ", "))
    }
}

struct TagChip: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name == CronaTagFilter.untagged ? "Untagged" : name)
                .font(.caption.weight(.medium))
                .foregroundStyle(PopupVisualTheme.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(PopupVisualTheme.primaryText.opacity(0.08)))
        .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
    }
}

/// All of an item's tags in the details view, shown only when it has any.
struct TagDetailSection: View {
    let tags: [String]
    let tagsModel: TagsModel

    var body: some View {
        if !tags.isEmpty {
            DetailSection(title: "Tags", icon: TagPresentation.icon) {
                TagFlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { name in
                        TagChip(name: name, color: TagPresentation.color(named: tagsModel.color(for: name)))
                    }
                }
            }
        }
    }
}
