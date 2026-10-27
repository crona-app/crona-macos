import SwiftUI

/// The tag filter for one tab, shared with the TUI through the `tagFilters` core setting.
struct TagFilterMenu: View {
    let pane: TagPane
    @ObservedObject var tagsModel: TagsModel

    var body: some View {
        let filter = tagsModel.filter(for: pane)
        let names = tagsModel.tags.map(\.name) + [CronaTagFilter.untagged]
        Menu {
            Section("Show") {
                ForEach(names, id: \.self) { name in
                    Toggle(TagPresentation.label(for: name), isOn: binding(name, in: filter.any, toggle: { $0.toggleShow(name) }))
                }
            }
            Menu("Hide") {
                ForEach(names, id: \.self) { name in
                    Toggle(TagPresentation.label(for: name), isOn: binding(name, in: filter.none, toggle: { $0.toggleHide(name) }))
                }
            }
            if !filter.isEmpty {
                Divider()
                Button("Clear Filter") { save(CronaTagFilter()) }
            }
        } label: {
            Image(systemName: filter.isEmpty
                ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filter.isEmpty ? PopupVisualTheme.secondaryText : PopupVisualTheme.semantic(.info))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(filter.isEmpty ? "Filter by tag" : "Filtered: \(filter.query)")
        .accessibilityLabel("Filter by tag")
    }

    private func binding(_ name: String, in list: [String], toggle: @escaping (inout CronaTagFilter) -> Void) -> Binding<Bool> {
        Binding(
            get: { list.contains(name) },
            set: { _ in
                var next = tagsModel.filter(for: pane)
                toggle(&next)
                save(next)
            }
        )
    }

    private func save(_ filter: CronaTagFilter) {
        Task { await tagsModel.setFilter(filter, for: pane) }
    }
}
