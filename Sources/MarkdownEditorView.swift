import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var autoFocus: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = NSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.insertionPointColor = MarkdownEditorTheme.caret
        textView.typingAttributes = MarkdownEditorHighlighter.baseAttributes

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.apply(text, to: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        textView.isEditable = isEditable
        if textView.string != text {
            context.coordinator.apply(text, to: textView)
        } else {
            context.coordinator.highlight(textView)
        }

        if autoFocus, context.coordinator.hasAutoFocused == false {
            context.coordinator.hasAutoFocused = true
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?
        var hasAutoFocused = false
        private var isApplying = false

        init(text: Binding<String>) {
            _text = text
        }

        func apply(_ text: String, to textView: NSTextView) {
            isApplying = true
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(NSAttributedString(string: text))
            highlight(textView)
            textView.setSelectedRange(NSRange(
                location: min(selectedRange.location, (text as NSString).length),
                length: min(selectedRange.length, max((text as NSString).length - selectedRange.location, 0))
            ))
            isApplying = false
        }

        func highlight(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            MarkdownEditorHighlighter.apply(to: textStorage)
            textView.typingAttributes = MarkdownEditorHighlighter.baseAttributes
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let textView = notification.object as? NSTextView else { return }
            text = textView.string
            highlight(textView)
        }
    }
}

