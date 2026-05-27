import SwiftUI

struct TaskSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore()
    @StateObject private var pasteCommandDispatcher = PasteCommandDispatcher()
    @State private var isTaskBoardCollapsed = false
    @State private var selectedNoteTaskID: TaskItem.ID?

    var body: some Scene {
        WindowGroup("TaskSnap") {
            TaskBoardView(
                store: store,
                pasteCommandDispatcher: pasteCommandDispatcher,
                isCollapsed: $isTaskBoardCollapsed,
                selectedNoteTaskID: $selectedNoteTaskID
            )
            .frame(
                minWidth: isTaskBoardCollapsed ? 72 : 320,
                idealWidth: isTaskBoardCollapsed ? 72 : 912,
                maxWidth: isTaskBoardCollapsed ? 72 : .infinity,
                minHeight: isTaskBoardCollapsed ? 72 : 420,
                idealHeight: isTaskBoardCollapsed ? 72 : 980,
                maxHeight: isTaskBoardCollapsed ? 72 : .infinity
            )
            .background {
                WindowConfigurator(isCollapsed: $isTaskBoardCollapsed)
                    .allowsHitTesting(false)
            }
            .onAppear {
                appDelegate.pasteCommandDispatcher = pasteCommandDispatcher
            }
        }
        .windowStyle(.hiddenTitleBar)

        Window("任务笔记", id: "task-note") {
            TaskNoteWindowView(store: store, selectedTaskID: $selectedNoteTaskID)
                .frame(minWidth: 820, idealWidth: 1180, minHeight: 560, idealHeight: 760)
                .background {
                    NoteWindowConfigurator()
                        .allowsHitTesting(false)
                }
        }
        .windowStyle(.hiddenTitleBar)

        .commands {
            CommandGroup(replacing: .newItem) {
                Button("清空已完成任务") {
                    store.clearCompleted()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
        }

        Settings {
            VisionModelSettingsView(store: store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var pasteCommandDispatcher: PasteCommandDispatcher?
    private var pasteEventMonitor: Any?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIcon.makeImage()
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        hideMainWindowOnLaunch()
        pasteEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard
                event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers?.lowercased() == "v",
                self?.shouldHandleScreenshotPaste == true
            else {
                return event
            }

            self?.pasteCommandDispatcher?.requestPaste()
            return nil
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let icon = AppIcon.makeImage(size: 64)
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = false
            button.image = icon
            button.target = self
            button.action = #selector(toggleMainWindow)
            button.toolTip = "TaskSnap"
        }
        statusItem = item
    }

    private func hideMainWindowOnLaunch() {
        DispatchQueue.main.async { [weak self] in
            self?.mainWindow()?.orderOut(nil)
        }
    }

    private func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.title == "TaskSnap" }
    }

    @objc private func toggleMainWindow() {
        guard let window = mainWindow() else { return }

        if window.isVisible && (window.isKeyWindow || NSApp.isActive) {
            window.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var shouldHandleScreenshotPaste: Bool {
        guard let keyWindow = NSApp.keyWindow, keyWindow.title == "TaskSnap" else {
            return false
        }

        return !(keyWindow.firstResponder is NSTextView)
    }
}
