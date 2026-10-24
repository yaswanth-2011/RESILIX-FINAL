import Foundation

/// Description of a model that can run locally on the device.
struct LocalModelDescriptor: Codable, Sendable, Equatable, Identifiable {
    enum Family: String, Codable, Sendable {
        case gemma
        case qwen
        case apple
    }

    enum Availability: String, Codable, Sendable {
        /// The runtime is present and the model file is installed.
        case ready
        /// The runtime exists but the model file is missing.
        case notInstalled
        /// The runtime itself is not available (no entitlement, no framework).
        case runtimeUnavailable
        /// The file is present but could not be read.
        case unusable
    }

    var id: String
    var family: Family
    var displayName: String
    /// Identifier of the upstream model on the model hub.
    var modelID: String
    /// Identifier of the converted LiteRT-LM artifact.
    var artifactID: String?
    /// Expected file name of the model file.
    var fileName: String
    var approximateBytes: Int64
    var license: String
    /// Human readable runtime requirement.
    var runtimeRequirement: String
    /// Path of the model file relative to the application support directory.
    var localRelativePath: String?
    var isDownloaded: Bool
    var availability: Availability
    var notes: String

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: approximateBytes, countStyle: .file)
    }
}

/// A single request to the local model runtime.
struct LocalModelRequest: Sendable {
    var prompt: String
    var systemInstructions: String?
    var maxTokens: Int
}

/// Reason why a model cannot be used right now.
enum LocalModelError: LocalizedError {
    case noModelSelected
    case modelNotInstalled(String)
    case runtimeUnavailable(String)
    case generationFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "No local model is selected."
        case .modelNotInstalled(let name):
            return "\(name) is not installed on this device yet."
        case .runtimeUnavailable(let reason):
            return "The local inference runtime is not available: \(reason)"
        case .generationFailed(let reason):
            return "The model could not answer: \(reason)"
        case .cancelled:
            return "The request was cancelled."
        }
    }
}
