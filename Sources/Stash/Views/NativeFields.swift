import AppKit
import SwiftUI

// MARK: - Rename field

/// A Finder-style rename box: takes the keyboard right away with the name selected.
/// Return saves, Esc cancels, clicking elsewhere saves.
struct RenameField: NSViewRepresentable {
    let initial: String
    var alignment: NSTextAlignment = .left
    var onChange: ((String) -> Void)? = nil
    /// On a selected (dark blue) row: the name box turns light gray with dark text, so it stands out from the bar.
    var onDark = false
    let commit: (String) -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FocusingField {
        let field = FocusingField(string: initial)
        field.font = .systemFont(ofSize: 12)
        field.alignment = alignment
        // No outline: a soft gray rounded box, the same for folders and files.
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 5
        field.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingMiddle
        field.onDark = onDark
        paint(field)
        return field
    }

    func updateNSView(_ field: FocusingField, context: Context) {
        guard field.onDark != onDark else { return }
        field.onDark = onDark
        paint(field)
    }

    private func paint(_ field: FocusingField) {
        field.textColor = onDark ? .black : .labelColor
        field.layer?.backgroundColor = (onDark ? NSColor(white: 0.95, alpha: 1) : NSColor.labelColor.withAlphaComponent(0.1)).cgColor
        // A thin darker edge, so the box stands apart from the bar behind it.
        field.layer?.borderWidth = onDark ? 1 : 0
        field.layer?.borderColor = NSColor(white: 0.62, alpha: 1).cgColor
        field.styleEditor()
    }

    final class FocusingField: NSTextField {
        var onDark = false

        /// The typing part: dark text and cursor in the gray box on a selected row.
        func styleEditor() {
            guard let editor = currentEditor() as? NSTextView else { return }
            editor.textColor = onDark ? .black : .labelColor
            editor.insertionPointColor = onDark ? .black : .labelColor
            editor.selectedTextAttributes = [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.3),
                                             .foregroundColor: onDark ? NSColor.black : NSColor.labelColor]
            editor.drawsBackground = false
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeKey()
                window.makeFirstResponder(self)
                // Select the name without its file type ("poster" of "poster.jpg"), like Finder.
                if let editor = self.currentEditor() {
                    self.styleEditor()
                    let text = self.stringValue as NSString
                    let ext = text.pathExtension
                    let length = ext.isEmpty ? text.length : text.length - ext.count - 1
                    editor.selectedRange = NSRange(location: 0, length: max(0, length))
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: RenameField
        private var done = false
        init(_ parent: RenameField) { self.parent = parent }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                done = true
                parent.cancel()
                return true
            }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                done = true
                parent.commit((control as? NSTextField)?.stringValue ?? "")
                return true
            }
            return false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.onChange?(field.stringValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard !done, let field = notification.object as? NSTextField else { return }
            done = true
            parent.commit(field.stringValue)
        }
    }
}
