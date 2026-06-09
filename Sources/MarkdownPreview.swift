import AppKit
import SwiftUI

// MARK: - Public preview view

struct MarkdownPreviewView: View {
    let markdown: String
    let isOutlineVisible: Bool

    @State private var selectedOutlineItemID: Int?

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(markdown)
    }

    private func outlineItems(for blocks: [MarkdownBlock]) -> [MarkdownOutlineItem] {
        var headingIndex = 0
        return blocks.compactMap { block in
            if case let .heading(level, text) = block.kind {
                let item = MarkdownOutlineItem(id: headingIndex, level: level, title: text)
                headingIndex += 1
                return item
            } else {
                return nil
            }
        }
    }

    var body: some View {
        let currentBlocks = blocks
        let currentOutlineItems = outlineItems(for: currentBlocks)

        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 24) {
                SelectableMarkdownTextView(
                    blocks: currentBlocks,
                    selectedOutlineItemID: selectedOutlineItemID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isOutlineVisible, !currentOutlineItems.isEmpty {
                    MarkdownOutlineView(items: currentOutlineItems) { item in
                        selectedOutlineItemID = item.id
                    }
                    .frame(width: 184)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: isOutlineVisible ? 1080 : 860, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 52)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Outline

private struct MarkdownOutlineItem: Identifiable {
    let id: Int
    let level: Int
    let title: String
}

private struct MarkdownOutlineView: View {
    let items: [MarkdownOutlineItem]
    let onSelect: (MarkdownOutlineItem) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("大纲")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    Text(item.title)
                        .font(.system(size: outlineFontSize(for: item.level), weight: item.level <= 2 ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, CGFloat(max(item.level - 1, 0)) * 8)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    private func outlineFontSize(for level: Int) -> CGFloat {
        level <= 2 ? 12 : 11
    }
}

// MARK: - Selectable text view (TextKit)

private struct SelectableMarkdownTextView: NSViewRepresentable {
    let blocks: [MarkdownBlock]
    let selectedOutlineItemID: Int?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = CopyableCodeTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        applyContent(to: textView, context: context)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        applyContent(to: textView, context: context)
        context.coordinator.scrollToHeadingIfNeeded(selectedOutlineItemID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func applyContent(to textView: CopyableCodeTextView, context: Context) {
        let rendered = MarkdownAttributedRenderer.render(blocks)
        guard context.coordinator.lastRenderedText != rendered.string else { return }

        textView.textStorage?.setAttributedString(rendered.attributedString)
        textView.codeBlocks = rendered.codeBlocks
        textView.needsDisplay = true
        context.coordinator.lastRenderedText = rendered.string
        context.coordinator.headingRanges = rendered.headingRanges
    }

    final class Coordinator {
        weak var textView: CopyableCodeTextView?
        var lastRenderedText = ""
        var headingRanges: [Int: NSRange] = [:]
        private var lastScrolledHeadingID: Int?

        @MainActor
        func scrollToHeadingIfNeeded(_ headingID: Int?) {
            guard
                let headingID,
                headingID != lastScrolledHeadingID,
                let textView,
                let range = headingRanges[headingID]
            else {
                return
            }

            lastScrolledHeadingID = headingID
            textView.scrollRangeToVisible(range)
            textView.setSelectedRange(NSRange(location: range.location, length: 0))
        }
    }
}

// MARK: - Code block range model

struct MarkdownCodeRange {
    let range: NSRange
    let code: String
}

// MARK: - Custom text view (continuous code background + copy button)

private final class CopyableCodeTextView: NSTextView {
    var codeBlocks: [MarkdownCodeRange] = [] {
        didSet { needsDisplay = true }
    }

    private let copyButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var hoveredCode: String?

    private static let blockInsetX: CGFloat = 6

    override convenience init(frame frameRect: NSRect) {
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        self.init(frame: frameRect, textContainer: container)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configureCopyButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCopyButton()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCodeBackgrounds()
        super.draw(dirtyRect)
    }

    private func drawCodeBackgrounds() {
        for block in codeBlocks {
            guard let rect = backgroundRect(for: block.range) else { continue }
            let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
            MarkdownStyle.codeBackground.setFill()
            path.fill()
            MarkdownStyle.codeBorder.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func backgroundRect(for range: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let origin = textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y

        // The vertical padding is baked into the code block as real blank lines
        // (see appendCodeBlock), so the background hugs the glyph bounds exactly and
        // can never overlap the following paragraph.
        let width = max(bounds.width - Self.blockInsetX * 2, 80)
        return NSRect(
            x: Self.blockInsetX,
            y: rect.minY,
            width: width,
            height: rect.height
        )
    }

    // MARK: Copy button

    private func configureCopyButton() {
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制代码")
        copyButton.imagePosition = .imageOnly
        copyButton.isBordered = false
        copyButton.bezelStyle = .regularSquare
        copyButton.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        copyButton.wantsLayer = true
        copyButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        copyButton.layer?.cornerRadius = 5
        copyButton.frame = NSRect(x: 0, y: 0, width: 24, height: 18)
        copyButton.target = self
        copyButton.action = #selector(copyHoveredCode)
        copyButton.isHidden = true
        copyButton.toolTip = "复制代码"
        addSubview(copyButton)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        updateCopyButton(for: point)
        updateCursor(for: point)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideCopyButton()
    }

    private func updateCopyButton(for point: NSPoint) {
        guard let characterIndex = characterIndex(at: point),
              let block = codeBlocks.first(where: { NSLocationInRange(characterIndex, $0.range) }),
              let rect = backgroundRect(for: block.range) else {
            hideCopyButton()
            return
        }

        hoveredCode = block.code
        copyButton.frame.origin = NSPoint(x: rect.maxX - copyButton.frame.width - 8, y: rect.minY + 1)
        copyButton.isHidden = false
    }

    private func hideCopyButton() {
        hoveredCode = nil
        copyButton.isHidden = true
    }

    @objc private func copyHoveredCode() {
        guard let hoveredCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hoveredCode, forType: .string)
    }

    // MARK: Cursor / hit testing

    private func updateCursor(for point: NSPoint) {
        guard
            let characterIndex = characterIndex(at: point),
            let textStorage,
            characterIndex < textStorage.length
        else {
            NSCursor.iBeam.set()
            return
        }

        if textStorage.attribute(.link, at: characterIndex, effectiveRange: nil) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    private func characterIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }
}

// MARK: - Attributed renderer

@MainActor
private enum MarkdownAttributedRenderer {
    static func render(_ blocks: [MarkdownBlock]) -> (
        attributedString: NSAttributedString,
        headingRanges: [Int: NSRange],
        codeBlocks: [MarkdownCodeRange],
        string: String
    ) {
        let result = NSMutableAttributedString()
        var headingRanges: [Int: NSRange] = [:]
        var codeBlocks: [MarkdownCodeRange] = []
        var headingIndex = 0

        for block in blocks {
            switch block.kind {
            case let .heading(level, text):
                appendSpacingIfNeeded(to: result, lines: level <= 1 ? 1 : 2)
                let start = result.length
                result.append(inlineAttributedString(
                    text,
                    font: headingFont(for: level),
                    color: .labelColor,
                    paragraphStyle: paragraphStyle(lineSpacing: 3, paragraphSpacing: 8)
                ))
                headingRanges[headingIndex] = NSRange(location: start, length: max(result.length - start, 1))
                headingIndex += 1
                result.append(NSAttributedString(string: "\n\n"))

            case let .paragraph(text):
                result.append(inlineAttributedString(
                    text,
                    font: MarkdownStyle.bodyFont,
                    color: MarkdownStyle.bodyText,
                    paragraphStyle: paragraphStyle(lineSpacing: 9, paragraphSpacing: 10)
                ))
                result.append(NSAttributedString(string: "\n\n"))

            case let .unorderedList(items):
                appendList(items, ordered: false, to: result)

            case let .orderedList(items):
                appendList(items, ordered: true, to: result)

            case let .codeBlock(code, language):
                appendSpacingIfNeeded(to: result, lines: 1)
                appendCodeBlock(code: code, language: language, to: result, codeBlocks: &codeBlocks)
                appendCodeBlockTrailingSpacing(to: result)
            }
        }

        while result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        return (result, headingRanges, codeBlocks, result.string)
    }

    private static func appendCodeBlock(
        code: String,
        language: String?,
        to result: NSMutableAttributedString,
        codeBlocks: inout [MarkdownCodeRange]
    ) {
        let content = code.isEmpty ? " " : code
        let style = paragraphStyle(lineSpacing: 5, paragraphSpacing: 0, lineBreakMode: .byCharWrapping)
        style.firstLineHeadIndent = 18
        style.headIndent = 18
        style.tailIndent = -18

        let start = result.length

        // Top padding rendered as an empty line whose height is fixed; it is part of
        // the highlighted range so the dark background hugs it exactly.
        result.append(NSAttributedString(
            string: "\n",
            attributes: [.font: MarkdownStyle.codeFont, .paragraphStyle: padLineStyle(height: MarkdownStyle.codePadTop)]
        ))

        result.append(CodeHighlighter.attributed(
            for: content,
            language: language,
            font: MarkdownStyle.codeFont,
            baseColor: MarkdownStyle.codeText,
            paragraphStyle: style
        ))

        // Bottom padding: terminate the last code line, then a fixed-height blank line.
        result.append(NSAttributedString(string: "\n", attributes: [.font: MarkdownStyle.codeFont, .paragraphStyle: style]))
        result.append(NSAttributedString(
            string: " ",
            attributes: [.font: MarkdownStyle.codeFont, .paragraphStyle: padLineStyle(height: MarkdownStyle.codePadBottom)]
        ))

        let range = NSRange(location: start, length: max(result.length - start, 1))
        codeBlocks.append(MarkdownCodeRange(range: range, code: code))
    }

    private static func padLineStyle(height: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        return style
    }

    private static func appendCodeBlockTrailingSpacing(to result: NSMutableAttributedString) {
        result.append(NSAttributedString(string: "\n\n"))
    }

    private static func appendList(_ items: [String], ordered: Bool, to result: NSMutableAttributedString) {
        let style = paragraphStyle(lineSpacing: 7, paragraphSpacing: 8, headIndent: 26)
        for (index, item) in items.enumerated() {
            let marker = ordered ? "\(index + 1). " : "•  "
            result.append(NSAttributedString(
                string: marker,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: MarkdownStyle.listMarker,
                    .paragraphStyle: style
                ]
            ))
            result.append(inlineAttributedString(
                item,
                font: MarkdownStyle.bodyFont,
                color: MarkdownStyle.bodyText,
                paragraphStyle: style
            ))
            result.append(NSAttributedString(string: index == items.count - 1 ? "\n" : "\n"))
        }
        result.append(NSAttributedString(string: "\n"))
    }

    private static func inlineAttributedString(
        _ markdown: String,
        font: NSFont,
        color: NSColor,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        guard let attributed = try? NSMutableAttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace),
            baseURL: nil
        ) else {
            return NSAttributedString(string: markdown, attributes: baseAttributes)
        }

        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.addAttributes(baseAttributes, range: fullRange)

        attributed.enumerateAttribute(.inlinePresentationIntent, in: fullRange) { value, range, _ in
            guard let raw = value as? Int else { return }
            let intent = InlinePresentationIntent(rawValue: UInt(raw))

            if intent.contains(.code) {
                let monoSize = max(font.pointSize - 1.5, 11)
                attributed.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: monoSize, weight: .regular),
                    .foregroundColor: MarkdownStyle.inlineCodeText,
                    .backgroundColor: MarkdownStyle.inlineCodeBackground
                ], range: range)
                return
            }

            var traits: NSFontTraitMask = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
            if !traits.isEmpty {
                let styled = NSFontManager.shared.convert(font, toHaveTrait: traits)
                attributed.addAttribute(.font, value: styled, range: range)
            }
        }

        return attributed
    }

    private static func headingFont(for level: Int) -> NSFont {
        switch level {
        case 1:
            .systemFont(ofSize: 28, weight: .bold)
        case 2:
            .systemFont(ofSize: 23, weight: .bold)
        case 3:
            .systemFont(ofSize: 19, weight: .semibold)
        case 4:
            .systemFont(ofSize: 16, weight: .semibold)
        default:
            .systemFont(ofSize: 15, weight: .semibold)
        }
    }

    private static func paragraphStyle(
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        headIndent: CGFloat = 0,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.headIndent = headIndent
        style.firstLineHeadIndent = 0
        style.lineBreakMode = lineBreakMode
        return style
    }

    private static func appendSpacingIfNeeded(to result: NSMutableAttributedString, lines: Int) {
        guard result.length > 0 else { return }
        result.append(NSAttributedString(string: String(repeating: "\n", count: lines)))
    }
}

