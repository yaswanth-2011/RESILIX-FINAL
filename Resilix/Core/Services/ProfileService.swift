import Foundation
import UIKit

/// Stores the local profile (display name and photo).
///
/// The photo is compressed and downscaled before it is written to disk so
/// that the profile stays small enough to be exchanged inside the mesh
/// metadata (and to be stored locally without wasting space).
@MainActor
final class ProfileService: ObservableObject {
    @Published private(set) var photoFileName: String?
    @Published private(set) var displayName: String = ResilixConstants.defaultAlias

    private let persistence = PersistenceController.shared
    private let maxDimension: CGFloat = 512

    func load(settings: AppSettings) async {
        displayName = settings.displayName
        photoFileName = settings.profilePhotoFileName
    }

    var photoURL: URL? {
        guard let photoFileName else { return nil }
        return persistence.baseURL
            .appendingPathComponent(ResilixConstants.profileDirectoryName, isDirectory: true)
            .appendingPathComponent(photoFileName)
    }

    /// Stores an image as the profile photo.
    @discardableResult
    func setPhoto(_ image: UIImage) async -> Bool {
        guard let resized = image.resized(maxDimension: maxDimension),
              let data = resized.jpegData(compressionQuality: 0.75) else { return false }
        let fileName = "profile-\(UUID().uuidString).jpg"
        let relative = "\(ResilixConstants.profileDirectoryName)/\(fileName)"
        do {
            try await persistence.write(data, to: relative)
            if let previous = photoFileName {
                await persistence.removeFile(at: "\(ResilixConstants.profileDirectoryName)/\(previous)")
            }
            photoFileName = fileName
            return true
        } catch {
            return false
        }
    }

    func clearPhoto() async {
        if let previous = photoFileName {
            await persistence.removeFile(at: "\(ResilixConstants.profileDirectoryName)/\(previous)")
        }
        photoFileName = nil
    }

    func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = trimmed.isEmpty ? ResilixConstants.defaultAlias : trimmed
    }

    /// Loads the stored photo (used by the chat header and the avatar).
    func loadPhoto() -> UIImage? {
        guard let url = photoURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

extension UIImage {
    /// Returns a copy of the image scaled so that its longest side is at
    /// most `maxDimension` points.
    func resized(maxDimension: CGFloat) -> UIImage? {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else { return nil }
        if longestSide <= maxDimension { return self }
        let scale = maxDimension / longestSide
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
