import SwiftUI

struct AwayCalendarPicker: View {
    @Binding var selection: Date?
    let earliestDate: Date
    let scheduledDates: Set<String>
    let calendar: Calendar

    @State private var visibleMonth: Date

    init(selection: Binding<Date?>, earliestDate: Date, scheduledDates: Set<String>, calendar: Calendar) {
        _selection = selection
        self.earliestDate = earliestDate
        self.scheduledDates = scheduledDates
        self.calendar = calendar
        _visibleMonth = State(initialValue: selection.wrappedValue ?? earliestDate)
    }

    var body: some View {
        let month = AwayCalendarMonth(containing: visibleMonth, calendar: calendar)
        let cells = month.cells
        let weekdayNames = calendar.shortStandaloneWeekdaySymbols

        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(month.start, format: .dateTime.month(.wide).year())
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                monthButton("Previous month", icon: "chevron.backward") {
                    visibleMonth = month.shifted(by: -1)
                }
                .disabled(calendar.isDate(month.start, equalTo: earliestDate, toGranularity: .month))
                monthButton("Next month", icon: "chevron.forward") {
                    visibleMonth = month.shifted(by: 1)
                }
            }

            Divider()

            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                GridRow {
                    ForEach(0..<7) { offset in
                        Text(weekdayNames[(calendar.firstWeekday - 1 + offset) % 7])
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)

                ForEach(0..<6) { week in
                    GridRow {
                        ForEach(0..<7) { weekday in
                            if let date = cells[week * 7 + weekday] {
                                dayButton(date)
                            } else {
                                Color.clear.frame(height: 30)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
        }
        .environment(\.calendar, calendar)
        .onChange(of: earliestDate) { _, date in
            if !calendar.isDate(visibleMonth, equalTo: date, toGranularity: .month), visibleMonth < date {
                visibleMonth = date
            }
            if let selection, selection < date {
                self.selection = nil
            }
        }
    }

    private func monthButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .frame(width: 14, height: 16)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
        .help(title)
    }

    private func dayButton(_ date: Date) -> some View {
        let isToday = calendar.isDate(date, inSameDayAs: earliestDate)
        let isSelected = selection.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let isScheduled = date >= earliestDate && scheduledDates.contains(CronaCalendarDate.string(from: date))

        return Button {
            selection = date
        } label: {
            Text(date, format: .dateTime.day())
                .font(.subheadline.weight(isSelected || isToday ? .semibold : .medium).monospacedDigit())
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .overlay(alignment: .bottom) {
                    if isScheduled {
                        Circle()
                            .fill(isSelected ? Color.white : Color.accentColor)
                            .frame(width: 4, height: 4)
                            .padding(.bottom, 3)
                    }
                }
        }
        .buttonStyle(AwayCalendarDayStyle(isSelected: isSelected, isToday: isToday))
        .disabled(date < earliestDate)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue(isScheduled ? "Already scheduled" : (isToday ? "Today" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct AwayCalendarMonth {
    let start: Date
    let calendar: Calendar

    init(containing date: Date, calendar: Calendar) {
        start = calendar.dateInterval(of: .month, for: date)?.start ?? date
        self.calendar = calendar
    }

    var cells: [Date?] {
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
        return (0..<42).map { cell in
            let offset = cell - leading
            guard offset >= 0, offset < dayCount else { return nil }
            return calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    func shifted(by months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: start) ?? start
    }
}

private struct AwayCalendarDayStyle: ButtonStyle {
    let isSelected: Bool
    let isToday: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)

        configuration.label
            .foregroundStyle(isSelected ? Color.white : (isEnabled ? Color.primary : Color.secondary.opacity(0.55)))
            .background(background(isPressed: configuration.isPressed), in: shape)
            .overlay {
                if isToday && !isSelected {
                    shape.strokeBorder(Color.accentColor.opacity(0.7))
                }
            }
            .contentShape(shape)
            .onHover { isHovered = $0 }
    }

    private func background(isPressed: Bool) -> Color {
        if isSelected { return Color.accentColor }
        if isPressed { return Color.primary.opacity(0.14) }
        return isEnabled && isHovered ? Color.primary.opacity(0.08) : .clear
    }
}
