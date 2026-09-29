import Foundation

struct SearchResult: Identifiable, Sendable {
    let id = UUID()
    let url: URL?
    let range: NSRange
    let line: Int
    let column: Int
    let preview: String
    let stamp: FileStamp?
    var documentID: UUID?
    var revision: Int?
    var documentTitle: String?
    var matchedText = ""
    var searchRange: NSRange?
    var groupID: String { documentID?.uuidString ?? url?.path ?? "current" }
    var title: String { documentTitle ?? url?.lastPathComponent ?? L10n.text("Document") }
}

struct SearchReport: Sendable {
    var results: [SearchResult] = []
    var failures: [String] = []
    var scanned = 0
    var truncated = false
    var cancelled = false
}
