import Foundation

struct RecoveryRecord: Codable, Identifiable {
    let id: UUID
    var fileURL: URL?
    var title: String
    var text: String
    var metadata: DocumentMetadata
    var savedAt: Date
}

final class RecoveryStore {
    static let shared = RecoveryStore()
    let directory: URL
    init(directory: URL? = nil) {
        let base = QuietGlyphApplication.isTesting ? FileManager.default.temporaryDirectory.appendingPathComponent("QuietGlyphTests-\(ProcessInfo.processInfo.processIdentifier)") :
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.innocentchildren.quietglyph")
        self.directory = directory ?? base.appendingPathComponent("Recovery", isDirectory: true)
    }
    func save(_ record: RecoveryRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: path(record.id), options: .atomic)
    }
    func records() -> [RecoveryRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "json" }.compactMap {
            guard let data = try? Data(contentsOf: $0) else { return nil }
            return try? JSONDecoder().decode(RecoveryRecord.self, from: data)
        }.sorted { $0.savedAt < $1.savedAt }
    }
    func remove(_ id: UUID) { try? FileManager.default.removeItem(at: path(id)) }
    private func path(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}
