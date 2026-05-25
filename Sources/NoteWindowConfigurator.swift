import AppKit
import SwiftUI

struct NoteWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()

        Task { @MainActor in
            guard let window = view.window else { return }
            context.coordinator.configure(window)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            guard let window = nsView.window else { return }
            context.coordinator.configure(window)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var doubleClickMonitor: Any?

        deinit {
            if let doubleClickMonitor {
                NSEvent.removeMonitor(doubleClickMonitor)
            }
        }

        @MainActor
        func configure(_ window: NSWindow) {
            self.window = window
            window.collectionBehavior.insert(.fullScreenPrimary)
            installDoubleClickMonitor(for: window)
        }

        @MainActor
        private func installDoubleClickMonitor(for window: NSWindow) {
            guard doubleClickMonitor == nil else { return }

            doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak window] event in
                guard
                    let self,
                    let window,
                    event.window === window,
                    event.clickCount == 2,
                    self.isInZoomArea(event.locationInWindow, window: window)
                else {
                    return event
                }

                window.performZoom(nil)
                return nil
            }
        }

        @MainActor
        private func isInZoomArea(_ location: NSPoint, window: NSWindow) -> Bool {
            let topBarHeight: CGFloat = 58
            let controlAreaWidth: CGFloat = 260
            let sidebarWidth: CGFloat = 58

            guard window.frame.height - location.y <= topBarHeight else {
                return false
            }

            guard location.x >= sidebarWidth else {
                return false
            }

            guard window.frame.width - location.x >= controlAreaWidth else {
                return false
            }

            return true
        }
    }
}
