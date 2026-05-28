import AppKit

enum MenuBarIcon {
    static func makeTemplateImage() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        NSColor.black.setStroke()

        let card = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 4.5, width: 11, height: 13), xRadius: 2.5, yRadius: 2.5)
        card.lineWidth = 1.7
        card.stroke()

        let linePath = NSBezierPath()
        linePath.lineWidth = 1.5
        linePath.lineCapStyle = .round
        linePath.move(to: NSPoint(x: 7, y: 13.5))
        linePath.line(to: NSPoint(x: 12.5, y: 13.5))
        linePath.move(to: NSPoint(x: 7, y: 10.8))
        linePath.line(to: NSPoint(x: 11.5, y: 10.8))
        linePath.move(to: NSPoint(x: 7, y: 8.1))
        linePath.line(to: NSPoint(x: 10.5, y: 8.1))
        linePath.stroke()

        let check = NSBezierPath()
        check.lineWidth = 2.1
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.move(to: NSPoint(x: 13.6, y: 10.3))
        check.line(to: NSPoint(x: 16, y: 7.9))
        check.line(to: NSPoint(x: 19.5, y: 14.2))
        check.stroke()

        image.isTemplate = true
        return image
    }
}
