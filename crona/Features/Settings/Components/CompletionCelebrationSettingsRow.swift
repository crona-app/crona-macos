import SwiftUI

/// Picks the focus-complete celebration and previews it on the current screen.
struct CompletionCelebrationSettingsRow: View {
    @Binding var selection: CompletionCelebrationStyle
    let onPreview: (CompletionCelebrationStyle) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SettingsPickerRow(
                title: "Completion Celebration",
                subtitle: "Played across the screen when a focus block completes. Reduce Motion turns it off.",
                selection: Binding(
                    get: { selection },
                    set: {
                        selection = $0
                        onPreview($0)
                    }
                )
            ) {
                ForEach(CompletionCelebrationStyle.allCases) { Text($0.title).tag($0) }
            }
            Button("Preview") { onPreview(selection) }
                .disabled(selection == .off)
        }
    }
}
