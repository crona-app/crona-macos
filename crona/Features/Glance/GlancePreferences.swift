import SwiftUI

enum GlanceWidget: String, Codable, CaseIterable, Identifiable {
    case issues, habits, calendar, selection, summary
    var id: String { rawValue }
    var title: String { rawValue == "summary" ? "Day Summary" : rawValue.capitalized }
}

struct GlancePreferences: Codable, Equatable {
    var hidden: Set<GlanceWidget> = []
    var order: [GlanceWidget] = GlanceWidget.allCases
    var startingSection = "planned"
    var unfinishedHabits = false
    var rememberDate = false
    var lastDate: String?
    var normalizedOrder: [GlanceWidget] {
        var seen: Set<GlanceWidget> = []
        return (order + GlanceWidget.allCases).filter { seen.insert($0).inserted }
    }
    func visible(_ widget: GlanceWidget) -> Bool { !hidden.contains(widget) }
}

struct GlanceCustomizationView: View {
    @ObservedObject var preferences: PreferencesService
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Choose what you want to see at a glance.").font(.body).foregroundStyle(.secondary)
            GlanceLayoutPreview(preferences: preferences.preferences.glance)
            ForEach([true, false], id: \.self) { main in
                SettingsCard(main ? "Main Column" : "Side Column") {
                    VStack(spacing: 14) {
                        ForEach(preferences.preferences.glance.normalizedOrder.filter { main == ([GlanceWidget.issues, .habits].contains($0)) }) { widget in
                            HStack {
                                Toggle(widget.title, isOn: Binding(get: { preferences.preferences.glance.visible(widget) }, set: { enabled in
                                    if enabled { preferences.preferences.glance.hidden.remove(widget) }
                                    else { preferences.preferences.glance.hidden.insert(widget) }
                                }))
                                Spacer()
                                Button { move(widget, offset: -1, main: main) } label: { Image(systemName: "chevron.up") }.help("Move up")
                                Button { move(widget, offset: 1, main: main) } label: { Image(systemName: "chevron.down") }.help("Move down")
                            }
                        }
                    }.padding(.vertical, 10)
                }
            }
            SettingsCard("Opening and Lists") {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Starting issue section", selection: $preferences.preferences.glance.startingSection) {
                        ForEach(["planned", "overdue", "upcoming", "inbox"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Toggle("Show only unfinished habits", isOn: $preferences.preferences.glance.unfinishedHabits)
                    Toggle("Open on the last viewed date", isOn: $preferences.preferences.glance.rememberDate)
                    Text("Otherwise Glance opens on Today.").foregroundStyle(.secondary)
                }.padding(.vertical, 10)
            }
            Button("Restore defaults") { preferences.preferences.glance = GlancePreferences() }
        }.font(.body)
    }
    private func move(_ widget: GlanceWidget, offset: Int, main: Bool) {
        var order = preferences.preferences.glance.normalizedOrder
        let group = order.filter { main == ([GlanceWidget.issues, .habits].contains($0)) }
        guard let index = group.firstIndex(of: widget), group.indices.contains(index + offset),
              let source = order.firstIndex(of: widget), let target = order.firstIndex(of: group[index + offset]) else { return }
        order.swapAt(source, target)
        preferences.preferences.glance.order = order
    }
}
