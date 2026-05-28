import AppKit

enum MenuBarIcon {
    static func makeTemplateImage() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        NSColor.black.setFill()

        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: 11, y: 2.2))
        mark.line(to: NSPoint(x: 13.8, y: 8.2))
        mark.line(to: NSPoint(x: 19.8, y: 11))
        mark.line(to: NSPoint(x: 13.8, y: 13.8))
        mark.line(to: NSPoint(x: 11, y: 19.8))
        mark.line(to: NSPoint(x: 8.2, y: 13.8))
        mark.line(to: NSPoint(x: 2.2, y: 11))
        mark.line(to: NSPoint(x: 8.2, y: 8.2))
        mark.close()
        mark.fill()

        image.isTemplate = true
        return image
    }
}
