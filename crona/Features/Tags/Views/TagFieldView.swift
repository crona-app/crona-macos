import SwiftUI

/// Edits a list of tags: chips with remove buttons, a field that adds on Return or comma, and existing tags as suggestions.
struct TagFieldView: View {
    @Binding var tags: [String]
    @ObservedObject var tagsModel: TagsModel
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { name in
                            Button {
                                tags.removeAll { $0 == name }
                            } label: {
                                HStack(spacing: 3) {
                                    TagChip(name: name, color: TagPresentation.color(named: tagsModel.color(for: name)))
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(PopupVisualTheme.tertiaryText)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(TagPresentation.label(for: name))")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 8) {
                TextField("Add a tag", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onChange(of: draft) { _, value in
                        if value.contains(",") { commit() }
                    }
                if !suggestions.isEmpty {
                    Menu {
                        ForEach(suggestions, id: \.self) { name in
                            Button(TagPresentation.label(for: name)) { tags.append(name); draft = "" }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Existing tags")
                }
            }
            .padding(10)
            .popupInputSurface(isFocused: isFocused)

            if isInvalid {
                Text("Use letters, digits, -, _ or /, up to 32 characters.")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.semantic(.error))
            }
        }
    }

    private var suggestions: [String] {
        let prefix = draft.trimmingCharacters(in: .whitespaces).lowercased()
        return tagsModel.tags.map(\.name)
            .filter { !tags.contains($0) && (prefix.isEmpty || $0.hasPrefix(prefix)) }
    }

    private var isInvalid: Bool {
        let pending = draft.replacingOccurrences(of: ",", with: "")
        return !pending.trimmingCharacters(in: .whitespaces).isEmpty && TagInput.normalize(pending) == nil
    }

    private func commit() {
        let parts = draft.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        var next = tags
        var rejected: [String] = []
        for part in parts where !part.trimmingCharacters(in: .whitespaces).isEmpty {
            let added = TagInput.adding(part, to: next)
            if added == next && TagInput.normalize(part) == nil { rejected.append(part) }
            next = added
        }
        tags = next
        draft = rejected.joined(separator: " ")
    }
}