// MARK: - Style palette

@MainActor
private enum MarkdownStyle {
    static let bodyFont = NSFont.systemFont(ofSize: 15)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    // Inner vertical padding of a code block, rendered as real blank lines.
    static let codePadTop: CGFloat = 20
    static let codePadBottom: CGFloat = 16

    static let bodyText = dynamic(light: 0x3A3D44, dark: 0xCBD0D8)
    static let listMarker = dynamic(light: 0x4C6F9B, dark: 0x8FB3DE)

    // Code blocks always render on a dark panel for a consistent, premium look.
    static let codeBackground = NSColor(srgbRed: 0.145, green: 0.157, blue: 0.176, alpha: 1)
    static let codeBorder = NSColor.white.withAlphaComponent(0.09)
    static let codeText = NSColor(srgbRed: 0.89, green: 0.91, blue: 0.93, alpha: 1)

    static let inlineCodeText = dynamic(light: 0xB5446E, dark: 0xF2A6C2)
    static let inlineCodeBackground = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.06)
    }

    static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.isDark ? rgb(dark) : rgb(light)
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
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: - Syntax highlighting

@MainActor
private enum CodeHighlighter {
    @MainActor
    enum Palette {
        static let comment = MarkdownStyle.rgb(0x7E8794)
        static let keyword = MarkdownStyle.rgb(0xC792EA)
        static let type = MarkdownStyle.rgb(0xFFCB6B)
        static let function = MarkdownStyle.rgb(0x82AAFF)
        static let string = MarkdownStyle.rgb(0xC3E88D)
        static let number = MarkdownStyle.rgb(0xF78C6C)
        static let constant = MarkdownStyle.rgb(0xF78C6C)
        static let variable = MarkdownStyle.rgb(0xF7C873)
        static let command = MarkdownStyle.rgb(0xE89A63)
        static let property = MarkdownStyle.rgb(0x82AAFF)
    }

