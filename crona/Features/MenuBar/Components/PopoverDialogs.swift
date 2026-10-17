import AppKit
import SwiftUI

struct PlaceholderPanel: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.primaryText)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.62))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
        .padding(20)
        .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 18))
    }
}

struct EndSessionSheetView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var endSession: EndSessionModel

    @ViewBuilder var body: some View {
        if appState.timerService.snapshot.adhoc {
            AdhocAttributionView(appState: appState, endSession: endSession)
                .frame(width: 392)
                .background(SheetGlassBackground())
        } else {
            ZStack {
                SheetGlassBackground()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("End Session")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(PopupVisualTheme.primaryText)
                        Text("Describe the work you completed in this session.")
                            .font(.subheadline)
                            .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.66))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Session Summary (required)")
                            .font(.headline)
                            .foregroundStyle(PopupVisualTheme.primaryText)

                        StableMultilineTextField(
                            text: $endSession.commitMessage,
                            placeholder: "Describe what you completed",
                            isEnabled: !endSession.isSubmitting,
                            focusRequest: endSession.focusRequest
                        )
                        .frame(height: 104)
                        .popupInputSurface(cornerRadius: 12)

                        if let error = endSession.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(PopupVisualTheme.semantic(.error).opacity(0.9))
                        }
                    }

                    HStack {
                        Button("Cancel") {
                            endSession.cancel()
                        }
                        .keyboardShortcut(.cancelAction)
                        .disabled(endSession.isSubmitting)

                        Spacer()

                        Button {
                            endSession.confirm()
                        } label: {
                            if endSession.isSubmitting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(endSession.actionTitle)
                            }
                        }
                        .keyboardShortcut(.return, modifiers: [.command])
                        .buttonStyle(.borderedProminent)
                        .disabled(!endSession.canSubmit)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
                .frame(maxWidth: 384, alignment: .leading)
            }
            .frame(width: 360)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

}

struct MetricStripCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String

    var body: some View {
        HStack {
            Label {
                Text(title)
                    .foregroundStyle(PopupVisualTheme.primaryText)
                    .font(.headline)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(.black)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(tint))
            }
            Spacer()
            Text(value)
                .foregroundStyle(PopupVisualTheme.primaryText)
                .font(.headline)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 18))
    }
}

struct EndsAtRow: View {
    let date: Date

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.58))

            Text("Ends At")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.72))

            Spacer()

            Text(TimerEndTimeFormatter.string(from: date))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(PopupVisualTheme.primaryText)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 42)
        .background(cardBackground(stroke: PopupVisualTheme.border, cornerRadius: 16))
    }
}

struct ReverseProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let shape = Capsule()
            let clampedProgress = max(0, min(1, progress))

            ZStack(alignment: .trailing) {
                shape
                    .fill(PopupVisualTheme.primaryText.opacity(0.045))

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                PopupVisualTheme.primaryText.opacity(0.22),
                                PopupVisualTheme.primaryText.opacity(0.46),
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: geometry.size.width * clampedProgress)

                LinearGradient(
                    colors: [
                        PopupVisualTheme.primaryText.opacity(0.16),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(PopupVisualTheme.primaryText.opacity(0.09), lineWidth: 0.5)
            )
            .animation(SystemGlassSettings.shared.reduceMotion ? nil : .easeOut(duration: 0.24), value: clampedProgress)
        }
    }
}

