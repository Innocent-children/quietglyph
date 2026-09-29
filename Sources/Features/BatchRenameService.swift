import AppKit

struct BatchRenameOptions: Equatable, Sendable {
    enum LetterCase: String, CaseIterable, Sendable { case unchanged = "Unchanged", upper = "UPPERCASE", lower = "lowercase" }
    var prefix = ""
    var suffix = ""
    var letterCase = LetterCase.unchanged
    var changeExtension = false
    var fileExtension = ""
    var patterns = "*"
    var recursive = false
}
struct BatchRenameItem: Identifiable, Sendable {
    var id: URL { source }
    let source: URL
    let destination: URL
    let stamp: FileStamp?
    var error: String?
    var status = "Ready"
}

enum BatchRenameService {
    static func preview(root: URL, options: BatchRenameOptions) throws -> [BatchRenameItem] {
        var query = SearchQuery(); query.filePatterns = options.patterns
        var rows: [BatchRenameItem] = []
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let url = walker?.nextObject() as? URL {
            try Task.checkCancellation()
            let flags = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if flags.isDirectory == true && !options.recursive { walker?.skipDescendants() }
            guard flags.isRegularFile == true, flags.isSymbolicLink != true, query.includes(url.lastPathComponent) else { continue }
            var stem = url.deletingPathExtension().lastPathComponent
            switch options.letterCase { case .unchanged: break; case .upper: stem = stem.uppercased(); case .lower: stem = stem.lowercased() }
            let ext = options.changeExtension ? options.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")) : url.pathExtension
            let name = options.prefix + stem + options.suffix + (ext.isEmpty ? "" : "." + ext)
            let target = url.deletingLastPathComponent().appendingPathComponent(name)
            let stamp = try? DocumentIO.stamp(url)
            var error: String?
            if name.isEmpty || name == "." || name == ".." || name.contains(where: { "/:\0".contains($0) }) { error = L10n.text("Enter a valid file name without / or :.") }
            else if !FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path) { error = L10n.text("Folder is not writable.") }
            else if FileManager.default.fileExists(atPath: target.path), target != url,
                    !(target.lastPathComponent.lowercased() == url.lastPathComponent.lowercased() && (try? DocumentIO.stamp(target).inode) == stamp?.inode) { error = L10n.text("A file with this name already exists.") }
            rows.append(BatchRenameItem(source: url, destination: target, stamp: stamp, error: error, status: target == url ? "Unchanged" : "Ready"))
        }
        let caseSensitive = (try? root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames) ?? false
        let groups = Dictionary(grouping: rows.indices, by: { caseSensitive ? rows[$0].destination.path : rows[$0].destination.path.lowercased() })
        for indices in groups.values where indices.count > 1 { for index in indices { rows[index].error = L10n.text("Several files have the same target name.") } }
        return rows.sorted { $0.source.path < $1.source.path }
    }
    @MainActor static func execute(_ item: BatchRenameItem, documents: [TextDocument]) async throws {
        guard item.error == nil, let stamp = item.stamp else { throw EditorError.invalidRange }
        guard try DocumentIO.stamp(item.source) == stamp else { throw EditorError.externalChange }
        if item.source == item.destination { return }
        if FileManager.default.fileExists(atPath: item.destination.path),
           !(item.source.lastPathComponent.lowercased() == item.destination.lastPathComponent.lowercased() && (try? DocumentIO.stamp(item.destination).inode) == stamp.inode) { throw CocoaError(.fileWriteFileExists) }
        try Task.checkCancellation()
        if let document = documents.first(where: { $0.fileURL?.standardizedFileURL == item.source.standardizedFileURL }) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                document.move(to: item.destination) { error in if let error { continuation.resume(throwing: error) } else { continuation.resume() } }
            }
        } else {
            var coordinationError: NSError?, moveError: Error?
            NSFileCoordinator().coordinate(writingItemAt: item.source, options: .forMoving, writingItemAt: item.destination, options: [], error: &coordinationError) { source, destination in
                do {
                    guard try DocumentIO.stamp(source) == stamp else { throw EditorError.externalChange }
                    try FileManager.default.moveItem(at: source, to: destination)
                } catch { moveError = error }
            }
            if let error = coordinationError ?? moveError { throw error }
        }
    }
}
