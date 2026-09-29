import Foundation

struct SessionEntry: Codable {
    var url: URL
    var mode: DocumentMode
    var selection: Int
    var frame: NSRect? = nil
}

final class SessionStore {
    static let shared = SessionStore()
    func windowFrame() -> NSRect? {
        guard !QuietGlyphApplication.isTesting, let value = UserDefaults.standard.string(forKey: "nativeWindowFrame") else { return nil }
        let frame = NSRectFromString(value)
        return frame.width > 0 && frame.height > 0 ? frame : nil
    }
    func saveWindowFrame(_ frame: NSRect) {
        guard !QuietGlyphApplication.isTesting else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "nativeWindowFrame")
    }
    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.innocentchildren.quietglyph").appendingPathComponent("session.json")
    func load() -> [SessionEntry] {
        if QuietGlyphApplication.isTesting { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SessionEntry].self, from: data)) ?? []
    }
    func save(_ entries: [SessionEntry]) {
        if QuietGlyphApplication.isTesting { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: url, options: .atomic)
        } catch { NSLog("Session save failed: %@", error.localizedDescription) }
    }
}