    private enum Family {
        case code
        case shell
        case json
        case plain
    }

    static func attributed(
        for code: String,
        language: String?,
        font: NSFont,
        baseColor: NSColor,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: font,
                .foregroundColor: baseColor,
                .paragraphStyle: paragraphStyle
            ]
        )
        let full = NSRange(location: 0, length: (code as NSString).length)

        switch family(for: language) {
        case .plain:
            break
        case .code:
            highlightCode(result, range: full)
        case .shell:
            highlightShell(result, range: full)
        case .json:
            highlightJSON(result, range: full)
        }

        return result
    }

    private static func family(for language: String?) -> Family {
        switch (language ?? "").lowercased() {
        case "", "text", "txt", "plain", "md", "markdown", "mdx", "log", "diff":
            return .plain
        case "sh", "bash", "shell", "zsh", "console", "shellsession", "ps1", "powershell":
            return .shell
        case "json", "jsonc", "json5":
            return .json
        default:
            return .code
        }
    }

    private static func apply(
        _ pattern: String,
        options: NSRegularExpression.Options = [],
        group: Int = 0,
        color: NSColor,
        to string: NSMutableAttributedString,
        range: NSRange
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        regex.enumerateMatches(in: string.string, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges > group else { return }
            let r = match.range(at: group)
            if r.location != NSNotFound, r.length > 0 {
                string.addAttribute(.foregroundColor, value: color, range: r)
            }
        }
    }

    private static func highlightCode(_ s: NSMutableAttributedString, range: NSRange) {
        // Order matters: later passes override earlier ones.
        apply("\\b[A-Z][A-Za-z0-9_]*\\b", color: Palette.type, to: s, range: range)
        apply("\\b([A-Za-z_][A-Za-z0-9_]*)\\s*(?=\\()", group: 1, color: Palette.function, to: s, range: range)

        let keywords = [
            "const", "let", "var", "function", "return", "async", "await", "import", "export",
            "from", "default", "class", "extends", "implements", "interface", "type", "enum",
            "new", "typeof", "instanceof", "in", "of", "if", "else", "for", "while", "do",
            "switch", "case", "break", "continue", "try", "catch", "finally", "throw", "void",
            "yield", "public", "private", "protected", "readonly", "static", "get", "set",
            "super", "this", "as", "namespace", "declare", "abstract", "is", "keyof", "infer",
            "func", "struct", "guard", "defer", "where", "init", "self", "weak", "lazy",
            "fileprivate", "internal", "open", "def", "elif", "except", "with", "lambda",
            "pass", "raise", "and", "or", "not", "package", "select", "chan", "go", "fn",
            "impl", "match", "mut", "use", "pub", "let", "override", "final", "throws"
        ]
        apply("\\b(?:" + keywords.joined(separator: "|") + ")\\b", color: Palette.keyword, to: s, range: range)
        apply("\\b(?:true|false|null|nil|undefined|None|True|False|NaN|Infinity)\\b", color: Palette.constant, to: s, range: range)
        apply("\\b\\d[\\d_]*(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b", color: Palette.number, to: s, range: range)

        apply("\"(?:[^\"\\\\]|\\\\.)*\"", color: Palette.string, to: s, range: range)
        apply("'(?:[^'\\\\]|\\\\.)*'", color: Palette.string, to: s, range: range)
        apply("`(?:[^`\\\\]|\\\\.)*`", color: Palette.string, to: s, range: range)

        apply("//[^\\n]*", color: Palette.comment, to: s, range: range)
        apply("/\\*[\\s\\S]*?\\*/", color: Palette.comment, to: s, range: range)
    }

    private static func highlightShell(_ s: NSMutableAttributedString, range: NSRange) {
        apply("(?m)^\\s*([A-Za-z_][\\w./-]*)", group: 1, color: Palette.command, to: s, range: range)
        apply("(?<=\\s)(--?[A-Za-z][\\w-]*)", group: 1, color: Palette.number, to: s, range: range)
        apply("\\$\\w+|\\$\\{[^}]+\\}", color: Palette.variable, to: s, range: range)
        apply("\"(?:[^\"\\\\]|\\\\.)*\"", color: Palette.string, to: s, range: range)
        apply("'[^']*'", color: Palette.string, to: s, range: range)
        apply("(?m)(?:^|\\s)(#.*)$", group: 1, color: Palette.comment, to: s, range: range)
    }

    private static func highlightJSON(_ s: NSMutableAttributedString, range: NSRange) {
        apply("-?\\b\\d[\\d.eE+-]*\\b", color: Palette.number, to: s, range: range)
        apply("\\b(?:true|false|null)\\b", color: Palette.constant, to: s, range: range)
        apply("\"(?:[^\"\\\\]|\\\\.)*\"", color: Palette.string, to: s, range: range)
        apply("\"(?:[^\"\\\\]|\\\\.)*\"(?=\\s*:)", color: Palette.property, to: s, range: range)
        apply("//[^\\n]*", color: Palette.comment, to: s, range: range)
    }
}

