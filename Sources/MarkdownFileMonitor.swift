import Darwin
import Foundation

extension Notification.Name {
    static let markdownFileDidChange = Notification.Name("TaskSnap.markdownFileDidChange")
}

/// Watches the containing directory so editors that save by atomically replacing the
/// Markdown file still produce a refresh event.
final class MarkdownFileMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "TaskSnap.MarkdownFileMonitor")
    private let debounceInterval: DispatchTimeInterval
    private var source: DispatchSourceFileSystemObject?
    private var pendingNotification: DispatchWorkItem?
    private var generation = 0

    init(debounceInterval: DispatchTimeInterval = .milliseconds(150)) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        stop()
    }

    func watch(fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw CocoaError(.fileReadNoPermission)
        }

        queue.sync {
            stopLocked()
            generation += 1
            let currentGeneration = generation
            let filePath = fileURL.standardizedFileURL.path
            let newSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .link, .rename, .delete, .revoke],
                queue: queue
            )

            newSource.setEventHandler { [weak self] in
                self?.scheduleNotification(for: filePath, generation: currentGeneration)
            }
            newSource.setCancelHandler {
                close(descriptor)
            }
            source = newSource
            newSource.resume()
        }
    }

    func stop() {
        queue.sync {
            stopLocked()
            generation += 1
        }
    }

    private func scheduleNotification(for filePath: String, generation currentGeneration: Int) {
        pendingNotification?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .markdownFileDidChange, object: filePath)
            }
        }
        pendingNotification = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func stopLocked() {
        pendingNotification?.cancel()
        pendingNotification = nil
        source?.cancel()
        source = nil
    }
}
