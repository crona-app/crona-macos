import SwiftUI

struct GlanceDayPanes: View {
    @ObservedObject var state: CompanionAppState
    @ObservedObject var model: GlanceModel
    @ObservedObject var day: PopoverDayModel
    @ObservedObject var issues: DailyIssuesModel
    @ObservedObject var habits: HabitsService
    @ObservedObject var stats: PopoverStatsService
    @ObservedObject private var preferences: PreferencesService
    @State private var loggingHabitID: Int64?
    @State private var logSeconds = 60
    @ObservedObject private var tags: TagsModel

    init(state: CompanionAppState, model: GlanceModel, day: PopoverDayModel, issues: DailyIssuesModel,
         habits: HabitsService, stats: PopoverStatsService) {
        preferences = state.preferences
        self.state = state
        self.model = model
        self.day = day
        self.issues = issues
        self.habits = habits
        self.stats = stats
        tags = state.tags
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = preferences.preferences.glance
            if layout.workWidgets.isEmpty && layout.overviewWidgets.isEmpty && !state.hasActiveFocusSession {
                VStack(spacing: 16) {
                    Button("Choose Panes") { model.showsCustomization = true }
                        .buttonStyle(GlanceButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if state.hasActiveFocusSession {
                            GlanceActiveSessionView(state: state)
                                .frame(height: min(520, max(320, geometry.size.height * 0.65)))
                        }
                        if !layout.overviewWidgets.isEmpty {
                            GlancePaneGridLayout(layout: layout.layout) {
                                ForEach(layout.overviewWidgets) { widget in
                                    overviewPane(widget)
                                }
                            }
                        }
                        if !state.hasActiveFocusSession && !layout.workWidgets.isEmpty {
                            GlancePaneGridLayout(layout: layout.layout) {
                                ForEach(layout.workWidgets) { widget in
                                    if widget == .issues { issuePane } else { habitPane }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    @ViewBuilder private func overviewPane(_ widget: GlanceWidget) -> some View {
        switch widget {
        case .calendar:
            pane("Calendar") {
                GlanceCalendarPane(day: day, stats: stats,
                    today: state.daemonConnection.currentDate.isEmpty ? DailyFocusService.todayString() : state.daemonConnection.currentDate,
                    settings: state.coreSettingsService.settings)
            }
        case .summary:
            pane("Day Summary") {
                if stats.snapshot.date == day.selectedDate,
                   let score = stats.snapshot.focusScore, let metrics = stats.snapshot.todayMetrics {
                    DailyStatsSummaryView(score: score, metrics: metrics,
                        message: stats.snapshot.scoreMessage, highRiskCount: nil, embedded: true)
                } else if stats.snapshot.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("No summary available").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        case .wellbeing:
            pane("Wellbeing") {
                GlanceWellbeingPane(state: state, day: day, stats: stats, showsCheckIn: $model.showsWellbeingCheckIn)
                    .id(day.selectedDate)
            }
        case .issues, .habits, .selection:
            EmptyView()
        }
    }

    private var issuePane: some View {
        pane("") {
            HStack(spacing: 8) {
                Text("Issues").font(.headline)
                Spacer()
                TagFilterMenu(pane: .issues, tagsModel: tags)
            }
            DailySectionPicker(dailyIssues: issues)
            if issues.isLoading { ProgressView().controlSize(.small) }
            if let error = issues.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
            let visibleIssues = issues.sections.issues(in: issues.section)
            workList(visibleIssues, emptyMessage: "No issues in this section") { issue in
                FocusIssueRow(appState: state, issue: issue,
                    isInbox: issues.section == .inbox,
                    onDetails: { if preferences.preferences.glance.visible(.selection) { model.previewIssue = issue; model.selectedHabit = nil } else { state.openIssueDetails(issue); state.detailBrowser.open(issue: issue, section: issues.section) } },
                    beforeAction: { handoff {} }, actionsEnabled: day.isToday,
                    onStart: { model.prepare(issue) })
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(
                        model.previewIssue?.id == issue.id ? PopupVisualTheme.semantic(.focus).opacity(0.6) : .clear))
                    .modifier(GlancePointerPopover(
                        isPresented: selectionPresentation { model.previewIssue?.id == issue.id }
                    ) { selectionInspector })
            }
        }
    }

    private var habitPane: some View {
        pane("") {
            HStack {
                Text("Habits · \(habits.snapshot.items.count)").font(.headline)
                Spacer()
                TagFilterMenu(pane: .habits, tagsModel: tags)
            }
            if let error = habits.snapshot.lastRefreshError { Text(error).font(.caption).foregroundStyle(.red) }
            let visibleHabits = habits.snapshot.date == day.selectedDate
                ? habits.snapshot.filtered(by: tags.filter(for: .habits), known: tags.knownNames).items.filter {
                    !preferences.preferences.glance.unfinishedHabits || (!$0.completed && $0.status != "failed")
                } : []
            workList(visibleHabits, emptyMessage: "No habits in this view", row: habitRow)
        }
    }

    @ViewBuilder private func workList<Item: Identifiable, Row: View>(
        _ items: [Item], emptyMessage: String, @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if items.isEmpty {
            Text(emptyMessage).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 16)
        } else if items.count > 7 {
            ScrollView {
                LazyVStack(spacing: 8) { ForEach(items, content: row) }
            }
            .frame(height: 470)
        } else {
            VStack(spacing: 8) { ForEach(items, content: row) }
        }
    }

    private func habitRow(_ habit: HabitRowModel) -> some View {
        HabitRow(tagsModel: tags, habit: habit,
                            isWorking: habits.actionInFlightHabitID == habit.id,
                            activeAction: habits.actionInFlightHabitID == habit.id ? habits.actionInFlightStatus : nil,
                            actionsDisabled: !day.isToday || habits.actionInFlightHabitID != nil,
                            isLogging: loggingHabitID == habit.id, logSeconds: $logSeconds,
                            onComplete: { Task { await habits.complete(habit) } },
                            onBeginLog: { beginLog(habit) },
                            onSubmitLog: {
                                Task { await habits.complete(habit, durationMinutes: max(1, logSeconds / 60)); loggingHabitID = nil }
                            }, onCancelLog: { loggingHabitID = nil },
                            onFail: { Task { await habits.fail(habit) } },
                            onClear: { Task { await habits.clearCompletion(habit) } },
                            openDetails: { if preferences.preferences.glance.visible(.selection) { model.selectedHabit = habit; model.previewIssue = nil } else { state.openHabitDetails(habit) } },
                            editHabit: { if day.isToday { handoff { state.habitEditor.presentEditor(for: habit) } } },
                            editTags: { if day.isToday { handoff { state.tagEditor.present(.habit(id: habit.id, name: habit.name), tags: habit.tags) } } },
                            deleteHabit: { if day.isToday { handoff { state.habitEditor.presentDelete(for: habit) } } },
                            isReadOnly: !day.isToday, selectsOnRowTap: true)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(
                model.selectedHabit?.id == habit.id ? PopupVisualTheme.semantic(.focus).opacity(0.6) : .clear))
            .modifier(GlancePointerPopover(
                isPresented: selectionPresentation { model.selectedHabit?.id == habit.id }
            ) { selectionInspector })
    }

    private func selectionPresentation(matches: @escaping () -> Bool) -> Binding<Bool> {
        Binding(
            get: { preferences.preferences.glance.visible(.selection) && matches() },
            set: { isPresented in
                // A dismissal from the previous row must leave the new selection intact.
                if !isPresented && matches() { model.clearSelection() }
            }
        )
    }

    private func beginLog(_ habit: HabitRowModel) {
        let minutes: Int = habit.targetMinutes ?? 1
        logSeconds = max(60, minutes * 60)
        loggingHabitID = habit.id
    }

    private var selectionInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Selection").font(.headline)
                Spacer()
                Button { model.clearSelection() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close selection")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) { previewContent }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            if !day.isToday {
                Button("Return to Today") { day.showToday() }.buttonStyle(GlanceButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @ViewBuilder private var previewContent: some View {
        if let issue = model.previewIssue {
            Text(issue.title).font(.title3.bold())
            Text("\(issue.repoName ?? "") / \(issue.streamName ?? "")").font(.caption).foregroundStyle(.secondary)
            Text(issue.description ?? "No description").textSelection(.enabled)
            if let notes = issue.notes, !notes.isEmpty { Text(notes).font(.caption) }
            Label(CronaIssueStatusPresentation.status(for: issue.status)?.title ?? issue.status, systemImage: CronaIssueStatusPresentation.icon(for: issue.status))
                .foregroundStyle(CronaIssueStatusPresentation.color(for: issue.status))
            Text("Worked " + MenuBarTextFormatter.formatMinutes(issue.workedSeconds / 60) +
                (issue.estimateMinutes.map { " of " + MenuBarTextFormatter.formatMinutes($0) } ?? ""))
                .font(.caption)
            TagChipsView(tags: issue.tags, tagsModel: tags)
            if day.isToday {
                Button {
                    model.clearSelection()
                    model.prepare(issue)
                } label: {
                    Label("Focus on this issue", systemImage: "play.fill")
                }
                    .buttonStyle(GlanceButtonStyle(prominent: true))
            }
        } else if let habit = model.selectedHabit {
            Text(habit.name).font(.title3.bold())
            Text(habit.description ?? "No description")
            if let notes = habit.notes, !notes.isEmpty { Text(notes).font(.caption) }
            Text("\(habit.repoName) / \(habit.streamName) · \(habit.status.isEmpty ? "Due" : habit.status.capitalized)").font(.caption).foregroundStyle(.secondary)
            if let target = habit.targetMinutes { Text("Target: " + MenuBarTextFormatter.formatMinutes(target)).font(.caption) }
            TagChipsView(tags: habit.tags, tagsModel: tags)
            if day.isToday && !habit.completed {
                Button { complete(habit) } label: {
                    Label(habit.targetMinutes == nil ? "Complete" : "Log duration…", systemImage: "checkmark")
                }
                .buttonStyle(GlanceButtonStyle(prominent: true))
                .disabled(habits.actionInFlightHabitID != nil)
            }
        }
    }

    private func complete(_ habit: HabitRowModel) {
        if habit.targetMinutes != nil {
            model.clearSelection()
            handoff { state.openHabitDetails(habit) }
        }
        else { Task { await habits.complete(habit) } }
    }

    private func handoff(_ action: () -> Void) {
        // Shared drafts are hosted over Glance.
        action()
    }

    private func pane<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty { Text(title).font(.headline) }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(GlancePaneSurface())
    }
}

private struct GlancePaneSurface: ViewModifier {
    @ObservedObject private var glass = SystemGlassSettings.shared

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        content
            .background {
                if glass.reduceTransparency {
                    shape.fill(PopupVisualTheme.popoverBackground)
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay { shape.strokeBorder(PopupVisualTheme.surfaceStroke, lineWidth: 1) }
    }
}
