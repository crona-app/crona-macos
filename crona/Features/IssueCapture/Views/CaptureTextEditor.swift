import AppKit
import SwiftUI

/// Lets the sheet replace the editor's text and caret when a suggestion is picked.
@MainActor
final class CaptureEditorController {
    fileprivate weak var textView: NSTextView?

    func replace(with text: String, caret: Int) {
        guard let textView else { return }
        textView.string = text
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: textView))
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }
}

enum CaptureEditorKey {
    case up, down, accept, dismiss
}

/// A plain-text editor that reports the annotation under the caret and lets the sheet take
/// arrow, Return, Tab and Escape while suggestions are showing.
struct CaptureTextEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: CaptureEditorController
    let onToken: (CaptureToken?) -> Void
    /// Returns true when the key was used for suggestions.
    let onKey: (CaptureEditorKey) -> Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.string = text
        controller.textView = textView
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptureTextEditor

        init(parent: CaptureTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            report(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            report(textView)
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onKey(.up)
            case #selector(NSResponder.moveDown(_:)): parent.onKey(.down)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)): parent.onKey(.accept)
            case #selector(NSResponder.cancelOperation(_:)): parent.onKey(.dismiss)
            default: false
            }
        }

        private func report(_ textView: NSTextView) {
            let selection = textView.selectedRange()
            let token = selection.length == 0
                ? CaptureAutocomplete.token(in: textView.string, caret: selection.location) : nil
            parent.onToken(token)
        }
    }
}
