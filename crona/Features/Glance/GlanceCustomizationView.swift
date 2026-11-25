import SwiftUI

struct GlanceCustomizationView: View {
    @ObservedObject var preferences: PreferencesService

    private var glance: GlancePreferences { preferences.preferences.glance }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard("Layout") {
                Picker("Pane layout", selection: $preferences.preferences.glance.layout) {
                    ForEach(GlanceLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }

            paneGroup("Overview", widgets: glance.orderedOverviewWidgets)
            paneGroup("Workspace", widgets: glance.orderedWorkWidgets)
            SettingsCard("Inspector") {
                visibilityToggle(.selection, title: "Show Selection inspector")
                    .padding(.vertical, 8)
            }
            GlanceLayoutPreview(preferences: glance)

            SettingsCard("Opening and Lists") {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Starting issue section", selection: $preferences.preferences.glance.startingSection) {
                        ForEach(["planned", "overdue", "upcoming", "inbox"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Toggle("Show only unfinished habits", isOn: $preferences.preferences.glance.unfinishedHabits)
                    Toggle("Open on the last viewed date", isOn: $preferences.preferences.glance.rememberDate)
                }
                .padding(.vertical, 10)
            }
            Button("Restore defaults") { preferences.preferences.glance = GlancePreferences() }
        }
        .font(.body)
    }

    private func paneGroup(_ title: String, widgets: [GlanceWidget]) -> some View {
        SettingsCard(title) {
            VStack(spacing: 10) {
                ForEach(Array(widgets.enumerated()), id: \.element) { index, widget in
                    HStack(spacing: 8) {
                        visibilityToggle(widget, title: widget.title)
                        Spacer()

                        moveButton(widget, up: true).disabled(index == 0)
                        moveButton(widget, up: false).disabled(index == widgets.count - 1)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func visibilityToggle(_ widget: GlanceWidget, title: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { glance.visible(widget) },
            set: { enabled in
                if enabled { preferences.preferences.glance.hidden.remove(widget) }
                else { preferences.preferences.glance.hidden.insert(widget) }
            }
        ))
    }

    private func moveButton(_ widget: GlanceWidget, up: Bool) -> some View {
        let title = "Move \(widget.title) \(up ? "up" : "down")"
        return Button {
            preferences.preferences.glance.move(widget, by: up ? -1 : 1)
        } label: {
            Image(systemName: up ? "chevron.up" : "chevron.down")
        }
        .accessibilityLabel(title)
        .help(title)
    }
}
