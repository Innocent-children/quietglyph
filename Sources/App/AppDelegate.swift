import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let documents: DocumentController
    var menuController: MenuController!
    private var settingsWindow: NSWindowController?
    private(set) var isPreparingTermination = false
    private let initialSession = SessionStore.shared.load()
    private lazy var autosave = AutosaveController(documents: { [weak self] in self?.documents.documents.compactMap { $0 as? TextDocument } ?? [] })
    private var settingsObserver: NSObjectProtocol?
    init(documents: DocumentController) { self.documents = documents; super.init() }
    func applicationWillFinishLaunching(_ notification: Notification) {
        documents.autosavingDelay = 0
        NSWindow.allowsAutomaticWindowTabbing = true
        menuController = MenuController(delegate: self)
        menuController.install()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppearancePolicy.shared
        NSApp.activate(ignoringOtherApps: true)
        guard !InklineApplication.isTesting else { documents.newDocument(nil); return }
        autosave.configure(enabled: SettingsStore.shared.values.timedSave)
        settingsObserver = NotificationCenter.default.addObserver(forName: SettingsStore.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.autosave.configure(enabled: SettingsStore.shared.values.timedSave) }
        }
        let records = RecoveryStore.shared.records()
        if !records.isEmpty {
            let alert = NSAlert()
            alert.messageText = L10n.text("Recover unsaved documents?")
            alert.informativeText = records.map(\.title).joined(separator: "\n")
            alert.addButton(withTitle: L10n.text("Recover")); alert.addButton(withTitle: L10n.text("Later")); alert.addButton(withTitle: L10n.text("Discard"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: records.forEach(documents.restore)
            case .alertThirdButtonReturn: records.forEach { RecoveryStore.shared.remove($0.id) }
            default: break
            }
        }
        if SettingsStore.shared.values.restoreSession {
            for entry in initialSession where FileManager.default.fileExists(atPath: entry.url.path) {
                if entry.mode == .text {
                    documents.open(entry.url) { document in
                        if SettingsStore.shared.values.rememberWindowFrame, let frame = entry.frame { (document.windowControllers.first as? DocumentWindowController)?.restoreFrame(frame) }
                        if let editor = document.editor {
                            editor.setSelections([NSRange(location: min(entry.selection, editor.source.length), length: 0)], scroll: true)
                        }
                    }
                } else { documents.openViewer(entry.url, mode: entry.mode, frame: entry.frame) }
            }
        }
        if documents.documents.isEmpty { documents.newDocument(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if documents.documents.isEmpty {
            documents.newDocument(nil)
        } else {
            for document in documents.documents {
                document.showWindows()
                for controller in document.windowControllers {
                    controller.window?.deminiaturize(nil)
                    controller.window?.makeKeyAndOrderFront(nil)
                }
            }
        }
        return false
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        filenames.forEach { documents.open(URL(fileURLWithPath: $0)) }
        sender.reply(toOpenOrPrint: .success)
    }
    func prepareTermination() {
        isPreparingTermination = true
        documents.saveSession()
        for document in documents.documents.compactMap({ $0 as? TextDocument }) {
            document.editor?.textView.unmarkText()
            document.persistRecovery()
        }
    }
    func cancelTermination() { isPreparingTermination = false; documents.saveSession() }
    func applicationWillTerminate(_ notification: Notification) {
        autosave.stop()
        if SettingsStore.shared.values.clearRecentOnQuit { documents.clearRecentDocuments(nil) }
        if !isPreparingTermination { documents.saveSession() }
    }
    deinit { if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) } }
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = L10n.text("Settings")
            window.styleMask = [.titled, .closable]
            window.center()
            settingsWindow = NSWindowController(window: window)
        }
        settingsWindow?.showWindow(nil); settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }
}
