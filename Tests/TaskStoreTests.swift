import AppKit
import Foundation
import Testing
@testable import TaskSnap

@MainActor
@Test func taskStoreAddsAndCompletesImageTasksAfterVisionConfiguration() async throws {
    let urls = temporaryStoreURLs()
    let store = TaskStore(
        storeURL: urls.tasks,
        configurationURL: urls.configuration,
        visionSummarizer: FakeVisionSummarizer(summary: "测试任务")
    )

    try await store.saveVisionConfiguration(VisionModelConfiguration(
        endpoint: "https://example.com",
        apiKey: "key",
        model: "vision-model"
    ))

    let didAdd = store.addImageData(testPNG, title: "测试任务")
    try await Task.sleep(for: .milliseconds(50))

    #expect(didAdd == true)
    #expect(store.tasks.count == 1)
    #expect(store.tasks[0].title == "测试任务")
    #expect(store.tasks[0].status == .active)

    store.complete(store.tasks[0])
    #expect(store.tasks[0].status == .completed)
    #expect(store.visibleTasks.count == 1)
    #expect(store.visibleTasks[0].status == .completed)
}

@MainActor
@Test func taskStoreRejectsImagesBeforeVisionConfiguration() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    let didAdd = store.addImageData(testPNG, title: "测试任务")

    #expect(didAdd == false)
    #expect(store.tasks.isEmpty)
}

@MainActor
@Test func taskStoreAddsManualTasksWithoutVisionConfiguration() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    let didAdd = store.addManualTask(title: "整理周会待办", description: "记录本周要跟进的接口、发布和验收事项")

    #expect(didAdd == true)
    #expect(store.tasks.count == 1)
    #expect(store.tasks[0].title == "整理周会待办")
    #expect(store.tasks[0].description == "记录本周要跟进的接口、发布和验收事项")
    #expect(store.tasks[0].inputSource == .manual)
    #expect(store.tasks[0].imageData == nil)
    #expect(TaskItem.manualIconNames.contains(store.tasks[0].manualIconName ?? ""))
}

@MainActor
@Test func taskStoreUpdatesTaskTitleAndDescription() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "整理周会待办", description: "记录本周要跟进的接口、发布和验收事项")

    let didUpdate = store.updateTask(
        store.tasks[0],
        title: " 确认上线计划 ",
        description: " 和产品确认发布时间、灰度范围和回滚预案 "
    )

    #expect(didUpdate == true)
    #expect(store.tasks[0].title == "确认上线计划")
    #expect(store.tasks[0].description == "和产品确认发布时间、灰度范围和回滚预案")
}

@MainActor
@Test func taskStoreRejectsTaskUpdateWithEmptyTitle() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "整理周会待办", description: "记录本周要跟进的接口、发布和验收事项")
    let originalTask = store.tasks[0]

    let didUpdate = store.updateTask(
        originalTask,
        title: "   ",
        description: "和产品确认发布时间、灰度范围和回滚预案"
    )

    #expect(didUpdate == false)
    #expect(store.tasks[0] == originalTask)
}

@MainActor
@Test func taskStoreRejectsTaskUpdateWithEmptyDescription() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "整理周会待办", description: "记录本周要跟进的接口、发布和验收事项")
    let originalTask = store.tasks[0]

    let didUpdate = store.updateTask(
        originalTask,
        title: "确认上线计划",
        description: "\n\t "
    )

    #expect(didUpdate == false)
    #expect(store.tasks[0] == originalTask)
}

@MainActor
@Test func taskStoreRejectsTaskUpdateForMissingTask() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    let didUpdate = store.updateTask(
        TaskItem(title: "不存在的任务", description: "不会写入列表"),
        title: "确认上线计划",
        description: "和产品确认发布时间、灰度范围和回滚预案"
    )

    #expect(didUpdate == false)
    #expect(store.tasks.isEmpty)
}

