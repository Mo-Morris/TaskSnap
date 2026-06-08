import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark

    static let storageKey = "appTheme"

    var id: String { rawValue }

    var colorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var title: String {
        switch self {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var localizedTitle: String {
        switch self {
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }
}
