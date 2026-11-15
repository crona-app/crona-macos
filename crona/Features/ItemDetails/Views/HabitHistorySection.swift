import SwiftUI

struct HabitHistorySection: View {
    let habit: HabitRowModel
    @ObservedObject var model: HabitHistoryModel
    @ObservedObject var day: PopoverDayModel

    var body: some View {
        let outcomes = model.outcomes(habitID: habit.id, through: day.selectedDate)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                progress
                ForEach([7, 30], id: \.self) { days in
                    HabitHitRateIndicator(
                        rate: HabitHistoryModel.hitRate(outcomes, through: day.selectedDate, days: days),
                        days: days
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Hit rate uses recorded outcomes; missing days are excluded.").font(.caption2).foregroundStyle(
                .secondary)
            Text("Last 14 days").font(.subheadline.bold())
            HStack(spacing: 4) {
                ForEach((0..<14).reversed(), id: \.self) { offset in
                    let date = LibraryDates.adding(-offset, to: day.selectedDate)
                    let status = outcomes.first { $0.date == date }?.status ?? ""
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            status == "completed"
                                ? Color.green : (status == "failed" ? Color.red : Color.secondary.opacity(0.15))
                        )
                        .frame(height: 14)
                        .help("\(date): \(status.isEmpty ? "No outcome" : status)")
                        .accessibilityLabel("\(date): \(status.isEmpty ? "No outcome" : status)")
                }
            }
            if model.isLoading { ProgressView().controlSize(.small) }
            if let error = model.error {
                LibraryErrorView(message: error) { Task { await model.refresh() } }
            }
            if outcomes.isEmpty && !model.isLoading && model.error == nil {
                Text("No outcomes recorded.").foregroundStyle(.secondary).font(.caption)
            }
            ForEach(Array(outcomes.prefix(7))) { outcome in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: outcome.status == "completed" ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(outcome.status == "completed" ? .green : .secondary)
                        Text(outcome.date).fontWeight(.medium)
                        Spacer()
                        Text(outcome.status.isEmpty ? "Logged" : outcome.status.capitalized)
                    }
                    if outcome.minutes > 0 {
                        Text(MenuBarTextFormatter.formatMinutes(outcome.minutes)).foregroundStyle(.secondary)
                    }
                    ForEach(Array(outcome.notes.enumerated()), id: \.offset) { _, note in
                        Text(note).textSelection(.enabled)
                    }
                }.font(.caption).padding(.vertical, 4)
            }
        }
        .onAppear { model.setVisible(true) }
        .onDisappear { model.setVisible(false) }
    }

    private var progress: some View {
        VStack(spacing: 4) {
            VStack(spacing: 4) {
                if let target = habit.targetMinutes, target > 0 {
                    ProgressView(value: min(Double(habit.durationMinutes ?? 0) / Double(target), 1))
                        .frame(width: 70)
                    Text("\(habit.durationMinutes ?? 0)/\(target)m").font(.caption.monospacedDigit())
                } else {
                    Image(systemName: habit.completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(habit.completed ? .green : .secondary).font(.title3)
                }
            }
            .frame(height: 56)
            Text(day.isToday ? "Today" : day.selectedDate).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

private struct HabitHitRateIndicator: View {
    let rate: Double?
    let days: Int

    private var tint: Color {
        guard let rate else { return .secondary }
        if rate >= 0.8 { return PopupVisualTheme.semantic(.success) }
        if rate >= 0.5 { return PopupVisualTheme.semantic(.warning) }
        return PopupVisualTheme.semantic(.error)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.secondary.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(1, max(0, rate ?? 0)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let rate {
                    Text(rate, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.weight(.semibold)).monospacedDigit()
                } else {
                    Text("—").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(2)
            .frame(width: 56, height: 56)
            Text("Hit / \(days)d").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(days)-day hit rate")
        .accessibilityValue(rate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "No recorded outcomes")
    }
}
