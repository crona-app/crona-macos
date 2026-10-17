import SwiftUI

struct IssueCreatorView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var issueCreator: IssueCreatorModel
    @FocusState private var focusedField: Field?
    @State private var selectedRepoID: Int64?
    @State private var selectedFollowUp: IssueCreationFollowUp?
    @State private var isDueDatePickerPresented = false

    private enum Field { case title, estimate, description }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: issueCreator.cancel) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(PopupVisualTheme.primaryText.opacity(0.06)))
                        .padding(7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(issueCreator.isSubmitting)
                .accessibilityLabel("Back")

                Text(issueCreator.issueBeingEdited == nil ? "Create Issue" : "Edit Issue")
                    .font(.headline)
                    .foregroundStyle(PopupVisualTheme.primaryText)

                Spacer()
            }

            Text("Title (required)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField("What needs doing?", text: $issueCreator.title)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .title)
                .onChange(of: issueCreator.title) { _, value in
                    if value.count > 120 { issueCreator.title = String(value.prefix(120)) }
                }
                .creatorField(isFocused: focusedField == .title)

            Text("Description (optional)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField("Add details or context", text: $issueCreator.description, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .focused($focusedField, equals: .description)
                .onChange(of: issueCreator.description) { _, value in
                    if value.count > 2_000 { issueCreator.description = String(value.prefix(2_000)) }
                }
                .creatorField(isFocused: focusedField == .description)

            Text("Estimate (optional) and scheduled date").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField("Estimate (e.g. 45m, 1h30m)", text: $issueCreator.estimate)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .estimate)
                    .creatorField(isFocused: focusedField == .estimate)

                Button {
                    isDueDatePickerPresented.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(PopupVisualTheme.secondaryText)
                        Text(formattedDueDate)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .creatorField()
                .popover(isPresented: $isDueDatePickerPresented, arrowEdge: .bottom) {
                    VStack {
                        DatePicker(
                            "Due Date",
                            selection: Binding(
                                get: { issueCreator.dueDate ?? issueCreator.defaultDueDate },
                                set: { issueCreator.dueDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        if issueCreator.dueDate == nil {
                            Button("Use selected date") {
                                issueCreator.dueDate = issueCreator.defaultDueDate
                                isDueDatePickerPresented = false
                            }
                        }
                        Button("No date") {
                            issueCreator.dueDate = nil
                            isDueDatePickerPresented = false
                        }
                    }
                    .disabled(issueCreator.isSubmitting)
                    .padding(12)
                }
            }

            if !issueCreator.estimate.isEmpty,
                case .failure = FlexibleDurationParser.optionalMinutes(issueCreator.estimate) {
                Text("Use a duration such as 45m or 1h30m.")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.semantic(.error))
            }

            Text("Destination (required)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            if issueCreator.issueBeingEdited == nil {
                destinationField
            } else {
                selectedDestinationField
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 12) {
                footerFeedback

                if issueCreator.issueBeingEdited == nil {
                    Text("After creating")
                        .font(.caption)
                        .foregroundStyle(PopupVisualTheme.secondaryText)

                    HStack(spacing: 18) {
                        Toggle("Create More", isOn: createMoreBinding)
                        Toggle("Start Focus", isOn: startFocusBinding)
                            .disabled(appState.hasActiveFocusSession)
                    }
                    .toggleStyle(.checkbox)
                    .controlSize(.regular)

                    Button(action: submitCreateAction) {
                        Text(createActionTitle)
                            .frame(maxWidth: .infinity)
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(createActionDisabled)
                } else {
                    Button(action: { issueCreator.submit(followUp: .close) }) {
                        Text(
                            issueCreator.isSubmitting
                                ? "Saving…" : "Save Changes"
                        )
                        .frame(maxWidth: .infinity)
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            validationMessage != nil
                                || issueCreator.isSubmitting
                                || appState.issueActionsService.actionInFlightIssueID != nil
                        )
                }
            }
        }
        .disabled(issueCreator.isSubmitting)
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            selectedRepoID = selectedDestination?.repoID
            DispatchQueue.main.async { focusedField = .title }
        }
        .onChange(of: appState.issueCreationService.destinations) { _, destinations in
            guard selectedRepoID == nil,
                let destinationID = issueCreator.destinationID
            else { return }
            selectedRepoID = destinations.first { $0.streamID == destinationID }?.repoID
        }
        .onChange(of: selectedRepoID) { _, repoID in
            guard let streamID = issueCreator.destinationID,
                appState.issueCreationService.destinations.first(where: { $0.streamID == streamID })?.repoID != repoID
            else { return }
            issueCreator.destinationID = nil
        }
        .onExitCommand {
            issueCreator.cancel()
        }
        .onChange(of: appState.hasActiveFocusSession) { _, isActive in
            if isActive, selectedFollowUp == .focus {
                selectedFollowUp = nil
            }
        }
    }

    private var destinationField: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Menu {
                    Button("Choose repo") {
                        selectedRepoID = nil
                    }
                    ForEach(repoGroups) { repo in
                        Button(repo.name) {
                            selectedRepoID = repo.id
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedRepoName)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(Color.clear)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .creatorField()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Menu {
                    Button("Choose stream") {
                        issueCreator.destinationID = nil
                    }
                    ForEach(filteredStreams) { destination in
                        Button(destination.streamName) {
                            issueCreator.destinationID = destination.streamID
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(selectedStreamName)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(Color.clear)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .creatorField()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(selectedRepoID == nil)
            .opacity(selectedRepoID == nil ? 0.58 : 1)
        }
    }

    private var selectedDestinationField: some View {
        HStack {
            Label("Destination", systemImage: "folder")
            Spacer()
            Text(selectedDestination?.label ?? "Unknown")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .creatorField()
    }

    private struct RepoGroup: Identifiable {
        let id: Int64
        let name: String
    }

    private var repoGroups: [RepoGroup] {
        var seen = Set<Int64>()
        return appState.issueCreationService.destinations.compactMap { destination in
            guard seen.insert(destination.repoID).inserted else { return nil }
            return RepoGroup(id: destination.repoID, name: destination.repoName)
        }
    }

    private var filteredStreams: [IssueDestination] {
        return appState.issueCreationService.destinations.filter {
            $0.repoID == selectedRepoID
        }
    }

    private var selectedRepoName: String {
        guard let selectedRepoID,
            let repo = repoGroups.first(where: { $0.id == selectedRepoID })
        else { return "Choose repo" }
        return repo.name
    }

    private var selectedStreamName: String {
        guard let selectedDestination else { return "Choose stream" }
        return selectedDestination.streamName
    }

    private var selectedDestination: IssueDestination? {
        appState.issueCreationService.destinations.first { $0.streamID == issueCreator.destinationID }
    }

    private var createActionDisabled: Bool {
        validationMessage != nil || issueCreator.isSubmitting
            || (selectedFollowUp == .focus && appState.hasActiveFocusSession)
    }

    private var footerFeedback: some View {
        Group {
            if let error = appState.issueCreationService.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(PopupVisualTheme.semantic(.error).opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Color.clear
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .contentTransition(.opacity)
    }

    private var createMoreBinding: Binding<Bool> {
        Binding(
            get: { selectedFollowUp == .more },
            set: { enabled in
                selectedFollowUp = enabled ? .more : (selectedFollowUp == .more ? nil : selectedFollowUp)
            }
        )
    }

    private var startFocusBinding: Binding<Bool> {
        Binding(
            get: { selectedFollowUp == .focus },
            set: { enabled in
                selectedFollowUp = enabled ? .focus : (selectedFollowUp == .focus ? nil : selectedFollowUp)
            }
        )
    }

    private var createActionTitle: String {
        switch selectedFollowUp {
        case .some(.more): return "Create More"
        case .some(.focus): return "Create & Focus"
        case .some(.close): return "Create Issue"
        case nil: return "Create Issue"
        }
    }

    private func submitCreateAction() {
        issueCreator.submit(followUp: selectedFollowUp ?? .close)
    }

    private var validationMessage: String? {
        if issueCreator.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Issue title is required."
        }
        if issueCreator.destinationID == nil { return "Choose a repo and stream." }
        if case .failure = FlexibleDurationParser.optionalMinutes(issueCreator.estimate) {
            return "Estimate must be like 90, 90m, 1h30m, 1.5h, or 1h34m23s."
        }
        return nil
    }

    private var formattedDueDate: String {
        issueCreator.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "No date"
    }
}

struct HabitCreatorView: View {
    @ObservedObject var appState: CompanionAppState
    @State private var selectedRepoID: Int64?
    @State private var scheduleSelection = "daily"
    @FocusState private var nameFocused: Bool

    private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: appState.cancelHabitCreator) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(PopupVisualTheme.controlBackground))
                        .menuBarIconHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text(appState.habitBeingEdited == nil ? "Create Habit" : "Edit Habit")
                    .font(.headline)
                Spacer()
            }

            Text("Name (required)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            TextField("Habit name", text: $appState.habitCreateName)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .creatorField(isFocused: nameFocused)

            if appState.habitBeingEdited == nil {
                destinationField
            } else {
                HStack {
                    Label("Destination", systemImage: "folder")
                    Spacer()
                    Text(destinationLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .creatorField()
            }

            scheduleSection

            TextField("Target duration (optional, e.g. 30m)", text: $appState.habitCreateTarget)
                .textFieldStyle(.plain)
                .creatorField()

            TextField("Description (optional)", text: $appState.habitCreateDescription, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .creatorField()

            if appState.habitBeingEdited != nil {
                Toggle("Active", isOn: $appState.habitCreateActive)
            }

            Divider().padding(.vertical, 4)

            if let error = appState.habitCreateError ?? appState.habitsService.lastManagementError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.semantic(.warning))
            }

            Button(action: appState.submitHabitCreator) {
                Text(appState.habitsService.isManagingHabit ? "Saving…" : (appState.habitBeingEdited == nil ? "Create Habit" : "Save Changes"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(appState.habitsService.isManagingHabit || appState.habitCreateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onExitCommand { appState.cancelHabitCreator() }
        .onAppear {
            DispatchQueue.main.async { nameFocused = true }
            scheduleSelection = appState.habitCreateScheduleType
            selectedRepoID = selectedDestination?.repoID ?? appState.issueCreationService.destinations.first?.repoID
            Task { await appState.issueCreationService.loadDestinations() }
        }
    }

    private var destinationField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Destination (required)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Menu {
                    ForEach(repoGroups) { repo in
                        Button(repo.name) {
                            selectedRepoID = repo.id
                            if selectedDestination?.repoID != repo.id {
                                appState.habitCreateDestinationID = nil
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(repoGroups.first { $0.id == selectedRepoID }?.name ?? "Choose repo").lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
                .creatorField()
                .frame(maxWidth: .infinity)

                Menu {
                    ForEach(appState.issueCreationService.destinations.filter { $0.repoID == selectedRepoID }) { destination in
                        Button(destination.streamName) {
                            appState.habitCreateDestinationID = destination.streamID
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedDestination?.streamName ?? "Choose stream").lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity, alignment: .leading)
                .creatorField()
                .frame(maxWidth: .infinity)
                .disabled(selectedRepoID == nil)
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                scheduleOption("daily", icon: "sun.max.fill", title: "Daily", subtitle: "Every day")
                scheduleOption("weekdays", icon: "briefcase.fill", title: "Weekdays", subtitle: "Monday through Friday")
                scheduleOption("weekly", icon: "calendar", title: "Custom", subtitle: "Choose specific days")
            }

            if scheduleSelection == "weekly" {
                HStack(spacing: 5) {
                    ForEach(0..<weekdayNames.count, id: \.self) { day in
                        Button {
                            if appState.habitCreateWeekdays.contains(day) {
                                appState.habitCreateWeekdays.remove(day)
                            } else {
                                appState.habitCreateWeekdays.insert(day)
                            }
                        } label: {
                            Text(weekdayNames[day])
                                .font(.caption2.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(appState.habitCreateWeekdays.contains(day) ? Color.accentColor.opacity(0.22) : PopupVisualTheme.primaryText.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(appState.habitCreateWeekdays.contains(day) ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
                        )
                    }
                }
                Text("Runs only on the days you select.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scheduleOption(_ value: String, icon: String, title: String, subtitle: String) -> some View {
        Button {
            scheduleSelection = value
            DispatchQueue.main.async {
                appState.habitCreateScheduleType = value
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(scheduleSelection == value ? Color.accentColor : .secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: scheduleSelection == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(scheduleSelection == value ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(scheduleSelection == value ? Color.accentColor.opacity(0.12) : PopupVisualTheme.primaryText.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(scheduleSelection == value ? Color.accentColor.opacity(0.45) : PopupVisualTheme.surfaceStroke, lineWidth: 1)
        )
    }

    private var selectedDestination: IssueDestination? {
        appState.issueCreationService.destinations.first { $0.streamID == appState.habitCreateDestinationID }
    }

    private var destinationLabel: String {
        selectedDestination?.label ?? "Unknown destination"
    }

    private struct RepoGroup: Identifiable {
        let id: Int64
        let name: String
    }

    private var repoGroups: [RepoGroup] {
        var seen = Set<Int64>()
        return appState.issueCreationService.destinations.compactMap { destination in
            guard seen.insert(destination.repoID).inserted else { return nil }
            return RepoGroup(id: destination.repoID, name: destination.repoName)
        }
    }


}

struct HabitDeleteConfirmationView: View {
    @ObservedObject var appState: CompanionAppState
    let habit: HabitRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Delete Habit", systemImage: "trash")
                .font(.headline)
                .foregroundStyle(PopupVisualTheme.semantic(.error))
            Text("Delete \"\(habit.name)\"? This cannot be undone.")
                .fixedSize(horizontal: false, vertical: true)
            if let error = appState.habitsService.lastManagementError {
                Text(error).font(.caption).foregroundStyle(PopupVisualTheme.semantic(.error))
            }
            HStack {
                Button("Cancel", action: appState.cancelHabitActionEditor)
                Spacer()
                Button("Delete", role: .destructive, action: appState.submitHabitActionEditor)
                    .disabled(appState.habitsService.isManagingHabit)
            }
        }
        .padding(20)
        .frame(width: 360)
        .frame(minHeight: 220)
    }
}

struct IssueCreationSuccessView: View {
    @ObservedObject var appState: CompanionAppState
    let success: IssueCreationSuccess

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(PopupVisualTheme.semantic(.success))
            Text("Created \(success.issue.title)").font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            if success.plannedForToday && !appState.hasActiveFocusSession {
                Button("Start Focus", action: appState.issueCreator.startFocusFromCreatedIssue)
                    .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(PopupVisualTheme.semantic(.warning))
            }
            Button(action: appState.issueCreator.dismissSuccess) { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(PopupVisualTheme.primaryText.opacity(0.07)))
    }
}

private extension View {
    func creatorField(isFocused: Bool = false) -> some View {
        padding(10)
            .popupInputSurface(isFocused: isFocused)
    }
}
