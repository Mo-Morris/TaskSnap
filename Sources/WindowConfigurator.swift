import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let isCollapsed: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configure(window, coordinator: context.coordinator)
        }

        return view
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
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = !isCollapsed

        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = isCollapsed
        window.standardWindowButton(.miniaturizeButton)?.isHidden = isCollapsed

        if isCollapsed {
            if coordinator.expandedFrame == nil, window.frame.width > 80, window.frame.height > 80 {
                coordinator.expandedFrame = window.frame
            }
            setWindow(window, size: CGSize(width: 56, height: 56), animated: true)
        } else if let expandedFrame = coordinator.expandedFrame {
            window.setFrame(expandedFrame, display: true, animate: true)
            coordinator.expandedFrame = nil
        }
    }

    private func setWindow(_ window: NSWindow, size: CGSize, animated: Bool) {
        var frame = window.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        window.setFrame(frame, display: true, animate: animated)
    }

    final class Coordinator {
        var expandedFrame: NSRect?
    }
}
