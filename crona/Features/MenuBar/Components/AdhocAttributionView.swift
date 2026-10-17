import SwiftUI

struct AdhocAttributionView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var endSession: EndSessionModel
    var onCancel: (() -> Void)? = nil
    @FocusState private var focusedField: Field?
    @State private var isDatePickerPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case title, description, estimate }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Group {
                switch endSession.adhocAttribution.resolution {
                case .attach: issuePicker
                case .create: createFields
                case .keep: keepContext
                case nil: choices
                }
            }

            if endSession.adhocAttribution.resolution != nil {
                summaryField
            }

            Spacer(minLength: 12)
            feedback
            if endSession.adhocAttribution.resolution != nil {
                Button(action: endSession.confirm) {
                    Text(endSession.isSubmitting ? "Saving..." : endSession.actionTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!endSession.canSubmit)
            }
        }
        .padding(20)
        .frame(height: endSession.adhocCompletionHeight, alignment: .topLeading)
        .foregroundStyle(PopupVisualTheme.primaryText)
        .disabled(endSession.isSubmitting)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: endSession.adhocAttribution.resolution)
        .task { await endSession.loadAdhocAttribution() }
        .onExitCommand { goBack() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(PopupVisualTheme.controlBackground))
                        .padding(7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(endSession.adhocAttribution.resolution == nil ? (onCancel == nil ? "Keep running" : "Back to timer options") : "Back to attribution choices")
                .disabled(endSession.adhocAttribution.createdIssue != nil)

                Text(endSession.adhocAttribution.resolution?.title ?? "Finish Focus")
                    .font(.headline)
                Spacer(minLength: 0)
                if endSession.adhocAttribution.resolution != nil {
                    Button(action: cancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PopupVisualTheme.secondaryText)
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel attribution")
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(PopupVisualTheme.semantic(.focus))
                Text("Ad Hoc Focus")
                Spacer()
                Text(MenuBarTextFormatter.formatClock(seconds: endSession.adhocElapsedSeconds))
                    .monospacedDigit()
                Text("elapsed").foregroundStyle(PopupVisualTheme.tertiaryText)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(PopupVisualTheme.secondaryText)
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where does this session belong?")
                .font(.subheadline)
                .foregroundStyle(PopupVisualTheme.secondaryText)
                .padding(.bottom, 4)
            ForEach(CronaAdhocResolution.allCases) { resolution in
                AdhocChoiceRow(resolution: resolution) {
                    endSession.adhocAttribution.resolution = resolution
                }
            }
        }
    }

    private var issuePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegmentedControl(selection: $endSession.adhocAttribution.filter, title: \.rawValue)
            let issues = endSession.adhocAttribution.filteredIssues(today: appState.daemonConnection.currentDate)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if endSession.adhocAttribution.isLoading {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
                    } else if issues.isEmpty {
                        Label("No issues in this tab", systemImage: "tray")
                            .font(.subheadline)
                            .foregroundStyle(PopupVisualTheme.secondaryText)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    ForEach(issues) { issue in
                        AdhocIssueRow(
                            issue: issue,
                            selected: endSession.adhocAttribution.selectedIssueID == issue.id,
                            dateLabel: issue.todoForDate.map { formattedPopoverDate($0, appState: appState) }
                        ) { endSession.adhocAttribution.selectedIssueID = issue.id }
                    }
                }
                .padding(2)
            }
            .frame(height: 172)
            .scrollIndicators(.hidden)
            if let selected = endSession.adhocAttribution.issues.first(where: { $0.id == endSession.adhocAttribution.selectedIssueID }) {
                Label(selected.title, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .lineLimit(1)
            } else {
                Text("Choose an issue to attach your work.")
                    .font(.caption).foregroundStyle(PopupVisualTheme.tertiaryText)
            }
        }
    }

    private var createFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let issue = endSession.adhocAttribution.createdIssue {
                Label("\(issue.title) was created. Retry to finish attaching this session.", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .padding(12)
                    .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 14))
            } else {
                TextField("What needs doing?", text: $endSession.adhocAttribution.title)
                    .focused($focusedField, equals: .title)
                    .attributionField(isFocused: focusedField == .title)
                    .accessibilityLabel("Issue title")
                TextField("Description (optional)", text: $endSession.adhocAttribution.description, axis: .vertical)
                    .lineLimit(2...3)
                    .focused($focusedField, equals: .description)
                    .attributionField(isFocused: focusedField == .description)
                HStack(spacing: 10) {
                    TextField("Estimate (e.g. 45m)", text: estimateBinding)
                        .focused($focusedField, equals: .estimate)
                        .attributionField(isFocused: focusedField == .estimate)
                        .accessibilityLabel("Estimate")
                    Button { isDatePickerPresented.toggle() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar").foregroundStyle(PopupVisualTheme.secondaryText)
                            Text(dateLabel).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .attributionField()
                    .accessibilityLabel("Scheduled date")
                    .popover(isPresented: $isDatePickerPresented, arrowEdge: .bottom) { datePicker }
                }
                destinationFields
            }
        }
        .textFieldStyle(.plain)
    }

    private var destinationFields: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(repoIDs, id: \.self) { repoID in
                    Button(destinations.first(where: { $0.repoID == repoID })?.repoName ?? "Repository") {
                        endSession.adhocAttribution.repoID = repoID
                        if selectedDestination?.repoID != repoID { endSession.adhocAttribution.destinationID = nil }
                    }
                }
            } label: { destinationLabel(destinations.first(where: { $0.repoID == activeRepoID })?.repoName ?? "Choose repo") }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
            .attributionField()
            .accessibilityLabel("Repository")

            Menu {
                ForEach(destinations.filter { $0.repoID == activeRepoID }) { destination in
                    Button(destination.streamName) { endSession.adhocAttribution.destinationID = destination.id }
                }
            } label: { destinationLabel(selectedDestination?.streamName ?? "Choose stream") }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
            .attributionField()
            .disabled(activeRepoID == nil)
            .accessibilityLabel("Stream")
        }
    }

    private func destinationLabel(_ title: String) -> some View {
        Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var datePicker: some View {
        VStack(spacing: 10) {
            DatePicker("Scheduled date", selection: Binding(
                get: { CronaCalendarDate.date(from: endSession.adhocAttribution.date) ?? appState.issueCreator.defaultDueDate },
                set: { endSession.adhocAttribution.date = CronaCalendarDate.string(from: $0) }
            ), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            Button("Use selected date") {
                if endSession.adhocAttribution.date.isEmpty {
                    endSession.adhocAttribution.date = CronaCalendarDate.string(from: appState.issueCreator.defaultDueDate)
                }
                isDatePickerPresented = false
            }
            Button("No date") {
                endSession.adhocAttribution.date = ""
                isDatePickerPresented = false
            }
        }
        .padding(12)
        .disabled(endSession.isSubmitting)
        .companionAppearance(appState)
    }

    private var summaryField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Summary (required)").font(.caption.weight(.medium)).foregroundStyle(PopupVisualTheme.secondaryText)
            StableMultilineTextField(
                text: $endSession.commitMessage,
                placeholder: "What did you work on?",
                isEnabled: !endSession.isSubmitting,
                focusRequest: endSession.focusRequest
            )
            .frame(height: 88)
            .popupInputSurface(cornerRadius: 12)
        }
    }

    private var keepContext: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ad hoc / Sessions").font(.subheadline.weight(.semibold))
                Text("Saved as completed for today.").font(.caption).foregroundStyle(PopupVisualTheme.secondaryText)
            }
        } icon: {
            Image(systemName: "timer").foregroundStyle(PopupVisualTheme.semantic(.focus))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 16))
    }

    @ViewBuilder private var feedback: some View {
        if let error = endSession.errorMessage ?? endSession.adhocAttribution.loadError {
            VStack(alignment: .leading, spacing: 6) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(PopupVisualTheme.semantic(.error))
                    .lineLimit(3)
                    .help(error)
                if endSession.adhocAttribution.loadError != nil {
                    Button("Retry Loading") { Task { await endSession.loadAdhocAttribution() } }
                        .font(.caption.weight(.semibold)).buttonStyle(.plain)
                }
            }
        } else if endSession.adhocAttribution.resolution == .create, endSession.adhocAttribution.createdIssue == nil, endSession.adhocAttribution.estimateMinutes < 0 {
            Text("Use an estimate like 45m or 1h30m.")
                .font(.caption).foregroundStyle(PopupVisualTheme.semantic(.error))
        }
    }

    private var destinations: [IssueDestination] { appState.issueCreationService.destinations }
    private var selectedDestination: IssueDestination? { destinations.first { $0.id == endSession.adhocAttribution.destinationID } }
    private var activeRepoID: Int64? { endSession.adhocAttribution.repoID ?? selectedDestination?.repoID }
    private var repoIDs: [Int64] { Array(Set(destinations.map(\.repoID))).sorted() }
    private var dateLabel: String {
        CronaCalendarDate.date(from: endSession.adhocAttribution.date)?.formatted(date: .abbreviated, time: .omitted) ?? "No date"
    }
    private var estimateBinding: Binding<String> {
        Binding(
            get: { endSession.adhocAttribution.estimateInput ?? (endSession.adhocAttribution.estimateMinutes > 0 ? "\(endSession.adhocAttribution.estimateMinutes)m" : "") },
            set: { value in
                endSession.adhocAttribution.estimateInput = value
                switch FlexibleDurationParser.optionalMinutes(value) {
                case .success(let minutes): endSession.adhocAttribution.estimateMinutes = minutes ?? 0
                case .failure: endSession.adhocAttribution.estimateMinutes = -1
                }
            }
        )
    }
    private func cancel() { (onCancel ?? endSession.cancel)() }
    private func goBack() {
        guard !endSession.isSubmitting else { return }
        if endSession.adhocAttribution.resolution != nil, endSession.adhocAttribution.createdIssue == nil {
            endSession.adhocAttribution.resolution = nil
        } else { cancel() }
    }
}

private extension View {
    func attributionField(isFocused: Bool = false) -> some View {
        padding(10).popupInputSurface(isFocused: isFocused)
    }
}