struct IssueActionEditorView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var issueActions: IssueActionEditorModel
    @FocusState private var noteIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch issueActions.editor {
            case .status(let issue, let status):
                statusEditor(issue: issue, status: status)
            case .dueDate(let issue):
                dueDateEditor(issue: issue)
            case .manualSession(let issue):
                manualSessionEditor(issue: issue)
            case .delete(let issue):
                deleteIssueEditor(issue: issue)
            case nil:
                EmptyView()
            }
        }
        .padding(20)
        .frame(maxWidth: 410)
        .background(PopoverDialogBackground(cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear {
            if case .status = issueActions.editor {
                DispatchQueue.main.async {
                    noteIsFocused = true
                }
            }
        }
    }

    @ViewBuilder
    private func statusEditor(
        issue: DailyFocusIssue,
        status: CronaIssueStatus
    ) -> some View {
        editorHeader(
            title: status.title,
            subtitle: issue.title,
            systemImage: status.systemImage
        )

        TextField(
            status.notePrompt ?? "Note",
            text: $issueActions.note,
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .lineLimit(3...5)
        .focused($noteIsFocused)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PopupVisualTheme.surfaceFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    noteIsFocused
                        ? Color.accentColor.opacity(0.72)
                        : PopupVisualTheme.surfaceStroke,
                    lineWidth: noteIsFocused ? 1.2 : 0.7
                )
        )

        editorError
        editorActions(
            submitTitle: "Change Status",
            submitDisabled: status.requiresNote
                && issueActions.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    @ViewBuilder
    private func dueDateEditor(issue: DailyFocusIssue) -> some View {
        editorHeader(
            title: "Choose Due Date",
            subtitle: issue.title,
            systemImage: "calendar"
        )

        DatePicker(
            "Due date",
            selection: $issueActions.date,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .frame(maxWidth: .infinity)

        editorError
        editorActions(submitTitle: "Set Due Date", submitDisabled: false)
    }

    @ViewBuilder
    private func manualSessionEditor(issue: DailyFocusIssue) -> some View {
        editorHeader(
            title: "Log Session",
            subtitle: issue.title,
            systemImage: "clock.fill",
            iconColor: PopupVisualTheme.semantic(.info)
        )

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Date", systemImage: "calendar")
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                Spacer()
                Text(formattedPopoverDate(issueActions.manualSession.date, appState: appState))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PopupVisualTheme.primaryText)
            }

            TextField("Summary (optional)", text: $issueActions.manualSession.summary)
                .textFieldStyle(.plain)
                .padding(10)
                .popupInputSurface()

            manualSessionSection("Duration", systemImage: "hourglass") {
                durationPickerRow(
                    title: "Work",
                    hours: $issueActions.manualSession.workHours,
                    minutes: $issueActions.manualSession.workMinutes
                )
                durationPickerRow(
                    title: "Break",
                    hours: $issueActions.manualSession.breakHours,
                    minutes: $issueActions.manualSession.breakMinutes
                )
            }

            manualSessionSection("Timing", systemImage: "clock") {
                HStack(spacing: 10) {
                    Text("Set start and end times")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 12)
                    Toggle("", isOn: $issueActions.manualSession.timesEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

                if issueActions.manualSession.timesEnabled {
                    timePickerRow(
                        title: "Start",
                        hour: $issueActions.manualSession.startHour,
                        minute: $issueActions.manualSession.startMinute,
                        period: $issueActions.manualSession.startPeriod
                    )
                    timePickerRow(
                        title: "End",
                        hour: $issueActions.manualSession.endHour,
                        minute: $issueActions.manualSession.endMinute,
                        period: $issueActions.manualSession.endPeriod
                    )
                }
            }

            Text("Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.secondaryText)
            TextField(
                "Anything else worth remembering? (optional)", text: $issueActions.manualSession.notes,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(2...3)
            .padding(10)
            .popupInputSurface()
        }

        editorError
        editorActions(submitTitle: "Log Session", submitDisabled: false)
    }

    @ViewBuilder
    private func deleteIssueEditor(issue: DailyFocusIssue) -> some View {
        editorHeader(
            title: "Confirm Delete",
            subtitle: issue.title,
            systemImage: "trash.fill",
            iconColor: PopupVisualTheme.semantic(.error)
        )

        Text("This will permanently remove the issue from Crona.")
            .font(.subheadline)
            .foregroundStyle(PopupVisualTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

        editorError

        HStack(spacing: 10) {
            Button("Cancel") {
                issueActions.cancel()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button(role: .destructive) {
                issueActions.submit()
            } label: {
                Label(
                    appState.issueActionsService.actionInFlightIssueID == issue.id
                        ? "Deleting…" : "Delete Issue",
                    systemImage: "trash"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(PopupVisualTheme.semantic(.error))
            .disabled(appState.issueActionsService.actionInFlightIssueID != nil)
        }
    }

    private func manualSessionSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.secondaryText)

            VStack(alignment: .leading, spacing: 8, content: content)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(
                        PopupVisualTheme.surfaceFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(
                        PopupVisualTheme.surfaceStroke, lineWidth: 0.7))
        }
    }

    private func durationPickerRow(
        title: String,
        hours: Binding<Int>,
        minutes: Binding<Int>
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Picker("Hours", selection: hours) {
                ForEach(0...12, id: \.self) { value in
                    Text("\(value) hr").tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Picker("Minutes", selection: minutes) {
                ForEach([0, 15, 30, 45], id: \.self) { value in
                    Text("\(value) min").tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private func timePickerRow(
        title: String,
        hour: Binding<Int>,
        minute: Binding<Int>,
        period: Binding<String>
    ) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Picker("Hour", selection: hour) {
                ForEach(1...12, id: \.self) { value in
                    Text(String(format: "%02d", value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Picker("Minute", selection: minute) {
                ForEach([0, 15, 30, 45], id: \.self) { value in
                    Text(String(format: ":%02d", value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Picker("AM or PM", selection: period) {
                Text("AM").tag("AM")
                Text("PM").tag("PM")
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var editorError: some View {
        if let error = issueActions.manualSessionError ?? appState.issueActionsService.lastErrorMessage
        {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(PopupVisualTheme.semantic(.warning))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func editorHeader(
        title: String,
        subtitle: String,
        systemImage: String,
        iconColor: Color = PopupVisualTheme.semantic(.warning)
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PopupVisualTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.primaryText.opacity(0.58))
                    .lineLimit(1)
            }
        }
    }

    private func editorActions(
        submitTitle: String,
        submitDisabled: Bool
    ) -> some View {
        HStack {
            Button("Cancel") {
                issueActions.cancel()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                issueActions.submit()
            } label: {
                HStack(spacing: 6) {
                    Image(
                        systemName: submitTitle == "Log Session" ? "clock.fill" : "checkmark"
                    )
                        .foregroundStyle(
                            submitTitle == "Log Session"
                                ? PopupVisualTheme.semantic(.warning)
                                : PopupVisualTheme.selectedControlText
                        )
                    Text(submitTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .frame(minWidth: submitTitle == "Log Session" ? 122 : 110)
            .keyboardShortcut(.defaultAction)
            .disabled(
                submitDisabled
                    || appState.issueActionsService.actionInFlightIssueID != nil
            )
        }
    }
}
