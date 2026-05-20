import Foundation

struct TaskItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var isDone: Bool
    var imageData: Data

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), isDone: Bool = false, imageData: Data) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.isDone = isDone
        self.imageData = imageData
    }
}
