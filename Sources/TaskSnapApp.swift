import AppKit
import SwiftUI

@MainActor
final class AppShellState: ObservableObject {
    @Published var isMainWindowCollapsed: Bool = false
    @Published var selectedNoteTaskID: TaskItem.ID?
    @Published var manualTaskFormRequestID: Int = 0
}

struct TaskSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore()
    @StateObject private var pasteCommandDispatcher = PasteCommandDispatcher()
    @StateObject private var shellState = AppShellState()

    var body: some Scene {
        Window("TaskSnap", id: "task-snap-main") {
            TaskBoardView(
                store: store,
                pasteCommandDispatcher: pasteCommandDispatcher
            )
            .frame(
                minWidth: shellState.isMainWindowCollapsed ? 72 : 320,
                idealWidth: shellState.isMainWindowCollapsed ? 72 : 912,
                maxWidth: shellState.isMainWindowCollapsed ? 72 : .infinity,
                minHeight: shellState.isMainWindowCollapsed ? 72 : 420,
                idealHeight: shellState.isMainWindowCollapsed ? 72 : 980,
                maxHeight: shellState.isMainWindowCollapsed ? 72 : .infinity
            )
            .background {
                WindowConfigurator(isCollapsed: $shellState.isMainWindowCollapsed)
                    .allowsHitTesting(false)
            }
            .environmentObject(shellState)
            .onAppear {
                appDelegate.pasteCommandDispatcher = pasteCommandDispatcher
                appDelegate.shellState = shellState
                appDelegate.store = store
            }
            .background {
                NoteWindowOpenerBridge { openNoteWindow in
                    appDelegate.openNoteWindow = openNoteWindow
                }
                .allowsHitTesting(false)
                .frame(width: 0, height: 0)
            }
        }
        .windowStyle(.hiddenTitleBar)

        Window("任务笔记", id: "task-note") {
            TaskNoteWindowView(store: store, selectedTaskID: $shellState.selectedNoteTaskID)
                .frame(minWidth: 820, idealWidth: 1180, minHeight: 560, idealHeight: 760)
                .background {
                    NoteWindowConfigurator()
                        .allowsHitTesting(false)
                }
        }
        .windowStyle(.hiddenTitleBar)

        .commands {
            CommandGroup(replacing: .newItem) {
                Button("归档已完成任务") {
                    store.archiveCompleted()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
        }

        Settings {
            VisionModelSettingsView(store: store)
        }
    }
}

private struct NoteWindowOpenerBridge: View {
    let register: (@escaping () -> Void) -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear {
                register {
                    openWindow(id: "task-note")
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var pasteCommandDispatcher: PasteCommandDispatcher?
    weak var shellState: AppShellState?
    weak var store: TaskStore?
    var openNoteWindow: (() -> Void)?
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let window = mainWindow() else {
            return true
        }

        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return false
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let icon = MenuBarIcon.makeTemplateImage()
            icon.size = NSSize(width: 20, height: 20)
            button.image = icon
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "TaskSnap"
        } else {
            NSLog("TaskSnap failed to create a menu bar status item button.")
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

    @objc private func statusItemClicked(_ sender: Any?) {
        let eventType = NSApp.currentEvent?.type
        if eventType == .rightMouseUp {
            presentStatusMenu()
        } else {
            toggleMainWindow()
        }
    }

    private func toggleMainWindow() {
        guard let window = mainWindow() else { return }

        if window.isVisible && (window.isKeyWindow || NSApp.isActive) {
            window.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func presentStatusMenu() {
        guard let statusItem, let button = statusItem.button else { return }

        let menu = makeStatusMenu()
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let isWindowVisible = mainWindow()?.isVisible == true
        let toggleVisibilityItem = NSMenuItem(
            title: isWindowVisible ? "隐藏浮窗" : "显示浮窗",
            action: #selector(menuToggleMainWindowVisibility),
            keyEquivalent: ""
        )
        toggleVisibilityItem.target = self
        menu.addItem(toggleVisibilityItem)

        let isCollapsed = shellState?.isMainWindowCollapsed == true
        let collapseToggleItem = NSMenuItem(
            title: isCollapsed ? "展开任务列表" : "收起为浮窗",
            action: #selector(menuToggleCollapsedState),
            keyEquivalent: ""
        )
        collapseToggleItem.target = self
        menu.addItem(collapseToggleItem)

        let openNoteItem = NSMenuItem(
            title: "打开任务笔记",
            action: #selector(menuOpenNoteWindow),
            keyEquivalent: ""
        )
        openNoteItem.target = self
        menu.addItem(openNoteItem)

        let manualTaskItem = NSMenuItem(
            title: "新建手动任务",
            action: #selector(menuTriggerManualTaskForm),
            keyEquivalent: ""
        )
        manualTaskItem.target = self
        menu.addItem(manualTaskItem)

        let clearCompletedItem = NSMenuItem(
            title: "归档已完成任务",
            action: #selector(menuArchiveCompletedTasks),
            keyEquivalent: ""
        )
        clearCompletedItem.target = self
        clearCompletedItem.isEnabled = (store?.tasks.contains(where: { $0.status == .completed }) ?? false)
        menu.addItem(clearCompletedItem)

        menu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(
            title: "偏好设置…",
            action: #selector(menuOpenPreferences),
            keyEquivalent: ","
        )
        preferencesItem.keyEquivalentModifierMask = [.command]
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        let aboutItem = NSMenuItem(
            title: "关于 TaskSnap",
            action: #selector(menuShowAboutPanel),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "退出 TaskSnap",
            action: #selector(menuQuitApp),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func menuToggleMainWindowVisibility() {
        guard let window = mainWindow() else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func menuToggleCollapsedState() {
        guard let shellState else { return }
        shellState.isMainWindowCollapsed.toggle()
        showMainWindowIfNeeded()
    }

    @objc private func menuOpenNoteWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openNoteWindow?()
    }

    @objc private func menuTriggerManualTaskForm() {
        guard let shellState else { return }
        if shellState.isMainWindowCollapsed {
            shellState.isMainWindowCollapsed = false
        }
        showMainWindowIfNeeded()
        shellState.manualTaskFormRequestID &+= 1
    }

    @objc private func menuArchiveCompletedTasks() {
        store?.archiveCompleted()
    }

    @objc private func menuOpenPreferences() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func menuShowAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func menuQuitApp() {
        NSApp.terminate(nil)
    }

    private func showMainWindowIfNeeded() {
        guard let window = mainWindow() else { return }
        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private var shouldHandleScreenshotPaste: Bool {
        guard let keyWindow = NSApp.keyWindow, keyWindow.title == "TaskSnap" else {
            return false
        }

        return !(keyWindow.firstResponder is NSTextView)
    }
}
