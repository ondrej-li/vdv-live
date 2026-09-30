import Foundation

/// Language the app is shown in.
///
/// Czech is the default: the feed, the place names and most of the audience are
/// Czech, so an English phone should not silently turn the app English. Anyone
/// who wants English can pick it in the settings.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case czech = "cs"
    case english = "en"
    case system = "system"

    var id: String { rawValue }

    /// Code handed to the system, `nil` to follow the device language.
    var localizationCode: String? {
        switch self {
        case .czech: return "cs"
        case .english: return "en"
        case .system: return nil
        }
    }

    /// Shown in the picker in the language itself, which is how language pickers
    /// are normally written.
    var displayName: String {
        switch self {
        case .czech: return "Čeština"
        case .english: return "English"
        case .system: return String(localized: "System")
        }
    }
}

/// Applies the chosen language to the process.
///
/// iOS reads `AppleLanguages` from the app's own defaults while it starts, so the
/// choice is written there and takes effect on the next launch. That is the
/// standard way to offer a language switch inside an app.
enum LanguageOverride {
    static let defaultsKey = "AppleLanguages"

    static func apply(_ language: AppLanguage, to defaults: UserDefaults = .standard) {
        guard let code = language.localizationCode else {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        defaults.set([code], forKey: defaultsKey)
    }
}
