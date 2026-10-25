import Foundation
import MapKit
import Combine

/// Stores and manages the offline map packs of the device.
///
/// A *pack* is either
///
/// * an **MBTiles** container (a SQLite database with a `tiles` table), or
/// * a **directory** with `<zoom>/<x>/<y>.png` tiles.
///
/// Packs are imported from the file system or downloaded once (the only step
/// that needs an internet connection) and are then rendered by
/// `OfflineTileOverlay` without any network access.
@MainActor
final class MapPackService: ObservableObject {
    @Published private(set) var packs: [MapPackDescriptor] = []
    @Published private(set) var activePackID: String?
    @Published private(set) var isBusy = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var lastErrorMessage: String?

    private let persistence = PersistenceController.shared
    private var readers: [String: MBTilesReader] = [:]

    init() {}

    // MARK: - Lifecycle

    func load() async {
        packs = await persistence.loadMapPacks()
        if let first = packs.first, activePackID == nil {
            activePackID = first.id
        }
    }

    var activePack: MapPackDescriptor? {
        packs.first { $0.id == activePackID }
    }

    var storageUsedBytes: Int {
        packs.reduce(0) { $0 + $1.byteCount }
    }

    // MARK: - Import

    /// Imports a map pack from a file URL (for example the document picker).
    @discardableResult
    func importPack(from url: URL) async throws -> MapPackDescriptor {
        isBusy = true
        defer { isBusy = false }
        lastErrorMessage = nil

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let fileExtension = url.pathExtension.lowercased()
        guard fileExtension == "mbtiles" || fileExtension == "sqlite" else {
            throw ResilixError.persistenceFailed(String(format: L("Unsupported map format: %@"), fileExtension))
        }

        let data = try Data(contentsOf: url)
        let id = UUID().uuidString
        let relativePath = "\(ResilixConstants.mapDirectoryName)/\(id).mbtiles"
        try await persistence.write(data, to: relativePath)

        let descriptor = try await describePack(id: id,
                                                relativePath: relativePath,
                                                name: url.deletingPathExtension().lastPathComponent,
                                                data: data)
        packs.append(descriptor)
        activePackID = id
        try? await persistence.saveMapPacks(packs)
        return descriptor
    }

    /// Downloads a map pack. This is the only operation that needs internet.
    @discardableResult
    func downloadPack(from url: URL, name: String) async throws -> MapPackDescriptor {
        isBusy = true
        downloadProgress = 0
        defer { isBusy = false }
        lastErrorMessage = nil

        do {
            let (temporaryURL, response) = try await PackDownloader.shared.download(from: url) { [weak self] progress in
                Task { @MainActor in self?.downloadProgress = progress }
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ResilixError.persistenceFailed(String(format: L("Download failed (HTTP %@)"), String(http.statusCode)))
            }
            let data = try Data(contentsOf: temporaryURL)
            let id = UUID().uuidString
            let relativePath = "\(ResilixConstants.mapDirectoryName)/\(id).mbtiles"
            try await persistence.write(data, to: relativePath)
            let descriptor = try await describePack(id: id,
                                                    relativePath: relativePath,
                                                    name: name,
                                                    data: data)
            packs.append(descriptor)
            activePackID = id
            try? await persistence.saveMapPacks(packs)
            return descriptor
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    private func describePack(id: String, relativePath: String, name: String, data: Data) async throws -> MapPackDescriptor {
        let fileURL = persistence.baseURL.appendingPathComponent(relativePath)
        guard let reader = MBTilesReader(url: fileURL) else {
            throw ResilixError.persistenceFailed(L("The file is not a readable MBTiles container"))
        }
        readers[id] = reader
        let places = reader.placeNames()
        return MapPackDescriptor(id: id,
                                 name: name.isEmpty ? L("Map pack") : name,
                                 relativePath: relativePath,
                                 format: .mbtiles,
                                 byteCount: data.count,
                                 minZoom: reader.minimumZoom,
                                 maxZoom: reader.maximumZoom,
                                 minLatitude: reader.minimumLatitude,
                                 maxLatitude: reader.maximumLatitude,
                                 minLongitude: reader.minimumLongitude,
                                 maxLongitude: reader.maximumLongitude,
                                 importedAt: Date(),
                                 sha256: PacketCrypto.sha256Hex(data),
                                 placeNames: places)
    }

    // MARK: - Management

    func activate(packID: String?) {
        activePackID = packID
    }

    func deletePack(_ packID: String) async {
        guard let pack = packs.first(where: { $0.id == packID }) else { return }
        readers.removeValue(forKey: packID)
        await persistence.removeFile(at: pack.relativePath)
        packs.removeAll { $0.id == packID }
        if activePackID == packID { activePackID = packs.first?.id }
        try? await persistence.saveMapPacks(packs)
    }

    // MARK: - Rendering

    /// Creates the tile overlay that renders a pack offline.
    func tileOverlay(for pack: MapPackDescriptor) -> MKTileOverlay? {
        switch pack.format {
        case .mbtiles:
            let fileURL = persistence.baseURL.appendingPathComponent(pack.relativePath)
            guard let reader = MBTilesReader(url: fileURL) else { return nil }
            readers[pack.id] = reader
            return OfflineTileOverlay(reader: reader)
        case .directory:
            let directory = persistence.baseURL.appendingPathComponent(pack.relativePath)
            return OfflineTileOverlay(directory: directory)
        }
    }

    /// Offline place search over the imported packs.
    func search(_ query: String) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        var results: [String] = []
        for pack in packs where pack.id == activePackID {
            for name in pack.placeNames where name.lowercased().contains(trimmed) {
                results.append(name)
                if results.count >= 25 { return results }
            }
        }
        return results
    }

    /// Removes old packs when the storage limit is exceeded.
    func enforceStorageLimit(limitBytes: Int) async {
        var total = storageUsedBytes
        guard total > limitBytes else { return }
        for pack in packs.sorted(by: { $0.importedAt < $1.importedAt }) {
            guard total > limitBytes else { break }
            await deletePack(pack.id)
            total -= pack.byteCount
        }
    }
}

/// Downloads a file with progress reporting (used for map packs).
final class PackDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = PackDownloader()

    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var progressHandler: (@Sendable (Double) -> Void)?

    func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.progressHandler = progress
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(min(1, max(0, fraction)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let continuation else { return }
        self.continuation = nil
        let response = downloadTask.response
        // Move the temporary file so that it survives the end of the session.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("pack-\(UUID().uuidString).mbtiles")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation.resume(returning: (destination, response ?? URLResponse()))
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}
