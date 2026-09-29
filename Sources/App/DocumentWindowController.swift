import AppKit
import SwiftUI

@MainActor
final class DocumentWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
    let sidebarModel = SidebarModel()
    let status = EditorStatus()
    let searchModel = SearchPanelModel()
    let split = NSSplitViewController()
    var editorController: EditorController?
    var viewer: LargeTextViewController?
    private var searchHost: NSHostingController<SearchPanel>!
    private var searchHeight: NSLayoutConstraint!
    private let textDocument: TextDocument
    private let documentTitleButton = NSButton()
    private weak var documentTitleField: NSTextField?
    private var documentTitleConstraints: [NSLayoutConstraint] = []
    private(set) var renamePopover: NSPopover?
    var preview: MarkdownPreviewController?
    var navigation: NSSegmentedControl?
    private var windowReady = false

    init(document: TextDocument) {
        textDocument = document
        let rememberedFrame = SettingsStore.shared.values.rememberWindowFrame ? SessionStore.shared.windowFrame() : nil
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1600, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 700, height: 420)
        window.titlebarAppearsTransparent = true
        // SessionStore and RecoveryStore own document restoration; avoid a second AppKit restoration pass.
        window.isRestorable = false
        window.tabbingIdentifier = "QuietGlyphDocuments"
        window.tabbingMode = .preferred
        super.init(window: window)
        window.delegate = self
        configureDocumentTitle()
        configureContent()
        let available = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1600, height: 900)
        let scale = min(1, min(available.width * 0.9 / 1600, available.height * 0.9 / 900))
        window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 1600 * scale, height: 900 * scale)), display: false)
        window.center()
        if let rememberedFrame { restoreFrame(rememberedFrame) }
        windowReady = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configureDocumentTitle() {
        documentTitleButton.isBordered = false
        documentTitleButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: L10n.text("Rename…"))
        documentTitleButton.imagePosition = .imageTrailing
        documentTitleButton.cell?.lineBreakMode = .byTruncatingTail
        documentTitleButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        documentTitleButton.target = self
        documentTitleButton.action = #selector(showDocumentRename(_:))
        documentTitleButton.toolTip = L10n.text("Rename…")
        documentTitleButton.setAccessibilityIdentifier("documentRename")
        documentTitleButton.setAccessibilityLabel(L10n.text("Rename…"))
        documentTitleButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            documentTitleButton.heightAnchor.constraint(equalToConstant: 18)
        ])
        attachDocumentRenameButton()
    }

    private func attachDocumentRenameButton() {
        guard let window, !window.title.isEmpty, let frame = window.contentView?.superview else { return }
        func titleField(in view: NSView) -> NSTextField? {
            if view === window.contentView { return nil }
            if let field = view as? NSTextField, field.stringValue == window.title { return field }
            for child in view.subviews {
                if let field = titleField(in: child) { return field }
            }
            return nil
        }
        guard let title = titleField(in: frame),
              let closeButton = window.standardWindowButton(.closeButton),
              let titlebar = closeButton.superview else { return }
        title.isHidden = true
        documentTitleButton.title = textDocument.displayName
        documentTitleButton.font = title.font
        if documentTitleField === title, documentTitleButton.superview === titlebar { return }
        NSLayoutConstraint.deactivate(documentTitleConstraints)
        documentTitleButton.removeFromSuperview()
        documentTitleField = title
        titlebar.addSubview(documentTitleButton)
        documentTitleConstraints = [
            documentTitleButton.centerXAnchor.constraint(equalTo: frame.centerXAnchor),
            documentTitleButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            documentTitleButton.widthAnchor.constraint(lessThanOrEqualTo: frame.widthAnchor, multiplier: 0.35),
            documentTitleButton.widthAnchor.constraint(lessThanOrEqualTo: frame.widthAnchor, constant: -600)
        ]
        NSLayoutConstraint.activate(documentTitleConstraints)
    }

    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        DispatchQueue.main.async { [weak self] in self?.attachDocumentRenameButton() }
    }

    @objc func showDocumentRename(_ sender: Any?) {
        if let renamePopover, renamePopover.isShown { renamePopover.performClose(sender); return }
        let popover = NSPopover()
        popover.behavior = .transient
        let host = NSHostingController(rootView: DocumentRenameView(document: textDocument) { [weak popover] in
            popover?.performClose(nil)
        })
        host.view.layoutSubtreeIfNeeded()
        popover.contentViewController = host
        popover.contentSize = host.view.fittingSize
        renamePopover = popover
        guard let frame = window?.contentView?.superview else { return }
        frame.layoutSubtreeIfNeeded()
        popover.show(relativeTo: documentTitleButton.convert(documentTitleButton.bounds, to: frame), of: frame, preferredEdge: .minY)
    }

    private func configureContent() {
        guard let window else { return }
        let document = textDocument
        searchModel.cancel()
        searchModel.report = SearchReport()
        searchModel.isVisible = false
        searchModel.editor = nil
        editorController = nil
        viewer = nil
        document.editor = nil
        for item in split.splitViewItems { split.removeSplitViewItem(item) }
        let sidebar = NSHostingController(rootView: SidebarView(model: sidebarModel))
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 170
        sidebarItem.maximumThickness = 340
        split.addSplitViewItem(sidebarItem)
        let center = NSViewController()
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 0; stack.detachesHiddenViews = true
        if document.mode == .text {
            let editor = EditorController(document: document)
            editorController = editor; document.editor = editor
            center.addChild(editor)
            stack.addArrangedSubview(editor.view)
            editor.view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            editor.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
            editor.textView.setAccessibilityIdentifier("editor")
            editor.onStatusChange = { [weak self] in self?.updateStatus() }
            searchModel.editor = editor
        } else if let url = document.fileURL {
            let viewer = document.mode == .hex ? HexViewController(url: url) : LargeTextViewController(url: url)
            self.viewer = viewer
            center.addChild(viewer); stack.addArrangedSubview(viewer.view)
            viewer.view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            viewer.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        }
        searchHost = NSHostingController(rootView: SearchPanel(model: searchModel))
        center.addChild(searchHost)
        stack.addArrangedSubview(searchHost.view)
        searchHost.view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        searchHeight = searchHost.view.heightAnchor.constraint(equalToConstant: 380)
        searchHeight.isActive = true
        searchHost.view.isHidden = true
        let bar = NSHostingView(rootView: StatusBarView(status: status))
        stack.addArrangedSubview(bar)
        bar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        bar.heightAnchor.constraint(equalToConstant: 26).isActive = true
        center.view = stack
        split.addSplitViewItem(NSSplitViewItem(viewController: center))
        window.contentViewController = split
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "NativeEditorToolbar")
            toolbar.delegate = self; toolbar.allowsUserCustomization = true; toolbar.autosavesConfiguration = true
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
        }
        sidebarModel.onOpen = { url in (NSDocumentController.shared as? DocumentController)?.open(url) }
        sidebarModel.onBookmark = { [weak self] line in self?.editorController?.goTo(line: line) }
        searchModel.onOpenResult = { [weak self] result in self?.activateResult(result) }
        window.initialFirstResponder = editorController?.textView ?? viewer?.textView
        if window.isKeyWindow { window.makeFirstResponder(window.initialFirstResponder) }
        updateStatus()
    }
    func reloadFromDocument() {
        let selection = editorController?.textView.selectedRange() ?? NSRange(location: 0, length: 0)
        configureContent()
        if let editorController {
            editorController.setSelections([NSRange(location: min(selection.location, editorController.source.length), length: 0)], scroll: true)
        } else { preview?.close(); preview = nil }
        window?.subtitle = ""
    }

    func updateStatus() {
        if let editor = editorController {
            let text = editor.source
            let selection = editor.selections.ranges.first ?? NSRange(location: 0, length: 0)
            let lines = TextRanges.lines(text)
            let line = lines.lastIndex(where: { $0.location <= selection.location }) ?? 0
            status.position = L10n.format("Ln %ld, Col %ld", line + 1, selection.location - lines[line].location + 1)
            status.selection = editor.selections.ranges.count > 1 ? L10n.format("%ld selections", editor.selections.ranges.count) : selection.length > 0 ? L10n.format("%ld selected", selection.length) : ""
            status.size = L10n.format("%ld lines", lines.count)
            status.language = L10n.text(editor.language.name)
            sidebarModel.bookmarks = editor.bookmarks.offsets.map { TextRanges.lineNumber(at: $0, in: text) }
            if preview?.window?.isVisible == true { preview?.render(editor.textView.string, baseURL: textDocument.fileURL?.deletingLastPathComponent()) }
        } else { status.position = L10n.text("Read Only"); status.language = textDocument.mode == .hex ? L10n.text("Hexadecimal") : L10n.text("Large Text") }
        status.encoding = textDocument.mode == .hex ? L10n.text("Bytes") : textDocument.metadata.encoding.title + (textDocument.metadata.hasBOM ? " BOM" : "")
        status.lineEnding = textDocument.mode == .text ? textDocument.metadata.lineEnding.title : L10n.text("Read Only")
        (NSDocumentController.shared as? DocumentController)?.refreshSidebars()
    }
    func showSearch() {
        guard textDocument.mode == .text else { viewer?.searchField.becomeFirstResponder(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = AppearancePolicy.shared.duration
            context.allowsImplicitAnimation = context.duration > 0
            searchHost.view.isHidden = false
            searchModel.isVisible = true
            window?.contentView?.layoutSubtreeIfNeeded()
        }
    }
    @objc func toggleSearch(_ sender: Any?) {
        if searchHost.view.isHidden { showSearch() } else { searchHost.view.isHidden = true; searchModel.isVisible = false; window?.makeFirstResponder(editorController?.textView) }
    }
    @objc func navigate(_ sender: NSSegmentedControl) { sidebarModel.selectedTab = sender.selectedSegment }
    @objc func toggleSidebar(_ sender: Any?) { split.toggleSidebar(sender) }
    func showPreview() {
        guard let editor = editorController else { return }
        if preview == nil { preview = MarkdownPreviewController() }
        preview?.render(editor.textView.string, baseURL: textDocument.fileURL?.deletingLastPathComponent()); preview?.showWindow(nil)
    }
    private func activateResult(_ result: SearchResult) {
        do { try SearchCoordinator.activate(result, editor: editorController) }
        catch { searchModel.message = error.localizedDescription }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        updateStatus()
        attachDocumentRenameButton()
    }
    func windowDidResize(_ notification: Notification) {
        rememberFrame()
        (NSDocumentController.shared as? DocumentController)?.saveSession()
        attachDocumentRenameButton()
        guard let renamePopover, renamePopover.isShown, let frame = window?.contentView?.superview else { return }
        frame.layoutSubtreeIfNeeded()
        renamePopover.positioningRect = documentTitleButton.convert(documentTitleButton.bounds, to: frame)
    }
    func windowDidMove(_ notification: Notification) { rememberFrame(); (NSDocumentController.shared as? DocumentController)?.saveSession() }
    private func rememberFrame() {
        if windowReady, SettingsStore.shared.values.rememberWindowFrame, let window { SessionStore.shared.saveWindowFrame(window.frame) }
    }
    func restoreFrame(_ requested: NSRect) {
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(requested) }) ?? NSScreen.main
        guard let screen else { return }
        let bounds = screen.visibleFrame
        var frame = requested
        frame.size.width = min(max(720, frame.width), bounds.width)
        frame.size.height = min(max(480, frame.height), bounds.height)
        frame.origin.x = min(max(bounds.minX, frame.minX), bounds.maxX - frame.width)
        frame.origin.y = min(max(bounds.minY, frame.minY), bounds.maxY - frame.height)
        window?.setFrame(frame, display: true)
    }
    func windowWillClose(_ notification: Notification) {
        searchModel.cancel()
        DispatchQueue.main.async { (NSDocumentController.shared as? DocumentController)?.refreshSidebars() }
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("sidebar"), .init("navigation"), .flexibleSpace, .init("find"), .init("settings")] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.init("sidebar"), .init("navigation"), .flexibleSpace, .init("find")] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier.rawValue {
        case "sidebar":
            item.label = L10n.text("Sidebar"); item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: L10n.text("Sidebar"))
            item.target = self; item.action = #selector(toggleSidebar(_:))
        case "navigation":
            item.label = L10n.text("Navigate")
            let control = AppKitControlFactory.navigation(labels: ["Files", "Bookmarks"], target: self, action: #selector(navigate(_:)))
            control.selectedSegment = 0; navigation = control; item.view = control
        case "find":
            item.label = L10n.text("Find"); item.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: L10n.text("Find"))
            item.target = self; item.action = #selector(toggleSearch(_:))
        case "settings":
            item.label = L10n.text("Settings"); item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: L10n.text("Settings"))
            item.target = (NSApp.delegate as? AppDelegate)?.menuController; item.action = #selector(MenuController.settings(_:))
        default: return nil
        }
        return item
    }
}
