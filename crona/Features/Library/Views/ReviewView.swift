import Charts
import SwiftUI

struct ReviewView: View {
    let appState: CompanionAppState
    @ObservedObject private var model: ReviewModel
    @ObservedObject private var settings: CoreSettingsService

    init(appState: CompanionAppState) {
        self.appState = appState
        model = appState.review
        settings = appState.coreSettingsService
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(display(model.range.start)) – \(display(model.range.end))").font(.title2.bold())
                    Text("Compared with \(display(model.range.previousStart)) – \(display(model.range.previousEnd))")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("All repositories and streams").font(.caption).foregroundStyle(.secondary)
                }
                workSection
                wellbeingSection
                planSection
                estimateSection
            }.padding(24).frame(maxWidth: 1100, alignment: .leading)
        }
        .toolbar {
            ToolbarItem {
                Picker("Period", selection: $model.period) {
                    ForEach(ReviewPeriod.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 150)
            }
            ToolbarItemGroup {
                Button {
                    model.shift(-1)
                } label: {
                    Label("Previous period", systemImage: "chevron.left")
                }
                Button(model.period == .week ? "This week" : "This month") {
                    model.anchor = model.today
                }
                .disabled(!model.canGoNext)
                .help(model.period == .week ? "Return to this week" : "Return to this month")
                Button {
                    model.shift(1)
                } label: {
                    Label("Next period", systemImage: "chevron.right")
                }
                .disabled(!model.canGoNext)
            }
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            if model.isLoading {
                ToolbarItem { ProgressView().controlSize(.small) }
            }
        }
        .onChange(of: model.range) { _, _ in model.invalidate() }
        .onAppear { model.setVisible(true) }
        .onDisappear { model.setVisible(false) }
        .onChange(of: settings.settings) { _, _ in model.invalidate() }
    }

    private var workSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Work").font(.title3.bold())
            if model.errors["Work"] == nil {
                HStack(spacing: 30) {
                    metric("Worked", duration(model.totalWork))
                    metric("Daily average", duration(model.averageWork))
                    metric("Sessions", String(model.totalSessions))
                }
                Text("Daily average includes every elapsed calendar day in this period.").font(.caption)
                    .foregroundStyle(.secondary)
                Chart {
                    ForEach(model.range.dates, id: \.self) { date in
                        BarMark(x: .value("Date", date), y: .value("Hours", Double(worked(date)) / 3600))
                            .foregroundStyle(
                                model.isAway(date) ? Color.green.opacity(0.5) : Color.accentColor.opacity(0.75))
                    }
                    ForEach(model.range.dates.filter { model.isAway($0) }, id: \.self) { date in
                        RuleMark(x: .value("Away day", date)).foregroundStyle(.green.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .reviewChartHover(dates: model.range.dates) { date in
                    let seconds = worked(date)
                    let sessions = model.metrics.first { $0.date == date }?.sessionCount ?? 0
                    return ReviewChartReadout(
                        date: display(date), isAway: model.isAway(date),
                        values: [
                            .init(label: "Worked", text: duration(seconds), plotValue: Double(seconds) / 3600),
                            .init(label: "Sessions", text: String(sessions), plotValue: nil),
                        ])
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 7)) { value in
                        AxisValueLabel { if let date = value.as(String.self) { Text(String(date.suffix(5))) } }
                    }
                }
                .frame(height: 175)
                Text("Hover over a graph to see its values. Green marks recorded away days.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            error("Work")
            if !model.scores.isEmpty {
                Chart(model.scores.filter(\.hasData)) { score in
                    LineMark(x: .value("Date", score.date), y: .value("Focus", score.score))
                    PointMark(x: .value("Date", score.date), y: .value("Focus", score.score))
                }
                .chartYScale(domain: 0...100)
                .reviewChartHover(dates: model.range.dates) { date in
                    let score = model.scores.first { $0.date == date && $0.hasData }?.score
                    return ReviewChartReadout(
                        date: display(date), isAway: model.isAway(date),
                        values: [
                            .init(
                                label: "Focus", text: score.map { "\($0)/100" } ?? "Not recorded",
                                plotValue: score.map(Double.init))
                        ])
                }
                .chartXAxis(.hidden).frame(height: 110)
                Text("Focus score · 0–100").font(.caption).foregroundStyle(.secondary)
            }
            error("Focus")
        }
    }

    private var wellbeingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Wellbeing").font(.title3.bold())
            if model.checkIns.isEmpty && !model.isLoading && model.errors["Wellbeing"] == nil {
                Text("No check-ins recorded in this period.").foregroundStyle(.secondary)
            } else if !model.checkIns.isEmpty {
                Chart(model.checkIns.sorted { $0.date < $1.date }, id: \.date) { entry in
                    LineMark(x: .value("Date", entry.date), y: .value("Rating", entry.mood))
                        .foregroundStyle(by: .value("Measure", "Mood"))
                    PointMark(x: .value("Date", entry.date), y: .value("Rating", entry.mood))
                        .foregroundStyle(by: .value("Measure", "Mood"))
                    LineMark(x: .value("Date", entry.date), y: .value("Rating", entry.energy))
                        .foregroundStyle(by: .value("Measure", "Energy"))
                    PointMark(x: .value("Date", entry.date), y: .value("Rating", entry.energy))
                        .foregroundStyle(by: .value("Measure", "Energy"))
                }
                .chartYScale(domain: 1...5).chartXAxis(.hidden)
                .reviewChartHover(dates: model.range.dates) { date in
                    let entry = model.checkIns.first { $0.date == date }
                    return ReviewChartReadout(
                        date: display(date), isAway: model.isAway(date),
                        values: [
                            .init(
                                label: "Mood", text: entry.map { "\($0.mood)/5" } ?? "Not recorded",
                                plotValue: entry.map { Double($0.mood) }),
                            .init(
                                label: "Energy", text: entry.map { "\($0.energy)/5" } ?? "Not recorded",
                                plotValue: entry.map { Double($0.energy) }),
                        ])
                }.frame(height: 150)
                Chart(model.checkIns.filter { $0.sleepHours != nil }.sorted { $0.date < $1.date }, id: \.date) {
                    entry in
                    BarMark(x: .value("Date", entry.date), y: .value("Hours asleep", entry.sleepHours ?? 0))
                        .foregroundStyle(.indigo.opacity(0.6))
                }
                .chartXAxis(.hidden)
                .reviewChartHover(dates: model.range.dates) { date in
                    let hours = model.checkIns.first { $0.date == date }?.sleepHours
                    return ReviewChartReadout(
                        date: display(date), isAway: model.isAway(date),
                        values: [
                            .init(
                                label: "Sleep",
                                text: hours.map { duration(Int(($0 * 3600).rounded())) } ?? "Not recorded",
                                plotValue: hours)
                        ])
                }.frame(height: 110)
                Text("Sleep · hours. Unrecorded wellbeing values are omitted.").font(.caption).foregroundStyle(
                    .secondary)
            }
            error("Wellbeing")
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Plan outcomes").font(.title3.bold())
            if let plan = model.plan {
                if plan.plannedCount == 0 {
                    Text("No committed plan entries in this period.").foregroundStyle(.secondary)
                } else {
                    Text(
                        "\(plan.completedCount)/\(plan.plannedCount) completed · \(String(format: "%.0f", (plan.completionRate ?? 0) * 100))%"
                    )
                    .font(.headline)
                    Text(
                        "\(plan.failedCount) failed · \(plan.missedCount) missed their planned day · \(plan.abandonedCount) abandoned"
                    )
                    Text("\(plan.carryOverCount) carried from an earlier plan")
                    Text("\(plan.fullyCompletedDays)/\(plan.plannedDays) planned days completed in full")
                    if let delta = model.completionDelta {
                        Text(String(format: "Completion %+.0f percentage points vs previous period", delta))
                    } else if model.previousPlan?.plannedCount == 0 {
                        Text("No committed entries in the comparison period.").foregroundStyle(.secondary)
                    }
                }
                Text("Counts are plan entries, not unique issues; carryovers can appear on multiple days.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            error("Plan")
            error("Comparison")
        }
    }

    private var estimateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Estimates").font(.title3.bold())
            if let estimates = model.estimates {
                if estimates.totalEstimateMinutes <= 0 {
                    Text("No estimates recorded for this period.").foregroundStyle(.secondary)
                } else {
                    Text(
                        "Estimated \(duration(estimates.totalEstimateMinutes * 60)) · tracked \(duration(estimates.totalActualSeconds))"
                    )
                    Text(
                        estimates.deltaSeconds == 0
                            ? "Tracked time matches the total estimate"
                            : "Tracked time \(duration(abs(estimates.deltaSeconds))) \(estimates.deltaSeconds > 0 ? "above" : "below") the total estimate"
                    )
                    if estimates.estimatedItems > 0 {
                        Text("\(estimates.estimatedItems) compared items · \(estimates.biasDescription)")
                        Text("Average gap \(duration(Int(abs(estimates.averageDeltaMinutes) * 60))) per compared item")
                    } else {
                        Text("No estimated items have tracked time yet; accuracy is unavailable.")
                    }
                }
                Text("Tracked time is time spent, not completion progress.").font(.caption).foregroundStyle(.secondary)
            }
            error("Estimates")
        }
    }

    @ViewBuilder private func error(_ section: String) -> some View {
        if let message = model.errors[section] {
            LibraryErrorView(message: "\(section): \(message)") { Task { await model.refresh(section: section) } }
        }
    }
    private func worked(_ date: String) -> Int { model.metrics.first { $0.date == date }?.workedSeconds ?? 0 }
    private func duration(_ seconds: Int) -> String { MenuBarTextFormatter.formatCompactDuration(seconds: seconds) }
    private func display(_ date: String) -> String { formattedPopoverDate(date, appState: appState) }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.monospacedDigit())
        }
    }
}
