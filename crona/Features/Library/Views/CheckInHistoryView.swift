import SwiftUI

struct CheckInHistoryView: View {
    let appState: CompanionAppState
    @ObservedObject private var model: CheckInHistoryModel
    @ObservedObject private var connection: DaemonConnectionService
    @ObservedObject private var settings: CoreSettingsService
    @State private var editing: CronaDailyCheckIn?
    @State private var deleting: CronaDailyCheckIn?

    init(appState: CompanionAppState) {
        self.appState = appState
        model = appState.checkInHistory
        connection = appState.daemonConnection
        settings = appState.coreSettingsService
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.error {
                LibraryErrorView(message: error) { Task { await model.refresh() } }
            }
            HSplitView {
                List(selection: $model.selectedDate) {
                    ForEach(model.filtered, id: \.date) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(formattedPopoverDate(entry.date, appState: appState)).fontWeight(.medium)
                                Spacer()
                                Text(LibraryDates.clock(entry.createdAt, timezone: connection.timezone) ?? "")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("Mood \(entry.mood)/5 · Energy \(entry.energy)/5")
                                .font(.caption).foregroundStyle(.secondary)
                            if let notes = entry.notes, !notes.isEmpty {
                                Text(notes).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4).tag(entry.date)
                    }
                }
                .frame(minWidth: 230, idealWidth: 280, maxWidth: 360)
                .overlay {
                    if model.filtered.isEmpty {
                        ContentUnavailableView(
                            model.isLoading ? "Loading check-ins" : "No check-ins", systemImage: "heart.text.square",
                            description: Text(
                                model.search.isEmpty ? "Create a check-in from Wellbeing." : "Try another search."))
                    }
                }
                if let entry = model.selected {
                    ScrollView {
                        CheckInRecordView(entry: entry, appState: appState)
                            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minWidth: 290)
                } else {
                    ContentUnavailableView("Select a check-in", systemImage: "heart.text.square")
                        .frame(maxWidth: .infinity)
                }
            }
            if settings.todayIsAway {
                Text("History is read-only during protected rest.").font(.caption).foregroundStyle(.secondary).padding(
                    8)
            }
        }
        .searchable(text: $model.search, prompt: "Search dates, ratings, or notes")
        .toolbar {
            ToolbarItemGroup {
                if model.isLoading { ProgressView().controlSize(.small) }
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button("Edit") { editing = model.selected }.disabled(model.selected == nil || !model.mutationsAllowed)
                Button {
                    deleting = model.selected
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(model.selected == nil || !model.mutationsAllowed)
            }
        }
        .sheet(item: $editing) { entry in HistoryCheckInEditor(appState: appState, entry: entry) }
        .confirmationDialog(
            "Delete check-in for \(deleting?.date ?? "")?",
            isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }
            ), titleVisibility: .visible
        ) {
            if let entry = deleting {
                Button("Delete Check-in", role: .destructive) { Task { await model.delete(date: entry.date) } }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("This removes the recorded ratings and notes for this date.")
        }
        .onChange(of: model.search) { _, _ in model.reconcileSelection() }
        .onAppear { model.setVisible(true) }
        .onDisappear { model.setVisible(false) }
    }
}

extension CronaDailyCheckIn: Identifiable { var id: String { date } }

struct CheckInRecordView: View {
    let entry: CronaDailyCheckIn
    @ObservedObject var appState: CompanionAppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(formattedPopoverDate(entry.date, appState: appState)).font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                row("Mood", "\(entry.mood)/5")
                row("Energy", "\(entry.energy)/5")
                row("Sleep", entry.sleepHours.map { String(format: "%.2g hours", $0) } ?? "Not recorded")
                row("Sleep score", entry.sleepScore.map { "\($0)/100" } ?? "Not recorded")
                row("Screen time", entry.screenTimeMinutes.map(MenuBarTextFormatter.formatMinutes) ?? "Not recorded")
            }
            if let notes = entry.notes, !notes.isEmpty {
                Divider()
                Text("Notes").font(.headline)
                Text(notes).textSelection(.enabled)
            }
            CheckInTimestampsView(
                entry: entry, timezone: appState.daemonConnection.timezone,
                settings: appState.coreSettingsService.settings)
        }
    }
    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

private struct HistoryCheckInEditor: View {
    let appState: CompanionAppState
    let entry: CronaDailyCheckIn
    @StateObject private var service: WellbeingService
    @Environment(\.dismiss) private var dismiss

    init(appState: CompanionAppState, entry: CronaDailyCheckIn) {
        self.appState = appState
        self.entry = entry
        let service = WellbeingService(daemonConnection: appState.daemonConnection)
        service.selectedDate = entry.date
        _service = StateObject(wrappedValue: service)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Check-in").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            ScrollView {
                WellbeingTabView(
                    appState: appState, service: service, historyDate: entry.date,
                    historyModel: appState.checkInHistory, onSaved: { dismiss() }
                )
                .padding(20)
            }
        }.frame(width: 430, height: 650)
    }
}
