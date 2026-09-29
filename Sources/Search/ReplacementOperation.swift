import Foundation

struct ReplacementReport: Sendable {
    var changed = 0
    var occurrences = 0
    var failures: [String] = []
    var cancelled = false
    var changedOpenDocuments = 0
    var changedClosedFiles = 0
}

enum ReplacementOperation {
    struct Prepared: Sendable {
        let url: URL
        let data: Data
        let stamp: FileStamp
        let occurrences: Int
        let changed: Bool
    }
    static func prepare(_ url: URL, expected: FileStamp, transform: (String) throws -> (edits: [TextEdit], occurrences: Int)) throws -> Prepared {
        guard try DocumentIO.stamp(url) == expected else { throw EditorError.externalChange }
        let decoded = try DocumentIO.read(url)
        let change = try transform(decoded.text)
        let applied = try EditTransaction.applying(change.edits, to: decoded.text)
        return Prepared(url: url, data: try FileCodec.encode(applied.text, metadata: decoded.metadata), stamp: expected,
                        occurrences: change.occurrences, changed: applied.text != decoded.text)
    }
    static func commit(_ prepared: Prepared) throws {
        try Task.checkCancellation()
        if prepared.changed { try DocumentIO.replace(prepared.url, data: prepared.data, expected: prepared.stamp) }
    }
    static func apply(_ results: [SearchResult], query: SearchQuery, openURLs: Set<URL>) async -> ReplacementReport {
        var report = ReplacementReport()
        let grouped = Dictionary(grouping: results.filter { $0.url != nil }, by: { $0.url! })
        for url in grouped.keys.sorted(by: { $0.path < $1.path }) {
            if Task.isCancelled { report.cancelled = true; break }
            do {
                guard !openURLs.contains(url.standardizedFileURL) else {
                    throw NSError(domain: "QuietGlyph", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("The file is open. Replace in its editor to preserve unsaved changes.")])
                }
                guard let stamp = grouped[url]?.first?.stamp, try DocumentIO.stamp(url) == stamp else { throw EditorError.externalChange }
                let prepared = try prepare(url, expected: stamp) { text in
                    let edits = try SearchService.edits(query, in: text); return (edits, edits.count)
                }
                try commit(prepared)
                guard prepared.changed else { continue }
                report.changed += 1
                report.changedClosedFiles += 1
                report.occurrences += prepared.occurrences
            } catch is CancellationError { report.cancelled = true; break }
            catch { report.failures.append("\(url.path): \(error.localizedDescription)") }
        }
        return report
    }
}
