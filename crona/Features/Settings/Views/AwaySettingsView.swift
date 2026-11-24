import SwiftUI

struct AwaySettingsView: View {
    @ObservedObject private var settingsService: CoreSettingsService
    @ObservedObject private var connection: DaemonConnectionService
    @Environment(\.locale) private var locale
    @State private var isAddingDate = false
    @State private var selectedDate: Date?

    init(appState: CompanionAppState) {
        _settingsService = ObservedObject(wrappedValue: appState.coreSettingsService)
        _connection = ObservedObject(wrappedValue: appState.daemonConnection)
    }

    private var settings: CronaCoreSettings { settingsService.settings }

    private var today: String {
        connection.currentDate.isEmpty ? DailyFocusService.todayString() : connection.currentDate
    }

    private var earliestDate: Date {
        weekdayCalendar.startOfDay(for: CronaCalendarDate.date(from: today) ?? Date())
    }

    private var weekdayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.firstWeekday = settings.weekStart == "sunday" ? 1 : (settings.weekStart == "saturday" ? 7 : 2)
        return calendar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
            awayTodayCard
            recurringDaysCard
            scheduledDatesCard

            if let error = settingsService.lastErrorDescription, !isAddingDate {
                settingsFootnote(error)
                    .foregroundStyle(.red)
            }
        }
    }

    private var awayTodayCard: some View {
        SettingsCard("Away Mode") {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk.circle.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Away Today")
                        .font(.headline)
                    Text("Protect the current Crona day from focus work.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Away Today", isOn: Binding(
                    get: { settings.awayModeEnabled },
                    set: { enabled in Task { await settingsService.setAwayMode(enabled) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(settingsService.isSaving)
            }
            .padding(.vertical, 8)
        }
    }

    private var recurringDaysCard: some View {
        SettingsCard("Recurring Days") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose which weekdays are always away.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { offset in
                        let weekday = (weekdayCalendar.firstWeekday - 1 + offset) % 7
                        weekdayButton(weekday)
                    }
                }
                .disabled(settingsService.isSaving)
            }
            .padding(.vertical, 8)
        }
    }

    private func weekdayButton(_ weekday: Int) -> some View {
        let isSelected = settings.restWeekdays.contains(weekday)
        let name = weekdayCalendar.weekdaySymbols[weekday]

        return Button {
            var weekdays = Set(settings.restWeekdays)
            if isSelected {
                weekdays.remove(weekday)
            } else {
                weekdays.insert(weekday)
            }
            Task {
                await settingsService.patch(
                    key: "restWeekdays",
                    value: .array(weekdays.sorted().map { .number(Double($0)) })
                )
            }
        } label: {
            Text(weekdayCalendar.shortWeekdaySymbols[weekday])
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.horizontal, 4)
                .background(
                    isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(name)
    }

    private var scheduledDatesCard: some View {
        let dates = settings.scheduledAwayDates(from: today)

        return SettingsCard("Scheduled Dates") {
            HStack(spacing: 12) {
                Text(dates.isEmpty ? "No scheduled away dates." : "One-off days away from focus work.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    selectedDate = nil
                    isAddingDate = true
                } label: {
                    Label("Add Date", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(settingsService.isSaving)
            }
            .padding(.vertical, 8)
            .popover(
                isPresented: $isAddingDate,
                attachmentAnchor: .point(UnitPoint(x: 0.75, y: 1)),
                arrowEdge: .top
            ) {
                datePicker
            }

            ForEach(dates, id: \.self) { date in
                Divider()
                scheduledDateRow(date)
            }
        }
    }

    private func scheduledDateRow(_ date: String) -> some View {
        let displayDate = CronaDateDisplayFormatter.string(fromISODate: date, settings: settings)

        return HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(displayDate)
                .font(.subheadline.weight(.medium))
            Spacer()
            Button {
                saveDates(settings.restSpecificDates.filter { $0 != date })
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Remove \(displayDate)")
            .help("Remove scheduled date")
            .disabled(settingsService.isSaving)
        }
        .padding(.vertical, 8)
    }

    private var datePicker: some View {
        let date = selectedDate.map { CronaCalendarDate.string(from: $0) }
        let alreadyScheduled = date.map { settings.restSpecificDates.contains($0) } ?? false

        return VStack(alignment: .leading, spacing: 12) {
            Text("Schedule an Away Day")
                .font(.headline)

            AwayCalendarPicker(
                selection: $selectedDate,
                earliestDate: earliestDate,
                scheduledDates: Set(settings.restSpecificDates),
                calendar: weekdayCalendar
            )

            if alreadyScheduled {
                Text("This date is already scheduled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = settingsService.lastErrorDescription {
                settingsFootnote(error)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { isAddingDate = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add Date") {
                    guard let date, date >= today else { return }
                    saveDates(settings.restSpecificDates + [date], addedDate: date)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(alreadyScheduled || (date ?? "") < today || settingsService.isSaving)
            }
        }
        .frame(width: 304)
        .padding(16)
    }

    private func saveDates(_ dates: [String], addedDate: String? = nil) {
        Task {
            guard !settingsService.isSaving else { return }
            await settingsService.patch(
                key: "restSpecificDates",
                value: .array(dates.sorted().map { .string($0) })
            )
            if let addedDate, settings.restSpecificDates.contains(addedDate) {
                isAddingDate = false
            }
        }
    }
}

extension CronaCoreSettings {
    func scheduledAwayDates(from today: String) -> [String] {
        Set(restSpecificDates.filter { $0 >= today }).sorted()
    }
}