@Test func markdownParserRecognizesHorizontalRules() {
    let blocks = MarkdownBlockParser.parse(
        """
        上半部分
        ---
        下半部分
        """
    )

    #expect(blocks.count == 3)
    if case .paragraph("上半部分") = blocks[0].kind {} else {
        Issue.record("Expected first block to be a paragraph.")
    }
    if case .horizontalRule = blocks[1].kind {} else {
        Issue.record("Expected --- to be parsed as a horizontal rule.")
    }
    if case .paragraph("下半部分") = blocks[2].kind {} else {
        Issue.record("Expected final block to be a paragraph.")
    }
}

@Test func markdownParserRecognizesTables() {
    let blocks = MarkdownBlockParser.parse(
        """
        | 任务 | 状态 | 负责人 |
        | :--- | :---: | ---: |
        | 发布 | 进行中 | 小王 |
        | 回归 | 完成 | 小李 |
        """
    )

    #expect(blocks.count == 1)
    guard case let .table(table) = blocks[0].kind else {
        Issue.record("Expected table markdown to be parsed as a table block.")
        return
    }

    #expect(table.headers == ["任务", "状态", "负责人"])
    #expect(table.alignments == [.leading, .center, .trailing])
    #expect(table.rows == [
        ["发布", "进行中", "小王"],
        ["回归", "完成", "小李"]
    ])
}

@Test @MainActor func markdownImageResolverResolvesRelativeNotePaths() throws {
    let base = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
    let markdown = "![截图](./screenshot.png)"
    let attributed = try NSMutableAttributedString(
        markdown: markdown,
        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace),
        baseURL: base
    )
    let key = NSAttributedString.Key("NSImageURL")
    var resolved: URL?
    attributed.enumerateAttribute(key, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
        if let raw = value as? URL {
            resolved = MarkdownImageAttachmentRenderer.resolveImageURL(raw, baseURL: base)
        }
    }
    #expect(resolved?.path == "/tmp/notes/screenshot.png")
}

@Test @MainActor func markdownPreviewEmbedsLocalImageAttachment() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let imageURL = directory.appending(path: "preview.png")
    try testPNG.write(to: imageURL)

    let markdown = "![截图](./preview.png)"
    guard let attributed = try? NSMutableAttributedString(
        markdown: markdown,
        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace),
        baseURL: directory
    ) else {
        Issue.record("Expected markdown image syntax to parse.")
        return
    }

    MarkdownImageAttachmentRenderer.applyImageAttachments(
        to: attributed,
        baseURL: directory,
        fallbackAttributes: [:]
    )

    #expect(attributed.string.contains("\u{FFFC}"))
}

@MainActor
@Test func taskStoreUpdatesAndPersistsTaskNotes() throws {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "确认上线计划", description: "记录发布窗口和回滚预案")

    let didUpdate = store.updateTaskNote(
        store.tasks[0],
        markdown: """
        ## 上线前确认清单
        - 确认发布时间
        - 灰度范围
        """
    )

    let reloadedStore = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)
    let storedMarkdown = try store.readNoteMarkdown(store.tasks[0].notes[0])
    let reloadedMarkdown = try reloadedStore.readNoteMarkdown(reloadedStore.tasks[0].notes[0])

    #expect(didUpdate == true)
    #expect(store.tasks[0].noteMarkdown == nil)
    #expect(store.tasks[0].notes.count == 1)
    #expect(storedMarkdown.contains("上线前确认清单") == true)
    #expect(reloadedStore.tasks[0].notes == store.tasks[0].notes)
    #expect(reloadedMarkdown == storedMarkdown)
}

@MainActor
@Test func taskStoreAllowsClearingTaskNotes() throws {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "确认上线计划", description: "记录发布窗口和回滚预案")
    _ = store.updateTaskNote(store.tasks[0], markdown: "## 上线前确认清单")

    let didClear = store.updateTaskNote(store.tasks[0], markdown: "")

    #expect(didClear == true)
    #expect(try store.readNoteMarkdown(store.tasks[0].notes[0]) == "")
}