@MainActor
private enum MarkdownEditorTheme {
    static let baseFont = bodyFont(size: 16, weight: .regular)
    static let headingFont = bodyFont(size: 18, weight: .bold)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)

    static let text = dynamic(light: 0x343840, dark: 0xD2D6DD)
    static let muted = dynamic(light: 0x7A828D, dark: 0x8F98A6)
    static let heading = dynamic(light: 0x2478B8, dark: 0x56A8F5)
    static let linkLabel = dynamic(light: 0xA8512B, dark: 0xE39A72)
    static let linkURL = dynamic(light: 0x3575A8, dark: 0x8FC4F4)
    static let code = dynamic(light: 0xA8512B, dark: 0xE6A17D)
    static let quote = dynamic(light: 0x47735C, dark: 0x73C596)
    static let emphasis = dynamic(light: 0x3A3D44, dark: 0xE3E6EA)
    static let caret = dynamic(light: 0x1E7FCA, dark: 0x65B9FF)
    static let inlineCodeBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.06)
    }

    static let keyword = dynamic(light: 0x8A4CC2, dark: 0xC792EA)
    static let string = dynamic(light: 0x3E7F40, dark: 0xC3E88D)
    static let number = dynamic(light: 0xB25538, dark: 0xF78C6C)
    static let command = dynamic(light: 0x8E5D1F, dark: 0xEBCB8B)

    static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light)
        }
    }

    static func rgb(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    static func bodyFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        let traits = descriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let symbolicTraits = (traits?[.symbolic] as? UInt32).map(NSFontDescriptor.SymbolicTraits.init(rawValue:)) ?? []
        let pingFangDescriptor = NSFontDescriptor(fontAttributes: [
            .family: "PingFang SC",
            .traits: [NSFontDescriptor.TraitKey.symbolic: symbolicTraits.rawValue]
        ])

        return NSFont(descriptor: pingFangDescriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

@MainActor
private enum MarkdownEditorHighlighter {
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: MarkdownEditorTheme.baseFont,
            .foregroundColor: MarkdownEditorTheme.text,
            .paragraphStyle: baseParagraphStyle()
        ]
    }

    static func apply(to textStorage: NSTextStorage) {
        let full = NSRange(location: 0, length: textStorage.length)
        guard full.length > 0 else { return }

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: full)

        let text = textStorage.string
        highlightFencedCode(in: textStorage, text: text)
        apply("(?m)^(#{1,6})(\\s+.*)$", to: textStorage) { match in
            let fullRange = match.range(at: 0)
            let markerRange = match.range(at: 1)
            textStorage.addAttributes([
                .font: MarkdownEditorTheme.headingFont,
                .foregroundColor: MarkdownEditorTheme.heading
            ], range: fullRange)
            textStorage.addAttributes([
                .foregroundColor: MarkdownEditorTheme.muted
            ], range: markerRange)
        }
        apply("(?m)^(> ?)(.*)$", to: textStorage) { match in
            textStorage.addAttributes([
                .foregroundColor: MarkdownEditorTheme.quote,
                .font: MarkdownEditorTheme.baseFont
            ], range: match.range(at: 1))
            textStorage.addAttributes([
                .foregroundColor: MarkdownEditorTheme.muted
            ], range: match.range(at: 2))
        }
        highlightInlineMarkdown(in: textStorage)
        textStorage.endEditing()
    }

    private static func highlightFencedCode(in textStorage: NSTextStorage, text: String) {
        apply("(?ms)^```([^\\n]*)\\n(.*?)^```", to: textStorage) { match in
            let fullRange = match.range(at: 0)
            let languageRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            textStorage.addAttributes([
                .font: MarkdownEditorTheme.codeFont,
                .foregroundColor: MarkdownEditorTheme.code
            ], range: fullRange)
            if languageRange.location != NSNotFound {
                textStorage.addAttributes([.foregroundColor: MarkdownEditorTheme.linkURL], range: languageRange)
            }
            if codeRange.location != NSNotFound {
                highlightCodeTokens(in: textStorage, range: codeRange)
            }
        }
    }

    private static func highlightInlineMarkdown(in textStorage: NSTextStorage) {
        apply("\\[([^\\]]+)\\]\\(([^\\)]+)\\)", to: textStorage) { match in
            textStorage.addAttributes([.foregroundColor: MarkdownEditorTheme.muted], range: match.range(at: 0))
            textStorage.addAttributes([.foregroundColor: MarkdownEditorTheme.linkLabel], range: match.range(at: 1))
            textStorage.addAttributes([
                .foregroundColor: MarkdownEditorTheme.linkURL,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: match.range(at: 2))
        }
        apply("`([^`\\n]+)`", to: textStorage) { match in
            textStorage.addAttributes([
                .foregroundColor: MarkdownEditorTheme.code,
                .backgroundColor: MarkdownEditorTheme.inlineCodeBackground
            ], range: match.range(at: 0))
        }
        apply("\\*\\*([^*]+)\\*\\*", to: textStorage) { match in
            textStorage.addAttributes([
                .font: MarkdownEditorTheme.bodyFont(size: 16, weight: .bold),
                .foregroundColor: MarkdownEditorTheme.emphasis
            ], range: match.range(at: 0))
        }
        apply("(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)", to: textStorage) { match in
            textStorage.addAttributes([
                .font: NSFontManager.shared.convert(MarkdownEditorTheme.baseFont, toHaveTrait: .italicFontMask),
                .foregroundColor: MarkdownEditorTheme.emphasis
            ], range: match.range(at: 0))
        }
    }

    private static func highlightCodeTokens(in textStorage: NSTextStorage, range: NSRange) {
        apply("\\b(?:const|let|var|function|return|async|await|import|export|from|class|type|interface|extends|if|else|for|while|switch|case|break|continue|try|catch|throw|new|func|struct|guard|where|init)\\b", to: textStorage, range: range) { match in
            textStorage.addAttributes([.foregroundColor: MarkdownEditorTheme.keyword], range: match.range(at: 0))
        }
        apply("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'", to: textStorage, range: range) { match in
            textStorage.addAttributes([.foregroundColor: MarkdownEditorTheme.string], range: match.range(at: 0))
        }
        apply("\\b\\d[\\d_]*(?:\\.\\d+)?\\b", to: textStorage, range: range) { match in
            textStorage.addAttributes([.foregroundColor: MarkdownEditorTheme.number], range: match.range(at: 0))
        }
        apply("(?m)^\\s*([A-Za-z_][\\w./-]*)", to: textStorage, range: range) { match in
            let commandRange = match.range(at: 1)
            guard commandRange.location != NSNotFound else { return }
            textStorage.addAttributes([.foregroundColor: MarkdownEditorTheme.command], range: commandRange)
        }
    }

    private static func apply(
        _ pattern: String,
        to textStorage: NSTextStorage,
        range: NSRange? = nil,
        handler: (NSTextCheckingResult) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let searchRange = range ?? NSRange(location: 0, length: textStorage.length)
        regex.enumerateMatches(in: textStorage.string, options: [], range: searchRange) { match, _, _ in
            guard let match else { return }
            handler(match)
        }
    }

    private static func baseParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = 3
        return style
    }
}
