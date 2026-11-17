import SwiftUI

struct DurationTextField: View {
    let title: String
    @Binding var text: String
    var maximumMinutes = Int.max / 60
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("1h30m", text: $text)
            .textFieldStyle(.plain)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .popupInputSurface(cornerRadius: 8)
            .frame(width: 96)
            .focused($isFocused)
            .accessibilityLabel(title)
            .help("Enter a duration, such as 1h07m or 47m")
            .onSubmit { normalize() }
            .onChange(of: isFocused) { _, focused in
                if !focused { normalize() }
            }
    }

    private func normalize() {
        if let minutes = DurationInput.minutes(text, maximum: maximumMinutes) {
            text = MenuBarTextFormatter.formatMinutes(minutes)
        }
    }
}
