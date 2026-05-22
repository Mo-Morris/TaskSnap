import Foundation

struct TaskItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var description: String?
    var createdAt: Date
    var isDone: Bool
    var imageData: Data?
    var backgroundColorHex: String
    var inputSource: TaskInputSource
    var manualIconName: String?

    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        createdAt: Date = Date(),
        isDone: Bool = false,
        imageData: Data? = nil,
        backgroundColorHex: String = TaskItem.randomLightColorHex(),
        inputSource: TaskInputSource = .screenshot,
        manualIconName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.isDone = isDone
        self.imageData = imageData
        self.backgroundColorHex = backgroundColorHex
        self.inputSource = inputSource
        self.manualIconName = manualIconName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        backgroundColorHex = try container.decodeIfPresent(String.self, forKey: .backgroundColorHex)
            ?? TaskItem.randomLightColorHex()
        inputSource = try container.decodeIfPresent(TaskInputSource.self, forKey: .inputSource)
            ?? (imageData == nil ? .manual : .screenshot)
        manualIconName = try container.decodeIfPresent(String.self, forKey: .manualIconName)
            ?? (inputSource == .manual ? TaskItem.randomManualIconName() : nil)
    }

    static func randomLightColorHex() -> String {
        let palette = [
            "#F8E7E0",
            "#E8F2D9",
            "#DDEFF5",
            "#F7EDCC",
            "#E9E4F7",
            "#DDF1EA",
            "#F5E0EC",
            "#E6EDF9"
        ]

        return palette.randomElement() ?? "#F8E7E0"
    }

    static func randomManualIconName() -> String {
        manualIconNames.randomElement() ?? "square.and.pencil"
    }

    static let manualIconNames = [
        "square.and.pencil",
        "checklist",
        "flag",
        "calendar",
        "bubble.left.and.bubble.right",
        "lightbulb",
        "chevron.left.forwardslash.chevron.right",
        "doc.text",
        "clock",
        "bookmark"
    ]
}

enum TaskInputSource: String, Codable, Equatable {
    case screenshot
    case manual

    var label: String {
        switch self {
        case .screenshot:
            "截图输入"
        case .manual:
            "手动输入"
        }
    }
}
