import AppKit
import UniformTypeIdentifiers

@MainActor
final class TextDocument: NSDocument {
    static let didChangeState = Notification.Name("TextDocumentDidChangeState")
    nonisolated(unsafe) var initialText = ""
    nonisolated(unsafe) var metadata = DocumentMetadata()
    nonisolated(unsafe) var mode: DocumentMode = .text
    nonisolated(unsafe) private var diskStamp: FileStamp?
    nonisolated(unsafe) private var sourceURL: URL?
    var recoveryID = UUID()
    var revision = 0
    weak var editor: EditorController?
    private var recoveryTask: Task<Void, Never>?
    private var hasProvisionalEdit = false
    private var fileMonitor: DocumentFileMonitor?
    private(set) var externalFileState: ExternalFileState = .unchanged
    enum ExternalFileState { case unchanged, changed, unavailable }
    var restoredTitle: String?
    override var displayName: String! {
        get { fileURL == nil ? restoredTitle ?? super.displayName : super.displayName }
        set { super.displayName = newValue }
    }
    override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }
    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        refreshExternalChangeNotice()
        NotificationCenter.default.post(name: Self.didChangeState, object: self)
    }
    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        refreshExternalChangeNotice()
        NotificationCenter.default.post(name: Self.didChangeState, object: self)
    }
    nonisolated override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.allowsOtherFileTypes = true
        savePanel.canSelectHiddenExtension = true
        savePanel.isExtensionHidden = false
        if fileURL == nil, let restoredTitle { savePanel.nameFieldStringValue = restoredTitle }
        return true
    }

    nonisolated override func read(from url: URL, ofType typeName: String) throws {
        let loadedStamp = try DocumentIO.stamp(url)
        var loadedText = ""
        var loadedMetadata = DocumentMetadata()
        var loadedMode: DocumentMode = mode == .hex ? .hex : .text
        if loadedStamp.size > DocumentIO.editableLimit {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let sample = try file.read(upToCount: 4096) ?? Data()
            var decoded: DecodedText?
            for trim in 0...min(4, sample.count) {
                if let value = try? TextFileCodec.decode(sample.dropLast(trim)) { decoded = value; break }
            }
            if loadedMode != .hex, let decoded, !decoded.text.contains("\0") {
                loadedMode = .largeText; loadedMetadata = decoded.metadata
            } else { loadedMode = .hex }
        } else {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if let decoded = try? TextFileCodec.decode(data), !decoded.text.contains("\0"), loadedMode != .hex {
                loadedText = decoded.text; loadedMetadata = decoded.metadata
            } else { loadedMode = .hex }
        }
        guard try DocumentIO.stamp(url) == loadedStamp else { throw EditorError.externalChange }
        initialText = loadedText
        metadata = loadedMetadata
        mode = loadedMode
        diskStamp = loadedStamp
        sourceURL = url
    }

    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        let previousLanguage = metadata.languageID
        try super.revert(toContentsOf: url, ofType: typeName)
        metadata.languageID = previousLanguage == "txt" ? LanguageRegistry.shared.detect(url).id : previousLanguage
        revision += 1
        recoveryTask?.cancel()
        RecoveryStore.shared.remove(recoveryID)
        for controller in windowControllers.compactMap({ $0 as? DocumentWindowController }) { controller.reloadFromDocument() }
        startWatching()
    }

    override func makeWindowControllers() {
        if diskStamp == nil, let fileURL, mode != .text {
            diskStamp = try? DocumentIO.stamp(fileURL)
            sourceURL = fileURL
        }
        if mode == .text, metadata.languageID == "txt", fileURL != nil {
            metadata.languageID = LanguageRegistry.shared.detect(fileURL, prefix: String(initialText.prefix(100))).id
        }
        let controller = DocumentWindowController(document: self)
        addWindowController(controller)
        startWatching()
    }

    nonisolated override func data(ofType typeName: String) throws -> Data {
        try MainActor.assumeIsolated {
            guard mode == .text else { throw EditorError.readOnly }
            editor?.breakTypingCoalescing()
            return try TextFileCodec.encode(editor?.textView.string ?? initialText, metadata: metadata)
        }
    }

    nonisolated override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        guard mode == .text else { throw EditorError.readOnly }
        let destination = url.standardizedFileURL.resolvingSymlinksInPath()
        let replacesOpenFile = saveOperation == .saveOperation || [sourceURL, fileURL].compactMap { $0 }.contains {
            $0.standardizedFileURL.resolvingSymlinksInPath() == destination
        }
        if replacesOpenFile, let expected = diskStamp, (try? DocumentIO.stamp(url)) != expected {
            Task { @MainActor [weak self] in self?.checkForExternalChanges() }
            throw EditorError.externalChange
        }
        try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
        if saveOperation == .saveOperation || saveOperation == .saveAsOperation {
            sourceURL = url
            diskStamp = try? DocumentIO.stamp(url)
            Task { @MainActor [weak self] in
                self?.startWatching()
                (NSDocumentController.shared as? DocumentController)?.saveSession()
            }
        }
    }

    override func save(_ sender: Any?) {
        editor?.textView.unmarkText()
        super.save(sender)
    }
    func saveTimed() async -> Error? {
        guard let url = fileURL, mode == .text, isDocumentEdited, editor?.textView.isComposing != true else { return nil }
        guard FileManager.default.isWritableFile(atPath: url.path) else { return EditorError.readOnly }
        return await withCheckedContinuation { continuation in
            save(to: url, ofType: fileType ?? UTType.plainText.identifier, for: .saveOperation) { error in
                continuation.resume(returning: error)
            }
        }
    }

    override func move(to url: URL, completionHandler: ((Error?) -> Void)? = nil) {
        super.move(to: url) { error in
            if error == nil {
                self.sourceURL = self.fileURL
                self.startWatching()
                self.persistRecovery()
                if self.mode != .text {
                    for controller in self.windowControllers.compactMap({ $0 as? DocumentWindowController }) {
                        controller.reloadFromDocument()
                    }
                }
                let documents = NSDocumentController.shared as? DocumentController
                documents?.refreshSidebars(refreshFolders: true)
                documents?.saveSession()
            }
            completionHandler?(error)
        }
    }

    override func rename(_ sender: Any?) {
        (windowControllers.first as? DocumentWindowController)?.showDocumentRename(sender)
    }

    func rename(to name: String, completion: @escaping (Error?) -> Void) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains(where: { "/:\0".contains($0) }) else {
            completion(NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteInvalidFileName.rawValue,
                               userInfo: [NSLocalizedDescriptionKey: L10n.text("Enter a valid file name without / or :.")]))
            return
        }
        guard let fileURL else {
            restoredTitle = name
            displayName = name
            windowControllers.forEach { $0.synchronizeWindowTitleWithDocumentName() }
            persistRecovery()
            (NSDocumentController.shared as? DocumentController)?.refreshSidebars()
            completion(nil)
            return
        }
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent(name)
        if destination == fileURL { completion(nil); return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            completion(NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteFileExists.rawValue,
                               userInfo: [NSLocalizedDescriptionKey: L10n.text("A file with this name already exists.")]))
            return
        }
        move(to: destination, completionHandler: completion)
    }

    func contentDidChange(provisional: Bool) {
        revision += 1
        guard !provisional else { return }
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.persistRecovery()
        }
    }
    func beginProvisionalEdit() {
        guard !hasProvisionalEdit else { return }
        hasProvisionalEdit = true
        updateChangeCount(.changeDone)
    }
    func endProvisionalEdit() {
        guard hasProvisionalEdit else { return }
        hasProvisionalEdit = false
        updateChangeCount(.changeUndone)
    }
    func persistRecovery() {
        guard mode == .text, let editor, !editor.textView.isComposing else { return }
        if !isDocumentEdited && fileURL != nil { RecoveryStore.shared.remove(recoveryID); return }
        let text = editor.textView.string
        if text.isEmpty && fileURL == nil { return }
        do {
            try RecoveryStore.shared.save(RecoveryRecord(id: recoveryID, fileURL: fileURL, title: displayName,
                                                         text: text, metadata: metadata, savedAt: Date()))
        } catch { NSLog("Recovery save failed: %@", error.localizedDescription) }
    }

    func changeEncoding(_ encoding: TextEncoding, bom: Bool? = nil) {
        editor?.breakTypingCoalescing()
        let previous = metadata
        undoManager?.registerUndo(withTarget: self) { $0.restoreMetadata(previous) }
        metadata.encoding = encoding
        metadata.hasBOM = bom ?? (!encoding.bom.isEmpty && metadata.hasBOM)
        undoManager?.setActionName(L10n.text("Encoding"))
        editor?.onStatusChange?()
    }
    private func restoreMetadata(_ value: DocumentMetadata) {
        let previous = metadata
        undoManager?.registerUndo(withTarget: self) { $0.restoreMetadata(previous) }
        metadata = value
        editor?.onStatusChange?()
    }
    func changeLineEnding(_ ending: LineEnding) {
        guard let editor else { return }
        undoManager?.beginUndoGrouping()
        let previous = metadata
        undoManager?.registerUndo(withTarget: self) { $0.restoreMetadata(previous) }
        metadata.lineEnding = ending
        do {
            try editor.apply([TextEdit(range: NSRange(location: 0, length: editor.source.length), replacement: ending.converting(editor.textView.string))], name: "Line Endings")
        } catch { NSApp.presentError(error) }
        undoManager?.endUndoGrouping()
        editor.onStatusChange?()
    }
    func reload(encoding: TextEncoding) throws {
        guard let url = fileURL, let editor else { return }
        guard !isDocumentEdited else { throw EditorError.externalChange }
        let loadedStamp = try DocumentIO.stamp(url)
        let decoded = try DocumentIO.read(url, preferred: encoding)
        guard try DocumentIO.stamp(url) == loadedStamp else { throw EditorError.externalChange }
        let languageID = metadata.languageID
        try editor.apply([TextEdit(range: NSRange(location: 0, length: editor.source.length), replacement: decoded.text)], name: "Reload Encoding")
        metadata = decoded.metadata
        metadata.languageID = languageID
        diskStamp = loadedStamp
        startWatching()
        editor.onStatusChange?()
    }
    func startWatching() {
        fileMonitor?.stop()
        fileMonitor = nil
        if let url = fileURL {
            fileMonitor = DocumentFileMonitor(url: url) { [weak self] in self?.checkForExternalChanges() }
        }
        checkForExternalChanges()
    }

    func checkForExternalChanges() {
        guard let url = fileURL, let diskStamp else {
            externalFileState = .unchanged
            refreshExternalChangeNotice()
            return
        }
        if let current = try? DocumentIO.stamp(url) {
            externalFileState = current == diskStamp ? .unchanged : .changed
        } else { externalFileState = .unavailable }
        refreshExternalChangeNotice()
    }

    private func refreshExternalChangeNotice() {
        for controller in windowControllers.compactMap({ $0 as? DocumentWindowController }) {
            controller.updateExternalChangeNotice()
        }
    }

    nonisolated override func presentedItemDidChange() {
        // Keep the in-memory version until the user explicitly chooses to reload.
        Task { @MainActor [weak self] in self?.checkForExternalChanges() }
    }

    nonisolated override func presentedItemDidMove(to newURL: URL) {
        super.presentedItemDidMove(to: newURL)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.sourceURL = self.fileURL
            self.startWatching()
        }
    }

    override func close() {
        RecoveryStore.shared.remove(recoveryID)
        fileMonitor?.stop()
        fileMonitor = nil
        recoveryTask?.cancel()
        super.close()
    }
    deinit { recoveryTask?.cancel() }
}
