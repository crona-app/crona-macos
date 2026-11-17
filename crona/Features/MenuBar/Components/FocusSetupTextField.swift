import AppKit
import SwiftUI

/// AppKit supplies select-on-focus and Return handling while SwiftUI owns the draft.
struct FocusSetupTextField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    var isDuration = true
    let onSubmit: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> NSTextField {
        let field = SelectOnFocusTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.isEnabled = isEnabled
        field.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        field.placeholderString = isDuration ? "1h30m" : "4"
        field.setAccessibilityLabel(title)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusSetupTextField
        init(_ parent: FocusSetupTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard parent.isDuration,
                  let minutes = DurationInput.minutes(parent.text, maximum: 1_440) else { return }
            parent.text = MenuBarTextFormatter.formatMinutes(minutes)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}

private final class SelectOnFocusTextField: NSTextField {
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Cell-based editing may bypass becomeFirstResponder on the field itself.
        currentEditor()?.selectAll(nil)
    }


    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentEditor() != nil else { return }
                self.selectText(nil)
            }
        }
        return accepted
    }
}
