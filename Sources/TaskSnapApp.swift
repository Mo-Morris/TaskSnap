import SwiftUI

@main
struct TaskSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings
    @StateObject private var store = TaskStore()
    @StateObject private var pasteCommandDispatcher = PasteCommandDispatcher()
    @State private var isTaskBoardCollapsed = false

    var body: some Scene {
        WindowGroup("TaskSnap") {
            TaskBoardView(
                store: store,
                pasteCommandDispatcher: pasteCommandDispatcher,
                isCollapsed: $isTaskBoardCollapsed
            )
            .frame(
                minWidth: isTaskBoardCollapsed ? 56 : 320,
                idealWidth: isTaskBoardCollapsed ? 56 : 520,
                maxWidth: isTaskBoardCollapsed ? 56 : .infinity,
                minHeight: isTaskBoardCollapsed ? 56 : 420,
                idealHeight: isTaskBoardCollapsed ? 56 : 420,
                maxHeight: isTaskBoardCollapsed ? 56 : .infinity
            )
            .background(WindowConfigurator(isCollapsed: isTaskBoardCollapsed))
            .onAppear {
                appDelegate.pasteCommandDispatcher = pasteCommandDispatcher
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("视觉模型设置...") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
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

    private var shouldHandleScreenshotPaste: Bool {
        guard let keyWindow = NSApp.keyWindow, keyWindow.title == "TaskSnap" else {
            return false
        }

        return !(keyWindow.firstResponder is NSTextView)
    }
}
