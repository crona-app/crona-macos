import SwiftUI

struct HabitDetailActionBar: View {
    let appState: CompanionAppState
    let habit: HabitRowModel
    @Binding var isLoggingDuration: Bool
    @Binding var durationDraft: String
    @Binding var durationError: String?
    let parsedDuration: Int?
    let beginLogging: () -> Void
    let submitDuration: () -> Void
    @FocusState private var durationFieldFocused: Bool

    var body: some View {
        DetailActionBar {
            if isLoggingDuration {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Log duration").font(.caption.weight(.semibold))
                    HStack(spacing: 8) {
                        TextField("0h0m0s", text: $durationDraft)
                            .textFieldStyle(.plain)
                            .popupInputSurface()
                            .padding(.horizontal, 9)
                            .frame(height: 30)
                            .focused($durationFieldFocused)
                            .onSubmit(submitDuration)
                            .onChange(of: durationDraft) { durationError = nil }
                            .onAppear { durationFieldFocused = true }
                        Button("Cancel") { isLoggingDuration = false }
                            .buttonStyle(.bordered)
                        Button("Save", action: submitDuration)
                            .buttonStyle(.borderedProminent)
                            .disabled(parsedDuration == nil || parsedDuration == 0)
                    }
                    Text("Use HhMmSs, for example 1h20m30s or 01:20:30")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let durationError {
                        Text(durationError).font(.caption).foregroundStyle(PopupVisualTheme.semantic(.error))
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if habit.completed || habit.status == "failed" {
                        Button {
                            appState.habitEditor.clearCompletion(habit)
                        } label: {
                            Label("Clear", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .help("Clear completion")
                    } else {
                        Button {
                            appState.habitEditor.fail(habit)
                        } label: {
                            Label("Fail", systemImage: "xmark")
                        }
                        .buttonStyle(.bordered)
                    }
                    Button(action: beginLogging) {
                        Label("Log Time", systemImage: "clock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    if !habit.completed && habit.status != "failed" {
                        Button {
                            appState.habitEditor.complete(habit)
                        } label: {
                            Label("Done", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
            }
        }
        .onChange(of: durationError) { _, error in
            if error != nil { durationFieldFocused = true }
        }
    }
}
