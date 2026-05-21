import Foundation

struct TaskItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var isDone: Bool
    var imageData: Data
    var backgroundColorHex: String

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        isDone: Bool = false,
        imageData: Data,
        backgroundColorHex: String = TaskItem.randomLightColorHex()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.isDone = isDone
        self.imageData = imageData
        self.backgroundColorHex = backgroundColorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        imageData = try container.decode(Data.self, forKey: .imageData)
        backgroundColorHex = try container.decodeIfPresent(String.self, forKey: .backgroundColorHex)
            ?? TaskItem.randomLightColorHex()
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
}