@MainActor
@Test func taskStoreCreatesMultipleLocalNotesForOneTask() throws {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "确认上线计划", description: "记录发布窗口和回滚预案")

    let first = try store.createLocalNote(for: store.tasks[0], title: "发布清单", initialMarkdown: "## 发布清单")
    let second = try store.createLocalNote(for: store.tasks[0], title: "回滚预案", initialMarkdown: "## 回滚预案")

    #expect(store.tasks[0].notes.count == 2)
    #expect(first.kind == .local)
    #expect(second.kind == .local)
    #expect(first.filePath != second.filePath)
    #expect(try store.readNoteMarkdown(first) == "## 发布清单")
    #expect(try store.readNoteMarkdown(second) == "## 回滚预案")
}

@MainActor
@Test func taskStoreAttachesExternalMarkdownAndWritesOriginalFile() throws {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)
    let externalURL = urls.tasks.deletingLastPathComponent().appending(path: "external-note.md")
    try FileManager.default.createDirectory(at: externalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "## 外部笔记\n原始内容".write(to: externalURL, atomically: true, encoding: .utf8)

    _ = store.addManualTask(title: "确认上线计划", description: "记录发布窗口和回滚预案")

    let note = try store.attachExternalNote(for: store.tasks[0], filePath: externalURL.path)
    try store.updateNoteMarkdown(note, markdown: "## 外部笔记\n已更新")

    #expect(note.kind == .external)
    #expect(store.tasks[0].notes.count == 1)
    #expect(try String(contentsOf: externalURL, encoding: .utf8) == "## 外部笔记\n已更新")
}

@MainActor
@Test func taskStoreRejectsInvalidExternalMarkdownPaths() throws {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)
    let textURL = urls.tasks.deletingLastPathComponent().appending(path: "not-markdown.txt")
    try FileManager.default.createDirectory(at: textURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "不是 markdown".write(to: textURL, atomically: true, encoding: .utf8)

    _ = store.addManualTask(title: "确认上线计划", description: "记录发布窗口和回滚预案")

    #expect(throws: TaskNoteError.emptyPath) {
        try store.attachExternalNote(for: store.tasks[0], filePath: " ")
    }
    #expect(throws: TaskNoteError.fileDoesNotExist) {
        try store.attachExternalNote(for: store.tasks[0], filePath: urls.tasks.deletingLastPathComponent().appending(path: "missing.md").path)
    }
    #expect(throws: TaskNoteError.unsupportedFileType) {
        try store.attachExternalNote(for: store.tasks[0], filePath: textURL.path)
    }
    #expect(store.tasks[0].notes.isEmpty)
}

@MainActor
@Test func taskStoreDeletesNoteReferencesByKind() throws {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)
    let externalURL = urls.tasks.deletingLastPathComponent().appending(path: "external-note.md")
    try FileManager.default.createDirectory(at: externalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "## 外部笔记".write(to: externalURL, atomically: true, encoding: .utf8)

    _ = store.addManualTask(title: "确认上线计划", description: "记录发布窗口和回滚预案")
    let local = try store.createLocalNote(for: store.tasks[0], title: "本地笔记", initialMarkdown: "## 本地笔记")
    let external = try store.attachExternalNote(for: store.tasks[0], filePath: externalURL.path)

    try store.deleteNoteReference(external, from: store.tasks[0])
    #expect(FileManager.default.fileExists(atPath: externalURL.path))
    #expect(store.tasks[0].notes.count == 1)

    try store.deleteNoteReference(local, from: store.tasks[0])
    #expect(!FileManager.default.fileExists(atPath: local.filePath))
    #expect(store.tasks[0].notes.isEmpty)
}

@MainActor
@Test func taskStoreRejectsNoteUpdateForMissingTask() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    let didUpdate = store.updateTaskNote(
        TaskItem(title: "不存在的任务", description: "不会写入列表"),
        markdown: "## 不会保存"
    )

    #expect(didUpdate == false)
    #expect(store.tasks.isEmpty)
}

@MainActor
@Test func taskStoreRestoresCompletedTasks() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "整理周会待办", description: "记录本周要跟进的接口、发布和验收事项")
    store.complete(store.tasks[0])
    store.restore(store.tasks[0])

    #expect(store.tasks[0].status == .active)
}

