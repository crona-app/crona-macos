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
    @State private var isHovered = false

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
        .contentShape(Rectangle())
        .fixedSize()
        .onHover { isHovered = $0 }
        .popover(isPresented: $isHovered, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(tags, id: \.self) { name in
                    TagChip(name: name, color: TagPresentation.color(named: tagsModel.color(for: name)))
                }
            }
            .padding(10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tags: " + tags.map(TagPresentation.label(for:)).joined(separator: ", "))
    }
}

struct TagChip: View {
    let name: String
    let color: Color

    var body: some View {
        Text(TagPresentation.label(for: name))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}

/// All of an item's tags in the details view, shown only when it has any.
struct TagDetailSection: View {
    let tags: [String]
    let tagsModel: TagsModel

    var body: some View {
        if !tags.isEmpty {
            DetailSection(title: "Tags", icon: TagPresentation.icon) {
                ViewThatFits(in: .horizontal) {
                    TagChipsView(tags: tags, tagsModel: tagsModel, limit: nil)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tags, id: \.self) { name in
                            TagChipsView(tags: [name], tagsModel: tagsModel, limit: nil)
                        }
                    }
                }
            }
        }
    }
}
