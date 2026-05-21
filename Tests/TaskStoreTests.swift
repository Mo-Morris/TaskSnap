import AppKit
import Foundation
import Testing
@testable import TaskSnap

@MainActor
@Test func taskStoreAddsAndTogglesImageTasksAfterVisionConfiguration() async throws {
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
    #expect(store.tasks[0].isDone == false)

    store.toggle(store.tasks[0])
    #expect(store.tasks[0].isDone == true)
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
        visionSummarizer: FakeVisionSummarizer(summaries: ["第三个任务", "第二个任务", "第一个任务"])
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
