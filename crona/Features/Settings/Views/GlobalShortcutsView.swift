import SwiftUI

struct GlobalShortcutsView: View {
    @ObservedObject var model: GlobalShortcutsModel
    var body: some View {
        SettingsCard("Global Shortcuts") {
            Text("Shortcuts work from any app while Crona is running, even when its menu bar icon is hidden.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(GlobalShortcutAction.allCases) { action in
                SettingsShortcutRow(title: action.title, onRecording: { model.isRecording = $0 }, shortcut: Binding(
                    get: { model.bindings[action.rawValue] },
                    set: { model.assign($0, to: action) }))
                if let error = model.errors[action.rawValue] {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Text("Pause / Resume is available for stopwatch sessions.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
