import Foundation

struct FileStamp: Equatable, Sendable {
    let size: UInt64
    let modified: Date?
    let inode: UInt64
}

enum DocumentIO {
    static var editableLimit: UInt64 { SettingsStore.editableLimit }
    static func stamp(_ url: URL) throws -> FileStamp {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileStamp(size: (a[.size] as? NSNumber)?.uint64Value ?? 0,
                         modified: a[.modificationDate] as? Date,
                         inode: (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0)
    }
    static func read(_ url: URL, preferred: TextEncoding? = nil) throws -> DecodedText {
        try TextFileCodec.decode(Data(contentsOf: url, options: .mappedIfSafe), preferred: preferred)
    }

    /**
     * Batch replacement coordinates access and checks the version again after
     * acquiring the write claim; a stale search result must not overwrite a file.
     */
    static func replace(_ url: URL, data: Data, expected: FileStamp) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing,
                                        error: &coordinationError) { target in
            do {
                guard try stamp(target) == expected else { throw EditorError.externalChange }
                let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
                try data.write(to: target, options: .atomic)
                if let permissions = attributes[.posixPermissions] {
                    try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
                }
            } catch { writeError = error }
        }
        if let error = coordinationError { throw error }
        if let error = writeError { throw error }
    }
}
