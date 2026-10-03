import AppKit
import SwiftUI

@MainActor
final class MenuController: NSObject, NSMenuItemValidation, NSMenuDelegate {
    struct ShortcutEntry: Identifiable { var id: String; var title: String }
    static var shortcutEntries: [ShortcutEntry] {
        func collect(_ menu: NSMenu) -> [ShortcutEntry] {
            menu.items.flatMap { item -> [ShortcutEntry] in
                if let submenu = item.submenu { return collect(submenu) }
                guard let id = item.identifier?.rawValue, !id.hasPrefix("recent:") else { return [] }
                return [ShortcutEntry(id: id, title: menu.title + " — " + item.title)]
            }
        }
        return NSApp.mainMenu.map(collect) ?? []
    }
    weak var delegate: AppDelegate?
    private var observer: NSObjectProtocol?
    private var batchSearchWindow: BatchSearchWindowController?
    private var toolWindows: [String: NSWindowController] = [:]
    init(delegate: AppDelegate) {
        self.delegate = delegate
        super.init()
        observer = NotificationCenter.default.addObserver(forName: SettingsStore.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.install() }
        }
    }
    var document: TextDocument? { NSDocumentController.shared.currentDocument as? TextDocument }
    var windowController: DocumentWindowController? { document?.windowControllers.first as? DocumentWindowController }
    var editor: EditorController? { document?.editor }

    func install() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let parent = NSMenuItem(title: L10n.text(title), action: nil, keyEquivalent: "")
            let child = NSMenu(title: L10n.text(title)); parent.submenu = child; main.addItem(parent); return child
        }
        func standard(_ menu: NSMenu, _ title: String, _ action: String, _ key: String = "") {
            let item = AppKitControlFactory.menuItem(title: title, selector: NSSelectorFromString(action), key: key)
            configureShortcut(item, id: "system:" + action)
            menu.addItem(item)
        }
        let app = menu("Inkline")
        standard(app, "About Inkline", "orderFrontStandardAboutPanel:")
        app.addItem(.separator())
        app.addItem(AppKitControlFactory.menuItem(title: "Settings…", selector: #selector(settings(_:)), key: ",", target: self))
        let services = NSMenu(title: L10n.text("Services"))
        let serviceItem = NSMenuItem(title: L10n.text("Services"), action: nil, keyEquivalent: ""); serviceItem.submenu = services; app.addItem(serviceItem); NSApp.servicesMenu = services
        app.addItem(.separator())
        standard(app, "Hide Inkline", "hide:", "h"); standard(app, "Show All", "unhideAllApplications:")
        app.addItem(.separator()); standard(app, "Quit Inkline", "terminate:", "q")
        let file = menu("File")
        standard(file, "New", "newDocument:", "n"); standard(file, "Open…", "openDocument:", "o")
        let recent = submenu(file, "Open Recent"); recent.identifier = NSUserInterfaceItemIdentifier("recent"); recent.delegate = self
        action(file, "Open Folder…", "open-folder")
        action(file, "Batch Rename…", "batch-rename")
        file.addItem(.separator()); standard(file, "Save", "saveDocument:", "s")
        standard(file, "Save As…", "saveDocumentAs:", "S"); standard(file, "Save All", "saveAllDocuments:")
        standard(file, "Rename…", "renameDocument:")
        standard(file, "Revert to Saved…", "revertDocumentToSaved:")
        file.addItem(.separator()); action(file, "Open as Hexadecimal", "hex"); action(file, "Open as Text", "text")
        file.addItem(.separator()); action(file, "Print…", "print", key: "p")
        standard(file, "Close", "performClose:", "w")
        action(file, "Close All", "close-all")
        let edit = menu("Edit")
        standard(edit, "Undo", "undo:", "z"); standard(edit, "Redo", "redo:", "Z")
        edit.addItem(.separator())
        standard(edit, "Cut", "cut:", "x"); standard(edit, "Copy", "copy:", "c"); standard(edit, "Paste", "paste:", "v")
        standard(edit, "Select All", "selectAll:", "a")
        action(edit, "Add Next Occurrence", "add-next", key: "d")
        action(edit, "Select All Occurrences", "select-occurrences")
        action(edit, "Column Selection…", "column-select"); action(edit, "Insert Column Numbers…", "column-numbers")
        action(edit, "Column Selection Mode", "column-mode")
        action(edit, "Insert Column Text…", "column-text")
        standard(edit, "Complete Word", "complete:")
        let search = menu("Search")
        action(search, "Find…", "find", key: "f"); action(search, "Replace…", "replace")
        action(search, "Find Next", "next", key: "g"); action(search, "Find Previous", "previous", key: "G")
        action(search, "Find in Folder…", "find-folder", key: "F"); action(search, "Go to Line…", "go-line", key: "l")
        action(search, "Batch Find…", "batch-find")
        action(search, "Navigate Back", "navigate-back", key: "[")
        action(search, "Navigate Forward", "navigate-forward", key: "]")
        let view = menu("View")
        action(view, "Toggle Sidebar", "sidebar"); action(view, "Hide Find Panel", "hide-find")
        action(view, "Wrap Lines", "wrap"); action(view, "Show Whitespace", "whitespace"); action(view, "Show Line Endings", "show-eol")
        action(view, "Detect Links", "links")
        view.addItem(.separator())
        action(view, "Toggle Fold", "fold"); action(view, "Fold All", "fold-all"); action(view, "Unfold All", "unfold-all")
        action(view, "Markdown Preview", "preview"); action(view, "Zoom In", "zoom-in", key: "+"); action(view, "Zoom Out", "zoom-out", key: "-")
        let theme = submenu(view, "Theme")
        for item in SettingsStore.shared.themes { action(theme, item.name, "theme:" + item.id) }
        let format = menu("Format")
        let cases = submenu(format, "Case & Whitespace")
        for item in TextCommand.allCases { action(cases, item.rawValue, "text:" + item.rawValue) }
        let lines = submenu(format, "Lines")
        for item in LineCommand.allCases { action(lines, item.rawValue, "line:" + item.rawValue) }
        action(lines, "Move Lines Up", "move-up"); action(lines, "Move Lines Down", "move-down")
        action(lines, "Insert Blank Line Above", "blank-above"); action(lines, "Insert Blank Line Below", "blank-below")
        action(format, "Toggle Line Comment", "comment", key: "/"); action(format, "Block Comment", "block-comment")
        action(format, "Remove Block Comment", "unblock-comment")
        action(format, "Format JSON", "json"); action(format, "Format XML", "xml")
        let ending = submenu(format, "Line Endings")
        for item in LineEnding.allCases { action(ending, item.title, "eol:" + item.rawValue) }
        let encodings = menu("Encoding")
        for item in TextEncoding.allCases { action(encodings, item.title, "encoding:" + item.rawValue) }
        action(encodings, "Toggle BOM", "bom")
        let reload = submenu(encodings, "Reload with Encoding")
        for item in TextEncoding.allCases { action(reload, item.title, "reload:" + item.rawValue) }
        action(encodings, "Batch Convert Folder…", "batch-encoding")
        let languages = menu("Language")
        for language in LanguageRegistry.shared.languages { action(languages, language.name, "language:" + language.id) }
        action(languages, "Edit Language Definitions…", "settings-languages")
        let bookmarks = menu("Bookmarks")
        action(bookmarks, "Toggle Bookmark", "bookmark"); action(bookmarks, "Next Bookmark", "bookmark-next"); action(bookmarks, "Previous Bookmark", "bookmark-previous")
        action(bookmarks, "Clear Bookmarks", "bookmark-clear")
        action(bookmarks, "Invert Bookmarks", "bookmark-invert")
        for (label, id) in [("Copy Bookmarked Lines", "copy"), ("Cut Bookmarked Lines", "cut"), ("Delete Bookmarked Lines", "delete"), ("Delete Unmarked Lines", "delete-unmarked"), ("Paste to Bookmarked Lines", "paste")] { action(bookmarks, label, "marked:" + id) }
        let tools = menu("Tools")
        action(tools, "MD5 / SHA…", "digest")
        action(tools, "Text Statistics…", "statistics")
        let marks = submenu(tools, "Mark Selection")
        for name in ["Yellow", "Red", "Blue", "Green", "Purple", "Clear"] { action(marks, name, "mark:" + name) }
        let windows = menu("Window")
        standard(windows, "Minimize", "performMiniaturize:", "m"); standard(windows, "Zoom", "performZoom:")
        standard(windows, "Show Next Tab", "selectNextTab:"); standard(windows, "Show Previous Tab", "selectPreviousTab:")
        standard(windows, "Move Tab to New Window", "moveTabToNewWindow:")
        standard(windows, "Merge All Windows", "mergeAllWindows:"); standard(windows, "Bring All to Front", "arrangeInFront:")
        NSApp.windowsMenu = windows
        let help = menu("Help"); action(help, "Editor Help", "help"); NSApp.helpMenu = help
        NSApp.mainMenu = main
    }

    private func submenu(_ parent: NSMenu, _ title: String) -> NSMenu {
        let item = NSMenuItem(title: L10n.text(title), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L10n.text(title)); item.submenu = menu; parent.addItem(item); return menu
    }
    private func action(_ menu: NSMenu, _ title: String, _ id: String, key: String = "", localizeTitle: Bool = true) {
        let item = AppKitControlFactory.menuItem(title: title, selector: #selector(run(_:)), key: key, target: self, localizeTitle: localizeTitle)
        configureShortcut(item, id: id)
        item.representedObject = id; menu.addItem(item)
    }
    private func configureShortcut(_ item: NSMenuItem, id: String) {
        item.identifier = NSUserInterfaceItemIdentifier(id)
        if let binding = SettingsStore.shared.values.shortcuts[id] {
            item.keyEquivalent = binding.key
            item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: binding.modifiers)
        } else if item.keyEquivalent != item.keyEquivalent.lowercased() {
            item.keyEquivalent = item.keyEquivalent.lowercased()
            item.keyEquivalentModifierMask = [.command, .shift]
        }
    }
    @objc func settings(_ sender: Any?) { delegate?.showSettings() }
    static func prompt(_ title: String, value: String = "", detail: String = "") -> String? {
        let alert = NSAlert(); alert.messageText = L10n.text(title); alert.informativeText = L10n.text(detail)
        let field = NSTextField(string: value); field.frame = NSRect(x: 0, y: 0, width: 360, height: 26)
        alert.accessoryView = field; alert.addButton(withTitle: L10n.text("OK")); alert.addButton(withTitle: L10n.text("Cancel"))
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
    private func showText(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = L10n.text(title); alert.informativeText = L10n.text(message); alert.addButton(withTitle: L10n.text("OK")); alert.runModal()
    }
    @objc func run(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            let value = parts[1]
            switch parts[0] {
            case "text": if let command = TextCommand(rawValue: value) { editor?.run(command) }
            case "line": if let command = LineCommand(rawValue: value) { editor?.run(command) }
            case "encoding": if let encoding = TextEncoding(rawValue: value) { document?.changeEncoding(encoding) }
            case "reload":
                if let encoding = TextEncoding(rawValue: value) { do { try document?.reload(encoding: encoding) } catch { NSApp.presentError(error) } }
            case "eol": if let ending = LineEnding(rawValue: value) { document?.changeLineEnding(ending) }
            case "language":
                document?.metadata.languageID = value
                editor?.language = LanguageRegistry.shared.language(value)
                windowController?.updateStatus()
            case "theme": SettingsStore.shared.values.themeID = value
            case "marked": markedLines(value)
            case "mark": markSelection(value)
            case "recent": delegate?.documents.open(URL(fileURLWithPath: value))
            default: break
            }
            return
        }
        switch id {
        case "batch-rename": showTool("Batch Rename", content: NSHostingController(rootView: BatchRenamePanel()))
        case "navigate-back": editor?.navigate(backwards: true)
        case "navigate-forward": editor?.navigate(backwards: false)
        case "unblock-comment": editor?.removeBlockComment()
        case "statistics":
            if let editor {
                let stats = TextStatistics(text: editor.textView.string, ranges: editor.selectedOrAll())
                showText("Text Statistics", L10n.format("Characters: %ld\nWords: %ld\nLines: %ld\nWhitespace: %ld\nNon-whitespace: %ld\nUTF-16 units: %ld", stats.characters, stats.words, stats.lines, stats.whitespace, stats.nonWhitespace, stats.utf16Units))
            }
        case "find", "replace": windowController?.showSearch()
        case "hide-find": windowController?.toggleSearch(nil)
        case "next": windowController?.searchModel.next()
        case "previous": windowController?.searchModel.next(backwards: true)
        case "find-folder": windowController?.showSearch(); windowController?.searchModel.chooseFolder()
        case "batch-find":
            batchSearchWindow = BatchSearchWindowController(editor: editor); batchSearchWindow?.showWindow(nil)
        case "column-text":
            if let value = Self.prompt("Insert Column Text") { editor?.selectColumnToEnd(); editor?.replaceSelections(with: value, name: "Column Text") }
        case "bookmark-invert": if let editor { editor.bookmarks.invert(in: editor.source); editor.textView.needsDisplay = true }
        case "close-all": delegate?.documents.closeAllDocuments(withDelegate: nil, didCloseAllSelector: nil, contextInfo: nil)
        case "go-line": if let value = Self.prompt("Go to Line", value: "1"), let line = Int(value) { editor?.goTo(line: line) }
        case "sidebar": windowController?.toggleSidebar(nil)
        case "open-folder": windowController?.sidebarModel.chooseFolder()
        case "wrap": SettingsStore.shared.values.wrapLines.toggle()
        case "whitespace": SettingsStore.shared.values.showWhitespace.toggle()
        case "show-eol": SettingsStore.shared.values.showLineEndings.toggle()
        case "links": SettingsStore.shared.values.detectLinks.toggle()
        case "zoom-in": SettingsStore.shared.values.fontSize = min(72, SettingsStore.shared.values.fontSize + 1)
        case "zoom-out": SettingsStore.shared.values.fontSize = max(8, SettingsStore.shared.values.fontSize - 1)
        case "fold": editor?.folding.toggle(at: editor?.textView.selectedRange().location ?? 0)
        case "fold-all": editor?.folding.collapseAll()
        case "unfold-all": editor?.folding.expandAll()
        case "add-next": editor?.addNextOccurrence()
        case "select-occurrences": editor?.addNextOccurrence(all: true)
        case "json": editor?.transform(name: "Format JSON", StructuredTextFormatter.json)
        case "xml": editor?.transform(name: "Format XML", StructuredTextFormatter.xml)
        case "comment": editor?.commentLines()
        case "block-comment":
            if let editor, !editor.language.blockCommentStart.isEmpty {
                editor.transform(name: "Block Comment") { editor.language.blockCommentStart + $0 + editor.language.blockCommentEnd }
            }
        case "preview": windowController?.showPreview()
        case "print": if let document, let window = windowController?.window { DocumentPrinter.printDocument(document, window: window) }
        case "hex": if let url = document?.fileURL { delegate?.documents.openViewer(url, mode: .hex) }
        case "text":
            if let url = document?.fileURL {
                do {
                    let decoded = try DocumentIO.read(url)
                    let textDocument = TextDocument()
                    textDocument.initialText = decoded.text; textDocument.metadata = decoded.metadata
                    textDocument.restoredTitle = L10n.format("%@ — Text Copy", url.lastPathComponent)
                    delegate?.documents.addDocument(textDocument)
                    textDocument.makeWindowControllers(); textDocument.updateChangeCount(.changeDone); textDocument.showWindows()
                } catch { NSApp.presentError(error) }
            }
        case "bom": if let document { document.changeEncoding(document.metadata.encoding, bom: !document.metadata.hasBOM) }
        case "bookmark":
            if let editor {
                let line = editor.source.lineRange(for: editor.textView.selectedRange())
                editor.bookmarks.toggle(line.location); editor.scrollView.verticalRulerView?.needsDisplay = true; windowController?.updateStatus()
            }
        case "bookmark-next", "bookmark-previous":
            if let editor, let offset = editor.bookmarks.next(after: editor.textView.selectedRange().location, backwards: id == "bookmark-previous") { editor.setSelections([NSRange(location: offset, length: 0)], scroll: true) }
        case "bookmark-clear": editor?.bookmarks.clear(); editor?.scrollView.verticalRulerView?.needsDisplay = true; windowController?.updateStatus()
        case "column-select": columnSelection()
        case "column-mode": editor?.selections.columnMode.toggle()
        case "column-numbers": columnNumbers()
        case "blank-above", "blank-below":
            if let editor {
                let lines = editor.selectedLines()
                let position = id == "blank-above" ? lines.location : NSMaxRange(lines)
                do { try editor.apply([TextEdit(range: NSRange(location: position, length: 0), replacement: document?.metadata.lineEnding.text ?? "\n")], name: "Insert Line") }
                catch { NSApp.presentError(error) }
            }
        case "move-up", "move-down": moveLines(up: id == "move-up")
        case "digest":
            let text = editor.map { editor in editor.selectedOrAll().map { editor.source.substring(with: $0) }.joined(separator: "\n") } ?? ""
            showTool("Text and File Checksums", content: NSHostingController(rootView: ChecksumPanel(model: ChecksumModel(text: text))))
        case "batch-encoding": batchEncoding()
        case "settings-languages": delegate?.showSettings()
        case "help": showText("Inkline", "Command-F finds text; Command-D adds the next occurrence. Command-Option-click adds a caret. Use Column Selection for rectangular editing.\n\nRegex uses Apple's ICU syntax and $1 replacement groups. Large files and hexadecimal views are read-only. File recovery copies never automatically overwrite the original.\n\nmacOS 27 uses system text-selection gestures and navigation tabs. macOS 15 and 26 use fewer custom animations.")
        default: break
        }
    }
    private func columnSelection() {
        guard let editor, let value = Self.prompt("Column Selection", value: "1,1,1,1", detail: "First line, last line, first column, last column (1-based)") else { return }
        let values = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 4, values.allSatisfy({ $0 > 0 }) else { return }
        let lines = TextRanges.lines(editor.source)
        guard values[0] <= lines.count, values[1] <= lines.count else { return }
        editor.selections.rectangle(from: values[0] - 1, to: values[1] - 1, columns: min(values[2], values[3]) - 1...max(values[2], values[3]) - 1, text: editor.source, tabWidth: SettingsStore.shared.tabWidth)
        editor.setSelections(editor.selections.ranges, scroll: true)
    }
    private func showTool(_ title: String, content: NSViewController) {
        let window = NSWindow(contentViewController: content)
        window.title = L10n.text(title); window.center()
        let controller = NSWindowController(window: window)
        toolWindows[title]?.close(); toolWindows[title] = controller; controller.showWindow(nil)
    }
    private func columnNumbers() {
        guard let editor, let value = Self.prompt("Insert Column Numbers", value: "1,1,1,10,,upper", detail: "Start, increment, repeat count, radix (2/8/10/16), prefix, upper/lower. A single caret continues to the last line.") else { return }
        let parts = value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 4, let start = Int(parts[0]), let step = Int(parts[1]), let repeated = Int(parts[2]), let radix = Int(parts[3]) else { return }
        editor.selectColumnToEnd()
        let values = ColumnCommands.values(count: editor.selections.ranges.count, start: start, increment: step, repeatCount: repeated, radix: radix, prefix: parts.count > 4 ? parts[4] : "", uppercase: parts.count < 6 || parts[5].lowercased() != "lower")
        editor.replaceSelections(with: values, name: "Column Numbers")
    }
    private func markedLines(_ operation: String) {
        guard let editor else { return }
        let ranges = TextRanges.lines(editor.source).filter { range in
            let marked = editor.bookmarks.offsets.contains { NSLocationInRange($0, range) || $0 == range.location }
            return range.length > 0 && (operation == "delete-unmarked" ? !marked : marked)
        }
        if operation == "copy" || operation == "cut" {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ranges.map { editor.source.substring(with: $0) }.joined(), forType: .string)
        }
        if ["cut", "delete", "delete-unmarked", "paste"].contains(operation) {
            let value = operation == "paste" ? NSPasteboard.general.string(forType: .string) ?? "" : ""
            do { try editor.apply(ranges.map { TextEdit(range: $0, replacement: value) }, name: "Bookmarked Lines") }
            catch { NSApp.presentError(error) }
        }
    }
    private func markSelection(_ name: String) {
        guard let editor else { return }
        editor.mark(editor.selectedOrAll(), color: name)
    }
    private func moveLines(up: Bool) {
        guard let editor else { return }
        let range = editor.selectedLines()
        let lines = TextRanges.lines(editor.source)
        guard let index = lines.firstIndex(where: { $0.location == range.location }) else { return }
        let endIndex = lines.lastIndex(where: { $0.location < NSMaxRange(range) }) ?? index
        let otherIndex = up ? index - 1 : endIndex + 1
        guard otherIndex >= 0, otherIndex < lines.count, lines[otherIndex].length > 0 else { return }
        let other = lines[otherIndex]
        let block = editor.source.substring(with: range)
        let neighbor = editor.source.substring(with: other)
        let ending = document?.metadata.lineEnding ?? .lf
        let trim: (String) -> String = { value in
            if value.hasSuffix("\r\n") { return (value as NSString).substring(to: (value as NSString).length - 2) }
            if value.hasSuffix("\n") || value.hasSuffix("\r") { return String(value.dropLast()) }
            return value
        }
        let region = NSUnionRange(range, other)
        let selectedText = editor.source.substring(with: region)
        let trailing = selectedText.hasSuffix("\r\n") || selectedText.hasSuffix("\n") || selectedText.hasSuffix("\r")
        let newText = (up ? [trim(block), trim(neighbor)] : [trim(neighbor), trim(block)]).joined(separator: ending.text) + (trailing ? ending.text : "")
        do { try editor.apply([TextEdit(range: region, replacement: newText)], name: "Move Lines") }
        catch { NSApp.presentError(error) }
    }
    private func batchEncoding() {
        showTool("Batch Conversion", content: NSHostingController(rootView: BatchEncodingPanel()))
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let id = menuItem.representedObject as? String else { return true }
        if id == "help" || id == "settings-languages" || id.hasPrefix("theme:") || id.hasPrefix("recent:") { return true }
        if ["batch-rename", "batch-encoding", "digest"].contains(id) { return true }
        if id == "close-all" { return !NSDocumentController.shared.documents.isEmpty }
        if ["sidebar", "open-folder", "hex", "text"].contains(id) { return document != nil }
        if id == "wrap" && windowController?.viewer?.isHex == true { return false }
        if editor == nil && !(windowController?.viewer != nil && ["wrap", "whitespace", "show-eol", "zoom-in", "zoom-out", "find"].contains(id)) { return false }
        if id == "wrap" { menuItem.state = SettingsStore.shared.values.wrapLines ? .on : .off }
        if id == "whitespace" { menuItem.state = SettingsStore.shared.values.showWhitespace ? .on : .off }
        if id == "show-eol" { menuItem.state = SettingsStore.shared.values.showLineEndings ? .on : .off }
        if id == "column-mode" { menuItem.state = editor?.selections.columnMode == true ? .on : .off }
        if id == "links" { menuItem.state = SettingsStore.shared.values.detectLinks ? .on : .off }
        if id.hasPrefix("language:") { menuItem.state = id == "language:" + (document?.metadata.languageID ?? "") ? .on : .off }
        if id.hasPrefix("encoding:") { menuItem.state = id == "encoding:" + (document?.metadata.encoding.rawValue ?? "") ? .on : .off }
        return true
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.identifier?.rawValue == "recent" else { return }
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs { action(menu, url.lastPathComponent, "recent:" + url.path, localizeTitle: false) }
        menu.addItem(.separator())
        menu.addItem(AppKitControlFactory.menuItem(title: "Clear Recent Files", selector: NSSelectorFromString("clearRecentDocuments:")))
    }
}
