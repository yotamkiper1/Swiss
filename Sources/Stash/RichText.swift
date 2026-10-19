import AppKit
import SwiftUI

// MARK: - The text view

/// Talks to the note's text view: the toolbar's buttons call these.
@MainActor
final class RichTextController: ObservableObject {
    weak var textView: NSTextView? { didSet { RichTextController.current = self } }
    /// The editor that's open (for test runs).
    static weak var current: RichTextController?
    @Published var fontFamily = "System"
    @Published var fontSize: CGFloat = 14

    nonisolated static let defaultFont = NSFont.systemFont(ofSize: 14)

    /// Sets an attribute on the selection, or on what you type next if nothing's selected.
    private func changeFonts(_ change: (NSFont) -> NSFont) {
        guard let textView, let storage = textView.textStorage else { return }
        let ranges = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        if ranges.isEmpty {
            let font = (textView.typingAttributes[.font] as? NSFont) ?? Self.defaultFont
            textView.typingAttributes[.font] = change(font)
        } else {
            storage.beginEditing()
            for range in ranges {
                storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                    storage.addAttribute(.font, value: change((value as? NSFont) ?? Self.defaultFont), range: sub)
                }
            }
            storage.endEditing()
            textView.didChangeText()
        }
        refresh()
    }

    func setFamily(_ family: String) {
        changeFonts { font in
            if family == "System" { return NSFont.systemFont(ofSize: font.pointSize) }
            return NSFontManager.shared.convert(font, toFamily: family)
        }
    }

    func setSize(_ size: CGFloat) {
        changeFonts { NSFontManager.shared.convert($0, toSize: max(6, min(size, 120))) }
    }

    func toggle(_ trait: NSFontTraitMask) {
        let current = (textView?.typingAttributes[.font] as? NSFont) ?? Self.defaultFont
        let has = NSFontManager.shared.traits(of: current).contains(trait)
        changeFonts { font in
            has ? NSFontManager.shared.convert(font, toNotHaveTrait: trait) : NSFontManager.shared.convert(font, toHaveTrait: trait)
        }
    }

    func toggleUnderline() {
        guard let textView, let storage = textView.textStorage else { return }
        let ranges = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        if ranges.isEmpty {
            let on = (textView.typingAttributes[.underlineStyle] as? Int ?? 0) != 0
            textView.typingAttributes[.underlineStyle] = on ? 0 : NSUnderlineStyle.single.rawValue
            return
        }
        let on = (storage.attribute(.underlineStyle, at: ranges[0].location, effectiveRange: nil) as? Int ?? 0) != 0
        for range in ranges {
            storage.addAttribute(.underlineStyle, value: on ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        }
        textView.didChangeText()
    }

    func setColor(_ color: NSColor?) {
        guard let textView, let storage = textView.textStorage else { return }
        let ranges = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        if ranges.isEmpty {
            if let color { textView.typingAttributes[.foregroundColor] = color } else { textView.typingAttributes.removeValue(forKey: .foregroundColor) }
            return
        }
        for range in ranges {
            if let color { storage.addAttribute(.foregroundColor, value: color, range: range) } else { storage.removeAttribute(.foregroundColor, range: range) }
        }
        textView.didChangeText()
    }

    /// 1.0, 1.15, 1.5, 2.0… for the paragraphs you're in.
    func setLineSpacing(_ multiple: CGFloat) {
        guard let textView, let storage = textView.textStorage else { return }
        let ranges = (textView.rangesForUserParagraphAttributeChange ?? [NSValue(range: textView.selectedRange())]).map(\.rangeValue)
        storage.beginEditing()
        for range in ranges {
            let paragraphs = (storage.string as NSString).paragraphRange(for: range)
            let style = ((storage.attribute(.paragraphStyle, at: min(paragraphs.location, max(storage.length - 1, 0)), effectiveRange: nil) as? NSParagraphStyle)
                ?? .default).mutableCopy() as! NSMutableParagraphStyle
            style.lineHeightMultiple = multiple
            if paragraphs.length > 0 { storage.addAttribute(.paragraphStyle, value: style, range: paragraphs) }
        }
        storage.endEditing()
        let typing = ((textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle) ?? .default).mutableCopy() as! NSMutableParagraphStyle
        typing.lineHeightMultiple = multiple
        textView.typingAttributes[.paragraphStyle] = typing
        textView.didChangeText()
    }

    /// Quick paragraph styles: a big bold title, a subtitle, or back to normal text.
    enum TextStyle: String, CaseIterable {
        case title = "Title", subtitle = "Subtitle", body = "Body"
        var font: NSFont {
            switch self {
            case .title: NSFont.systemFont(ofSize: 22, weight: .bold)
            case .subtitle: NSFont.systemFont(ofSize: 16, weight: .semibold)
            case .body: RichTextController.defaultFont
            }
        }
    }

    /// The lines you're on become a title, a subtitle or normal text (and so does what you type next).
    func setStyle(_ style: TextStyle) {
        guard let textView, let storage = textView.textStorage else { return }
        let paragraphs = (storage.string as NSString).paragraphRange(for: textView.selectedRange())
        if paragraphs.length > 0 {
            storage.beginEditing()
            storage.addAttribute(.font, value: style.font, range: paragraphs)
            storage.endEditing()
            textView.didChangeText()
        }
        textView.typingAttributes[.font] = style.font
        refresh()
    }

    enum ListStyle: String, CaseIterable {
        case dash = "– ", bullet = "• ", number = "1. "
        func marker(_ n: Int) -> String { self == .number ? "\(n). " : rawValue }
        static func detect(_ line: String) -> (ListStyle, Int)? {
            if line.hasPrefix(ListStyle.dash.rawValue) { return (.dash, 0) }
            if line.hasPrefix(ListStyle.bullet.rawValue) { return (.bullet, 0) }
            let digits = line.prefix { $0.isNumber }
            if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". "), let n = Int(digits) { return (.number, n) }
            return nil
        }
    }

    /// Turns the lines you're on into a list (or back into plain lines).
    func toggleList(_ style: ListStyle) {
        guard let textView, let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let paragraphs = text.paragraphRange(for: textView.selectedRange())
        var lines: [NSRange] = []
        text.enumerateSubstrings(in: paragraphs, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in lines.append(range) }
        if lines.isEmpty { lines = [NSRange(location: paragraphs.location, length: 0)] }
        let allHaveIt = lines.allSatisfy { ListStyle.detect(text.substring(with: $0))?.0 == style }
        storage.beginEditing()
        var n = lines.count
        for range in lines.reversed() { // back to front, so earlier ranges stay valid
            let line = text.substring(with: range)
            if let (existing, number) = ListStyle.detect(line) {
                let length = existing == .number ? "\(number). ".count : existing.rawValue.count
                storage.deleteCharacters(in: NSRange(location: range.location, length: length))
            }
            if !allHaveIt {
                let attrs = range.length > 0 ? storage.attributes(at: range.location, effectiveRange: nil) : textView.typingAttributes
                storage.insert(NSAttributedString(string: style.marker(n), attributes: attrs), at: range.location)
            }
            n -= 1
        }
        storage.endEditing()
        textView.didChangeText()
    }

    /// Puts an emoji where you're typing.
    func insert(_ text: String) {
        guard let textView, let storage = textView.textStorage else { return }
        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: textView.typingAttributes))
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
    }

    /// The Mac's full emoji picker, typing into the note.
    func showEmojiPicker() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        NSApp.orderFrontCharacterPalette(textView)
    }

    func refresh() {
        let font = (textView?.typingAttributes[.font] as? NSFont) ?? Self.defaultFont
        fontSize = font.pointSize
        fontFamily = font.familyName == NSFont.systemFont(ofSize: 12).familyName ? "System" : (font.familyName ?? "System")
    }
}