@MainActor
@Test func taskStoreArchivesTasksWithoutDeletingThem() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "整理周会待办", description: "记录本周要跟进的接口、发布和验收事项")

    store.archive(store.tasks[0])

    #expect(store.tasks.count == 1)
    #expect(store.tasks[0].status == .archived)
    #expect(store.visibleTasks.isEmpty)
}

@MainActor
@Test func taskStoreArchivesCompletedTasksOnly() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "进行中任务", description: "继续显示在主列表")
    _ = store.addManualTask(title: "已完成任务 A", description: "会进入归档")
    _ = store.addManualTask(title: "已完成任务 B", description: "也会进入归档")

    let completedA = store.tasks.first { $0.title == "已完成任务 A" }!
    let completedB = store.tasks.first { $0.title == "已完成任务 B" }!
    store.complete(completedA)
    store.complete(completedB)
    store.archiveCompleted()

    #expect(store.tasks.map(\.status).filter { $0 == .archived }.count == 2)
    #expect(store.visibleTasks.count == 1)
    #expect(store.visibleTasks[0].title == "进行中任务")
    #expect(store.activeTaskCount == 1)
}

@MainActor
@Test func taskStoreMigratesLegacyIncompleteTasksToActive() throws {
    let urls = temporaryStoreURLs()
    try writeLegacyTasksJSON(
        """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "title": "旧进行中任务",
            "createdAt": 0,
            "isDone": false
          }
        ]
        """,
        to: urls.tasks
    )

    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    #expect(store.tasks.count == 1)
    #expect(store.tasks[0].status == .active)
}

@MainActor
@Test func taskStoreMigratesLegacyCompletedTasksToCompleted() throws {
    let urls = temporaryStoreURLs()
    try writeLegacyTasksJSON(
        """
        [
          {
            "id": "22222222-2222-2222-2222-222222222222",
            "title": "旧已完成任务",
            "createdAt": 0,
            "isDone": true
          }
        ]
        """,
        to: urls.tasks
    )

    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    #expect(store.tasks.count == 1)
    #expect(store.tasks[0].status == .completed)
    #expect(store.visibleTasks.count == 1)
}

@MainActor
@Test func taskStoreMigratesLegacyInlineMarkdownToLocalNoteFile() throws {
    let urls = temporaryStoreURLs()
    try writeLegacyTasksJSON(
        """
        [
          {
            "id": "33333333-3333-3333-3333-333333333333",
            "title": "旧笔记任务",
            "createdAt": 0,
            "status": "active",
            "noteMarkdown": "## 旧笔记\\n- 迁移到文件"
          }
        ]
        """,
        to: urls.tasks
    )

    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)
    let reloadedStore = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)
    let migratedMarkdown = try store.readNoteMarkdown(store.tasks[0].notes[0])

    #expect(store.tasks.count == 1)
    #expect(store.tasks[0].noteMarkdown == nil)
    #expect(store.tasks[0].notes.count == 1)
    #expect(store.tasks[0].notes[0].kind == .local)
    #expect(migratedMarkdown.contains("迁移到文件") == true)
    #expect(reloadedStore.tasks[0].notes == store.tasks[0].notes)
}

@MainActor
@Test func taskStoreToggleCompletionFlipsActiveAndCompleted() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "整理周会待办", description: "记录本周要跟进的接口、发布和验收事项")

    store.toggleCompletion(store.tasks[0])
    #expect(store.tasks[0].status == .completed)

    store.toggleCompletion(store.tasks[0])
    #expect(store.tasks[0].status == .active)
}

@MainActor
@Test func taskStoreToggleCompletionDoesNothingOnArchivedTasks() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "已归档任务", description: "在归档列表中不会被切换状态")
    store.archive(store.tasks[0])

    store.toggleCompletion(store.tasks[0])

    #expect(store.tasks[0].status == .archived)
}

@MainActor
@Test func taskStoreUnarchiveRestoresTaskToActive() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "待恢复的归档任务", description: "撤销归档后应该回到任务列表")
    store.archive(store.tasks[0])

    store.unarchive(store.tasks[0])

    #expect(store.tasks[0].status == .active)
    #expect(store.visibleTasks.count == 1)
    #expect(store.archivedTasks.isEmpty)
}

