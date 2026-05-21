import Combine
import Foundation

@MainActor
final class PasteCommandDispatcher: ObservableObject {
    @Published private(set) var requestID = UUID()

    func requestPaste() {
        requestID = UUID()
    }
}
