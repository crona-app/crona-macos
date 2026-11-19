import SwiftUI

struct GlobalShortcutsView: View {
    @ObservedObject var model: GlobalShortcutsModel
    @ObservedObject var preferences: PreferencesService

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Use Crona shortcuts from any app, even when the menu bar icon is hidden.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsCard("Popup Placement") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 20) {
                        Text("Open shortcut popups at")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        Picker("Open shortcut popups at", selection: $preferences.preferences.shortcutPopupPlacement) {
                            ForEach(ShortcutPopupPlacement.allCases, id: \.self) { placement in
                                Text(placement.title).tag(placement)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                    Text("Screen center uses the screen containing your pointer. Clicking the menu bar icon always opens the popup beside it.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("When the menu bar icon is hidden, shortcut popups always open in the center.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .padding(.vertical, 8)
            }

            SettingsCard("Global Shortcuts") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(GlobalShortcutAction.allCases) { action in
                        VStack(alignment: .leading, spacing: 4) {
                            SettingsShortcutRow(title: action.title, onRecording: { model.isRecording = $0 }, shortcut: Binding(
                                get: { model.bindings[action.rawValue] },
                                set: { model.assign($0, to: action) }))
                            if let error = model.errors[action.rawValue] {
                                Text(error).font(.body).foregroundStyle(.red)
                            }
                        }
                    }
                    Divider()
                        .padding(.vertical, 4)
                    Text("Pause / Resume is available for stopwatch sessions.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
        }
    }
}
