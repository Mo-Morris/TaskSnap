import AppKit
import SwiftUI

// MARK: - Image preview sheet

struct MarkdownPreviewImageItem: Identifiable {
    let id = UUID()
    let image: NSImage
    let title: String?
}

@MainActor
enum MarkdownImageZoomLayout {
    /// Inline preview: large enough to read, still smaller than the zoom sheet.
    static let inlineMaxWidth: CGFloat = 720
    static let sheetScreenCoverage: CGFloat = 0.92
    static let sheetHeaderHeight: CGFloat = 52
    static let sheetPadding: CGFloat = 32
    static let sheetMinimumSize = CGSize(width: 720, height: 540)

    static func sheetSize(for image: NSImage) -> CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let maxContentWidth = screen.width * sheetScreenCoverage - sheetPadding
        let maxContentHeight = screen.height * sheetScreenCoverage - sheetHeaderHeight - sheetPadding

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(
                width: max(sheetMinimumSize.width, screen.width * sheetScreenCoverage),
                height: max(sheetMinimumSize.height, screen.height * sheetScreenCoverage)
            )
        }

        let aspect = imageSize.width / imageSize.height
        var contentWidth = min(imageSize.width, maxContentWidth)
        var contentHeight = contentWidth / aspect

        if contentHeight > maxContentHeight {
            contentHeight = maxContentHeight
            contentWidth = contentHeight * aspect
        }

        // Upscale small images so the zoom sheet still feels like a real enlargement.
        let minZoomedEdge = min(560, min(maxContentWidth, maxContentHeight) * 0.65)
        if max(contentWidth, contentHeight) < minZoomedEdge {
            if contentWidth >= contentHeight {
                contentWidth = minZoomedEdge
                contentHeight = contentWidth / aspect
            } else {
                contentHeight = minZoomedEdge
                contentWidth = contentHeight * aspect
            }

            if contentWidth > maxContentWidth {
                contentWidth = maxContentWidth
                contentHeight = contentWidth / aspect
            }
            if contentHeight > maxContentHeight {
                contentHeight = maxContentHeight
                contentWidth = contentHeight * aspect
            }
        }

        return CGSize(
            width: max(sheetMinimumSize.width, contentWidth + sheetPadding),
            height: max(sheetMinimumSize.height, contentHeight + sheetHeaderHeight + sheetPadding)
        )
    }
}

private struct MarkdownImagePreviewSheet: View {
    let item: MarkdownPreviewImageItem
    @Environment(\.dismiss) private var dismiss

    private var sheetSize: CGSize {
        MarkdownImageZoomLayout.sheetSize(for: item.image)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(item.title?.isEmpty == false ? item.title! : "图片")
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("关闭")
            }
            .padding(14)

            GeometryReader { proxy in
                Image(nsImage: item.image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(16)
            .background(Color.black.opacity(0.06))
        }
        .frame(width: sheetSize.width, height: sheetSize.height)
    }
}

// MARK: - Public preview view

struct MarkdownPreviewView: View {
    let markdown: String
    let isOutlineVisible: Bool
    var baseURL: URL? = nil

    @State private var selectedOutlineItemID: Int?
    @State private var previewImageItem: MarkdownPreviewImageItem?

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
                    selectedOutlineItemID: selectedOutlineItemID,
                    baseURL: baseURL,
                    onImagePreview: { item in
                        previewImageItem = item
                    }
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
        .sheet(item: $previewImageItem) { item in
            MarkdownImagePreviewSheet(item: item)
        }
    }
}

// MARK: - Compact task description preview

struct MarkdownDescriptionPreviewView: View {
    let markdown: String
    let isCompleted: Bool

