import AppKit
import Foundation
import Testing
@testable import TaskSnap

@MainActor
@Test func taskStoreAddsAndTogglesImageTasks() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "TaskSnapTests")
        .appending(path: UUID().uuidString)
        .appending(path: "tasks.json")

    guard let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=") else {
        Issue.record("Could not create test PNG")
        return
    }

    let store = TaskStore(storeURL: url)
    store.addImageData(png, title: "测试任务")

    #expect(store.tasks.count == 1)
    #expect(store.tasks[0].title == "测试任务")
    #expect(store.tasks[0].isDone == false)

    store.toggle(store.tasks[0])
    #expect(store.tasks[0].isDone == true)
}
