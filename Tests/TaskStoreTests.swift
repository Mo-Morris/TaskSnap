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

@MainActor
@Test func taskStoreUpdatesAndPersistsTaskNotes() {
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

    #expect(didUpdate == true)
    #expect(store.tasks[0].noteMarkdown?.contains("上线前确认清单") == true)
    #expect(reloadedStore.tasks[0].noteMarkdown == store.tasks[0].noteMarkdown)
}

@MainActor
@Test func taskStoreAllowsClearingTaskNotes() {
    let urls = temporaryStoreURLs()
    let store = TaskStore(storeURL: urls.tasks, configurationURL: urls.configuration)

    _ = store.addManualTask(title: "确认上线计划", description: "记录发布窗口和回滚预案")
    _ = store.updateTaskNote(store.tasks[0], markdown: "## 上线前确认清单")

    let didClear = store.updateTaskNote(store.tasks[0], markdown: "")

    #expect(didClear == true)
    #expect(store.tasks[0].noteMarkdown == "")
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

    store.complete(store.tasks[0])
    store.complete(store.tasks[1])
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
