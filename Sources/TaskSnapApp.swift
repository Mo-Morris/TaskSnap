import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppShellState: ObservableObject {
    @Published var isMainWindowCollapsed: Bool = false
    @Published var selectedNoteTaskID: TaskItem.ID?
    @Published var noteTaskListScope: NoteTaskListScope {
        didSet {
            UserDefaults.standard.set(noteTaskListScope.rawValue, forKey: NoteTaskListScope.storageKey)
        }
    }
    @Published var selectedArchivedTaskID: TaskItem.ID?
    @Published var manualTaskFormRequestID: Int = 0

    init() {
        let storedScope = UserDefaults.standard.string(forKey: NoteTaskListScope.storageKey)
            .flatMap(NoteTaskListScope.init(rawValue:))
        noteTaskListScope = storedScope ?? .all
    }
}

enum NoteTaskListScope: String {
    static let storageKey = "TaskSnap.noteTaskListScope"

    case all
    case selectedOnly
}

struct TaskSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppTheme.storageKey) private var themeRawValue = AppTheme.light.rawValue
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
            .preferredColorScheme(.dark)
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
            .background {
                ArchiveWindowOpenerBridge { openArchiveWindow in
                    appDelegate.openArchiveWindow = openArchiveWindow
                }
                .allowsHitTesting(false)
                .frame(width: 0, height: 0)
            }
            .background {
                SettingsOpenerBridge { openSettingsWindow in
                    appDelegate.openSettingsWindow = openSettingsWindow
                }
                .allowsHitTesting(false)
                .frame(width: 0, height: 0)
            }
        }
        .windowStyle(.hiddenTitleBar)

        Window("任务笔记", id: "task-note") {
            TaskNoteWindowView(
                store: store,
                selectedTaskID: $shellState.selectedNoteTaskID,
                taskListScope: $shellState.noteTaskListScope
            )
                .frame(minWidth: 820, idealWidth: 1180, minHeight: 560, idealHeight: 760)
                .preferredColorScheme(selectedTheme.colorScheme)
                .background {
                    NoteWindowConfigurator()
                        .allowsHitTesting(false)
                }
        }
        .windowStyle(.hiddenTitleBar)

        Window("归档管理", id: "task-archive") {
            ArchiveWindowView(store: store, selectedTaskID: $shellState.selectedArchivedTaskID)
                .frame(minWidth: 820, idealWidth: 1080, minHeight: 560, idealHeight: 720)
                .preferredColorScheme(selectedTheme.colorScheme)
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
                .preferredColorScheme(selectedTheme.colorScheme)
        }
    }

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .light
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

private struct ArchiveWindowOpenerBridge: View {
    let register: (@escaping () -> Void) -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .onAppear {
                register {
                    openWindow(id: "task-archive")
                }
            }
    }
}

private struct SettingsOpenerBridge: View {
    let register: (@escaping () -> Void) -> Void

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .onAppear {
                register {
                    openSettings()
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
    var openArchiveWindow: (() -> Void)?
    var openSettingsWindow: (() -> Void)?
    private var pasteEventMonitor: Any?
    private var statusItem: NSStatusItem?
    private var hotKeyEventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []

    private static let dockWindowTitles: Set<String> = ["任务笔记", "归档管理"]
    private static weak var activeDelegate: AppDelegate?
    private static let hotKeySignature = fourCharacterCode("TSNP")

    private enum HotKey: UInt32 {
        case toggleMainWindow = 1
        case toggleNoteWindow = 2
    }

    @objc private func documentWindowStateMayHaveChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshActivationPolicy()
        }
    }

