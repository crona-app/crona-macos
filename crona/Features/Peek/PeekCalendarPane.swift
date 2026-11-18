import SwiftUI

struct PeekCalendarPane: View {
    @ObservedObject var day: PopoverDayModel
    @ObservedObject var stats: PopoverStatsService
    let today: String
    let settings: CronaCoreSettings
    var compact = false
    @State private var showsMonth = false
    @State private var month: Date = Date()

    private var calendar: Calendar { Calendar.current }
    private var days: [Date] {
        let start = calendar.dateInterval(of: .month, for: month)!.start
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: start)!.count
        let cells = ((offset + count + 6) / 7) * 7
        return (0..<cells).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: start) }
    }
    private var visibleDays: [Date] {
        guard compact && !showsMonth else { return days }
        let selected = CronaCalendarDate.date(from: day.selectedDate) ?? month
        let start = calendar.dateInterval(of: .weekOfYear, for: selected)?.start ?? selected
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var dateKey: String { CronaCalendarDate.string(from: month) }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Button(month.formatted(.dateTime.month(.wide).year())) { showsMonth.toggle() }.font(.subheadline.bold()).buttonStyle(.plain)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(dateKey.prefix(7) >= today.prefix(7))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(0..<7) { index in
                    Text(calendar.veryShortWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(visibleDays, id: \.self) { date in
                    let key = CronaCalendarDate.string(from: date)
                    let score = stats.cachedSnapshot(for: key)?.focusScore?.score
                    let selected = key == day.selectedDate
                    Button { day.select(key) } label: {
                        VStack(spacing: 3) {
                            HStack(spacing: 1) {
                                Text("\(calendar.component(.day, from: date))").font(.caption2.bold())
                                if settings.isHistoricalAwayDate(key) { Image(systemName: "figure.walk").font(.system(size: 8)) }
                            }
                            ZStack {
                                Circle().stroke(.secondary.opacity(0.15), lineWidth: 3)
                                if let score {
                                    Circle().trim(from: 0, to: CGFloat(score) / 100)
                                        .stroke(score >= 70 ? PopupVisualTheme.semantic(.success) : PopupVisualTheme.semantic(.focus), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    Text("\(score)").font(.system(size: 8, weight: .semibold))
                                }
                            }.frame(width: 22, height: 22)
                        }.frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(selected ? PopupVisualTheme.selectedControlBackground : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(key == today ? PopupVisualTheme.semantic(.focus) : .clear))
                            .opacity(calendar.isDate(date, equalTo: month, toGranularity: .month) ? 1 : 0.35)
                    }.buttonStyle(.plain).disabled(key > today)
                        .accessibilityLabel("\(key), score \(score.map(String.init) ?? "unavailable")")
                }
            }
        }
        .onAppear { month = CronaCalendarDate.date(from: day.selectedDate) ?? Date() }
        .onChange(of: day.selectedDate) { _, value in month = CronaCalendarDate.date(from: value) ?? month }
        .task(id: dateKey + today) {
            await stats.prefetchCalendarDates(days.map { CronaCalendarDate.string(from: $0) }.filter { $0 <= today })
        }
    }
    private func shift(_ count: Int) { month = calendar.date(byAdding: .month, value: count, to: month) ?? month }
}
