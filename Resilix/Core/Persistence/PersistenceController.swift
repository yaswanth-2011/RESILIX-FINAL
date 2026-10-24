import Foundation

actor PersistenceController {
    static let shared = PersistenceController()
    private let fm = FileManager.default
    private nonisolated var baseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Resilix", isDirectory: true)
    }
    init() { try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true) }

    private func url(for file: String) -> URL { baseURL.appendingPathComponent(file) }

    func save<T: Codable>(_ value: T, to file: String) throws {
        let data = try JSONEncoder().encode(value)
        do { try data.write(to: url(for: file), options: .atomic) }
        catch { throw ResilixError.persistenceFailed(error.localizedDescription) }
    }
    func load<T: Codable>(_ type: T.Type, from file: String) throws -> T {
        let u = url(for: file)
        guard fm.fileExists(atPath: u.path) else { throw ResilixError.persistenceFailed("file not found") }
        let data = try Data(contentsOf: u)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { // corrupt recovery
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
    }
    // Typed helpers
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
}
