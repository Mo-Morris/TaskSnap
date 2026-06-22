import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    @Binding var isCollapsed: Bool
    private let collapsedSize = CGSize(width: 72, height: 72)
    private let defaultExpandedSize = CGSize(width: 912, height: 980)
    private let expandedTopMargin: CGFloat = 18

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()

        Task { @MainActor in
            guard let window = view.window else { return }
            configure(window, coordinator: context.coordinator)
        }

        return view
    }

    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            guard let window = nsView.window else { return }
            configure(window, coordinator: context.coordinator)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    private func configure(_ window: NSWindow, coordinator: Coordinator) {
        coordinator.isCollapsed = $isCollapsed
        coordinator.windowHeight = window.frame.height
        coordinator.installDoubleClickMonitor(for: window)
        coordinator.installWindowTracking(for: window)

        window.level = .floating
        window.isMovableByWindowBackground = isCollapsed
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = !isCollapsed
        window.backgroundColor = isCollapsed
            ? .clear
            : NSColor(srgbRed: 0.16, green: 0.16, blue: 0.16, alpha: 1)
        window.hasShadow = !isCollapsed

        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = isCollapsed
        window.standardWindowButton(.miniaturizeButton)?.isHidden = isCollapsed

        window.sharingType = isCollapsed ? .none : .readWrite

        if coordinator.currentIsCollapsed == nil {
            coordinator.currentIsCollapsed = isCollapsed
            coordinator.noteCurrentFrame(window.frame, isCollapsed: isCollapsed)
            return
        }

        guard coordinator.currentIsCollapsed != isCollapsed else {
            coordinator.noteCurrentFrame(window.frame, isCollapsed: isCollapsed)
            return
        }

        if isCollapsed {
            let expandedFrame = coordinator.lastExpandedFrame ?? window.frame
            coordinator.lastExpandedFrame = expandedFrame

            let collapsedFrame: NSRect
            if coordinator.lastExpandedFrameWasDragged {
                collapsedFrame = nearestFrame(
                    to: expandedFrame,
                    targetSize: collapsedSize,
                    in: window
                )
            } else if let lastCollapsedFrame = coordinator.lastCollapsedFrame {
                collapsedFrame = clamped(lastCollapsedFrame, in: visibleFrame(for: lastCollapsedFrame, window: window))
            } else {
                collapsedFrame = nearestFrame(
                    to: expandedFrame,
                    targetSize: collapsedSize,
                    in: window
                )
            }

            coordinator.currentIsCollapsed = true
            coordinator.lastCollapsedFrame = collapsedFrame
            coordinator.lastCollapsedFrameWasDragged = false
            coordinator.performProgrammaticFrameChange {
                window.setFrame(collapsedFrame, display: true, animate: true)
            }
        } else {
            let collapsedFrame = coordinator.lastCollapsedFrame ?? window.frame
            coordinator.lastCollapsedFrame = collapsedFrame

            let expandedSize = coordinator.lastExpandedFrame?.size ?? defaultExpandedSize
            let expandedFrame: NSRect
            if
                coordinator.lastExpandedFrameWasDragged,
                !coordinator.lastCollapsedFrameWasDragged,
                let lastExpandedFrame = coordinator.lastExpandedFrame
            {
                expandedFrame = clamped(lastExpandedFrame, in: visibleFrame(for: lastExpandedFrame, window: window))
            } else {
                expandedFrame = raisedExpandedFrame(
                    to: collapsedFrame,
                    targetSize: expandedSize,
                    in: window
                )
            }

            coordinator.currentIsCollapsed = false
            coordinator.lastExpandedFrame = expandedFrame
            coordinator.lastExpandedFrameWasDragged = false
            coordinator.performProgrammaticFrameChange {
                window.setFrame(expandedFrame, display: true, animate: true)
            }
        }
    }

    private func raisedExpandedFrame(to anchor: NSRect, targetSize: CGSize, in window: NSWindow) -> NSRect {
        let visibleFrame = visibleFrame(for: anchor, window: window)
        let width = min(targetSize.width, visibleFrame.width)
        let height = min(targetSize.height, visibleFrame.height)
        let centeredX = anchor.midX - width / 2
        let raisedY = visibleFrame.maxY - height - expandedTopMargin

        return clamped(
            NSRect(x: centeredX, y: raisedY, width: width, height: height),
            in: visibleFrame
        )
    }

    private func nearestFrame(to anchor: NSRect, targetSize: CGSize, in window: NSWindow) -> NSRect {
        let gap: CGFloat = 10
        let halfWidthDelta = (anchor.width - targetSize.width) / 2
        let halfHeightDelta = (anchor.height - targetSize.height) / 2
        let candidates = [
            NSRect(x: anchor.maxX + gap, y: anchor.midY - targetSize.height / 2, width: targetSize.width, height: targetSize.height),
            NSRect(x: anchor.minX - gap - targetSize.width, y: anchor.midY - targetSize.height / 2, width: targetSize.width, height: targetSize.height),
            NSRect(x: anchor.midX - targetSize.width / 2, y: anchor.maxY + gap, width: targetSize.width, height: targetSize.height),
            NSRect(x: anchor.midX - targetSize.width / 2, y: anchor.minY - gap - targetSize.height, width: targetSize.width, height: targetSize.height),
            NSRect(x: anchor.minX + halfWidthDelta, y: anchor.minY + halfHeightDelta, width: targetSize.width, height: targetSize.height)
        ]

        let visibleFrame = visibleFrame(for: anchor, window: window)
        if let containedFrame = candidates
            .filter({ visibleFrame.contains($0) })
            .min(by: { distance(from: anchor, to: $0) < distance(from: anchor, to: $1) }) {
            return containedFrame
        }

        return candidates
            .map { clamped($0, in: visibleFrame) }
            .min(by: { distance(from: anchor, to: $0) < distance(from: anchor, to: $1) })
            ?? clamped(NSRect(origin: anchor.origin, size: targetSize), in: visibleFrame)
    }

    private func visibleFrame(for frame: NSRect, window: NSWindow) -> NSRect {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })?.visibleFrame
            ?? window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? frame
    }

    private func clamped(_ frame: NSRect, in visibleFrame: NSRect) -> NSRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - width
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - height

        return NSRect(
            x: min(max(frame.minX, minX), maxX),
            y: min(max(frame.minY, minY), maxY),
            width: width,
            height: height
        )
    }

    private func distance(from source: NSRect, to target: NSRect) -> CGFloat {
        let dx = source.midX - target.midX
        let dy = source.midY - target.midY
        return sqrt(dx * dx + dy * dy)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var currentIsCollapsed: Bool?
        var lastExpandedFrame: NSRect?
        var lastCollapsedFrame: NSRect?
        var lastExpandedFrameWasDragged = false
        var lastCollapsedFrameWasDragged = false
        var isCollapsed: Binding<Bool>?
        var windowHeight: CGFloat = 0
        private weak var window: NSWindow?
        private weak var trackedWindow: NSWindow?
        private var isChangingFrameProgrammatically = false
        private var doubleClickMonitor: Any?

        deinit {
            if let doubleClickMonitor {
                NSEvent.removeMonitor(doubleClickMonitor)
            }
            NotificationCenter.default.removeObserver(self)
        }

        @MainActor
        func installDoubleClickMonitor(for window: NSWindow) {
            self.window = window

            guard doubleClickMonitor == nil else {
                return
            }

            doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak window] event in
                guard
                    let self,
                    let window,
                    event.window === window,
                    event.clickCount == 2,
                    self.isCollapsed?.wrappedValue == false,
                    self.isInTopCollapseArea(event.locationInWindow)
                else {
                    return event
                }

                self.isCollapsed?.wrappedValue = true
                return nil
            }
        }

        @MainActor
        func installWindowTracking(for window: NSWindow) {
            guard trackedWindow !== window else {
                return
            }

            NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: trackedWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: trackedWindow)

            self.window = window
            trackedWindow = window
            window.delegate = self

            NotificationCenter.default.addObserver(self, selector: #selector(windowDidMove(_:)), name: NSWindow.didMoveNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidResize(_:)), name: NSWindow.didResizeNotification, object: window)
        }

        @MainActor
        func noteCurrentFrame(_ frame: NSRect, isCollapsed: Bool) {
            if isChangingFrameProgrammatically {
                return
            }

            if isCollapsed {
                if frame.width <= 100, frame.height <= 100 {
                    lastCollapsedFrame = frame
                }
            } else if frame.width > 80, frame.height > 80 {
                lastExpandedFrame = frame
            }
        }

        @MainActor
        func performProgrammaticFrameChange(_ change: () -> Void) {
            isChangingFrameProgrammatically = true
            change()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self else { return }
                self.isChangingFrameProgrammatically = false
                if let window = self.window {
                    self.noteCurrentFrame(window.frame, isCollapsed: self.currentIsCollapsed == true)
                }
            }
        }

        @MainActor
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard isCollapsed?.wrappedValue == false else {
                return true
            }

            isCollapsed?.wrappedValue = true
            return false
        }

        @MainActor
        private func isInTopCollapseArea(_ location: NSPoint) -> Bool {
            let topCollapseAreaHeight: CGFloat = 48
            return windowHeight - location.y <= topCollapseAreaHeight
        }

        @MainActor
        @objc func windowDidMove(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            recordTrackedFrame(window.frame, moved: true)
        }

        @MainActor
        @objc func windowDidResize(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            recordTrackedFrame(window.frame, moved: false)
        }

        @MainActor
        private func recordTrackedFrame(_ frame: NSRect, moved: Bool) {
            if isChangingFrameProgrammatically {
                return
            }

            if currentIsCollapsed == true {
                if frame.width <= 100, frame.height <= 100 {
                    lastCollapsedFrame = frame
                }
                if moved, frame.width <= 100, frame.height <= 100 {
                    lastCollapsedFrameWasDragged = true
                }
            } else if frame.width > 80, frame.height > 80 {
                lastExpandedFrame = frame
                if moved {
                    lastExpandedFrameWasDragged = true
                }
            }
        }
    }
}