@MainActor
@Test func taskStorePermanentlyDeletesArchivedTask() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "待删除归档任务", description: "永久删除后不应再存在")
    store.archive(store.tasks[0])

    store.permanentlyDelete(store.tasks[0])

    #expect(store.tasks.isEmpty)
    #expect(store.archivedTasks.isEmpty)
}

@MainActor
@Test func taskStorePermanentlyDeleteIgnoresNonArchivedTasks() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "进行中任务", description: "不在归档中，不应被永久删除")

    store.permanentlyDelete(store.tasks[0])

    #expect(store.tasks.count == 1)
    #expect(store.tasks[0].status == .active)
}

@MainActor
@Test func taskStorePermanentlyDeletePersistsRemoval() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "待删除归档任务", description: "永久删除后重载也不存在")
    store.archive(store.tasks[0])
    store.permanentlyDelete(store.tasks[0])

    let reloadedStore = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    #expect(reloadedStore.tasks.isEmpty)
}

@MainActor
@Test func taskStoreUnarchiveIgnoresNonArchivedTasks() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "进行中任务", description: "撤销归档对它无效")

    store.unarchive(store.tasks[0])

    #expect(store.tasks[0].status == .active)
}

@MainActor
@Test func taskStoreArchivedTasksOnlyContainsArchivedItems() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "进行中任务", description: "不在归档列表")
    _ = store.addManualTask(title: "已完成任务", description: "也不在归档列表")
    _ = store.addManualTask(title: "归档任务", description: "在归档列表里")

    store.complete(store.tasks[1])
    store.archive(store.tasks[0])

    #expect(store.archivedTasks.count == 1)
    #expect(store.archivedTasks[0].title == "归档任务")
}

@MainActor
@Test func taskStorePersistsArchivedStatus() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "待归档任务", description: "归档后仍保存在 tasks.json")
    store.archive(store.tasks[0])

    let reloadedStore = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    #expect(reloadedStore.tasks.count == 1)
    #expect(reloadedStore.tasks[0].status == .archived)
    #expect(reloadedStore.visibleTasks.isEmpty)
}

@MainActor
@Test func savingVisionConfigurationValidatesBeforePersisting() async throws {
    let urls = temporaryStoreURLs()
    let summarizer = FakeVisionSummarizer(summary: "整理登录页文案")
    let store = TaskStore(
        storeURL: urls.tasks,
        configurationURL: urls.configuration,
        visionSummarizer: summarizer
    )

    try await store.saveVisionConfiguration(VisionModelConfiguration(
        endpoint: " https://example.com ",
        apiKey: " key ",
        model: " vision-model "
    ))

    #expect(summarizer.didValidate == true)
    #expect(store.visionConfiguration?.endpoint == "https://example.com")
    #expect(store.visionConfiguration?.apiKey == "key")
    #expect(store.visionConfiguration?.model == "vision-model")
    #expect(FileManager.default.fileExists(atPath: urls.configuration.path))
}

@MainActor
@Test func configuredVisionModelSummarizesNewImageTasks() async throws {
    let urls = temporaryStoreURLs()
    let summarizer = FakeVisionSummarizer(summary: "检查结算页异常")
    let store = TaskStore(
        storeURL: urls.tasks,
        configurationURL: urls.configuration,
        visionSummarizer: summarizer
    )

    try await store.saveVisionConfiguration(VisionModelConfiguration(
        endpoint: "https://example.com",
        apiKey: "key",
        model: "vision-model"
    ))

    let didAdd = store.addImageData(testPNG, title: "截图任务")
    try await Task.sleep(for: .milliseconds(50))

    #expect(didAdd == true)
    #expect(store.tasks.first?.title == "检查结算页异常")
}

@MainActor
@Test func taskStoreCompletingTaskMovesItToBottomOfVisibleList() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "C", description: "最早")
    _ = store.addManualTask(title: "B", description: "中间")
    _ = store.addManualTask(title: "A", description: "最新")

    #expect(store.visibleTasks.map(\.title) == ["A", "B", "C"])

    let taskB = store.tasks.first { $0.title == "B" }!
    store.complete(taskB)

    #expect(store.visibleTasks.map(\.title) == ["A", "C", "B"])
    #expect(store.visibleTasks.last?.title == "B")
    #expect(store.visibleTasks.last?.status == .completed)
}