    private func refreshActivationPolicy() {
        let hasVisibleDockWindow = NSApp.windows.contains { window in
            (window.isVisible || window.isMiniaturized)
                && Self.dockWindowTitles.contains(window.title)
        }

        if hasVisibleDockWindow {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                applyDockIcon()
            }
        } else if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
            // Switching back to .accessory while the app is still the active
            // application leaves a ghost Dock tile (with the default icon).
            // Resigning active lets the system drop the Dock icon immediately.
            NSApp.deactivate()
        }
    }

    private func applyDockIcon() {
        let icon = AppIcon.makeImage()
        NSApp.applicationIconImage = icon
        DispatchQueue.main.async {
            NSApp.applicationIconImage = icon
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.activeDelegate = self
        NSApp.applicationIconImage = AppIcon.makeImage()
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        installGlobalHotKeys()
        hideMainWindowOnLaunch()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentWindowStateMayHaveChanged(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentWindowStateMayHaveChanged(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
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

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyRefs.forEach { hotKeyRef in
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
        }

        if let hotKeyEventHandler {
            RemoveEventHandler(hotKeyEventHandler)
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

    private func noteWindow() -> NSWindow? {
        NSApp.windows.first { $0.title == "任务笔记" }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        presentStatusMenu()
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
            keyEquivalent: "o"
        )
        toggleVisibilityItem.keyEquivalentModifierMask = [.control, .shift]
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

        let isNoteWindowVisible = noteWindow()?.isVisible == true
        let toggleNoteWindowItem = NSMenuItem(
            title: isNoteWindowVisible ? "隐藏任务笔记" : "打开任务笔记",
            action: #selector(menuToggleNoteWindowVisibility),
            keyEquivalent: "i"
        )
        toggleNoteWindowItem.keyEquivalentModifierMask = [.control, .shift]
        toggleNoteWindowItem.target = self
        menu.addItem(toggleNoteWindowItem)

        let manualTaskItem = NSMenuItem(
            title: "新建手动任务",
            action: #selector(menuTriggerManualTaskForm),
            keyEquivalent: ""
        )
        manualTaskItem.target = self
        menu.addItem(manualTaskItem)

        let archiveManagerItem = NSMenuItem(
            title: "归档管理…",
            action: #selector(menuOpenArchiveWindow),
            keyEquivalent: ""
        )
        archiveManagerItem.target = self
        menu.addItem(archiveManagerItem)

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
            showMainWindowIfNeeded()
        }
    }

    @objc private func menuToggleCollapsedState() {
        guard let shellState else { return }
        shellState.isMainWindowCollapsed.toggle()
        showMainWindowIfNeeded()
    }

    @objc private func menuToggleNoteWindowVisibility() {
        if let window = noteWindow(), window.isVisible {
            window.orderOut(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        openNoteWindow?()
    }

    @objc private func menuOpenArchiveWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openArchiveWindow?()
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
        if let openSettingsWindow {
            openSettingsWindow()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
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

    private func installGlobalHotKeys() {
        let eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard
                    status == noErr,
                    hotKeyID.signature == AppDelegate.hotKeySignature,
                    let hotKey = HotKey(rawValue: hotKeyID.id)
                else {
                    return status
                }

                DispatchQueue.main.async {
                    AppDelegate.activeDelegate?.handleGlobalHotKey(hotKey)
                }

                return noErr
            },
            1,
            [eventSpec],
            nil,
            &hotKeyEventHandler
        )

        guard handlerStatus == noErr else {
            NSLog("TaskSnap failed to install global hotkey handler: \(handlerStatus)")
            return
        }

        registerHotKey(.toggleMainWindow, keyCode: UInt32(kVK_ANSI_O))
        registerHotKey(.toggleNoteWindow, keyCode: UInt32(kVK_ANSI_I))
    }

    private func registerHotKey(_ hotKey: HotKey, keyCode: UInt32) {
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: hotKey.rawValue)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(controlKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
        } else {
            NSLog("TaskSnap failed to register hotkey \(hotKey.rawValue): \(status)")
        }
    }

    private func handleGlobalHotKey(_ hotKey: HotKey) {
        switch hotKey {
        case .toggleMainWindow:
            menuToggleMainWindowVisibility()
        case .toggleNoteWindow:
            menuToggleNoteWindowVisibility()
        }
    }

    private var shouldHandleScreenshotPaste: Bool {
        guard let keyWindow = NSApp.keyWindow, keyWindow.title == "TaskSnap" else {
            return false
        }

        return !(keyWindow.firstResponder is NSTextView)
    }
}

private func fourCharacterCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}
