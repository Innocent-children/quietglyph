import AppKit
import UniformTypeIdentifiers

@MainActor
final class DocumentController: NSDocumentController {
    private var documentObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var stateObserver: NSObjectProtocol?

    override func addDocument(_ document: NSDocument) {
        if stateObserver == nil {
            stateObserver = NotificationCenter.default.addObserver(forName: NativeTextDocument.didChangeState, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSidebars() }
            }
        }
        super.addDocument(document)
        documentObservations[ObjectIdentifier(document)] = document.observe(\.fileURL) { [weak self] _, _ in
            Task { @MainActor in self?.refreshSidebars() }
        }
        saveSession()
    }
    override func removeDocument(_ document: NSDocument) {
        documentObservations.removeValue(forKey: ObjectIdentifier(document))
        super.removeDocument(document)
        if (NSApp.delegate as? AppDelegate)?.isPreparingTermination != true { saveSession() }
    }
    override var defaultType: String? { UTType.plainText.identifier }
    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let document = NativeTextDocument()
        document.fileType = UTType.plainText.identifier
        return document
    }
    func open(_ url: URL, completion: ((NativeTextDocument) -> Void)? = nil) {
        openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error { NSApp.presentError(error) }
            if let document = document as? NativeTextDocument { completion?(document) }
            self.refreshSidebars()
        }
    }
    func openViewer(_ url: URL, mode: DocumentMode, frame: NSRect? = nil) {
        let document = NativeTextDocument()
        document.fileURL = url
        document.fileType = UTType.data.identifier
        document.mode = mode
        addDocument(document)
        document.makeWindowControllers()
        if SettingsStore.shared.values.rememberWindowFrame, let frame { (document.windowControllers.first as? DocumentWindowController)?.restoreFrame(frame) }
        document.showWindows()
        refreshSidebars()
    }
    func restore(_ record: RecoveryRecord) {
        let document = NativeTextDocument()
        document.recoveryID = record.id
        document.initialText = record.text
        document.metadata = record.metadata
        document.restoredTitle = L10n.format("Recovered — %@", record.title)
        document.fileType = UTType.plainText.identifier
        addDocument(document)
        document.makeWindowControllers()
        document.updateChangeCount(.changeDone)
        document.showWindows()
        refreshSidebars()
    }
    func refreshSidebars(refreshFolders: Bool = false) {
        let items = documents.compactMap { $0 as? NativeTextDocument }.map { document in
            OpenDocumentItem(id: document.recoveryID, title: document.displayName, modified: document.isDocumentEdited) { [weak document] in
                document?.showWindows()
                document?.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
            }
        }
        for document in documents {
            guard let sidebar = (document.windowControllers.first as? DocumentWindowController)?.sidebarModel else { continue }
            sidebar.documents = items
            if refreshFolders { sidebar.folder = sidebar.folder.map { FolderNode($0.url) } }
        }
    }
    func saveSession() {
        SessionStore.shared.save(documents.compactMap { document in
            guard let document = document as? NativeTextDocument, let url = document.fileURL else { return nil }
            return SessionEntry(url: url, mode: document.mode, selection: document.editor?.textView.selectedRange().location ?? 0,
                                frame: SettingsStore.shared.values.rememberWindowFrame ? document.windowControllers.first?.window?.frame : nil)
        })
    }
    deinit { if let stateObserver { NotificationCenter.default.removeObserver(stateObserver) } }
}
