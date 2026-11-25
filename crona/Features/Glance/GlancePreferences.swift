import SwiftUI

enum GlanceWidget: String, Codable, CaseIterable, Identifiable {
    case issues, habits, calendar, selection, summary, wellbeing
    var id: String { rawValue }
    var isWorkList: Bool { self == .issues || self == .habits }
    var title: String { rawValue == "summary" ? "Day Summary" : rawValue.capitalized }
}

nonisolated enum GlanceLayout: String, Codable, CaseIterable, Identifiable {
    case adaptive, singleColumn

    var id: Self { self }
    var title: String { self == .adaptive ? "Adaptive Grid" : "Single Column" }
}

struct GlancePreferences: Codable, Equatable {
    var hidden: Set<GlanceWidget> = [.wellbeing]
    var layout: GlanceLayout = .adaptive
    var order: [GlanceWidget] = GlanceWidget.allCases
    var startingSection = "planned"
    var unfinishedHabits = false
    var rememberDate = false
    var lastDate: String?

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hidden = try values.decodeIfPresent(Set<GlanceWidget>.self, forKey: .hidden) ?? []
        if !values.contains(.layout) { hidden.insert(.wellbeing) }
        let savedLayout = try values.decodeIfPresent(String.self, forKey: .layout)
        layout = savedLayout.flatMap(GlanceLayout.init(rawValue:)) ?? .adaptive
        order = try values.decodeIfPresent([GlanceWidget].self, forKey: .order) ?? GlanceWidget.allCases
        startingSection = try values.decodeIfPresent(String.self, forKey: .startingSection) ?? startingSection
        unfinishedHabits = try values.decodeIfPresent(Bool.self, forKey: .unfinishedHabits) ?? false
        rememberDate = try values.decodeIfPresent(Bool.self, forKey: .rememberDate) ?? false
        lastDate = try values.decodeIfPresent(String.self, forKey: .lastDate)
    }

    var normalizedOrder: [GlanceWidget] {
        var seen: Set<GlanceWidget> = []
        return (order + GlanceWidget.allCases).filter { seen.insert($0).inserted }
    }
    func visible(_ widget: GlanceWidget) -> Bool { !hidden.contains(widget) }

    var visibleWidgets: [GlanceWidget] { normalizedOrder.filter(visible) }
    var orderedWorkWidgets: [GlanceWidget] { normalizedOrder.filter(\.isWorkList) }
    var orderedOverviewWidgets: [GlanceWidget] { normalizedOrder.filter { !$0.isWorkList && $0 != .selection } }
    var workWidgets: [GlanceWidget] { orderedWorkWidgets.filter(visible) }
    var overviewWidgets: [GlanceWidget] { orderedOverviewWidgets.filter(visible) }

    mutating func move(_ widget: GlanceWidget, by offset: Int) {
        let group = widget.isWorkList ? orderedWorkWidgets : orderedOverviewWidgets
        guard let index = group.firstIndex(of: widget), group.indices.contains(index + offset) else { return }
        var updated = normalizedOrder
        guard let from = updated.firstIndex(of: widget),
              let to = updated.firstIndex(of: group[index + offset]) else { return }
        updated.swapAt(from, to)
        order = updated
    }
}
