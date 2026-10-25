import Foundation
import SwiftUI

/// Applies and persists the interface language.
///
/// The selection is stored in `UserDefaults` (key `language`) and is applied
/// to the whole app through the SwiftUI `\.locale` environment value, so
/// every localized string is resolved with the chosen language. The
/// `AppleLanguages` default is written as well so that system components
/// (date pickers, share sheets) use the same language.
final class LocalizationManager: ObservableObject {
    nonisolated(unsafe) static let shared = LocalizationManager()

    /// All languages the app ships with.
    static let supportedLanguages: [(name: String, code: String)] = [
        ("English", "en"),
        ("Hindi", "hi"),
        ("Telugu", "te"),
        ("Tamil", "ta"),
        ("Kannada", "kn"),
        ("Malayalam", "ml"),
        ("Marathi", "mr"),
        ("Bengali", "bn"),
        ("Gujarati", "gu"),
        ("Punjabi", "pa"),
        ("Urdu", "ur")
    ]

    private let defaultsKey = "language"

    @Published private(set) var currentLanguageName: String = "English"

    /// Thread safe holder for the active language code.
    ///
    /// `L()` is called from background queues as well (transport callbacks,
    /// AI tasks, persistence), so the active code must not be read from a
    /// property that the main thread mutates while a worker reads it.
    private final class LanguageState: @unchecked Sendable {
        private let lock = NSLock()
        private var code: String = "en"

        var current: String {
            lock.lock()
            defer { lock.unlock() }
            return code
        }

        func set(_ newValue: String) {
            lock.lock()
            code = newValue
            lock.unlock()
        }
    }

    private static let state = LanguageState()

    private init() {
        currentLanguageName = UserDefaults.standard.string(forKey: defaultsKey) ?? "English"
        apply(currentLanguageName, persist: false)
    }

    /// Language codes that are offered in the settings.
    var languageNames: [String] { Self.supportedLanguages.map { $0.name } }

    /// Locale of the selected language.
    var locale: Locale {
        Locale(identifier: Self.state.current)
    }

    /// BCP-47 code of a language name (falls back to English).
    static func code(for name: String) -> String {
        supportedLanguages.first { $0.name == name }?.code ?? "en"
    }

    /// Resolves a key with the currently selected language.
    func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key),
              bundle: .main,
              locale: locale)
    }

    /// Stores and applies a language.
    func apply(_ name: String, persist: Bool = true) {
        currentLanguageName = Self.supportedLanguages.contains { $0.name == name } ? name : "English"
        let code = Self.code(for: currentLanguageName)
        Self.state.set(code)
        if persist {
            UserDefaults.standard.set(currentLanguageName, forKey: defaultsKey)
        }
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
    }
}

/// Shortcut for a localized string that uses the selected app language.
func L(_ key: String) -> String {
    LocalizationManager.shared.localized(key)
}
