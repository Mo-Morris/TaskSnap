import AppKit

enum AppIcon {
    static func makeImage(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        bounds.fill()

        drawBackground(in: bounds)
        drawStackedSnap(in: bounds)
        drawSparkle(in: bounds)

        return image
    }

    private static func drawBackground(in bounds: NSRect) {
        let radius = bounds.width * 0.22
        let backgroundPath = NSBezierPath(roundedRect: bounds.insetBy(dx: bounds.width * 0.08, dy: bounds.height * 0.08), xRadius: radius, yRadius: radius)
        let gradient = NSGradient(colors: [
            NSColor(red: 0.39, green: 0.72, blue: 1.0, alpha: 1),
            NSColor(red: 0.68, green: 0.42, blue: 0.98, alpha: 1),
            NSColor(red: 0.46, green: 0.93, blue: 0.66, alpha: 1)
        ])

        gradient?.draw(in: backgroundPath, angle: -38)

        NSColor.white.withAlphaComponent(0.22).setStroke()
        backgroundPath.lineWidth = bounds.width * 0.018
        backgroundPath.stroke()
    }

    private static func drawStackedSnap(in bounds: NSRect) {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = bounds.width * 0.035
        shadow.shadowOffset = NSSize(width: 0, height: -bounds.height * 0.018)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()

        let backCard = NSBezierPath(roundedRect: NSRect(
            x: bounds.width * 0.28,
            y: bounds.height * 0.25,
            width: bounds.width * 0.40,
            height: bounds.height * 0.50
        ), xRadius: bounds.width * 0.045, yRadius: bounds.width * 0.045)

        var transform = AffineTransform(translationByX: bounds.midX, byY: bounds.midY)
        transform.rotate(byDegrees: -8)
        transform.translate(x: -bounds.midX, y: -bounds.midY)
        backCard.transform(using: transform)

        NSColor.white.withAlphaComponent(0.34).setFill()
        backCard.fill()

        let frontCardRect = NSRect(
            x: bounds.width * 0.32,
            y: bounds.height * 0.24,
            width: bounds.width * 0.44,
            height: bounds.height * 0.54
        )
        let frontCard = NSBezierPath(roundedRect: frontCardRect, xRadius: bounds.width * 0.05, yRadius: bounds.width * 0.05)
        NSColor.white.setFill()
        frontCard.fill()

        NSGraphicsContext.restoreGraphicsState()

        let photoRect = NSRect(
            x: frontCardRect.minX + frontCardRect.width * 0.18,
            y: frontCardRect.minY + frontCardRect.height * 0.53,
            width: frontCardRect.width * 0.64,
            height: frontCardRect.height * 0.24
        )
        let photoPath = NSBezierPath(roundedRect: photoRect, xRadius: bounds.width * 0.025, yRadius: bounds.width * 0.025)
        NSColor(red: 0.60, green: 0.52, blue: 0.98, alpha: 0.18).setFill()
        photoPath.fill()

        NSColor(red: 0.55, green: 0.42, blue: 0.94, alpha: 1).setStroke()
        let mountain = NSBezierPath()
        mountain.lineWidth = bounds.width * 0.018
        mountain.lineCapStyle = .round
        mountain.lineJoinStyle = .round
        mountain.move(to: NSPoint(x: photoRect.minX + photoRect.width * 0.17, y: photoRect.minY + photoRect.height * 0.30))
        mountain.line(to: NSPoint(x: photoRect.minX + photoRect.width * 0.39, y: photoRect.minY + photoRect.height * 0.57))
        mountain.line(to: NSPoint(x: photoRect.minX + photoRect.width * 0.53, y: photoRect.minY + photoRect.height * 0.42))
        mountain.line(to: NSPoint(x: photoRect.minX + photoRect.width * 0.78, y: photoRect.minY + photoRect.height * 0.65))
        mountain.stroke()

        NSColor(red: 0.17, green: 0.80, blue: 0.52, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: frontCardRect.minX + frontCardRect.width * 0.20,
            y: frontCardRect.minY + frontCardRect.height * 0.26,
            width: bounds.width * 0.075,
            height: bounds.width * 0.075
        )).fill()

        NSColor(red: 0.58, green: 0.42, blue: 0.96, alpha: 0.24).setFill()
        NSBezierPath(roundedRect: NSRect(
            x: frontCardRect.minX + frontCardRect.width * 0.40,
            y: frontCardRect.minY + frontCardRect.height * 0.28,
            width: frontCardRect.width * 0.38,
            height: bounds.height * 0.052
        ), xRadius: bounds.width * 0.018, yRadius: bounds.width * 0.018).fill()
    }

    private static func drawSparkle(in bounds: NSRect) {
        let center = NSPoint(x: bounds.width * 0.72, y: bounds.height * 0.72)
        let longRadius = bounds.width * 0.13
        let shortRadius = bounds.width * 0.044
        let path = NSBezierPath()

        for index in 0..<8 {
            let angle = (CGFloat(index) * .pi / 4) + .pi / 2
            let radius = index.isMultiple(of: 2) ? longRadius : shortRadius
            let point = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)

            if index == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }

        path.close()

        let shadow = NSShadow()
        shadow.shadowBlurRadius = bounds.width * 0.018
        shadow.shadowOffset = NSSize(width: 0, height: -bounds.height * 0.01)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
