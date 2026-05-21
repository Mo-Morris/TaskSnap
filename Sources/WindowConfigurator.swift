import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    @Binding var isCollapsed: Bool

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()

        DispatchQueue.main.async {
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
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            configure(window, coordinator: context.coordinator)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func configure(_ window: NSWindow, coordinator: Coordinator) {
        coordinator.isCollapsed = $isCollapsed
        coordinator.windowHeight = window.frame.height
        coordinator.installDoubleClickMonitor(for: window)

        window.level = .floating
        window.isMovableByWindowBackground = isCollapsed
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = !isCollapsed
        window.backgroundColor = isCollapsed ? .clear : .windowBackgroundColor
        window.hasShadow = !isCollapsed

        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = isCollapsed
        window.standardWindowButton(.miniaturizeButton)?.isHidden = isCollapsed

        if isCollapsed {
            if coordinator.expandedFrame == nil, window.frame.width > 80, window.frame.height > 80 {
                coordinator.expandedFrame = window.frame
            }
            setCollapsedWindowFrame(window, size: CGSize(width: 72, height: 72), animated: true)
        } else if let expandedFrame = coordinator.expandedFrame {
            window.setFrame(expandedFrame, display: true, animate: true)
            coordinator.expandedFrame = nil
        }
    }

    private func setCollapsedWindowFrame(_ window: NSWindow, size: CGSize, animated: Bool) {
        var frame = window.frame
        frame.origin.y += frame.height - size.height
        frame.size = size

        window.setFrame(frame, display: true, animate: animated)
    }

    final class Coordinator {
        var expandedFrame: NSRect?
        var isCollapsed: Binding<Bool>?
        var windowHeight: CGFloat = 0
        private weak var window: NSWindow?
        private var doubleClickMonitor: Any?

        deinit {
            if let doubleClickMonitor {
                NSEvent.removeMonitor(doubleClickMonitor)
            }
        }

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

        private func isInTopCollapseArea(_ location: NSPoint) -> Bool {
            let topCollapseAreaHeight: CGFloat = 48
            return windowHeight - location.y <= topCollapseAreaHeight
        }
    }
}
