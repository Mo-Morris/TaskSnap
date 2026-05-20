import SwiftUI

@main
struct TaskSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup("TaskSnap") {
            TaskBoardView(store: store)
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 460, minHeight: 420)
                .background(WindowConfigurator())
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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }
}
