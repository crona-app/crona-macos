import SwiftUI

/// Stats section: the top tags by focused time for the shown day or its week.
struct FocusByTagSection: View {
    let date: String
    @ObservedObject var tagFocus: TagFocusModel
    @ObservedObject var tagsModel: TagsModel
    @State private var showsWeek = false

    var body: some View {
        let rows = showsWeek ? tagFocus.week : tagFocus.today
        Group {
            if !tagFocus.today.isEmpty || !tagFocus.week.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Focus by tag", systemImage: TagPresentation.icon)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PopupVisualTheme.secondaryText)
                        Spacer()
                        Picker("Range", selection: $showsWeek) {
                            Text("Day").tag(false)
                            Text("Week").tag(true)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }

                    if rows.isEmpty {
                        Text("No tagged focus time yet.")
                            .font(.caption)
                            .foregroundStyle(PopupVisualTheme.secondaryText)
                    } else {
                        let top = max(rows.first?.workedSeconds ?? 1, 1)
                        ForEach(rows) { row in
                            rowView(row, fraction: Double(row.workedSeconds) / Double(top))
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PopupVisualTheme.surfaceFill))
            }
        }
        .task(id: date) { await tagFocus.refresh(date: date) }
    }

    private func rowView(_ row: CronaTimeDistributionRow, fraction: Double) -> some View {
        let color = TagPresentation.color(named: tagsModel.color(for: row.key))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                TagChip(name: row.key, color: color)
                Spacer()
                Text(MenuBarTextFormatter.formatCompactDuration(seconds: row.workedSeconds))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(PopupVisualTheme.primaryText)
            }
            GeometryReader { proxy in
                Capsule().fill(color.opacity(0.5)).frame(width: max(4, proxy.size.width * fraction))
            }
            .frame(height: 3)
        }
    }
}
