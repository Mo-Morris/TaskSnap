import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = [] {
        didSet {
            save()
        }
    }

    private let storeURL: URL
    private let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.storeURL = appSupport.appending(path: "TaskSnap/tasks.json")
        }

        load()
    }

    func addImageData(_ data: Data, title: String? = nil) {
        guard NSImage(data: data) != nil else {
            return
        }

        let taskTitle = title ?? "截图任务 \(titleFormatter.string(from: Date()))"
        tasks.insert(TaskItem(title: taskTitle, imageData: data), at: 0)
    }

    func toggle(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else {
            return
        }

        tasks[index].isDone.toggle()
    }

    func delete(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
    }

    func clearCompleted() {
        tasks.removeAll { $0.isDone }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: storeURL)
            tasks = try JSONDecoder().decode([TaskItem].self, from: data)
        } catch {
            tasks = []
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to persist tasks: \(error)")
        }
    }
}