/// A rich text box (NSTextView) for notes.
struct RichTextView: NSViewRepresentable {
    @Binding var text: NSAttributedString
    let controller: RichTextController
    var autoFocus = true
    /// Return (without Shift): save the note.
    var onSubmit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let textView = scroll.documentView as! NSTextView
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = RichTextController.defaultFont
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(text)
        if let storage = textView.textStorage { Coordinator.alignByLanguage(storage, textView: textView) }
        textView.typingAttributes[.font] = RichTextController.defaultFont
        // Each paragraph runs the way its language does: Hebrew and Arabic start from the right.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .natural
        paragraph.baseWritingDirection = .natural
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        textView.baseWritingDirection = .natural
        controller.textView = textView
        if autoFocus {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {}

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: RichTextView
        init(_ parent: RichTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let storage = textView.textStorage else { return }
            Self.alignByLanguage(storage, textView: textView)
            parent.text = NSAttributedString(attributedString: storage)
        }

        /// Each paragraph runs the way its language does: one that starts in Hebrew or Arabic goes right-to-left,
        /// against the right edge — by itself, as you type (even in notes saved left-aligned before).
        static func alignByLanguage(_ storage: NSTextStorage, textView: NSTextView) {
            let text = storage.string as NSString
            var changed = false
            text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs]) { paragraph, range, enclosing, _ in
                guard let paragraph, enclosing.length > 0 else { return }
                let rtl = paragraph.isRightToLeft
                let current = storage.attribute(.paragraphStyle, at: enclosing.location, effectiveRange: nil) as? NSParagraphStyle ?? .default
                let wantDirection: NSWritingDirection = rtl ? .rightToLeft : .natural
                let wantAlignment: NSTextAlignment = rtl ? .right : .natural
                guard current.baseWritingDirection != wantDirection || current.alignment != wantAlignment else { return }
                let style = current.mutableCopy() as! NSMutableParagraphStyle
                style.baseWritingDirection = wantDirection
                style.alignment = wantAlignment
                storage.addAttribute(.paragraphStyle, value: style, range: enclosing)
                changed = true
            }
            // What you type next follows the paragraph you're in.
            let at = min(textView.selectedRange().location, max(0, storage.length - 1))
            if storage.length > 0, let style = storage.attribute(.paragraphStyle, at: at, effectiveRange: nil) {
                textView.typingAttributes[.paragraphStyle] = style
            }
            _ = changed
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            MainActor.assumeIsolated { parent.controller.refresh() }
        }

        /// Return saves the note. Shift+Return goes down a line — in a list it starts the next item,
        /// and on an empty item it ends the list.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)), let storage = textView.textStorage else { return false }
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            if !shift, let submit = parent.onSubmit {
                submit()
                return true
            }
            let text = storage.string as NSString
            let lineRange = text.lineRange(for: NSRange(location: textView.selectedRange().location, length: 0))
            let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
            guard let (style, number) = RichTextController.ListStyle.detect(line) else {
                textView.insertText("\n", replacementRange: textView.selectedRange())
                return true
            }
            let marker = style == .number ? "\(number). " : style.rawValue
            if line == marker.trimmingCharacters(in: .whitespaces) || line == marker {
                textView.insertText("", replacementRange: NSRange(location: lineRange.location, length: (line as NSString).length))
                return true
            }
            textView.insertText("\n" + style.marker(number + 1), replacementRange: textView.selectedRange())
            return true
        }
    }
}

