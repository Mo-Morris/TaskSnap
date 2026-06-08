import Foundation

struct TaskNote: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var kind: TaskNoteKind
    var filePath: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        kind: TaskNoteKind,
        filePath: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.filePath = filePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }
}

enum TaskNoteKind: String, Codable, Equatable {
    case local
    case external

    var label: String {
        switch self {
        case .local:
            "本地笔记"
        case .external:
            "外部文件"
        }
    }
}

enum TaskNoteError: LocalizedError, Equatable {
    case emptyTitle
    case emptyPath
    case fileDoesNotExist
    case unsupportedFileType
    case missingTask
    case missingNote
    case unreadableFile
    case unwritableFile

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "笔记标题不能为空。"
        case .emptyPath:
            "Markdown 文件路径不能为空。"
        case .fileDoesNotExist:
            "找不到这个 Markdown 文件。"
        case .unsupportedFileType:
            "请选择 .md 或 .markdown 文件。"
        case .missingTask:
            "找不到对应任务。"
        case .missingNote:
            "找不到对应笔记。"
        case .unreadableFile:
            "无法读取这个 Markdown 文件。"
        case .unwritableFile:
            "无法写入这个 Markdown 文件。"
        }
    }
}
