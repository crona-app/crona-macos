import SwiftUI

/// Edits a list of tags: wrapping chips with remove buttons, and a field that suggests existing tags
/// as you type, with an "Add new" row for names that do not exist yet.
struct TagFieldView: View {
    @Binding var tags: [String]
    /// Text typed but not yet added; the owning model folds it in on save.
    @Binding var draft: String
    @ObservedObject var tagsModel: TagsModel
    @FocusState private var isFocused: Bool
    @State private var highlighted = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 8) {
                if !tags.isEmpty {
                    TagFlowLayout(spacing: 6) {
                        ForEach(tags, id: \.self) { name in
                            EditableTagChip(name: name, color: color(name)) {
                                tags.removeAll { $0 == name }
                            }
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: TagPresentation.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PopupVisualTheme.tertiaryText)
                    TextField(tags.isEmpty ? "Add tags" : "Add another", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        // Handle Return here so a sheet's default button (Create, Save) cannot take it first.
                        .onKeyPress(.return) { submit() }
                        .onSubmit { _ = submit() }
                        .onKeyPress(.downArrow) { move(1) }
                        .onKeyPress(.upArrow) { move(-1) }
                        .onChange(of: draft) { _, value in
                            highlighted = 0
                            if value.contains(",") { commitDraft() }
                        }
                }
            }
            .padding(10)
            .popupInputSurface(isFocused: isFocused)

            if isFocused && !suggestions.isEmpty {
                suggestionList
            } else if isInvalid {
                Text("Tags use letters, digits, -, _ or /, up to 32 characters.")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.semantic(.error))
            }
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                Button {
                    add(suggestion.name)
                } label: {
                    HStack(spacing: 8) {
                        switch suggestion {
                        case .existing(let name):
                            Circle().fill(color(name)).frame(width: 8, height: 8)
                            Text(name)
                                .foregroundStyle(PopupVisualTheme.primaryText)
                        case .create(let name):
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(PopupVisualTheme.semantic(.info))
                            Text("Add new tag ") + Text(name).bold()
                        }
                        Spacer(minLength: 0)
                        if index == highlighted {
                            Image(systemName: "return")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(PopupVisualTheme.tertiaryText)
                        }
                    }
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(index == highlighted ? PopupVisualTheme.primaryText.opacity(0.08) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { highlighted = index } }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(PopupVisualTheme.primaryText.opacity(0.05)))
    }

    private var suggestions: [TagSuggestion] {
        TagSuggestions.make(draft: draft, existing: tagsModel.tags.map(\.name), selected: tags)
    }

    private var isInvalid: Bool {
        let pending = draft.replacingOccurrences(of: ",", with: "")
        return !pending.trimmingCharacters(in: .whitespaces).isEmpty && TagInput.normalize(pending) == nil
    }

    private func color(_ name: String) -> Color {
        TagPresentation.color(named: tagsModel.color(for: name))
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !suggestions.isEmpty else { return .ignored }
        highlighted = (highlighted + step + suggestions.count) % suggestions.count
        return .handled
    }

    /// Adds the highlighted suggestion or the typed text. With nothing typed, Return falls through to the sheet.
    private func submit() -> KeyPress.Result {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return .ignored }
        let options = suggestions
        if options.indices.contains(highlighted) {
            add(options[highlighted].name)
        } else {
            commitDraft()
        }
        isFocused = true
        return .handled
    }

    private func add(_ name: String) {
        if !tags.contains(name) { tags.append(name) }
        draft = ""
        highlighted = 0
    }

    private func commitDraft() {
        tags = TagInput.committing(draft, into: tags)
        draft = ""
    }
}

/// A legible tag chip for editing: a color dot, the name in primary text, and a remove button.
private struct EditableTagChip: View {
    let name: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name)
                .font(.callout.weight(.medium))
                .foregroundStyle(PopupVisualTheme.primaryText)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(name)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Capsule().fill(PopupVisualTheme.primaryText.opacity(0.08)))
        .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct TagFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty && row.width + spacing + size.width > width {
                let y = row.y + row.height + spacing
                rows.append(Row(y: y))
                row = rows[rows.count - 1]
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
