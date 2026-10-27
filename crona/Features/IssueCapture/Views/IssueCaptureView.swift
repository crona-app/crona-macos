import SwiftUI

/// Paste or type one issue per line, preview how the daemon reads them, then import them together.
struct IssueCaptureView: View {
    @ObservedObject var appState: CompanionAppState
    @ObservedObject var issueCapture: IssueCaptureModel
    @FocusState private var isEditorFocused: Bool

    init(appState: CompanionAppState, issueCapture: IssueCaptureModel) {
        self.appState = appState
        self.issueCapture = issueCapture
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
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $issueCapture.text)
                    .scrollContentBackground(.hidden)
                    .focused($isEditorFocused)
            }
            .font(.body)
            .frame(height: 120)
            .padding(10)
            .popupInputSurface(isFocused: isEditorFocused)

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
        .onAppear { isEditorFocused = true }
        .onExitCommand(perform: issueCapture.dismiss)
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