    var body: some View {
        CompactMarkdownTextView(
            blocks: MarkdownBlockParser.parse(markdown),
            isCompleted: isCompleted
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompactMarkdownTextView: NSViewRepresentable {
    let blocks: [MarkdownBlock]
    let isCompleted: Bool

    func makeNSView(context: Context) -> CompactLinkTextView {
        let textView = CompactLinkTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.allowsUndo = false
        textView.delegate = context.coordinator
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        applyContent(to: textView)
        return textView
    }

    func updateNSView(_ textView: CompactLinkTextView, context: Context) {
        applyContent(to: textView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: CompactLinkTextView, context: Context) -> CGSize? {
        guard let width = proposal.width ?? (textView.bounds.width > 0 ? textView.bounds.width : nil),
              width > 0,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else {
            return nil
        }

        textView.frame.size.width = width
        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = ceil(usedRect.height + textView.textContainerInset.height * 2)
        return CGSize(width: width, height: max(height, 1))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func applyContent(to textView: CompactLinkTextView) {
        textView.clearHoveredLink()
        textView.textStorage?.setAttributedString(MarkdownCompactAttributedRenderer.render(blocks, isCompleted: isCompleted))
        textView.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = CompactLinkTextView.url(from: link) else {
                return false
            }

            NSWorkspace.shared.open(url)
            return true
        }
    }
}

private final class CompactLinkTextView: NSTextView {
    private var trackingArea: NSTrackingArea?
    private var hoveredLinkRange: NSRange?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // This text view is embedded directly in SwiftUI. When the pointer is
        // NOT over a link we must return nil so the surrounding card keeps
        // receiving clicks/drags. The catch: while nil is returned the card owns
        // the pointer, and once we DO return self (over a link) AppKit no longer
        // routes `mouseMoved`/`cursorUpdate` to us — SwiftUI's host owns cursor
        // management. `hitTest` is therefore the only callback that fires
        // reliably on every pointer move at any window width, so we drive the
        // hover highlight + pointer cursor from right here.
        //
        // `point` arrives in the superview's coordinate system and must be
        // converted into this view's own (flipped) coordinates first.
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        guard bounds.contains(localPoint) else {
            clearHoveredLink()
            return nil
        }

        let range = linkRange(at: localPoint)
        updateHoveredLink(to: range)
        guard range != nil else {
            return nil
        }

        NSCursor.pointingHand.set()
        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        // NOTE: do NOT use `.inVisibleRect` here. This text view is embedded
        // directly in SwiftUI (no enclosing scroll view) and is vertically
        // self-resizing, which makes `visibleRect` report a stale, fixed-size
        // rectangle that does not follow the real bounds. Binding the tracking
        // area to that bogus rect makes hover detection stop firing once the
        // card grows wider. An explicit `bounds` rect, rebuilt on every layout
        // pass, stays correct at any window width.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        // Fires only over the non-link part of the card (where `hitTest`
        // returns nil); used purely to drop a stale highlight.
        updateHoveredLink(to: linkRange(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearHoveredLink()
    }

    private func linkRange(at point: NSPoint) -> NSRange? {
        guard
            let layoutManager,
            let textContainer,
            let textStorage,
            textStorage.length > 0
        else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let textContainerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        var hitRange: NSRange?
        textStorage.enumerateAttribute(.link, in: NSRange(location: 0, length: textStorage.length)) { value, range, stop in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphRange, lineStop in
                let fragmentGlyphRange = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard fragmentGlyphRange.length > 0 else { return }
                let rect = layoutManager.boundingRect(forGlyphRange: fragmentGlyphRange, in: textContainer)
                if rect.insetBy(dx: -2, dy: -2).contains(textContainerPoint) {
                    hitRange = range
                    lineStop.pointee = true
                    stop.pointee = true
                }
            }
        }
        return hitRange
    }

    private func updateHoveredLink(to range: NSRange?) {
        if NSEqualRanges(range ?? NSRange(location: NSNotFound, length: 0), hoveredLinkRange ?? NSRange(location: NSNotFound, length: 0)) {
            return
        }

        clearHoveredLink()
        guard let range else { return }
        layoutManager?.addTemporaryAttributes(MarkdownStyle.linkHoverAttributes, forCharacterRange: range)
        hoveredLinkRange = range
        needsDisplay = true
    }

    func clearHoveredLink() {
        guard let hoveredLinkRange else { return }
        layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: hoveredLinkRange)
        layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: hoveredLinkRange)
        layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: hoveredLinkRange)
        self.hoveredLinkRange = nil
        needsDisplay = true
    }

    static func url(from link: Any) -> URL? {
        if let url = link as? URL {
            return url
        }

        if let string = link as? String {
            return URL(string: string)
        }

        return nil
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
                .font(.custom("PingFang SC", size: 13).weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    Text(item.title)
                        .font(.custom("PingFang SC", size: outlineFontSize(for: item.level))
                            .weight(item.level <= 2 ? .semibold : .regular))
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
        level <= 2 ? 13 : 12
    }
}

// MARK: - Selectable text view (TextKit)

private struct SelectableMarkdownTextView: NSViewRepresentable {
    let blocks: [MarkdownBlock]
    let selectedOutlineItemID: Int?
    let baseURL: URL?
    var onImagePreview: ((MarkdownPreviewImageItem) -> Void)? = nil

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

        textView.onImagePreview = onImagePreview

        scrollView.documentView = textView
        context.coordinator.textView = textView
        applyContent(to: textView, context: context)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        textView.onImagePreview = onImagePreview
        applyContent(to: textView, context: context)
        context.coordinator.scrollToHeadingIfNeeded(selectedOutlineItemID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func applyContent(to textView: CopyableCodeTextView, context: Context) {
        let rendered = MarkdownAttributedRenderer.render(blocks, baseURL: baseURL)
        guard context.coordinator.lastRenderedText != rendered.string else { return }

        textView.clearHoveredLink()
        textView.textStorage?.setAttributedString(rendered.attributedString)
        textView.codeBlocks = rendered.codeBlocks
        textView.quoteRanges = rendered.quoteRanges
        textView.dividerRanges = rendered.dividerRanges
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

private final class PointingHandCodeCopyButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private final class CopyableCodeTextView: NSTextView {
    var onImagePreview: ((MarkdownPreviewImageItem) -> Void)?

    var codeBlocks: [MarkdownCodeRange] = [] {
        didSet { needsDisplay = true }
    }
    var quoteRanges: [NSRange] = [] {
        didSet { needsDisplay = true }
    }
    var dividerRanges: [NSRange] = [] {
        didSet { needsDisplay = true }
    }

    private let copyButton = PointingHandCodeCopyButton()
    private let copiedLabel = NSTextField(labelWithString: "已复制")
    private var trackingArea: NSTrackingArea?
    private var hoveredCode: String?
    private var hoveredLinkRange: NSRange?
    private var hideCopiedLabelWorkItem: DispatchWorkItem?

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
        drawQuoteBars()
        drawCodeBackgrounds()
        drawDividers()
        super.draw(dirtyRect)
    }

    private func drawQuoteBars() {
        for range in quoteRanges {
            guard let rect = contentRect(for: range) else { continue }
            let path = NSBezierPath(roundedRect: NSRect(
                x: 2,
                y: rect.minY + 1,
                width: 3,
                height: max(rect.height - 2, 3)
            ), xRadius: 1.5, yRadius: 1.5)
            MarkdownStyle.quoteBar.setFill()
            path.fill()
        }
    }

    private func drawCodeBackgrounds() {
        for block in codeBlocks {
            guard let rect = codeBackgroundRect(for: block.range) else { continue }
            let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
            MarkdownStyle.codeBackground.setFill()
            path.fill()
            MarkdownStyle.codeBorder.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawDividers() {
        for range in dividerRanges {
            guard let rect = contentRect(for: range) else { continue }
            let path = NSBezierPath()
            let y = rect.midY.rounded(.down) + 0.5
            path.move(to: NSPoint(x: 0, y: y))
            path.line(to: NSPoint(x: bounds.width, y: y))
            MarkdownStyle.divider.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func contentRect(for range: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let origin = textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        return rect
    }

    private func codeBackgroundRect(for range: NSRange) -> NSRect? {
        guard let rect = contentRect(for: range) else { return nil }
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

        copiedLabel.font = .systemFont(ofSize: 11, weight: .medium)
        copiedLabel.textColor = NSColor.white.withAlphaComponent(0.88)
        copiedLabel.alignment = .right
        copiedLabel.isHidden = true
        copiedLabel.alphaValue = 0
        copiedLabel.frame = NSRect(x: 0, y: 0, width: 42, height: 18)
        addSubview(copiedLabel)
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

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let attachment = imageAttachment(at: point) {
            onImagePreview?(MarkdownPreviewImageItem(image: attachment.previewImage, title: attachment.altText))
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        updateCopyButton(for: point)
        updateHoveredLink(for: point)
        updateCursor(for: point)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideCopyButton()
        clearHoveredLink()
    }

    private func updateCopyButton(for point: NSPoint) {
        guard let characterIndex = characterIndex(at: point),
              let block = codeBlocks.first(where: { NSLocationInRange(characterIndex, $0.range) }),
              let rect = codeBackgroundRect(for: block.range) else {
            hideCopyButton()
            return
        }

        hoveredCode = block.code
        positionCopyControls(in: rect)
        copyButton.isHidden = false
    }

    private func hideCopyButton() {
        hoveredCode = nil
        copyButton.isHidden = true
        hideCopiedLabel()
    }

    @objc private func copyHoveredCode() {
        guard let hoveredCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hoveredCode, forType: .string)
        showCopiedLabel()
    }

    // MARK: Cursor / hit testing

    private func updateCursor(for point: NSPoint) {
        if !copyButton.isHidden, copyButton.frame.contains(point) {
            NSCursor.pointingHand.set()
            return
        }

        if imageAttachment(at: point) != nil || linkRange(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    private func updateHoveredLink(for point: NSPoint) {
        let range = linkRange(at: point)
        if NSEqualRanges(range ?? NSRange(location: NSNotFound, length: 0), hoveredLinkRange ?? NSRange(location: NSNotFound, length: 0)) {
            return
        }

        clearHoveredLink()
        guard let range else { return }
        layoutManager?.addTemporaryAttributes(MarkdownStyle.linkHoverAttributes, forCharacterRange: range)
        hoveredLinkRange = range
        needsDisplay = true
    }

    func clearHoveredLink() {
        guard let hoveredLinkRange else { return }
        layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: hoveredLinkRange)
        layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: hoveredLinkRange)
        layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: hoveredLinkRange)
        self.hoveredLinkRange = nil
        needsDisplay = true
    }

    private func imageAttachment(at point: NSPoint) -> MarkdownImageTextAttachment? {
        guard
            let characterIndex = characterIndex(at: point, requiringGlyphHit: true),
            let textStorage,
            let attachment = textStorage.attribute(.attachment, at: characterIndex, effectiveRange: nil) as? MarkdownImageTextAttachment
        else {
            return nil
        }

        return attachment
    }

    private func linkRange(at point: NSPoint) -> NSRange? {
        guard
            let layoutManager,
            let textContainer,
            let textStorage,
            textStorage.length > 0
        else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        var hitRange: NSRange?
        textStorage.enumerateAttribute(.link, in: NSRange(location: 0, length: textStorage.length)) { value, range, stop in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphRange, lineStop in
                let fragmentGlyphRange = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard fragmentGlyphRange.length > 0 else { return }
                let rect = layoutManager.boundingRect(forGlyphRange: fragmentGlyphRange, in: textContainer)
                if rect.insetBy(dx: -2, dy: -2).contains(containerPoint) {
                    hitRange = range
                    lineStop.pointee = true
                    stop.pointee = true
                }
            }
        }
        return hitRange
    }

    private func characterIndex(at point: NSPoint, requiringGlyphHit: Bool = false) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        if requiringGlyphHit {
            let glyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 1),
                in: textContainer
            )
            guard glyphRect.insetBy(dx: -2, dy: -2).contains(containerPoint) else {
                return nil
            }
        }
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }

    private func positionCopyControls(in rect: NSRect) {
        copyButton.frame.origin = NSPoint(x: rect.maxX - copyButton.frame.width - 8, y: rect.minY + 1)
        copiedLabel.frame.origin = NSPoint(
            x: copyButton.frame.minX - copiedLabel.frame.width - 7,
            y: copyButton.frame.minY
        )
        window?.invalidateCursorRects(for: copyButton)
    }

    private func showCopiedLabel() {
        hideCopiedLabelWorkItem?.cancel()
        copiedLabel.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            copiedLabel.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.hideCopiedLabel()
        }
        hideCopiedLabelWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    private func hideCopiedLabel() {
        hideCopiedLabelWorkItem?.cancel()
        hideCopiedLabelWorkItem = nil

        guard !copiedLabel.isHidden || copiedLabel.alphaValue > 0 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            copiedLabel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.copiedLabel.isHidden = true
        }
    }
}


// MARK: - Markdown image attachments

@MainActor
final class MarkdownImageTextAttachment: NSTextAttachment {
    let previewImage: NSImage
    let sourceURL: URL?
    let altText: String?

    init(image: NSImage, sourceURL: URL?, altText: String?) {
        self.previewImage = image
        self.sourceURL = sourceURL
        self.altText = altText
        super.init(data: nil, ofType: nil)
        self.image = image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
enum MarkdownImageAttachmentRenderer {
    static let imageURLKey = NSAttributedString.Key("NSImageURL")
    static let defaultMaxImageWidth: CGFloat = MarkdownImageZoomLayout.inlineMaxWidth

    static func resolveImageURL(_ raw: URL, baseURL: URL?) -> URL? {
        if raw.scheme == "http" || raw.scheme == "https" || raw.scheme == "data" {
            return raw
        }

        let composite = String(describing: raw)
        if composite.contains(" -- ") {
            let parts = composite.components(separatedBy: " -- ")
            let reference = parts[0]
            if reference.hasPrefix("/") {
                return URL(fileURLWithPath: reference)
            }

            if var resolvedBase = parts.count > 1 ? URL(string: parts[1]) : baseURL {
                if !resolvedBase.hasDirectoryPath {
                    resolvedBase = URL(fileURLWithPath: resolvedBase.path, isDirectory: true)
                }
                return URL(string: reference, relativeTo: resolvedBase)?.standardizedFileURL
            }
        }

        if raw.isFileURL {
            return raw.standardizedFileURL
        }

        if let baseURL {
            let rawString = raw.absoluteString.removingPercentEncoding ?? raw.absoluteString
            return URL(string: rawString, relativeTo: baseURL)?.standardizedFileURL
        }

        return raw
    }

    static func loadImage(from url: URL) -> NSImage? {
        if url.scheme == "data" {
            return imageFromDataURL(url.absoluteString)
        }
        return NSImage(contentsOf: url)
    }

    private static func imageFromDataURL(_ dataURL: String) -> NSImage? {
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let payload = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: payload) else { return nil }
        return NSImage(data: data)
    }

    static func applyImageAttachments(
        to attributed: NSMutableAttributedString,
        baseURL: URL?,
        maxImageWidth: CGFloat = defaultMaxImageWidth,
        fallbackAttributes: [NSAttributedString.Key: Any]
    ) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        var replacements: [(NSRange, NSAttributedString)] = []

        attributed.enumerateAttribute(imageURLKey, in: fullRange) { value, range, _ in
            guard let raw = value as? URL else { return }

            let alt = (attributed.string as NSString).substring(with: range)
            if let resolved = resolveImageURL(raw, baseURL: baseURL),
               let image = loadImage(from: resolved),
               image.size.width > 0,
               image.size.height > 0 {
                let attachment = makeAttachment(
                    image: image,
                    sourceURL: resolved,
                    altText: alt.isEmpty ? nil : alt,
                    maxWidth: maxImageWidth
                )
                replacements.append((range, NSAttributedString(attachment: attachment)))
            } else {
                let label = alt.isEmpty ? "[图片]" : "[图片: \(alt)]"
                replacements.append((range, NSAttributedString(string: label, attributes: fallbackAttributes)))
            }
        }

        for (range, replacement) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            attributed.replaceCharacters(in: range, with: replacement)
        }
    }

    private static func makeAttachment(
        image: NSImage,
        sourceURL: URL?,
        altText: String?,
        maxWidth: CGFloat
    ) -> MarkdownImageTextAttachment {
        let attachment = MarkdownImageTextAttachment(image: image, sourceURL: sourceURL, altText: altText)

        let width = min(image.size.width, maxWidth)
        let height = width * (image.size.height / image.size.width)
        attachment.bounds = CGRect(x: 0, y: -4, width: width, height: height)
        return attachment
    }
}

// MARK: - Attributed renderer

@MainActor
private enum MarkdownAttributedRenderer {
    static func render(_ blocks: [MarkdownBlock], baseURL: URL? = nil) -> (
        attributedString: NSAttributedString,
        headingRanges: [Int: NSRange],
        codeBlocks: [MarkdownCodeRange],
        quoteRanges: [NSRange],
        dividerRanges: [NSRange],
        string: String
    ) {
        let result = NSMutableAttributedString()
        var headingRanges: [Int: NSRange] = [:]
        var codeBlocks: [MarkdownCodeRange] = []
        var quoteRanges: [NSRange] = []
        var dividerRanges: [NSRange] = []
        var headingIndex = 0

        for block in blocks {
            switch block.kind {
            case let .heading(level, text):
                appendSpacingIfNeeded(to: result, lines: 1)
                let start = result.length
                result.append(inlineAttributedString(
                    text,
                    font: headingFont(for: level),
                    color: .labelColor,
                    paragraphStyle: paragraphStyle(lineSpacing: 1.5, paragraphSpacing: 4),
                    baseURL: baseURL
                ))
                headingRanges[headingIndex] = NSRange(location: start, length: max(result.length - start, 1))
                headingIndex += 1
                result.append(NSAttributedString(string: "\n"))

            case let .paragraph(text):
                result.append(inlineAttributedString(
                    text,
                    font: MarkdownStyle.bodyFont,
                    color: MarkdownStyle.bodyText,
                    paragraphStyle: paragraphStyle(lineSpacing: 4, paragraphSpacing: 6),
                    baseURL: baseURL
                ))
                result.append(NSAttributedString(string: "\n"))

            case let .unorderedList(items):
                appendList(items, ordered: false, to: result, baseURL: baseURL)

            case let .orderedList(items):
                appendList(items, ordered: true, to: result, baseURL: baseURL)

            case let .blockquote(text):
                appendBlockquote(text, to: result, quoteRanges: &quoteRanges, baseURL: baseURL)

            case .horizontalRule:
                appendDivider(to: result, dividerRanges: &dividerRanges)

            case let .codeBlock(code, language):
                appendSpacingIfNeeded(to: result, lines: 1)
                appendCodeBlock(code: code, language: language, to: result, codeBlocks: &codeBlocks)
                appendCodeBlockTrailingSpacing(to: result)
            }
        }

        while result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        return (result, headingRanges, codeBlocks, quoteRanges, dividerRanges, result.string)
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

    private static func appendList(_ items: [String], ordered: Bool, to result: NSMutableAttributedString, baseURL: URL?) {
        let style = paragraphStyle(lineSpacing: 4, paragraphSpacing: 4, headIndent: 26)
        for (index, item) in items.enumerated() {
            let marker = ordered ? "\(index + 1). " : "•  "
            result.append(NSAttributedString(
                string: marker,
                attributes: [
                    .font: MarkdownStyle.bodyFont(size: 16, weight: .semibold),
                    .foregroundColor: MarkdownStyle.listMarker,
                    .paragraphStyle: style
                ]
            ))
            result.append(inlineAttributedString(
                item,
                font: MarkdownStyle.bodyFont,
                color: MarkdownStyle.bodyText,
                paragraphStyle: style,
                baseURL: baseURL
            ))
            result.append(NSAttributedString(string: index == items.count - 1 ? "\n" : "\n"))
        }
        result.append(NSAttributedString(string: "\n"))
    }

    private static func appendBlockquote(_ text: String, to result: NSMutableAttributedString, quoteRanges: inout [NSRange], baseURL: URL?) {
        appendSpacingIfNeeded(to: result, lines: 1)
        let start = result.length
        let style = paragraphStyle(lineSpacing: 4, paragraphSpacing: 6, headIndent: 18)
        style.firstLineHeadIndent = 18
        result.append(inlineAttributedString(
            text,
            font: MarkdownStyle.bodyFont,
            color: MarkdownStyle.quoteText,
            paragraphStyle: style,
                baseURL: baseURL
        ))
        let range = NSRange(location: start, length: max(result.length - start, 1))
        quoteRanges.append(range)
        result.append(NSAttributedString(string: "\n"))
    }

    private static func appendDivider(to result: NSMutableAttributedString, dividerRanges: inout [NSRange]) {
        appendSpacingIfNeeded(to: result, lines: 1)
        let style = paragraphStyle(lineSpacing: 0, paragraphSpacing: 10)
        style.minimumLineHeight = 20
        style.maximumLineHeight = 20
        let start = result.length
        result.append(NSAttributedString(
            string: " ",
            attributes: [
                .font: MarkdownStyle.bodyFont,
                .paragraphStyle: style
            ]
        ))
        dividerRanges.append(NSRange(location: start, length: 1))
        result.append(NSAttributedString(string: "\n"))
    }

    private static func inlineAttributedString(
        _ markdown: String,
        font: NSFont,
        color: NSColor,
        paragraphStyle: NSParagraphStyle,
        baseURL: URL?
    ) -> NSAttributedString {
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        guard let attributed = try? NSMutableAttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace),
            baseURL: baseURL
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
        MarkdownImageAttachmentRenderer.applyImageAttachments(
            to: attributed,
            baseURL: baseURL,
            fallbackAttributes: baseAttributes
        )

        return attributed
    }