// MARK: - Block model

struct MarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([String])
        case codeBlock(code: String, language: String?)
    }
}

// MARK: - Block parser

enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var unorderedItems: [String] = []
        var orderedItems: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var fenceDepth = 0

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(MarkdownBlock(kind: .paragraph(paragraphLines.joined(separator: "\n"))))
            paragraphLines.removeAll()
        }

        func flushUnorderedList() {
            guard !unorderedItems.isEmpty else { return }
            blocks.append(MarkdownBlock(kind: .unorderedList(unorderedItems)))
            unorderedItems.removeAll()
        }

        func flushOrderedList() {
            guard !orderedItems.isEmpty else { return }
            blocks.append(MarkdownBlock(kind: .orderedList(orderedItems)))
            orderedItems.removeAll()
        }

        func flushOpenBlocks() {
            flushParagraph()
            flushUnorderedList()
            flushOrderedList()
        }

        func flushCodeBlock() {
            blocks.append(MarkdownBlock(kind: .codeBlock(code: codeLines.joined(separator: "\n"), language: codeLanguage)))
            codeLines.removeAll()
            codeLanguage = nil
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Inside a fenced code block. Nested fences with an info string open a
            // deeper level (kept as literal content); a bare fence closes one level.
            // This keeps blocks that embed example fences (e.g. a ```md block that
            // contains a ```text block) intact instead of splitting them.
            if fenceDepth > 0 {
                if let fence = fenceInfo(trimmed) {
                    if fence.hasInfo {
                        fenceDepth += 1
                        codeLines.append(line)
                    } else {
                        fenceDepth -= 1
                        if fenceDepth == 0 {
                            flushCodeBlock()
                        } else {
                            codeLines.append(line)
                        }
                    }
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if let fence = fenceInfo(trimmed) {
                flushOpenBlocks()
                fenceDepth = 1
                codeLanguage = fence.hasInfo ? fence.info : nil
                continue
            }

            if trimmed.isEmpty {
                flushOpenBlocks()
                continue
            }

            if let heading = heading(from: trimmed) {
                flushOpenBlocks()
                blocks.append(MarkdownBlock(kind: .heading(level: heading.level, text: heading.text)))
                continue
            }

            if let item = unorderedListItem(from: trimmed) {
                flushParagraph()
                flushOrderedList()
                unorderedItems.append(item)
                continue
            }

            if let item = orderedListItem(from: trimmed) {
                flushParagraph()
                flushUnorderedList()
                orderedItems.append(item)
                continue
            }

            flushUnorderedList()
            flushOrderedList()
            paragraphLines.append(line)
        }

        if fenceDepth > 0 {
            flushCodeBlock()
        }
        flushOpenBlocks()

        return blocks
    }

    private static func fenceInfo(_ line: String) -> (info: String, hasInfo: Bool)? {
        guard line.hasPrefix("```") else {
            return nil
        }
        let info = line.drop { $0 == "`" }.trimmingCharacters(in: .whitespaces)
        let firstToken = info.split(separator: " ").first.map(String.init) ?? ""
        return (firstToken, !firstToken.isEmpty)
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else {
            return nil
        }

        let markers = line.prefix { $0 == "#" }
        guard (1...6).contains(markers.count) else {
            return nil
        }

        let remainder = line.dropFirst(markers.count)
        guard remainder.first == " " else {
            return nil
        }

        let text = remainder.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (markers.count, text)
    }

    private static func unorderedListItem(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            let item = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
        return nil
    }

    private static func orderedListItem(from line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else {
            return nil
        }

        let number = line[..<dotIndex]
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else {
            return nil
        }

        let afterDot = line[line.index(after: dotIndex)...]
        guard afterDot.first == " " else {
            return nil
        }

        let item = afterDot.dropFirst().trimmingCharacters(in: .whitespaces)
        return item.isEmpty ? nil : item
    }
}
