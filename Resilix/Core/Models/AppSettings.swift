import Foundation
import SwiftUI

/// Persisted user/application preferences.
///
/// Decoding is implemented by hand so settings written by previous builds
/// (which did not contain the newer keys) still load, and so a corrupt or
/// partially written file never prevents the app from starting.
struct AppSettings: Codable, Sendable, Equatable {
    var onboardingCompleted: Bool = false
    var relayEnabled: Bool = false
    var locationSharingEnabled: Bool = false
    var messageExpiryEnabled: Bool = false
    var displayName: String = "Node"
    var isDemoMode: Bool = false
    var appearance: Appearance = .dark

    // MARK: - Added by the functional implementation
    /// Interface language (matches `SettingsView.Language` raw values).
    var language: String = "English"
    /// File name of the local profile photo inside the `Profile` directory.
    var profilePhotoFileName: String?
    /// Identifier of the local AI model the user selected.
    var selectedAIModelID: String?
    /// Whether the AI assistant may keep the conversation history on disk.
    var aiConversationPersistence: Bool = true
    /// Maximum size (bytes) the app may use for received media.
    var mediaStorageLimitBytes: Int = 512 * 1024 * 1024

    enum Appearance: String, Codable, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case onboardingCompleted, relayEnabled, locationSharingEnabled, messageExpiryEnabled
        case displayName, isDemoMode, appearance, language, profilePhotoFileName
        case selectedAIModelID, aiConversationPersistence, mediaStorageLimitBytes
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        relayEnabled = try container.decodeIfPresent(Bool.self, forKey: .relayEnabled) ?? false
        locationSharingEnabled = try container.decodeIfPresent(Bool.self, forKey: .locationSharingEnabled) ?? false
        messageExpiryEnabled = try container.decodeIfPresent(Bool.self, forKey: .messageExpiryEnabled) ?? false
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "Node"
        isDemoMode = try container.decodeIfPresent(Bool.self, forKey: .isDemoMode) ?? false
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .dark
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "English"
        profilePhotoFileName = try container.decodeIfPresent(String.self, forKey: .profilePhotoFileName)
        selectedAIModelID = try container.decodeIfPresent(String.self, forKey: .selectedAIModelID)
        aiConversationPersistence = try container.decodeIfPresent(Bool.self, forKey: .aiConversationPersistence) ?? true
        mediaStorageLimitBytes = try container.decodeIfPresent(Int.self, forKey: .mediaStorageLimitBytes) ?? (512 * 1024 * 1024)
    }
}
