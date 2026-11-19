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
            let visible = preferences.preferences.glance.normalizedOrder.filter { preferences.preferences.glance.visible($0) }
            let main = visible.filter { $0 == .issues || $0 == .habits }
            let side = visible.filter { $0 != .issues && $0 != .habits }
            if state.hasActiveFocusSession {
                GlanceSessionRowLayout(sideWidth: GlanceLayoutMetrics.sideWidth(geometry.size.width),
                    availableHeight: geometry.size.height) {
                    GlanceActiveSessionView(state: state)
                    if geometry.size.width >= 1000 && geometry.size.height >= 600
                        && (preferences.preferences.glance.visible(.calendar) || preferences.preferences.glance.visible(.summary)) {
                        VStack(spacing: 20) {
                            if preferences.preferences.glance.visible(.calendar) { calendar(compact: geometry.size.height < 820) }
                            if preferences.preferences.glance.visible(.summary) { summary }
                        }.frame(width: GlanceLayoutMetrics.sideWidth(geometry.size.width))
                    }
                }
            } else if visible.isEmpty {
                VStack(spacing: 16) {
                    Text("Choose widgets to make Glance yours.")
                    Button("Customize Glance") { model.showsCustomization = true }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if geometry.size.width >= 800 {
                        HStack(alignment: .top, spacing: 20) {
                            if !main.isEmpty { column(main, height: geometry.size.height) }
                            if !side.isEmpty {
                                column(side, height: geometry.size.height)
                                    .frame(maxWidth: main.isEmpty ? .infinity : GlanceLayoutMetrics.sideWidth(geometry.size.width))
                            }
                        }
                    } else { column(main + side, height: geometry.size.height) }
                }
            }
        }
    }

    private func column(_ widgets: [GlanceWidget], height: CGFloat) -> some View {
        VStack(spacing: 20) {
            ForEach(widgets) { widget in
                switch widget {
                case .issues: issuePane.frame(height: GlanceLayoutMetrics.height(.issues, availableHeight: height))
                case .habits: habitPane.frame(height: GlanceLayoutMetrics.height(.habits, availableHeight: height))
                case .calendar: calendar(compact: height < 820)
                case .selection: preview.frame(height: GlanceLayoutMetrics.height(.selection, availableHeight: height))
                case .summary: summary
                }
            }
        }.frame(maxWidth: .infinity)
    }

    private var issuePane: some View {
        pane("", flexible: true) {
            HStack(spacing: 8) {
                Text("Issues").font(.headline)
                Spacer()
                TagFilterMenu(pane: .issues, tagsModel: tags)
            }
            DailySectionPicker(dailyIssues: issues)
            if issues.isLoading { ProgressView().controlSize(.small) }
            if let error = issues.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(issues.sections.issues(in: issues.section)) { issue in
                        FocusIssueRow(appState: state, issue: issue,
                            isInbox: issues.section == .inbox,
                            onDetails: { if preferences.preferences.glance.visible(.selection) { model.previewIssue = issue; model.selectedHabit = nil } else { state.openIssueDetails(issue); state.detailBrowser.open(issue: issue, section: issues.section) } },
                            beforeAction: { handoff {} }, actionsEnabled: day.isToday,
                            onStart: { model.prepare(issue) })
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(
                                model.previewIssue?.id == issue.id ? PopupVisualTheme.semantic(.focus).opacity(0.6) : .clear))
                    }
                    if issues.sections.issues(in: issues.section).isEmpty { Text("No issues in this section").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100) }
                }
            }
        }
    }

    private var habitPane: some View {
        pane("", flexible: true) {
            HStack {
                Text("Habits · \(habits.snapshot.items.count)").font(.headline)
                Spacer()
                TagFilterMenu(pane: .habits, tagsModel: tags)
            }
            if let error = habits.snapshot.lastRefreshError { Text(error).font(.caption).foregroundStyle(.red) }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(habits.snapshot.date == day.selectedDate ? habits.snapshot.filtered(by: tags.filter(for: .habits), known: tags.knownNames).items.filter { !preferences.preferences.glance.unfinishedHabits || (!$0.completed && $0.status != "failed") } : []) { habit in
                        habitRow(habit)
                    }
                    if habits.snapshot.items.isEmpty { Text("No habits due").foregroundStyle(.secondary) }
                }
            }
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
    }

    private func beginLog(_ habit: HabitRowModel) {
        let minutes: Int = habit.targetMinutes ?? 1
        logSeconds = max(60, minutes * 60)
        loggingHabitID = habit.id
    }

    private func calendar(compact: Bool) -> some View {
        pane("Calendar") {
            GlanceCalendarPane(day: day, stats: stats,
                today: state.daemonConnection.currentDate.isEmpty ? DailyFocusService.todayString() : state.daemonConnection.currentDate,
                settings: state.coreSettingsService.settings, compact: compact)
        }
    }

    private var preview: some View {
        pane("Selection", flexible: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) { previewContent }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !day.isToday { Button("Return to Today for actions") { day.showToday() }.buttonStyle(GlanceButtonStyle()) }
        }
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
                Button { model.prepare(issue) } label: { Label("Focus on this issue", systemImage: "play.fill") }
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
        } else { Text("Select an issue or habit to see its details.").foregroundStyle(.secondary) }
    }

    private var summary: some View {
        pane("Day Summary") {
            if stats.snapshot.date == day.selectedDate, let score = stats.snapshot.focusScore, let metrics = stats.snapshot.todayMetrics {
                DailyStatsSummaryView(score: score, metrics: metrics, message: stats.snapshot.scoreMessage, highRiskCount: nil)
            } else if stats.snapshot.isLoading { ProgressView() }
            else { Text("No summary available").foregroundStyle(.secondary) }
        }
    }

    private func complete(_ habit: HabitRowModel) {
        if habit.targetMinutes != nil { handoff { state.openHabitDetails(habit) } }
        else { Task { await habits.complete(habit) } }
    }

    private func handoff(_ action: () -> Void) {
        // Shared drafts are hosted over Glance.
        action()
    }

    private func pane<Content: View>(_ title: String, flexible: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty { Text(title).font(.headline) }
            content()
        }.padding(18)
            .frame(maxWidth: .infinity, maxHeight: flexible ? .infinity : nil, alignment: .topLeading)
            .modifier(GlancePaneSurface())
    }
}

private struct GlancePaneSurface: ViewModifier {
    @ObservedObject private var glass = SystemGlassSettings.shared
    @ViewBuilder func body(content: Content) -> some View {
        if glass.reduceTransparency {
            content.background(PopupVisualTheme.popoverBackground, in: RoundedRectangle(cornerRadius: 22))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
    }
}
