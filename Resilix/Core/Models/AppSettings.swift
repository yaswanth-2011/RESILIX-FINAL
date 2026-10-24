import Foundation
import SwiftUI

struct AppSettings: Codable, Sendable, Equatable {
    var onboardingCompleted: Bool = false
    var relayEnabled: Bool = false
    var locationSharingEnabled: Bool = false
    var messageExpiryEnabled: Bool = false
    var displayName: String = "Node"
    var isDemoMode: Bool = false
    var appearance: Appearance = .dark
    
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
}