    private static func headingFont(for level: Int) -> NSFont {
        switch level {
        case 1:
            MarkdownStyle.bodyFont(size: 31, weight: .bold)
        case 2:
            MarkdownStyle.bodyFont(size: 25, weight: .bold)
        case 3:
            MarkdownStyle.bodyFont(size: 21, weight: .semibold)
        case 4:
            MarkdownStyle.bodyFont(size: 18, weight: .semibold)
        default:
            MarkdownStyle.bodyFont(size: 16, weight: .semibold)
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

@MainActor
private enum MarkdownCompactAttributedRenderer {
    static func render(_ blocks: [MarkdownBlock], isCompleted: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for block in blocks {
            switch block.kind {
            case let .heading(level, text):
                appendSpacingIfNeeded(to: result)
                result.append(inlineAttributedString(
                    text,
                    font: headingFont(for: level),
                    color: .secondaryLabelColor,
                    paragraphStyle: paragraphStyle(lineSpacing: 3, paragraphSpacing: 5)
                ))
                result.append(NSAttributedString(string: "\n"))

            case let .paragraph(text):
                result.append(inlineAttributedString(
                    text,
                    font: bodyFont,
                    color: .secondaryLabelColor,
                    paragraphStyle: paragraphStyle(lineSpacing: 4, paragraphSpacing: 5)
                ))
                result.append(NSAttributedString(string: "\n"))

            case let .unorderedList(items):
                appendList(items, ordered: false, to: result)

            case let .orderedList(items):
                appendList(items, ordered: true, to: result)

            case let .blockquote(text):
                appendSpacingIfNeeded(to: result)
                result.append(inlineAttributedString(
                    text,
                    font: bodyFont,
                    color: .tertiaryLabelColor,
                    paragraphStyle: paragraphStyle(lineSpacing: 4, paragraphSpacing: 5, headIndent: 12)
                ))
                result.append(NSAttributedString(string: "\n"))

            case .horizontalRule:
                appendSpacingIfNeeded(to: result)
                result.append(NSAttributedString(string: "\n"))

            case let .codeBlock(code, _):
                appendSpacingIfNeeded(to: result)
                result.append(NSAttributedString(
                    string: code.isEmpty ? " " : code,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .backgroundColor: MarkdownStyle.inlineCodeBackground,
                        .paragraphStyle: paragraphStyle(lineSpacing: 3, paragraphSpacing: 5, lineBreakMode: .byCharWrapping)
                    ]
                ))
                result.append(NSAttributedString(string: "\n"))
            }
        }

        while result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        if isCompleted, result.length > 0 {
            result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: result.length))
        }

        return result
    }

