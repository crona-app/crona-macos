import SwiftUI

struct AdhocAttributionView: View {
    @ObservedObject var appState: CompanionAppState
    var onCancel: (() -> Void)? = nil
    @FocusState private var focusedField: Field?
    @State private var isDatePickerPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case title, description, estimate }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Group {
                switch appState.adhocAttribution.resolution {
                case .attach: issuePicker
                case .create: createFields
                case .keep: keepContext
                case nil: choices
                }
            }

            if appState.adhocAttribution.resolution != nil {
                summaryField
            }

            Spacer(minLength: 12)
            feedback
            if appState.adhocAttribution.resolution != nil {
                Button(action: appState.confirmEndSession) {
                    Text(appState.isSubmittingEndSession ? "Saving..." : appState.endSessionActionTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!appState.canSubmitEndSession)
            }
        }
        .padding(20)
        .frame(height: appState.adhocCompletionHeight, alignment: .topLeading)
        .foregroundStyle(PopupVisualTheme.primaryText)
        .disabled(appState.isSubmittingEndSession)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: appState.adhocAttribution.resolution)
        .task { await appState.loadAdhocAttribution() }
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
                .accessibilityLabel(appState.adhocAttribution.resolution == nil ? (onCancel == nil ? "Keep running" : "Back to timer options") : "Back to attribution choices")
                .disabled(appState.adhocAttribution.createdIssue != nil)

                Text(appState.adhocAttribution.resolution?.title ?? "Finish Focus")
                    .font(.headline)
                Spacer(minLength: 0)
                if appState.adhocAttribution.resolution != nil {
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
                Text(MenuBarTextFormatter.formatClock(seconds: appState.adhocElapsedSeconds))
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
                    appState.adhocAttribution.resolution = resolution
                }
            }
        }
    }

    private var issuePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegmentedControl(selection: $appState.adhocAttribution.filter, title: \.rawValue)
            let issues = appState.adhocAttribution.filteredIssues(today: appState.daemonConnection.currentDate)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if appState.adhocAttribution.isLoading {
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
                            selected: appState.adhocAttribution.selectedIssueID == issue.id,
                            dateLabel: issue.todoForDate.map { formattedPopoverDate($0, appState: appState) }
                        ) { appState.adhocAttribution.selectedIssueID = issue.id }
                    }
                }
                .padding(2)
            }
            .frame(height: 172)
            .scrollIndicators(.hidden)
            if let selected = appState.adhocAttribution.issues.first(where: { $0.id == appState.adhocAttribution.selectedIssueID }) {
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
            if let issue = appState.adhocAttribution.createdIssue {
                Label("\(issue.title) was created. Retry to finish attaching this session.", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(PopupVisualTheme.secondaryText)
                    .padding(12)
                    .background(subtleCardBackground(stroke: PopupVisualTheme.border, cornerRadius: 14))
            } else {
                TextField("What needs doing?", text: $appState.adhocAttribution.title)
                    .focused($focusedField, equals: .title)
                    .attributionField(isFocused: focusedField == .title)
                    .accessibilityLabel("Issue title")
                TextField("Description (optional)", text: $appState.adhocAttribution.description, axis: .vertical)
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
                        appState.adhocAttribution.repoID = repoID
                        if selectedDestination?.repoID != repoID { appState.adhocAttribution.destinationID = nil }
                    }
                }
            } label: { destinationLabel(destinations.first(where: { $0.repoID == activeRepoID })?.repoName ?? "Choose repo") }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
            .attributionField()
            .accessibilityLabel("Repository")

            Menu {
                ForEach(destinations.filter { $0.repoID == activeRepoID }) { destination in
                    Button(destination.streamName) { appState.adhocAttribution.destinationID = destination.id }
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
                get: { CronaCalendarDate.date(from: appState.adhocAttribution.date) ?? appState.defaultIssueCreateDate },
                set: { appState.adhocAttribution.date = CronaCalendarDate.string(from: $0) }
            ), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            Button("Use selected date") {
                if appState.adhocAttribution.date.isEmpty {
                    appState.adhocAttribution.date = CronaCalendarDate.string(from: appState.defaultIssueCreateDate)
                }
                isDatePickerPresented = false
            }
            Button("No date") {
                appState.adhocAttribution.date = ""
                isDatePickerPresented = false
            }
        }
        .padding(12)
        .disabled(appState.isSubmittingEndSession)
        .companionAppearance(appState)
    }

    private var summaryField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Summary (required)").font(.caption.weight(.medium)).foregroundStyle(PopupVisualTheme.secondaryText)
            StableMultilineTextField(
                text: $appState.endSessionCommitMessage,
                placeholder: "What did you work on?",
                isEnabled: !appState.isSubmittingEndSession,
                focusRequest: appState.endSessionFocusRequest
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
        if let error = appState.endSessionErrorMessage ?? appState.adhocAttribution.loadError {
            VStack(alignment: .leading, spacing: 6) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(PopupVisualTheme.semantic(.error))
                    .lineLimit(3)
                    .help(error)
                if appState.adhocAttribution.loadError != nil {
                    Button("Retry Loading") { Task { await appState.loadAdhocAttribution() } }
                        .font(.caption.weight(.semibold)).buttonStyle(.plain)
                }
            }
        } else if appState.adhocAttribution.resolution == .create, appState.adhocAttribution.createdIssue == nil, appState.adhocAttribution.estimateMinutes < 0 {
            Text("Use an estimate like 45m or 1h30m.")
                .font(.caption).foregroundStyle(PopupVisualTheme.semantic(.error))
        }
    }

    private var destinations: [IssueDestination] { appState.issueCreationService.destinations }
    private var selectedDestination: IssueDestination? { destinations.first { $0.id == appState.adhocAttribution.destinationID } }
    private var activeRepoID: Int64? { appState.adhocAttribution.repoID ?? selectedDestination?.repoID }
    private var repoIDs: [Int64] { Array(Set(destinations.map(\.repoID))).sorted() }
    private var dateLabel: String {
        CronaCalendarDate.date(from: appState.adhocAttribution.date)?.formatted(date: .abbreviated, time: .omitted) ?? "No date"
    }
    private var estimateBinding: Binding<String> {
        Binding(
            get: { appState.adhocAttribution.estimateInput ?? (appState.adhocAttribution.estimateMinutes > 0 ? "\(appState.adhocAttribution.estimateMinutes)m" : "") },
            set: { value in
                appState.adhocAttribution.estimateInput = value
                switch FlexibleDurationParser.optionalMinutes(value) {
                case .success(let minutes): appState.adhocAttribution.estimateMinutes = minutes ?? 0
                case .failure: appState.adhocAttribution.estimateMinutes = -1
                }
            }
        )
    }
    private func cancel() { (onCancel ?? appState.cancelEndSession)() }
    private func goBack() {
        guard !appState.isSubmittingEndSession else { return }
        if appState.adhocAttribution.resolution != nil, appState.adhocAttribution.createdIssue == nil {
            appState.adhocAttribution.resolution = nil
        } else { cancel() }
    }
}

private extension View {
    func attributionField(isFocused: Bool = false) -> some View {
        padding(10).popupInputSurface(isFocused: isFocused)
    }
}
