import SwiftUI

/// Paste or type one issue per line, preview how the daemon reads them, then import them together.
struct IssueCaptureView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var issueCapture: IssueCaptureModel
    @ObservedObject private var issueCreationService: IssueCreationService
    @ObservedObject private var tagsModel: TagsModel
    @State private var editor = CaptureEditorController()
    @State private var token: CaptureToken?
    @State private var highlighted = 0

    init(appState: CompanionAppState, issueCapture: IssueCaptureModel) {
        self.appState = appState
        self.issueCapture = issueCapture
        self.issueCreationService = appState.issueCreationService
        self.tagsModel = appState.tags
    }

    private var suggestions: [CaptureSuggestion] {
        guard let token else { return [] }
        return CaptureAutocomplete.suggestions(
            for: token, destinations: issueCreationService.destinations, tags: tagsModel.tags.map(\.name))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button(action: issueCapture.dismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(PopupVisualTheme.primaryText.opacity(0.06)))
                        .padding(7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(issueCapture.isImporting)
                .accessibilityLabel("Back")

                Text("Capture Issues")
                    .font(.headline)
                    .foregroundStyle(PopupVisualTheme.primaryText)

                Spacer()

                if issueCapture.isParsing {
                    ProgressView().controlSize(.small)
                }
            }

            ZStack(alignment: .topLeading) {
                if issueCapture.text.isEmpty {
                    Text("- One issue per line")
                        .foregroundStyle(PopupVisualTheme.tertiaryText)
                        .allowsHitTesting(false)
                }
                CaptureTextEditor(
                    text: $issueCapture.text, controller: editor,
                    onToken: { next in
                        if next != token { highlighted = 0 }
                        token = next
                    },
                    onKey: handleKey)
            }
            .font(.body)
            .frame(height: 120)
            .padding(10)
            .popupInputSurface(isFocused: true)

            if !suggestions.isEmpty {
                suggestionList
            } else {
                Text("#repo/stream  ~estimate  @date  +tag")
                    .font(.caption.monospaced())
                    .foregroundStyle(PopupVisualTheme.tertiaryText)
            }

            if !issueCapture.proposals.isEmpty {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(issueCapture.proposals) { proposal in
                            proposalRow(proposal)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let error = issueCapture.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.semantic(.error).opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await issueCapture.importAll() }
            } label: {
                Text(
                    issueCapture.isImporting
                        ? "Importing…" : IssueCaptureModel.importButtonTitle(count: issueCapture.importableCount)
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!issueCapture.canImport)
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onExitCommand(perform: issueCapture.dismiss)
        .task {
            if issueCreationService.destinations.isEmpty { await issueCreationService.loadDestinations() }
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                Button {
                    accept(suggestion)
                } label: {
                    HStack(spacing: 8) {
                        Text(suggestion.label)
                            .foregroundStyle(PopupVisualTheme.primaryText)
                        Spacer(minLength: 0)
                        if index == highlighted {
                            Image(systemName: "return")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(PopupVisualTheme.tertiaryText)
                        }
                    }
                    .font(.callout)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(index == highlighted ? PopupVisualTheme.primaryText.opacity(0.08) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { highlighted = index } }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 12).fill(PopupVisualTheme.primaryText.opacity(0.05)))
    }

    private func handleKey(_ key: CaptureEditorKey) -> Bool {
        let options = suggestions
        guard !options.isEmpty else {
            // NSTextView would otherwise show its own word completions on Escape.
            if key == .dismiss { issueCapture.dismiss(); return true }
            return false
        }
        switch key {
        case .up: highlighted = (highlighted - 1 + options.count) % options.count
        case .down: highlighted = (highlighted + 1) % options.count
        case .accept: accept(options[min(highlighted, options.count - 1)])
        case .dismiss: token = nil
        }
        return true
    }

    private func accept(_ suggestion: CaptureSuggestion) {
        guard let token else { return }
        let result = CaptureAutocomplete.apply(suggestion, to: issueCapture.text, replacing: token)
        self.token = nil
        editor.replace(with: result.text, caret: result.caret)
        editor.focus()
    }

    private func proposalRow(_ proposal: CronaCaptureProposal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(proposal.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PopupVisualTheme.primaryText)
                .lineLimit(2)
            Text(details(for: proposal))
                .font(.caption)
                .foregroundStyle(PopupVisualTheme.secondaryText)
                .lineLimit(1)
            ForEach(proposal.flags ?? [], id: \.self) { flag in
                Label(flag, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(PopupVisualTheme.semantic(.error))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(PopupVisualTheme.primaryText.opacity(0.06)))
    }

    private func details(for proposal: CronaCaptureProposal) -> String {
        var parts = [target(for: proposal)]
        if let minutes = proposal.estimateMinutes, minutes > 0 {
            parts.append(MenuBarTextFormatter.formatMinutes(minutes))
        }
        if let date = proposal.todoForDate, !date.isEmpty {
            parts.append(formattedPopoverDate(date, appState: appState))
        }
        if let tags = proposal.tags, !tags.isEmpty {
            parts.append(tags.map { "#\($0)" }.joined(separator: " "))
        }
        return parts.joined(separator: "  ·  ")
    }

    private func target(for proposal: CronaCaptureProposal) -> String {
        if proposal.inbox == true { return "Inbox" }
        switch (proposal.repoName, proposal.streamName) {
        case let (repo?, stream?): return "\(repo) / \(stream)"
        case let (repo?, nil): return repo
        case let (nil, stream?): return stream
        default: return "Inbox"
        }
    }
}
