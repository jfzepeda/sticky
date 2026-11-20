import AppKit
import StickyCore
import SwiftUI

/// Multi-line plain-text editor with list auto-formatting (`ListFormatting`):
/// "- " → "• ", "1 " → "1. ", Return continues the list, Return on an empty item ends it.
/// Wraps `NSTextView` because SwiftUI's `TextEditor` can't intercept keystrokes or place
/// the cursor on macOS 14. Edits go through `insertText` so ⌘Z undoes them.
struct ListTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var textColor: NSColor = .labelColor
    var autofocus = false

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.string = text
        apply(to: textView)

        if autofocus {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        apply(to: textView)
        context.coordinator.placeholder?.isHidden = !text.isEmpty
        if context.coordinator.placeholder == nil, !placeholder.isEmpty {
            context.coordinator.installPlaceholder(placeholder, in: textView)
        }
    }

    private func apply(to textView: NSTextView) {
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.typingAttributes = [.font: font, .foregroundColor: textColor]
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var placeholder: NSTextField?

        init(text: Binding<String>) { self.text = text }

        func installPlaceholder(_ string: String, in textView: NSTextView) {
            let label = NSTextField(labelWithString: string)
            label.font = textView.font
            label.textColor = .placeholderTextColor
            label.translatesAutoresizingMaskIntoConstraints = false
            textView.addSubview(label)
            let inset = textView.textContainerInset
            let padding = textView.textContainer?.lineFragmentPadding ?? 5
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: inset.width + padding),
                label.topAnchor.constraint(equalTo: textView.topAnchor, constant: inset.height),
            ])
            label.isHidden = !textView.string.isEmpty
            placeholder = label
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            placeholder?.isHidden = !textView.string.isEmpty
        }

        /// "- " / "1 " typed at a line start become list markers.
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            guard replacementString == " ", range.length == 0,
                  let prefix = linePrefix(in: textView, upTo: range.location),
                  let replacement = ListFormatting.replacementOnSpace(linePrefix: prefix.text)
            else { return true }
            textView.insertText(replacement, replacementRange: prefix.range)
            return false
        }

        /// Return continues the list, or ends it on an empty item.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let selection = textView.selectedRange()
            guard selection.length == 0,
                  let prefix = linePrefix(in: textView, upTo: selection.location)
            else { return false }
            switch ListFormatting.newlineAction(line: prefix.text) {
            case .plain:
                return false
            case .insert(let continuation):
                textView.insertText(continuation, replacementRange: selection)
            case .endList(let markerLength):
                textView.insertText("", replacementRange: NSRange(location: prefix.range.location,
                                                                  length: markerLength))
            }
            return true
        }

        /// The current line from its start up to `location`, with its range.
        private func linePrefix(in textView: NSTextView, upTo location: Int) -> (text: String, range: NSRange)? {
            let string = textView.string as NSString
            guard location <= string.length else { return nil }
            let lineStart = string.lineRange(for: NSRange(location: location, length: 0)).location
            let range = NSRange(location: lineStart, length: location - lineStart)
            return (string.substring(with: range), range)
        }
    }
}
