import Foundation

struct BatchEncodingItem: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let metadata: DocumentMetadata?
    let stamp: FileStamp?
    var error: String?
    var status = "Ready"
}
enum BatchEncodingService {
    static func scan(root: URL, patterns: String, recursive: Bool, openURLs: Set<URL>) throws -> [BatchEncodingItem] {
        var query = SearchQuery(); query.filePatterns = patterns
        var rows: [BatchEncodingItem] = []
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = walker?.nextObject() as? URL {
            try Task.checkCancellation()
            do {
                let flags = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                if flags.isDirectory == true && !recursive { walker?.skipDescendants() }
                guard flags.isRegularFile == true, flags.isSymbolicLink != true, query.includes(url.lastPathComponent) else { continue }
                guard !openURLs.contains(url.standardizedFileURL.resolvingSymlinksInPath()) else { throw NSError(domain: "QuietGlyph", code: 1, userInfo: [NSLocalizedDescriptionKey: L10n.text("The file is open. Close it before batch conversion.")]) }
                let stamp = try DocumentIO.stamp(url)
                guard stamp.size <= DocumentIO.editableLimit else { throw NSError(domain: "QuietGlyph", code: 2, userInfo: [NSLocalizedDescriptionKey: L10n.text("File exceeds the conversion size limit.")]) }
                let decoded = try DocumentIO.read(url)
                guard !decoded.text.contains("\0") else { throw EditorError.decoding }
                guard try DocumentIO.stamp(url) == stamp else { throw EditorError.externalChange }
                rows.append(BatchEncodingItem(url: url, metadata: decoded.metadata, stamp: stamp))
            } catch { rows.append(BatchEncodingItem(url: url, metadata: nil, stamp: nil, error: error.localizedDescription)) }
        }
        return rows.sorted { $0.url.path < $1.url.path }
    }
    static func prepare(_ item: BatchEncodingItem, encoding: TextEncoding, bom: Bool) throws -> Data {
        guard item.error == nil, let stamp = item.stamp, try DocumentIO.stamp(item.url) == stamp else { throw EditorError.externalChange }
        var decoded = try DocumentIO.read(item.url, preferred: item.metadata?.encoding)
        decoded.metadata.encoding = encoding; decoded.metadata.hasBOM = bom && !encoding.bom.isEmpty
        try Task.checkCancellation()
        return try TextFileCodec.encode(decoded.text, metadata: decoded.metadata)
    }
}
