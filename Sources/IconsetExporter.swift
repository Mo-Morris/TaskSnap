import AppKit
import Foundation

enum IconsetExporter {
    private struct Variant {
        let fileName: String
        let pixelSize: Int
    }

    private static let variants: [Variant] = [
        Variant(fileName: "icon_16x16.png", pixelSize: 16),
        Variant(fileName: "icon_16x16@2x.png", pixelSize: 32),
        Variant(fileName: "icon_32x32.png", pixelSize: 32),
        Variant(fileName: "icon_32x32@2x.png", pixelSize: 64),
        Variant(fileName: "icon_128x128.png", pixelSize: 128),
        Variant(fileName: "icon_128x128@2x.png", pixelSize: 256),
        Variant(fileName: "icon_256x256.png", pixelSize: 256),
        Variant(fileName: "icon_256x256@2x.png", pixelSize: 512),
        Variant(fileName: "icon_512x512.png", pixelSize: 512),
        Variant(fileName: "icon_512x512@2x.png", pixelSize: 1024)
    ]

    enum ExportError: Error, CustomStringConvertible {
        case bitmapCreationFailed(Int)
        case pngEncodingFailed(String)

        var description: String {
            switch self {
            case .bitmapCreationFailed(let size):
                return "Failed to create bitmap representation for size \(size)"
            case .pngEncodingFailed(let name):
                return "Failed to encode PNG data for \(name)"
            }
        }
    }

    static func export(to directoryPath: String) throws {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        for variant in variants {
            let pngData = try renderPNG(pixelSize: variant.pixelSize, fileName: variant.fileName)
            let outputURL = directoryURL.appendingPathComponent(variant.fileName)
            try pngData.write(to: outputURL, options: .atomic)
        }
    }

    private static func renderPNG(pixelSize: Int, fileName: String) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else {
            throw ExportError.bitmapCreationFailed(pixelSize)
        }
        bitmap.size = NSSize(width: pixelSize, height: pixelSize)

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw ExportError.bitmapCreationFailed(pixelSize)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        let image = AppIcon.makeImage(size: CGFloat(pixelSize))
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.pngEncodingFailed(fileName)
        }
        return pngData
    }
}