// MARK: - Toolbar

/// Aa font and size · line spacing · color · B I U · lists.
struct RichTextToolbar: View {
    @ObservedObject var controller: RichTextController
    @State private var showingEmoji = false
    private static let families = ["System"] + NSFontManager.shared.availableFontFamilies.sorted()
    /// Quick emojis, by feel.
    static let emojiRows = ["😀😂🥹😍🤔😎😴😭", "👍👏🙏💪🔥✨⭐️❤️", "✅❌⚠️💡📌📎📷🎵", "🎨🖌️🎬🗂️📝📅⏰🚀"]
    private let sizes: [CGFloat] = [10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32, 40, 48]
    private let spacings: [CGFloat] = [1.0, 1.15, 1.5, 2.0, 2.5]
    private let colors: [(String, NSColor?)] = [
        ("Default", nil), ("Gray", .systemGray), ("Red", .systemRed), ("Orange", .systemOrange),
        ("Yellow", .systemYellow), ("Green", .systemGreen), ("Blue", .systemBlue), ("Purple", .systemPurple), ("Pink", .systemPink),
    ]

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(RichTextController.TextStyle.allCases, id: \.self) { style in
                    Button(style.rawValue) { controller.setStyle(style) }
                }
            } label: {
                Text("Title").font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Title, Subtitle or Body for the line you're on")
            divider
            Menu {
                ForEach(Self.families, id: \.self) { family in
                    Button {
                        controller.setFamily(family)
                    } label: {
                        if family == controller.fontFamily { Label(family, systemImage: "checkmark") } else { Text(family) }
                    }
                }
            } label: {
                Text("Aa").font(.system(size: 14, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Font: \(controller.fontFamily)")

            Menu {
                ForEach(sizes, id: \.self) { size in
                    Button("\(Int(size))") { controller.setSize(size) }
                }
            } label: {
                Text("\(Int(controller.fontSize))").font(.system(size: 13)).monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Size")

            divider
            tool("bold", "Bold") { controller.toggle(.boldFontMask) }
            tool("italic", "Italic") { controller.toggle(.italicFontMask) }
            tool("underline", "Underline") { controller.toggleUnderline() }
            divider

            Menu {
                ForEach(spacings, id: \.self) { spacing in
                    Button(String(format: spacing == 1.15 ? "%.2f" : "%.1f", spacing)) { controller.setLineSpacing(spacing) }
                }
            } label: {
                Image(systemName: "arrow.up.and.down.text.horizontal").font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Line spacing")

            Menu {
                ForEach(colors, id: \.0) { name, color in
                    Button {
                        controller.setColor(color)
                    } label: {
                        Label(name, systemImage: "circle.fill")
                    }
                }
            } label: {
                Image(systemName: "paintpalette").font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Text color")

            Button { showingEmoji.toggle() } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
            .help("Emoji")
            .popover(isPresented: $showingEmoji, arrowEdge: .bottom) { emojiGrid }

            divider
            tool("list.dash", "Dash list") { controller.toggleList(.dash) }
            tool("list.bullet", "Bullet list") { controller.toggleList(.bullet) }
            tool("list.number", "Numbered list") { controller.toggleList(.number) }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }

    /// A small grid of quick emojis, and the Mac's full picker.
    private var emojiGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 1), count: 8), spacing: 1) {
                ForEach(Array(Self.emojiRows.joined()), id: \.self) { emoji in
                    Button {
                        controller.insert(String(emoji))
                        showingEmoji = false
                    } label: {
                        Text(String(emoji)).font(.system(size: 14)).frame(width: 22, height: 22)
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            Divider()
            Button {
                showingEmoji = false
                controller.showEmojiPicker()
            } label: {
                Text("More…").font(.system(size: 10.5))
            }
            .buttonStyle(QuietButtonStyle())
            .foregroundStyle(.secondary)
        }
        .padding(6)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1, height: 17).padding(.horizontal, 3)
    }

    private func tool(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle())
        .help(help)
    }
}

// MARK: - Saving

extension NSAttributedString {
    var rtfData: Data? {
        try? data(from: NSRange(location: 0, length: length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    /// True if it has anything beyond plain text in the standard font.
    var hasFormatting: Bool {
        var formatted = false
        enumerateAttributes(in: NSRange(location: 0, length: length)) { attrs, _, stop in
            if let font = attrs[.font] as? NSFont, font != RichTextController.defaultFont { formatted = true }
            if attrs[.foregroundColor] != nil || (attrs[.underlineStyle] as? Int ?? 0) != 0 { formatted = true }
            if let style = attrs[.paragraphStyle] as? NSParagraphStyle, style.lineHeightMultiple != 0, style.lineHeightMultiple != 1 { formatted = true }
            if formatted { stop.pointee = true }
        }
        return formatted
    }
}

extension Item {
    /// The note as formatted text (plain notes come back in the standard font).
    var attributedText: NSAttributedString {
        if let data = richText, let rich = NSAttributedString(rtf: data, documentAttributes: nil) { return rich }
        return NSAttributedString(string: text ?? "", attributes: [.font: RichTextController.defaultFont])
    }
}

extension Store {
    /// Saves a note's formatted text, keeping a plain copy for search, tags and the card's title.
    func setNote(_ id: UUID, _ attributed: NSAttributedString) {
        let plain = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id) {
            $0.text = plain.isEmpty && $0.kind != .text ? nil : plain
            $0.richText = attributed.hasFormatting ? attributed.rtfData : nil
            $0.tags = Store.tags(in: plain)
        }
    }
}

/// The toolbar and the text box together, used for new notes and for editing.
struct RichNoteEditor: View {
    @Binding var text: NSAttributedString
    @StateObject private var controller = RichTextController()
    var placeholder = "Write a note…"
    /// Return saves; Shift+Return is a new line.
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Scrolls sideways if the window is too narrow for all the tools.
            ScrollView(.horizontal, showsIndicators: false) {
                RichTextToolbar(controller: controller).fixedSize()
            }
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
            ZStack(alignment: .topLeading) {
                if text.length == 0 {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                        .padding(.leading, 7)
                        .allowsHitTesting(false)
                }
                RichTextView(text: $text, controller: controller, onSubmit: onSubmit)
            }
        }
    }
}


extension String {
    /// True when the text starts in a right-to-left language (Hebrew, Arabic…), judged by its first letter.
    var isRightToLeft: Bool {
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return true // Hebrew, Arabic, Syriac, Thaana…
            default:
                if CharacterSet.letters.contains(scalar) { return false }
            }
        }
        return false
    }
}

extension View {
    /// Text that starts in Hebrew or Arabic starts from the right.
    @ViewBuilder func naturalDirection(_ text: String?) -> some View {
        if text?.isRightToLeft == true {
            self.multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
        } else {
            self
        }
    }
}
