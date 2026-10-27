import SwiftUI

/// Tag chips in each tag's color. With a limit, extra tags collapse into `+N`.
struct TagChipsView: View {
    let tags: [String]
    @ObservedObject var tagsModel: TagsModel
    var limit: Int? = 2

    var body: some View {
        if !tags.isEmpty {
            let split = TagChipLayout.split(tags, limit: limit ?? tags.count)
            HStack(spacing: 4) {
                ForEach(split.shown, id: \.self) { name in
                    TagChip(name: name, color: TagPresentation.color(named: tagsModel.color(for: name)))
                }
                if let overflow = TagChipLayout.overflowLabel(split.overflow) {
                    Text(overflow)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PopupVisualTheme.secondaryText)
                        .help(tags.dropFirst(split.shown.count).map(TagPresentation.label(for:)).joined(separator: " "))
                }
            }
            .fixedSize()
        }
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