    private static let bodyFont = MarkdownStyle.bodyFont(size: 14, weight: .regular)

    private static func appendList(_ items: [String], ordered: Bool, to result: NSMutableAttributedString) {
        let style = paragraphStyle(lineSpacing: 4, paragraphSpacing: 4, headIndent: 20)
        for (index, item) in items.enumerated() {
            let marker = ordered ? "\(index + 1). " : "•  "
            result.append(NSAttributedString(
                string: marker,
                attributes: [
                    .font: MarkdownStyle.bodyFont(size: 14, weight: .semibold),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: style
                ]
            ))
            result.append(inlineAttributedString(
                item,
                font: bodyFont,
                color: .secondaryLabelColor,
                paragraphStyle: style
            ))
            result.append(NSAttributedString(string: "\n"))
        }
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
                attributed.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: MarkdownStyle.inlineCodeText,
                    .backgroundColor: MarkdownStyle.inlineCodeBackground
                ], range: range)
                return
            }

            var traits: NSFontTraitMask = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
            if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
            if !traits.isEmpty {
                attributed.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: traits), range: range)
            }
        }

        return attributed
    }

    private static func headingFont(for level: Int) -> NSFont {
        level <= 2 ? MarkdownStyle.bodyFont(size: 15, weight: .semibold) : MarkdownStyle.bodyFont(size: 14, weight: .semibold)
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

    private static func appendSpacingIfNeeded(to result: NSMutableAttributedString) {
        guard result.length > 0, !result.string.hasSuffix("\n") else { return }
        result.append(NSAttributedString(string: "\n"))
    }
}

