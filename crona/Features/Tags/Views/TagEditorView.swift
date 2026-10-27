import SwiftUI

struct TagEditorView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var tagEditor: TagEditorModel

    init(appState: CompanionAppState, tagEditor: TagEditorModel) {
        self.appState = appState
        self.tagEditor = tagEditor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: tagEditor.dismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(PopupVisualTheme.primaryText.opacity(0.06)))
                        .padding(7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(tagEditor.isSaving)
                .accessibilityLabel("Back")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Tags")
                        .font(.headline)
                        .foregroundStyle(PopupVisualTheme.primaryText)
                    Text(tagEditor.target?.name ?? "")
                        .font(.caption)
                        .foregroundStyle(PopupVisualTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer()
            }

            TagFieldView(tags: $tagEditor.tags, draft: $tagEditor.draft, tagsModel: appState.tags)

            if let error = tagEditor.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.semantic(.error).opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await tagEditor.save() }
            } label: {
                Text(tagEditor.isSaving ? "Saving…" : "Save Tags")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(tagEditor.isSaving)
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onExitCommand(perform: tagEditor.dismiss)
    }
}
