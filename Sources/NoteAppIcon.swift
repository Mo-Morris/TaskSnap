import AppKit

/// Dock artwork used while the note window is open.
///
/// It keeps TaskSnap's gradient tile and sparkle, while replacing the stacked
/// screenshot cards with a ruled note page so the relationship is recognizable
/// at Dock sizes.
enum NoteAppIcon {
    static func makeImage(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()
        defer { image.unlockFocus() }

        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        bounds.fill()

        drawBackground(in: bounds)
        drawNote(in: bounds)
        drawSparkle(in: bounds)

        return image
    }

    private static func drawBackground(in bounds: NSRect) {
        let inset = bounds.width * 0.08
        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            xRadius: bounds.width * 0.22,
            yRadius: bounds.width * 0.22
        )
        let gradient = NSGradient(colors: [
            NSColor(red: 0.39, green: 0.72, blue: 1.0, alpha: 1),
            NSColor(red: 0.68, green: 0.42, blue: 0.98, alpha: 1),
            NSColor(red: 0.46, green: 0.93, blue: 0.66, alpha: 1)
        ])

        gradient?.draw(in: path, angle: -38)
        NSColor.white.withAlphaComponent(0.22).setStroke()
        path.lineWidth = bounds.width * 0.018
        path.stroke()
    }

    private static func drawNote(in bounds: NSRect) {
        let pageRect = NSRect(
            x: bounds.width * 0.28,
            y: bounds.height * 0.22,
            width: bounds.width * 0.48,
            height: bounds.height * 0.58
        )
        let cornerRadius = bounds.width * 0.055
        let page = NSBezierPath(
            roundedRect: pageRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )

        let shadow = NSShadow()
        shadow.shadowBlurRadius = bounds.width * 0.04
        shadow.shadowOffset = NSSize(width: 0, height: -bounds.height * 0.02)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        page.fill()
        NSGraphicsContext.restoreGraphicsState()

        let bindingColor = NSColor(red: 0.55, green: 0.42, blue: 0.94, alpha: 1)
        bindingColor.setFill()
        NSBezierPath(
            roundedRect: NSRect(
                x: pageRect.minX,
                y: pageRect.minY,
                width: bounds.width * 0.065,
                height: pageRect.height
            ),
            xRadius: cornerRadius,
            yRadius: cornerRadius
        ).fill()

        // Cover the inner rounded edge to leave only the notebook's colored spine.
        NSColor.white.setFill()
        NSRect(
            x: pageRect.minX + bounds.width * 0.042,
            y: pageRect.minY,
            width: bounds.width * 0.035,
            height: pageRect.height
        ).fill()

        let lineColor = NSColor(red: 0.55, green: 0.42, blue: 0.94, alpha: 0.28)
        let lineStartX = pageRect.minX + pageRect.width * 0.25
        let longLineWidth = pageRect.width * 0.56
        let lineHeight = bounds.height * 0.026

        for (index, widthScale) in [0.76, 1.0, 0.88, 0.64].enumerated() {
            let y = pageRect.maxY - pageRect.height * (0.25 + CGFloat(index) * 0.16)
            lineColor.setFill()
            NSBezierPath(
                roundedRect: NSRect(
                    x: lineStartX,
                    y: y,
                    width: longLineWidth * widthScale,
                    height: lineHeight
                ),
                xRadius: lineHeight / 2,
                yRadius: lineHeight / 2
            ).fill()
        }

        let checkCenter = NSPoint(
            x: pageRect.minX + pageRect.width * 0.16,
            y: pageRect.maxY - pageRect.height * 0.25 + lineHeight / 2
        )
        let checkRadius = bounds.width * 0.038
        NSColor(red: 0.17, green: 0.80, blue: 0.52, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: checkCenter.x - checkRadius,
            y: checkCenter.y - checkRadius,
            width: checkRadius * 2,
            height: checkRadius * 2
        )).fill()

        let check = NSBezierPath()
        check.move(to: NSPoint(x: checkCenter.x - checkRadius * 0.48, y: checkCenter.y))
        check.line(to: NSPoint(x: checkCenter.x - checkRadius * 0.12, y: checkCenter.y - checkRadius * 0.35))
        check.line(to: NSPoint(x: checkCenter.x + checkRadius * 0.52, y: checkCenter.y + checkRadius * 0.38))
        check.lineWidth = bounds.width * 0.013
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor.white.setStroke()
        check.stroke()
    }

    private static func drawSparkle(in bounds: NSRect) {
        let center = NSPoint(x: bounds.width * 0.74, y: bounds.height * 0.74)
        let longRadius = bounds.width * 0.115
        let shortRadius = bounds.width * 0.04
        let path = NSBezierPath()

        for index in 0..<8 {
            let angle = (CGFloat(index) * .pi / 4) + .pi / 2
            let radius = index.isMultiple(of: 2) ? longRadius : shortRadius
            let point = NSPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )

            index == 0 ? path.move(to: point) : path.line(to: point)
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