@MainActor
@Test func taskStoreRestoringTaskMovesItToTopOfVisibleList() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "C", description: "最早")
    _ = store.addManualTask(title: "B", description: "中间")
    _ = store.addManualTask(title: "A", description: "最新")

    let taskC = store.tasks.first { $0.title == "C" }!
    store.complete(taskC)

    #expect(store.visibleTasks.map(\.title) == ["A", "B", "C"])

    store.restore(taskC)

    #expect(store.visibleTasks.first?.title == "C")
    #expect(store.visibleTasks.first?.status == .active)
    #expect(store.visibleTasks.map(\.title) == ["C", "A", "B"])
}

@MainActor
@Test func taskStoreCompletingTaskKeepsArchivedTasksInPlace() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "C", description: "最早")
    _ = store.addManualTask(title: "B", description: "中间")
    _ = store.addManualTask(title: "A", description: "最新")

    let taskC = store.tasks.first { $0.title == "C" }!
    store.archive(taskC)

    let taskA = store.tasks.first { $0.title == "A" }!
    store.complete(taskA)

    #expect(store.archivedTasks.map(\.title) == ["C"])
    #expect(store.visibleTasks.map(\.title) == ["B", "A"])
    #expect(store.visibleTasks.last?.status == .completed)
}

@MainActor
@Test func taskStoreToggleCompletionRepositionsTask() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "C", description: "最早")
    _ = store.addManualTask(title: "B", description: "中间")
    _ = store.addManualTask(title: "A", description: "最新")

    let taskA = store.tasks.first { $0.title == "A" }!
    store.toggleCompletion(taskA)
    #expect(store.visibleTasks.map(\.title) == ["B", "C", "A"])
    #expect(store.visibleTasks.last?.status == .completed)

    store.toggleCompletion(taskA)
    #expect(store.visibleTasks.first?.title == "A")
    #expect(store.visibleTasks.first?.status == .active)
}

@MainActor
@Test func taskStoreMovesImageTasks() async throws {
    let urls = temporaryStoreURLs()
    let store = TaskStore(
        storeURL: urls.tasks,
        configurationURL: urls.configuration,
        visionSummarizer: FakeVisionSummarizer(summary: "")
    )

    try await store.saveVisionConfiguration(VisionModelConfiguration(
        endpoint: "https://example.com",
        apiKey: "key",
        model: "vision-model"
    ))

    _ = store.addImageData(testPNG, title: "第三个任务")
    _ = store.addImageData(testPNG, title: "第二个任务")
    _ = store.addImageData(testPNG, title: "第一个任务")
    try await Task.sleep(for: .milliseconds(50))

    let firstTask = store.tasks[0]
    store.move(firstTask, to: 3)

    #expect(store.tasks.map(\.title) == ["第二个任务", "第三个任务", "第一个任务"])
}

private func temporaryStoreURLs() -> (tasks: URL, configuration: URL) {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "TaskSnapTests")
        .appending(path: UUID().uuidString)

    return (
        directory.appending(path: "tasks.json"),
        directory.appending(path: "vision-model.json")
    )
}

private func writeLegacyTasksJSON(_ json: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(json.utf8).write(to: url)
}

private let testPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!

private final class FakeVisionSummarizer: VisionSummarizing, @unchecked Sendable {
    var didValidate = false
    private let summaries: SummaryQueue

    init(summary: String) {
        summaries = SummaryQueue([summary])
    }

    init(summaries: [String]) {
        self.summaries = SummaryQueue(summaries)
    }

    func summarize(imageData: Data, configuration: VisionModelConfiguration) async throws -> String {
        await summaries.next()
    }

    func validate(configuration: VisionModelConfiguration) async throws {
        didValidate = true
    }
}

private actor SummaryQueue {
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        if values.count > 1 {
            return values.removeFirst()
        }

        return values.first ?? ""
    }
}
