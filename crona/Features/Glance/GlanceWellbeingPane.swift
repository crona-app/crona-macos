import SwiftUI

struct GlanceWellbeingPane: View {
    let state: CompanionAppState
    let isToday: Bool
    let stats: PopoverStatsService
    @Binding var showsCheckIn: Bool
    @StateObject private var wellbeing: WellbeingService

    init(state: CompanionAppState, day: PopoverDayModel, stats: PopoverStatsService, showsCheckIn: Binding<Bool>) {
        self.state = state
        self.stats = stats
        _showsCheckIn = showsCheckIn
        isToday = day.isToday
        _wellbeing = StateObject(wrappedValue: WellbeingService(
            daemonConnection: state.daemonConnection, selectedDate: day.selectedDate
        ))
    }

    var body: some View {
        HStack(spacing: 12) {
            if let entry = wellbeing.snapshot.checkIn {
                Text("Mood \(entry.mood)/5 · Energy \(entry.energy)/5")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if wellbeing.snapshot.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text(wellbeing.snapshot.lastErrorDescription == nil ? "No check-in yet" : "Check-in unavailable")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(wellbeing.snapshot.checkIn == nil ? "Check In" : "Edit Check-In") {
                showsCheckIn = true
            }
            .buttonStyle(GlanceButtonStyle())
            .disabled(wellbeing.snapshot.isLoading)
            .fixedSize()
            .popover(isPresented: $showsCheckIn) {
                ScrollView {
                    WellbeingTabView(appState: state, service: wellbeing, embeddedDayIsToday: isToday, stats: stats)
                        .padding(20)
                }
                .frame(width: 460, height: 500)
            }
        }
        .task { await wellbeing.refresh() }
        .onDisappear { showsCheckIn = false }
    }
}
