import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskNoteWindowView: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedTaskID: TaskItem.ID?

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
    @FocusState private var isEditorFocused: Bool

    private var visibleTasks: [TaskItem] {
        store.visibleTasks
    }

    private var selectedTask: TaskItem? {
        guard let selectedTaskID else {
            return visibleTasks.first
        }

        return visibleTasks.first { $0.id == selectedTaskID } ?? visibleTasks.first
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
        HStack(spacing: 0) {
            if isTaskSidebarCollapsed {
                collapsedTaskSidebar
            } else {
                taskTitleSidebar
            }

            Divider()

            documentPane
        }
        .frame(minWidth: 820, minHeight: 560)
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

            Text("从任务列表点击查看或添加笔记后进入这里；左侧只显示标题，用来快速切换当前任务。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(visibleTasks) { task in
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
        .frame(width: 292)
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

                Text(note.map { "\(TaskDisplayText(task: task).title) · \($0.kind.label) · 自动保存" } ?? "\(TaskDisplayText(task: task).title) · 还没有笔记")
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
                        MarkdownPreviewView(markdown: document.previewMarkdown, isOutlineVisible: isOutlineVisible)
                    }
                case .markdown:
                    TextEditor(text: noteMarkdownBinding)
                        .font(.system(size: 14, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 44)
                        .padding(.vertical, 22)
                        .background(Color(nsColor: .textBackgroundColor))
                        .focused($isEditorFocused)
                        .disabled(noteErrorMessage != nil && noteMarkdown.isEmpty)
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
                VStack(alignment: .leading, spacing: 7) {
                    Text(TaskDisplayText(task: task).title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
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

    private var statusText: String {
        let noteCount = task.notes.count
        let noteState = noteCount > 0 ? "\(noteCount) 篇笔记" : "空笔记"
        let doneState = task.status == .completed ? "已完成" : "进行中"
        return "\(noteState) · \(doneState)"
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
            .padding(.trailing, 24)
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
        .frame(maxWidth: isOutlineVisible ? 1080 : 840, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 52)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

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

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = CopyableCodeTextView(
            frame: NSRect(x: 0, y: 0, width: 100, height: 100),
            textContainer: textContainer
        )
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.linkTextAttributes = [
            NSAttributedString.Key.foregroundColor: NSColor.linkColor,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        applyContent(to: textView, context: context)
        updateLayout(for: textView, in: scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        updateLayout(for: textView, in: scrollView)
        applyContent(to: textView, context: context)
        context.coordinator.scrollToHeadingIfNeeded(selectedOutlineItemID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func applyContent(to textView: NSTextView, context: Context) {
        let rendered = MarkdownAttributedRenderer.render(blocks)
        if context.coordinator.lastRenderedText != rendered.string {
            textView.textStorage?.setAttributedString(rendered.attributedString)
            if let codeTextView = textView as? CopyableCodeTextView {
                codeTextView.codeBlocks = rendered.codeBlocks
            }
            context.coordinator.lastRenderedText = rendered.string
            context.coordinator.headingRanges = rendered.headingRanges
        }
    }

    private func updateLayout(for textView: NSTextView, in scrollView: NSScrollView) {
        let scrollbarGutter: CGFloat = 28
        let contentWidth = max(scrollView.contentSize.width, 100)
        let textWidth = max(contentWidth - scrollbarGutter, 100)
        textView.textContainer?.containerSize = NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: textWidth,
            height: max(scrollView.contentSize.height, textView.intrinsicContentSize.height, 100)
        )
    }

    final class Coordinator {
        weak var textView: NSTextView?
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

private struct MarkdownCodeRange {
    let range: NSRange
    let code: String
}

private final class CopyableCodeTextView: NSTextView {
    var codeBlocks: [MarkdownCodeRange] = []

    private let copyButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var hoveredCode: String?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configureCopyButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCopyButton()
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

    private func configureCopyButton() {
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制代码")
        copyButton.bezelStyle = .rounded
        copyButton.isBordered = true
        copyButton.frame = NSRect(x: 0, y: 0, width: 30, height: 28)
        copyButton.target = self
        copyButton.action = #selector(copyHoveredCode)
        copyButton.isHidden = true
        addSubview(copyButton)
    }

    private func updateCopyButton(for point: NSPoint) {
        guard
            let layoutManager,
            let textContainer
        else {
            hideCopyButton()
            return
        }

        let textContainerOrigin = textContainerOrigin(layoutManager: layoutManager, textContainer: textContainer)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        guard let block = codeBlocks.first(where: { NSLocationInRange(characterIndex, $0.range) }) else {
            hideCopyButton()
            return
        }

        hoveredCode = block.code
        let glyphRange = layoutManager.glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
        let codeRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        copyButton.frame.origin = NSPoint(x: max(codeRect.maxX - 38, codeRect.minX), y: codeRect.maxY - 34)
        copyButton.isHidden = false
    }

    private func hideCopyButton() {
        hoveredCode = nil
        copyButton.isHidden = true
    }

    private func textContainerOrigin(layoutManager: NSLayoutManager, textContainer: NSTextContainer) -> NSPoint {
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSPoint(x: textContainerInset.width, y: textContainerInset.height - usedRect.minY)
    }

    @objc private func copyHoveredCode() {
        guard let hoveredCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hoveredCode, forType: .string)
    }

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
        guard
            let layoutManager,
            let textContainer
        else {
            return nil
        }

        let textContainerOrigin = textContainerOrigin(layoutManager: layoutManager, textContainer: textContainer)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }
}

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
                appendSpacingIfNeeded(to: result, lines: level == 1 ? 0 : 1)
                let start = result.length
                result.append(inlineAttributedString(
                    text,
                    font: headingFont(for: level),
                    color: .labelColor,
                    paragraphStyle: paragraphStyle(lineSpacing: 2, paragraphSpacing: 10)
                ))
                headingRanges[headingIndex] = NSRange(location: start, length: max(result.length - start, 1))
                headingIndex += 1
                result.append(NSAttributedString(string: "\n\n"))

            case let .paragraph(text):
                result.append(inlineAttributedString(
                    text,
                    font: .systemFont(ofSize: 15),
                    color: .labelColor,
                    paragraphStyle: paragraphStyle(lineSpacing: 7, paragraphSpacing: 8)
                ))
                result.append(NSAttributedString(string: "\n\n"))

            case let .unorderedList(items):
                appendList(items, ordered: false, to: result)

            case let .orderedList(items):
                appendList(items, ordered: true, to: result)

            case let .codeBlock(code):
                appendSpacingIfNeeded(to: result, lines: 1)
                let start = result.length
                result.append(NSAttributedString(
                    string: code.isEmpty ? " " : code,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                        .foregroundColor: NSColor.labelColor,
                        .backgroundColor: NSColor.labelColor.withAlphaComponent(0.07),
                        .paragraphStyle: paragraphStyle(lineSpacing: 4, paragraphSpacing: 12)
                    ]
                ))
                codeBlocks.append(MarkdownCodeRange(range: NSRange(location: start, length: max(result.length - start, 1)), code: code))
                result.append(NSAttributedString(string: "\n\n"))
            }
        }

        while result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        return (result, headingRanges, codeBlocks, result.string)
    }

    private static func appendList(_ items: [String], ordered: Bool, to result: NSMutableAttributedString) {
        let style = paragraphStyle(lineSpacing: 5, paragraphSpacing: 4, headIndent: 28)
        for (index, item) in items.enumerated() {
            let marker = ordered ? "\(index + 1). " : "• "
            result.append(NSAttributedString(
                string: marker,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: style
                ]
            ))
            result.append(inlineAttributedString(
                item,
                font: .systemFont(ofSize: 15),
                color: .labelColor,
                paragraphStyle: style
            ))
            result.append(NSAttributedString(string: "\n"))
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

        attributed.addAttributes(baseAttributes, range: NSRange(location: 0, length: attributed.length))
        return attributed
    }

    private static func headingFont(for level: Int) -> NSFont {
        switch level {
        case 1:
            .systemFont(ofSize: 28, weight: .bold)
        case 2:
            .systemFont(ofSize: 22, weight: .bold)
        case 3:
            .systemFont(ofSize: 18, weight: .semibold)
        default:
            .systemFont(ofSize: 16, weight: .semibold)
        }
    }

    private static func paragraphStyle(
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        headIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.headIndent = headIndent
        style.firstLineHeadIndent = 0
        return style
    }

    private static func appendSpacingIfNeeded(to result: NSMutableAttributedString, lines: Int) {
        guard result.length > 0 else { return }
        result.append(NSAttributedString(string: String(repeating: "\n", count: lines)))
    }
}

private struct MarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case heading(level: Int, text: String)
        case paragraph(String)
        case unorderedList([String])
        case orderedList([String])
        case codeBlock(String)
    }
}

private enum MarkdownBlockParser {
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
        var isInCodeBlock = false

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

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if isInCodeBlock {
                    blocks.append(MarkdownBlock(kind: .codeBlock(codeLines.joined(separator: "\n"))))
                    codeLines.removeAll()
                    isInCodeBlock = false
                } else {
                    flushOpenBlocks()
                    isInCodeBlock = true
                }
                continue
            }

            if isInCodeBlock {
                codeLines.append(line)
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

        if isInCodeBlock {
            blocks.append(MarkdownBlock(kind: .codeBlock(codeLines.joined(separator: "\n"))))
        }
        flushOpenBlocks()

        return blocks
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
