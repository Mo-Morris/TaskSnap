import AppKit

if let idx = CommandLine.arguments.firstIndex(of: "--export-iconset"),
   CommandLine.arguments.indices.contains(idx + 1) {
    let outputPath = CommandLine.arguments[idx + 1]
    do {
        try IconsetExporter.export(to: outputPath)
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Failed to export iconset: \(error)\n".utf8))
        exit(1)
    }
}

TaskSnapApp.main()
