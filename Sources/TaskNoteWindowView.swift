@preconcurrency import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskNoteWindowView: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedTaskID: TaskItem.ID?
    @Binding var taskListScope: NoteTaskListScope

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var displayMode: NoteDisplayMode = .preview
    @State private var editingTask: TaskItem?
    @State private var selectedNoteID: TaskNote.ID?
    @State private var noteMarkdown = ""
    @State private var noteErrorMessage: String?
    @State private var noteCreationTask: TaskItem?
    @State private var isTaskSidebarCollapsed = false
    @State private var isOutlineVisible = true
    @State private var sidebarDragStartWidth: Double?
    @State private var liveSidebarWidth: Double?
    @AppStorage("TaskSnap.noteSidebarWidth") private var sidebarWidth = 292.0
    @AppStorage("TaskSnap.noteWindowZoomScale") private var noteWindowZoomScale = 1.0
    @FocusState private var isEditorFocused: Bool

    private let minSidebarWidth = 180.0
    private let maxSidebarWidth = 560.0
    private let minNoteWindowZoomScale = 0.8
    private let maxNoteWindowZoomScale = 1.35
    private let noteWindowZoomStep = 0.1

    private var visibleTasks: [TaskItem] {
        store.visibleTasks
    }

    private var sidebarTasks: [TaskItem] {
        switch taskListScope {
        case .all:
            visibleTasks
        case .selectedOnly:
            selectedTask.map { [$0] } ?? []
        }
    }

    private var selectedTask: TaskItem? {
        guard let selectedTaskID else {
            return visibleTasks.first
        }

        return visibleTasks.first { $0.id == selectedTaskID } ?? visibleTasks.first
    }

    private var effectiveSidebarWidth: Double {
        liveSidebarWidth ?? sidebarWidth
    }

    private var selectedNote: TaskNote? {
        guard let selectedTask else {
            return nil
        }

        if let selectedNoteID,
           let note = selectedTask.notes.first(where: { $0.id == selectedNoteID }) {
            return note
        }

        return selectedTask.notes.first
    }

    private var noteMarkdownBinding: Binding<String> {
        Binding {
            noteMarkdown
        } set: { newValue in
            noteMarkdown = newValue
            guard let selectedNote else { return }
            do {
                try store.updateNoteMarkdown(selectedNote, markdown: newValue)
                noteErrorMessage = nil
            } catch {
                noteErrorMessage = error.localizedDescription
            }
        }
    }

    var body: some View {
        Group {
            if visibleTasks.isEmpty {
                emptyWindow
            } else {
                noteWindow
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if selectedTaskID == nil {
                selectedTaskID = visibleTasks.first?.id
            }
            selectDefaultNoteIfNeeded()
            loadSelectedNote()
        }
        .onChange(of: selectedTaskID) {
            selectDefaultNoteIfNeeded(force: true)
            loadSelectedNote()
        }
        .onChange(of: selectedNoteID) {
            loadSelectedNote()
        }
        .onChange(of: visibleTasks.map { "\($0.id):\($0.notes.map(\.id))" }) {
            selectDefaultNoteIfNeeded()
            loadSelectedNote()
        }
        .sheet(item: $editingTask) { task in
            NoteTaskEditFormView(task: task) { title, description in
                store.updateTask(task, title: title, description: description)
            }
        }
        .sheet(item: $noteCreationTask) { task in
            NoteCreationFormView(task: task) { title in
                createLocalNote(for: task, title: title)
            }
        }
    }

    private var noteWindow: some View {
        let zoomScale = CGFloat(noteWindowZoomScale)

        return GeometryReader { proxy in
            noteWindowContent
                .frame(
                    width: max(proxy.size.width / zoomScale, 1),
                    height: max(proxy.size.height / zoomScale, 1),
                    alignment: .topLeading
                )
                .scaleEffect(zoomScale, anchor: .topLeading)
        }
        .frame(minWidth: 820, minHeight: 560)
        .overlay {
            noteWindowZoomShortcuts
        }
    }

    private var noteWindowZoomShortcuts: some View {
        VStack {
            Button("") {
                adjustNoteWindowZoom(by: noteWindowZoomStep)
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("") {
                adjustNoteWindowZoom(by: noteWindowZoomStep)
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("") {
                adjustNoteWindowZoom(by: -noteWindowZoomStep)
            }
            .keyboardShortcut("-", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var noteWindowContent: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if isTaskSidebarCollapsed {
                    collapsedTaskSidebar
                } else {
                    taskTitleSidebar
                }

                documentPane
            }
            .overlay(alignment: .topLeading) {
                sidebarResizeHandle
                    .frame(height: proxy.size.height + proxy.safeAreaInsets.top)
                    .offset(
                        x: CGFloat(effectiveSidebarWidthForHandle - 12),
                        y: -proxy.safeAreaInsets.top
                    )
            }
        }
    }

    private var effectiveSidebarWidthForHandle: Double {
        isTaskSidebarCollapsed ? 58 : effectiveSidebarWidth
    }

    private var sidebarResizeHandle: some View {
        ResizableNoteSidebarDivider(
            onDragDelta: { delta in
                if sidebarDragStartWidth == nil {
                    sidebarDragStartWidth = effectiveSidebarWidth
                }

                let startWidth = sidebarDragStartWidth ?? effectiveSidebarWidth
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    liveSidebarWidth = clampedSidebarWidth(
                        startWidth + Double(delta) / noteWindowZoomScale
                    )
                }
            },
            onDragEnded: {
                if let liveSidebarWidth {
                    sidebarWidth = liveSidebarWidth
                }
                self.liveSidebarWidth = nil
                sidebarDragStartWidth = nil
            }
        )
        .frame(width: 12)
        .frame(maxHeight: .infinity)
    }

    private var taskTitleSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("任务标题")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                NoteToolbarButton(systemName: "sidebar.left", help: "折叠任务列表") {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        isTaskSidebarCollapsed = true
                    }
                }
            }

            Picker("笔记范围", selection: $taskListScope) {
                Text("当前").tag(NoteTaskListScope.selectedOnly)
                Text("全部").tag(NoteTaskListScope.all)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .help("切换当前任务笔记或全部任务笔记")

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(sidebarTasks) { task in
                        TaskTitleListItem(
                            task: task,
                            selectedNoteID: selectedNoteID,
                            isSelected: task.id == selectedTask?.id,
                            noteExists: noteExists,
                            onSelectTask: {
                                selectedTaskID = task.id
                                selectedNoteID = task.notes.first?.id
                            },
                            onSelectNote: { note in
                                selectedTaskID = task.id
                                selectedNoteID = note.id
                            },
                            onCreateNote: {
                                noteCreationTask = task
                            },
                            onAttachExternalNote: {
                                chooseExternalNote(for: task)
                            },
                            onDeleteNote: { note in
                                deleteNote(note, from: task)
                            }
                        )
                    }
                }
                .padding(.bottom, 18)
            }
        }
        .padding(18)
        .frame(width: effectiveSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.46))
    }

    private var collapsedTaskSidebar: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    isTaskSidebarCollapsed = false
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.1), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("展开任务列表")
            .accessibilityLabel("展开任务列表")

            Text("\(visibleTasks.count)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.vertical, 18)
        .frame(width: 58)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.46))
    }

    @ViewBuilder
    private var documentPane: some View {
        if let selectedTask {
            VStack(spacing: 0) {
                documentTitleBar(for: selectedTask, note: selectedNote)

                Divider()

                documentContent(for: selectedTask)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            emptyWindow
        }
    }

    private func documentTitleBar(for task: TaskItem, note: TaskNote?) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.map { TaskNoteDocument(markdown: noteMarkdown, fallbackTitle: $0.title).title } ?? "任务笔记")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Text(note == nil ? "" : "自动保存")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NoteToolbarButton(systemName: "doc.on.doc", help: "复制 Markdown") {
                copyToPasteboard(noteMarkdown)
            }
            .disabled(note == nil)

            NoteToolbarButton(
                systemName: isOutlineVisible ? "list.bullet.rectangle.fill" : "list.bullet.rectangle",
                help: isOutlineVisible ? "隐藏大纲" : "显示大纲"
            ) {
                isOutlineVisible.toggle()
            }

            Picker("", selection: $displayMode) {
                Text("Preview").tag(NoteDisplayMode.preview)
                Text("Markdown").tag(NoteDisplayMode.markdown)
            }
            .pickerStyle(.segmented)
            .frame(width: 166)
            .disabled(note == nil)
        }
        .padding(.leading, 52)
        .padding(.trailing, 18)
        .frame(height: 58)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    @ViewBuilder
    private func documentContent(for task: TaskItem) -> some View {
        if let selectedNote {
            let document = TaskNoteDocument(markdown: noteMarkdown, fallbackTitle: selectedNote.title)

            VStack(spacing: 0) {
                if let noteErrorMessage {
                    Text(noteErrorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 52)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.08))
                }

                switch displayMode {
                case .preview:
                    if document.previewMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                emptyNoteView
                            }
                            .frame(maxWidth: 840, alignment: .leading)
                            .padding(.horizontal, 52)
                            .padding(.vertical, 30)
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
                        MarkdownPreviewView(
                            markdown: document.previewMarkdown,
                            isOutlineVisible: isOutlineVisible,
                            baseURL: selectedNote.fileURL.deletingLastPathComponent()
                        )
                    }
                case .markdown:
                    MarkdownEditorView(
                        text: noteMarkdownBinding,
                        isEditable: noteErrorMessage == nil || !noteMarkdown.isEmpty,
                        autoFocus: isEditorFocused
                    )
                        .padding(.horizontal, 44)
                        .padding(.vertical, 22)
                        .background(Color(nsColor: .textBackgroundColor))
                        .onAppear {
                            isEditorFocused = true
                        }
                }
            }
        } else {
            emptyTaskNotesView(for: task)
        }
    }

    private var emptyNoteView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            Text("还没有笔记")
                .font(.headline)

            Button("开始写笔记") {
                displayMode = .markdown
                isEditorFocused = true
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .foregroundStyle(.secondary)
    }

    private func emptyTaskNotesView(for task: TaskItem) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.secondary)

            Text("这个任务还没有笔记")
                .font(.headline)

            if let noteErrorMessage {
                Text(noteErrorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 10) {
                Button {
                    noteCreationTask = task
                } label: {
                    Label("新建笔记", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    chooseExternalNote(for: task)
                } label: {
                    Label("关联 md 文件", systemImage: "link")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.secondary)
    }

    private var emptyWindow: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)

            Text("还没有可关联的任务")
                .font(.title3.weight(.semibold))

            Text("先在任务列表里创建任务，再查看或添加笔记。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
    }

    private func selectDefaultNoteIfNeeded(force: Bool = false) {
        guard let selectedTask else {
            selectedNoteID = nil
            return
        }

        if force || selectedNoteID == nil || !selectedTask.notes.contains(where: { $0.id == selectedNoteID }) {
            selectedNoteID = selectedTask.notes.first?.id
        }
    }

    private func loadSelectedNote() {
        guard let selectedNote else {
            noteMarkdown = ""
            noteErrorMessage = nil
            displayMode = .markdown
            return
        }

        do {
            noteMarkdown = try store.readNoteMarkdown(selectedNote)
            noteErrorMessage = nil
        } catch {
            noteMarkdown = ""
            noteErrorMessage = error.localizedDescription
        }

        displayMode = markdown.isEmpty ? .markdown : .preview
    }

    private var markdown: String {
        noteMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createLocalNote(for task: TaskItem, title: String) {
        do {
            let note = try store.createLocalNote(for: task, title: title, initialMarkdown: "# \(title)\n")
            selectedTaskID = task.id
            selectedNoteID = note.id
            noteErrorMessage = nil
        } catch {
            noteErrorMessage = error.localizedDescription
        }
    }

    private func chooseExternalNote(for task: TaskItem) {
        let panel = NSOpenPanel()
        panel.title = "选择 Markdown 文件"
        panel.prompt = "关联"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["md", "markdown"].compactMap { UTType(filenameExtension: $0) }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        attachExternalNote(for: task, filePath: url.path)
    }

    private func attachExternalNote(for task: TaskItem, filePath: String) {
        do {
            let note = try store.attachExternalNote(for: task, filePath: filePath)
            selectedTaskID = task.id
            selectedNoteID = note.id
            noteErrorMessage = nil
        } catch {
            noteErrorMessage = error.localizedDescription
        }
    }

    private func deleteNote(_ note: TaskNote, from task: TaskItem) {
        do {
            try store.deleteNoteReference(note, from: task)
            selectedTaskID = task.id
            if selectedNoteID == note.id {
                selectedNoteID = visibleTasks.first(where: { $0.id == task.id })?.notes.first?.id
            }
            noteErrorMessage = nil
        } catch {
            noteErrorMessage = error.localizedDescription
        }
    }

    private func noteExists(_ note: TaskNote) -> Bool {
        FileManager.default.fileExists(atPath: note.filePath)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func adjustNoteWindowZoom(by delta: Double) {
        noteWindowZoomScale = min(max(noteWindowZoomScale + delta, minNoteWindowZoomScale), maxNoteWindowZoomScale)
    }

    private func clampedSidebarWidth(_ width: Double) -> Double {
        min(max(width, minSidebarWidth), maxSidebarWidth)
    }
}

private struct ResizableNoteSidebarDivider: NSViewRepresentable {
    let onDragDelta: (CGFloat) -> Void
    let onDragEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NoteSidebarDividerView {
        let view = NoteSidebarDividerView()
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NoteSidebarDividerView, context: Context) {
        context.coordinator.onDragDelta = onDragDelta
        context.coordinator.onDragEnded = onDragEnded
    }

    final class Coordinator: NSObject, NoteSidebarDividerViewDelegate {
        var onDragDelta: ((CGFloat) -> Void)?
        var onDragEnded: (() -> Void)?

        func dividerView(_ view: NoteSidebarDividerView, didDragBy delta: CGFloat) {
            onDragDelta?(delta)
        }

        func dividerViewDidEndDrag(_ view: NoteSidebarDividerView) {
            onDragEnded?()
        }
    }
}

@MainActor
private protocol NoteSidebarDividerViewDelegate: AnyObject {
    func dividerView(_ view: NoteSidebarDividerView, didDragBy delta: CGFloat)
    func dividerViewDidEndDrag(_ view: NoteSidebarDividerView)
}

@MainActor
private final class NoteSidebarDividerView: NSView {
    weak var delegate: NoteSidebarDividerViewDelegate?

    private var isHovering = false
    private var isDragging = false
    private var dragOriginX: CGFloat = 0
    nonisolated(unsafe) private var eventMonitor: Any?

    override var isFlipped: Bool { true }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        guard window != nil else {
            clearInteractionState()
            return
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMonitoredEvent(event)
            }
            return event
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for area in trackingAreas {
            removeTrackingArea(area)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateHoverState(for: event)
        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoverState(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverState(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHovering(false)
    }

    override func mouseDown(with event: NSEvent) {
        dragOriginX = event.locationInWindow.x
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        updateHoverState(for: event)
        let delta = event.locationInWindow.x - dragOriginX
        delegate?.dividerView(self, didDragBy: delta)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        updateHoverState(for: event)
        needsDisplay = true
        delegate?.dividerViewDidEndDrag(self)
    }

    private func handleMonitoredEvent(_ event: NSEvent) {
        guard event.window === window else {
            clearInteractionState()
            return
        }

        if event.type == .leftMouseUp, isDragging {
            isDragging = false
            delegate?.dividerViewDidEndDrag(self)
        }

        updateHoverState(for: event)
    }

    private func updateHoverState(for event: NSEvent) {
        guard event.window === window else {
            setHovering(false)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        setHovering(bounds.contains(point))
    }

    private func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering
        needsDisplay = true
    }

    private func clearInteractionState() {
        let shouldRedraw = isHovering || isDragging
        isHovering = false
        isDragging = false
        if shouldRedraw {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let hairlineWidth = 1 / backingScale
        let lineWidth: CGFloat = isDragging ? 3 : (isHovering ? 2.5 : hairlineWidth)
        let lineColor: NSColor = if isDragging {
            .controlAccentColor
        } else if isHovering {
            .controlAccentColor.withAlphaComponent(0.72)
        } else {
            .separatorColor.withAlphaComponent(0.12)
        }

        lineColor.setFill()
        let lineX = ((bounds.maxX - lineWidth) * backingScale).rounded(.down) / backingScale
        let lineRect = NSRect(
            x: lineX,
            y: 0,
            width: lineWidth,
            height: bounds.height
        )
        lineRect.fill()
    }

    override func accessibilityLabel() -> String? {
        "调整任务列表宽度"
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .splitter
    }
}



private struct TaskTitleListItem: View {
    let task: TaskItem
    let selectedNoteID: TaskNote.ID?
    let isSelected: Bool
    let noteExists: (TaskNote) -> Bool
    let onSelectTask: () -> Void
    let onSelectNote: (TaskNote) -> Void
    let onCreateNote: () -> Void
    let onAttachExternalNote: () -> Void
    let onDeleteNote: (TaskNote) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var itemBackground: Color {
        if isSelected {
            return Color(hex: task.backgroundColorHex).opacity(isDark ? 0.24 : 0.36)
        }
        return isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.62)
    }

    private var itemStroke: Color {
        if isSelected {
            return Color.accentColor.opacity(isDark ? 0.45 : 0.32)
        }
        return isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelectTask) {
                Text(TaskDisplayText(task: task).title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(itemBackground)
                )
                .overlay(alignment: .leading) {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.accentColor.opacity(0.72))
                            .frame(width: 3)
                            .padding(.vertical, 8)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(itemStroke, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .contextMenu {
                Button(action: onCreateNote) {
                    Label("新建笔记", systemImage: "square.and.pencil")
                }

                Button(action: onAttachExternalNote) {
                    Label("关联 md 文件", systemImage: "link")
                }
            }

            if isSelected {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(task.notes) { note in
                        NoteListItem(
                            note: note,
                            isSelected: note.id == selectedNoteID,
                            exists: noteExists(note)
                        ) {
                            onSelectNote(note)
                        } onDelete: {
                            onDeleteNote(note)
                        }
                    }
                }
                .padding(.leading, 8)
                .contextMenu {
                    Button(action: onCreateNote) {
                        Label("新建笔记", systemImage: "square.and.pencil")
                    }

                    Button(action: onAttachExternalNote) {
                        Label("关联 md 文件", systemImage: "link")
                    }
                }
            }
        }
    }

}

private struct NoteListItem: View {
    let note: TaskNote
    let isSelected: Bool
    let exists: Bool
    let action: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: note.kind == .local ? "doc.text" : "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(exists ? .secondary : .red)
                    .frame(width: 14)

                Text(note.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(exists ? .primary : .red)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(exists ? note.filePath : "文件不存在：\(note.filePath)")
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label(deleteLabel, systemImage: note.kind == .local ? "trash" : "link.badge.minus")
            }
        }
    }

    private var deleteLabel: String {
        switch note.kind {
        case .local:
            "删除笔记"
        case .external:
            "解除关联"
        }
    }
}

private struct NoteToolbarButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .background(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.1), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct NoteCreationFormView: View {
    let task: TaskItem
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @FocusState private var isTitleFocused: Bool

    init(task: TaskItem, onCreate: @escaping (String) -> Void) {
        self.task = task
        self.onCreate = onCreate
        _title = State(initialValue: TaskDisplayText(task: task).title)
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("新建笔记")
                    .font(.system(size: 22, weight: .bold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("笔记标题")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("例如：上线排查记录", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTitleFocused)
            }

            HStack(spacing: 12) {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("创建") {
                    onCreate(title)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .padding(26)
        .frame(width: 420)
        .onAppear {
            isTitleFocused = true
        }
    }
}

private struct NoteTaskEditFormView: View {
    let task: TaskItem
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var description: String
    @FocusState private var isTitleFocused: Bool

    init(task: TaskItem, onSave: @escaping (String, String) -> Void) {
        self.task = task
        self.onSave = onSave

        let displayText = TaskDisplayText(task: task)
        _title = State(initialValue: displayText.title)
        _description = State(initialValue: displayText.description)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("编辑任务")
                    .font(.system(size: 24, weight: .bold))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("任务名称")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("例如：明天确认上线计划", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTitleFocused)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("任务描述")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $description)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 118)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    }
            }

            HStack(spacing: 12) {
                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("保存修改") {
                    onSave(title, description)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(28)
        .frame(width: 460)
        .onAppear {
            isTitleFocused = true
        }
    }
}

private enum NoteDisplayMode {
    case preview
    case markdown
}

private struct TaskNoteDocument {
    let markdown: String?
    let fallbackTitle: String

    var title: String {
        firstHeading ?? fallbackTitle
    }

    var previewMarkdown: String {
        markdown ?? ""
    }

    private var firstHeading: String? {
        guard let markdown else {
            return nil
        }

        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            if let title = Self.headingTitle(from: String(line)) {
                return title
            }
        }

        return nil
    }

    private static func headingTitle(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else {
            return nil
        }

        let markers = trimmed.prefix { $0 == "#" }
        guard (1...2).contains(markers.count) else {
            return nil
        }

        let title = trimmed.dropFirst(markers.count).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }
}
