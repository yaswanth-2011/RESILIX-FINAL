import Foundation

/// File based persistence for the application.
///
/// Everything the app has to survive a restart with is stored below
/// `Application Support/Resilix`:
///
/// ```
/// Resilix/
///   settings.json      user preferences
///   messages.json      conversation history
///   peer_keys.json     pinned public keys of the peers
///   relay_queue.json   packets waiting for a route
///   dedup_store.json   identifiers of the processed packets
///   Media/             received photos, audio and files
///   Profile/           the local profile photo
///   Maps/              downloaded offline map packs
///   Models/            downloaded AI models
/// ```
actor PersistenceController {
    static let shared = PersistenceController()
    private let fm = FileManager.default

    nonisolated var baseURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("Resilix", isDirectory: true)
    }

    init() {
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        for name in [ResilixConstants.mediaDirectoryName,
                     ResilixConstants.profileDirectoryName,
                     ResilixConstants.mapDirectoryName,
                     ResilixConstants.modelDirectoryName] {
            try? fm.createDirectory(at: baseURL.appendingPathComponent(name, isDirectory: true),
                                    withIntermediateDirectories: true)
        }
    }

    private func url(for file: String) -> URL { baseURL.appendingPathComponent(file) }

    // MARK: - Generic documents

    func save<T: Codable>(_ value: T, to file: String) throws {
        let data = try JSONEncoder().encode(value)
        do {
            try data.write(to: url(for: file), options: .atomic)
        } catch {
            throw ResilixError.persistenceFailed(error.localizedDescription)
        }
    }

    func load<T: Codable>(_ type: T.Type, from file: String) throws -> T {
        let u = url(for: file)
        guard fm.fileExists(atPath: u.path) else { throw ResilixError.persistenceFailed("file not found") }
        let data = try Data(contentsOf: u)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Corrupt recovery: the broken file is removed so that the next
            // start is not blocked by it.
            try? fm.removeItem(at: u)
            throw ResilixError.persistenceFailed("corrupt data removed")
        }
    }

    func loadIfExists<T: Codable>(_ type: T.Type, from file: String) -> T? {
        guard fm.fileExists(atPath: url(for: file).path) else { return nil }
        return try? load(type, from: file)
    }

    func delete(file: String) { try? fm.removeItem(at: url(for: file)) }

    func clearAll() {
        try? fm.removeItem(at: baseURL)
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        for name in [ResilixConstants.mediaDirectoryName,
                     ResilixConstants.profileDirectoryName,
                     ResilixConstants.mapDirectoryName,
                     ResilixConstants.modelDirectoryName] {
            try? fm.createDirectory(at: baseURL.appendingPathComponent(name, isDirectory: true),
                                    withIntermediateDirectories: true)
        }
    }

    // MARK: - Typed helpers

    func saveMessages(_ m: [MeshMessage]) throws { try save(m, to: "messages.json") }
    func loadMessages() -> [MeshMessage] { loadIfExists([MeshMessage].self, from: "messages.json") ?? [] }
    func saveContacts(_ c: [ResilixContact]) throws { try save(c, to: "contacts.json") }
    func loadContacts() -> [ResilixContact] { loadIfExists([ResilixContact].self, from: "contacts.json") ?? [] }
    func saveResources(_ r: [MapResource]) throws { try save(r, to: "resources.json") }
    func loadResources() -> [MapResource] { loadIfExists([MapResource].self, from: "resources.json") ?? [] }
    func saveIncidents(_ i: [Incident]) throws { try save(i, to: "incidents.json") }
    func loadIncidents() -> [Incident] { loadIfExists([Incident].self, from: "incidents.json") ?? [] }
    func saveSettings(_ s: AppSettings) throws { try save(s, to: "settings.json") }
    func loadSettings() -> AppSettings { loadIfExists(AppSettings.self, from: "settings.json") ?? AppSettings() }
    func saveAIConversation(_ c: [AIChatTurn]) throws { try save(c, to: "ai_conversation.json") }
    func loadAIConversation() -> [AIChatTurn] { loadIfExists([AIChatTurn].self, from: "ai_conversation.json") ?? [] }
    func saveMapPacks(_ p: [MapPackDescriptor]) throws { try save(p, to: "map_packs.json") }
    func loadMapPacks() -> [MapPackDescriptor] { loadIfExists([MapPackDescriptor].self, from: "map_packs.json") ?? [] }

    // MARK: - Binary files (media, profile, maps, models)

    func directoryURL(named name: String) -> URL {
        let url = baseURL.appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func fileExists(at relativePath: String) -> Bool {
        fm.fileExists(atPath: baseURL.appendingPathComponent(relativePath).path)
    }

    func write(_ data: Data, to relativePath: String) throws {
        let target = baseURL.appendingPathComponent(relativePath)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            throw ResilixError.persistenceFailed(error.localizedDescription)
        }
    }

    func read(from relativePath: String) throws -> Data {
        let target = baseURL.appendingPathComponent(relativePath)
        guard fm.fileExists(atPath: target.path) else { throw ResilixError.persistenceFailed("file not found") }
        return try Data(contentsOf: target)
    }

    func removeFile(at relativePath: String) {
        try? fm.removeItem(at: baseURL.appendingPathComponent(relativePath))
    }

    /// Total size (bytes) of a directory inside the application support area.
    func directorySize(named name: String) -> Int {
        let url = baseURL.appendingPathComponent(name, isDirectory: true)
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.fileSizeKey],
                                             options: [.skipsHiddenFiles]) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += values?.fileSize ?? 0
        }
        return total
    }

    /// Removes the oldest files of a directory until the given budget is met.
    @discardableResult
    func enforceStorageLimit(named name: String, limitBytes: Int) -> Int {
        let url = baseURL.appendingPathComponent(name, isDirectory: true)
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                                             options: [.skipsHiddenFiles]) else { return 0 }
        var files: [(url: URL, size: Int, date: Date)] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            files.append((fileURL, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast))
        }
        var total = files.reduce(0) { $0 + $1.size }
        guard total > limitBytes else { return 0 }
        var removed = 0
        for file in files.sorted(by: { $0.date < $1.date }) {
            guard total > limitBytes else { break }
            try? fm.removeItem(at: file.url)
            total -= file.size
            removed += 1
        }
        return removed
    }
}
