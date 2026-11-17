import SwiftUI

struct WellbeingTabView: View {
    private enum SaveFeedback: Equatable {
        case success
        case error(String)
    }

    @ObservedObject var appState: CompanionAppState
    @ObservedObject private var popoverStatsService: PopoverStatsService
    @ObservedObject private var wellbeingService: WellbeingService
    private let historyDate: String?
    @ObservedObject private var historyModel: CheckInHistoryModel
    private let onSaved: () -> Void
    @State private var mood = 0
    @State private var energy = 0
    @State private var timing = WellbeingTimingDraft()
    @State private var notes = ""
    @State private var validationError: String?
    @State private var loadedEntry: CronaDailyCheckIn?
    @State private var baselineRequest: CronaDailyCheckInUpsertRequest?
    @State private var saveFeedback: SaveFeedback?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var suppressServiceError = false

    private let leadingRailWidth: CGFloat = 22
    private let leadingRailSpacing: CGFloat = 11
    private let textColumnWidth: CGFloat = 106

    init(appState: CompanionAppState, service: WellbeingService? = nil, historyDate: String? = nil,
         historyModel: CheckInHistoryModel? = nil, onSaved: @escaping () -> Void = {}) {
        self.appState = appState
        self.popoverStatsService = appState.popoverStatsService
        self.wellbeingService = service ?? appState.wellbeingService
        self.historyDate = historyDate
        self.historyModel = historyModel ?? appState.checkInHistory
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let historyDate {
                Text(formattedPopoverDate(historyDate, appState: appState)).font(.headline)
            } else {
                PopoverDayHeader(appState: appState, libraryDestination: .checkIns)
            }
            if let entry = wellbeingService.snapshot.checkIn {
                CheckInTimestampsView(entry: entry, timezone: appState.daemonConnection.timezone, settings: appState.coreSettingsService.settings)
            }
            ratingRow(
                title: "Mood",
                subtitle: isHistorical ? "How you felt that day" : "Your mood today",
                symbol: "face.smiling",
                value: $mood,
                tint: PopupVisualTheme.semantic(.mood)
            )
            ratingRow(
                title: "Energy",
                subtitle: isHistorical ? "Your energy that day" : "Your energy level",
                symbol: "bolt.fill",
                value: $energy,
                tint: PopupVisualTheme.semantic(.energy)
            )

            VStack(spacing: 0) {
                durationInput(
                    title: "Sleep duration",
                    subtitle: isHistorical ? "Time asleep the night before" : "Time asleep last night",
                    symbol: "moon.zzz.fill",
                    isIncluded: $timing.hasSleepDuration,
                    text: $timing.sleepDuration
                )
                Divider().padding(.leading, 42)
                scoreInput
                Divider().padding(.leading, 42)
                durationInput(
                    title: "Screen time",
                    subtitle: isHistorical ? "Total device time that day" : "Total device time today",
                    symbol: "display",
                    isIncluded: $timing.hasScreenTime,
                    text: $timing.screenDuration
                )
            }
            .background(cardBackground(stroke: PopupVisualTheme.border, cornerRadius: 14))

            VStack(alignment: .leading, spacing: 7) {
                Text("Notes")
                    .font(.subheadline.weight(.semibold))
                StableMultilineTextField(text: $notes, placeholder: "Anything else worth remembering? (optional)")
                    .frame(height: 64)
                    .popupInputSurface(cornerRadius: 12)
            }

            feedbackView

            Button(action: save) {
                if wellbeingService.snapshot.isSaving {
                    ProgressView().controlSize(.small)
                } else if saveFeedback == .success {
                    Label("Check-In Updated", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                } else {
                    Text(wellbeingService.snapshot.checkIn == nil ? "Save Check-In" : "Update Check-In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSave)
        }
        .fixedSize(horizontal: false, vertical: true)
        .task { await wellbeingService.refresh() }
        .onChange(of: wellbeingService.snapshot.checkIn) { _, entry in load(entry) }
        .onChange(of: wellbeingService.snapshot.date) { _, _ in load(wellbeingService.snapshot.checkIn) }
        .onChange(of: currentRequest) { _, _ in
            guard saveFeedback != nil else { return }
            feedbackDismissTask?.cancel()
            saveFeedback = nil
        }
        .onAppear { load(wellbeingService.snapshot.checkIn) }
        .onDisappear { feedbackDismissTask?.cancel() }
    }

    private var isHistorical: Bool { historyDate != nil || !appState.day.isToday }

    private var canSave: Bool {
        (historyDate == nil || historyModel.mutationsAllowed)
            && timing.validationError == nil
            && mood > 0
            && energy > 0
            && !wellbeingService.snapshot.isSaving
            && currentRequest != baselineRequest
    }

    @ViewBuilder
    private var feedbackView: some View {
        Group {
            switch saveFeedback {
            case .success:
                Label("Check-in updated", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(PopupVisualTheme.semantic(.success))
            case let .error(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(PopupVisualTheme.semantic(.error).opacity(0.9))
                    .lineLimit(2)
            case nil:
                if let error = timing.validationError ?? validationError
                    ?? (suppressServiceError ? nil : wellbeingService.snapshot.lastErrorDescription) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(PopupVisualTheme.semantic(.error).opacity(0.9))
                        .lineLimit(2)
                } else {
                    Color.clear
                }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        .contentTransition(.opacity)
    }


    private func ratingRow(
        title: String,
        subtitle: String,
        symbol: String,
        value: Binding<Int>,
        tint: Color
    ) -> some View {
        HStack(spacing: leadingRailSpacing) {
            Image(systemName: symbol)
                .frame(width: leadingRailWidth)
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.68))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PopupVisualTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: textColumnWidth, alignment: .leading)
            Spacer(minLength: 0)
            ForEach(1...5, id: \.self) { rating in
                Button { value.wrappedValue = rating } label: {
                    Text("\(rating)")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 30)
                        .background(Capsule().fill(value.wrappedValue == rating ? tint.opacity(0.82) : PopupVisualTheme.primaryText.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title) \(rating) of 5")
                .accessibilityAddTraits(value.wrappedValue == rating ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
    }

    private func durationInput(
        title: String,
        subtitle: String,
        symbol: String,
        isIncluded: Binding<Bool>,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.68))
                .frame(width: leadingRailWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(PopupVisualTheme.secondaryText)
            }
            Spacer(minLength: 8)
            if isIncluded.wrappedValue {
                DurationTextField(title: title, text: text, maximumMinutes: 1_440)
                clearButton { isIncluded.wrappedValue = false }
            } else {
                addButton { isIncluded.wrappedValue = true }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
    }

    private var scoreInput: some View {
        HStack(spacing: 11) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.68))
                .frame(width: leadingRailWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sleep score").font(.subheadline.weight(.semibold))
                Text("Recovery quality, from 0 to 100").font(.caption).foregroundStyle(PopupVisualTheme.secondaryText)
            }
            Spacer(minLength: 8)
            if timing.hasSleepScore {
                TextField("80", text: $timing.sleepScoreText)
                    .textFieldStyle(.plain)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .popupInputSurface(cornerRadius: 8)
                    .frame(width: 64)
                    .accessibilityLabel("Sleep score")
                    .help("Enter a score from 0 to 100")
                clearButton { timing.hasSleepScore = false }
            } else {
                addButton { timing.hasSleepScore = true }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
    }

    private func addButton(action: @escaping () -> Void) -> some View {
        Button("Add", action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func clearButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear value")
    }

    private func load(_ entry: CronaDailyCheckIn?) {
        guard loadedEntry != entry else { return }
        loadedEntry = entry
        suppressServiceError = false
        mood = entry?.mood ?? 0
        energy = entry?.energy ?? 0
        timing = WellbeingTimingDraft(entry: entry)
        notes = entry?.notes ?? ""
        baselineRequest = request(
            mood: mood,
            energy: energy,
            sleepHours: timing.sleepHours,
            sleepScore: timing.sleepScore,
            screenTimeMinutes: timing.screenTimeMinutes,
            notes: notes
        )
    }

    private func save() {
        guard timing.validationError == nil else { return }
        validationError = nil
        suppressServiceError = true
        feedbackDismissTask?.cancel()
        saveFeedback = nil
        let request = currentRequest
        Task {
            let saved: Bool
            if let historyDate {
                saved = await historyModel.save(request, originalDate: historyDate)
            } else { saved = await wellbeingService.save(request) }
            if saved {
                baselineRequest = request
                showFeedback(.success)
                onSaved()
                await popoverStatsService.refresh()
                await popoverStatsService.refreshTodayMetrics()
            } else {
                showFeedback(.error(
                    (historyDate == nil ? wellbeingService.snapshot.lastErrorDescription : historyModel.error)
                        ?? "Couldn’t update the check-in. Try again."
                ))
            }
        }
    }

    private var currentRequest: CronaDailyCheckInUpsertRequest {
        request(
            mood: mood,
            energy: energy,
            sleepHours: timing.sleepHours,
            sleepScore: timing.sleepScore,
            screenTimeMinutes: timing.screenTimeMinutes,
            notes: notes
        )
    }

    private func request(
        mood: Int,
        energy: Int,
        sleepHours: Double?,
        sleepScore: Int?,
        screenTimeMinutes: Int?,
        notes: String
    ) -> CronaDailyCheckInUpsertRequest {
        CronaDailyCheckInUpsertRequest(
            date: historyDate ?? wellbeingService.snapshot.date.nilIfEmpty ?? DailyFocusService.todayString(),
            mood: mood,
            energy: energy,
            sleepHours: sleepHours,
            sleepScore: sleepScore,
            screenTimeMinutes: screenTimeMinutes,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    private func showFeedback(_ feedback: SaveFeedback) {
        feedbackDismissTask?.cancel()
        saveFeedback = feedback
        feedbackDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            saveFeedback = nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
