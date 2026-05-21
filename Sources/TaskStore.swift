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
    @Published private(set) var visionConfiguration: VisionModelConfiguration?
    @Published private(set) var summarizingTaskIDs: Set<TaskItem.ID> = []

    private let storeURL: URL
    private let configurationURL: URL
    private let visionSummarizer: VisionSummarizing
    private let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    init(
        storeURL: URL? = nil,
        configurationURL: URL? = nil,
        visionSummarizer: VisionSummarizing = OpenAICompatibleVisionClient()
    ) {
        self.visionSummarizer = visionSummarizer

        if let storeURL {
            self.storeURL = storeURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.storeURL = appSupport.appending(path: "TaskSnap/tasks.json")
        }

        if let configurationURL {
            self.configurationURL = configurationURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.configurationURL = appSupport.appending(path: "TaskSnap/vision-model.json")
        }

        load()
        loadConfiguration()
    }

    @discardableResult
    func addImageData(_ data: Data, title: String? = nil) -> Bool {
        guard visionConfiguration != nil else {
            return false
        }

        guard NSImage(data: data) != nil else {
            return false
        }

        let taskTitle = title ?? "截图任务 \(titleFormatter.string(from: Date()))"
        let task = TaskItem(title: taskTitle, imageData: data)
        tasks.insert(task, at: 0)
        summarizeTaskIfConfigured(task)
        return true
    }

    @discardableResult
    func addImageFromPasteboard() -> Bool {
        guard visionConfiguration != nil else {
            return false
        }

        guard let data = NSPasteboard.general.imageData() else {
            return false
        }

        addImageData(data, title: "剪贴板截图 \(titleFormatter.string(from: Date()))")
        return true
    }

    func saveVisionConfiguration(_ configuration: VisionModelConfiguration) async throws {
        let normalized = VisionModelConfiguration(
            endpoint: configuration.trimmedEndpoint,
            apiKey: configuration.trimmedAPIKey,
            model: configuration.trimmedModel
        )

        try await visionSummarizer.validate(configuration: normalized)
        visionConfiguration = normalized
        saveConfiguration()
    }

    func clearVisionConfiguration() {
        visionConfiguration = nil
        try? FileManager.default.removeItem(at: configurationURL)
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

    private func loadConfiguration() {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: configurationURL)
            visionConfiguration = try JSONDecoder().decode(VisionModelConfiguration.self, from: data)
        } catch {
            visionConfiguration = nil
        }
    }

    private func saveConfiguration() {
        do {
            try FileManager.default.createDirectory(at: configurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(visionConfiguration)
            try data.write(to: configurationURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to persist vision configuration: \(error)")
        }
    }

    private func summarizeTaskIfConfigured(_ task: TaskItem) {
        guard let configuration = visionConfiguration else {
            return
        }

        summarizingTaskIDs.insert(task.id)

        Task {
            do {
                let summary = try await visionSummarizer.summarize(imageData: task.imageData, configuration: configuration)
                updateTitle(for: task.id, title: summary)
            } catch {
                updateTitle(for: task.id, title: "\(task.title)（总结失败）")
            }

            summarizingTaskIDs.remove(task.id)
        }
    }

    private func updateTitle(for id: TaskItem.ID, title: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            return
        }

        tasks[index].title = normalizedTitle
    }
}

private extension NSPasteboard {
    func imageData() -> Data? {
        if let data = data(forType: .png), NSImage(data: data) != nil {
            return data
        }

        if let data = data(forType: .tiff), let image = NSImage(data: data) {
            return image.pngData()
        }

        if let fileURL = readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
           let data = try? Data(contentsOf: fileURL),
           NSImage(data: data) != nil {
            return data
        }

        return nil
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard
            let tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