// MARK: - Style palette

@MainActor
private enum MarkdownStyle {
    static let bodyFont = bodyFont(size: 16, weight: .regular)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    // Inner vertical padding of a code block, rendered as real blank lines.
    static let codePadTop: CGFloat = 20
    static let codePadBottom: CGFloat = 16

    static let bodyText = dynamic(light: 0x3A3D44, dark: 0xCBD0D8)
    static let listMarker = dynamic(light: 0x4C6F9B, dark: 0x8FB3DE)
    static let quoteText = dynamic(light: 0x5B6370, dark: 0xB7BECA)
    static let quoteBar = dynamic(light: 0x8AA1BA, dark: 0x5F7FA4)
    static let divider = dynamic(light: 0xD5DAE2, dark: 0x3B4654)

    // Code blocks always render on a dark panel for a consistent, premium look.
    static let codeBackground = NSColor(srgbRed: 0.145, green: 0.157, blue: 0.176, alpha: 1)
    static let codeBorder = NSColor.white.withAlphaComponent(0.09)
    static let codeText = NSColor(srgbRed: 0.89, green: 0.91, blue: 0.93, alpha: 1)

    static let inlineCodeText = dynamic(light: 0xB5446E, dark: 0xF2A6C2)
    static let inlineCodeBackground = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.06)
    }
    static let linkHoverBackground = NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor.linkColor.withAlphaComponent(0.24) : NSColor.linkColor.withAlphaComponent(0.14)
    }
    static var linkHoverAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.linkColor,
            .backgroundColor: linkHoverBackground,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
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
        case blockquote(String)
        case horizontalRule
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
        var quoteLines: [String] = []
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

        func flushBlockquote() {
            guard !quoteLines.isEmpty else { return }
            blocks.append(MarkdownBlock(kind: .blockquote(quoteLines.joined(separator: "\n"))))
            quoteLines.removeAll()
        }

        func flushOpenBlocks() {
            flushParagraph()
            flushUnorderedList()
            flushOrderedList()
            flushBlockquote()
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

            if isHorizontalRule(trimmed) {
                flushOpenBlocks()
                blocks.append(MarkdownBlock(kind: .horizontalRule))
                continue
            }

            if let heading = heading(from: trimmed) {
                flushOpenBlocks()
                blocks.append(MarkdownBlock(kind: .heading(level: heading.level, text: heading.text)))
                continue
            }

            if let quoteLine = blockquoteLine(from: trimmed) {
                flushParagraph()
                flushUnorderedList()
                flushOrderedList()
                quoteLines.append(quoteLine)
                continue
            }

            if let item = unorderedListItem(from: trimmed) {
                flushParagraph()
                flushOrderedList()
                flushBlockquote()
                unorderedItems.append(item)
                continue
            }

            if let item = orderedListItem(from: trimmed) {
                flushParagraph()
                flushUnorderedList()
                flushBlockquote()
                orderedItems.append(item)
                continue
            }

            flushUnorderedList()
            flushOrderedList()
            flushBlockquote()
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

    private static func blockquoteLine(from line: String) -> String? {
        guard line.hasPrefix(">") else {
            return nil
        }

        let content = line.dropFirst()
        if content.first == " " {
            return String(content.dropFirst())
        }
        return String(content)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let markers = line.filter { !$0.isWhitespace }
        guard markers.count >= 3, let marker = markers.first, marker == "-" || marker == "*" || marker == "_" else {
            return false
        }
        return markers.allSatisfy { $0 == marker }
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
