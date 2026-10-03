import SwiftUI

/// Whether the app follows the device's light and dark appearance or overrides it.
///
/// Offered on the settings screen. Unlike the language, which iOS resolves while
/// the process starts, this one is applied to the window and takes effect at
/// once.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    /// Whatever the device is set to, which is what the app did until there was
    /// a choice.
    case system
    case light
    case dark

    var id: String { rawValue }

    /// Scheme handed to SwiftUI, `nil` to follow the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var displayName: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }
}
