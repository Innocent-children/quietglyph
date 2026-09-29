import SwiftUI

@MainActor
final class BatchSearchModel: ObservableObject {
    @Published var rules = [BatchSearchRule(), BatchSearchRule()]
    @Published var scope = SearchScope.document
    @Published var folder: URL?
    @Published var patterns = "*"
    @Published var exclusions = ""
    @Published var recursive = true
    @Published var busy = false
    @Published var message = ""
    @Published var report = SearchReport()
    weak var editor: EditorController?
    private var work: Task<Void, Never>?
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK { folder = panel.url; scope = .directory }
    }
    func load() {
        let panel = NSOpenPanel()
        if panel.runModal() == .OK, let url = panel.url {
            do { rules = try BatchSearchRule.importText(String(contentsOf: url, encoding: .utf8)) } catch { message = error.localizedDescription }
        }
    }
    func save() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "rules.ini"
        if panel.runModal() == .OK, let url = panel.url {
            do { try BatchSearchRule.exportText(rules).write(to: url, atomically: true, encoding: .utf8) } catch { message = error.localizedDescription }
        }
    }
    func run(replacing: Bool) {
        let active = rules.filter(\.enabled)
        guard !active.isEmpty, active.allSatisfy({ !$0.find.isEmpty }) else { message = L10n.text("Find text must not be empty."); return }
        do { for rule in active { _ = try rule.query().regex() } } catch { message = error.localizedDescription; return }
        if scope == .directory && folder == nil { chooseFolder(); if folder == nil { return } }
        if replacing && scope == .directory {
            let alert = NSAlert(); alert.messageText = L10n.text("Batch Replace")
            alert.informativeText = L10n.text("Open documents will be changed with Undo and remain unsaved. Closed files will be saved immediately. Changed files will be skipped and reported.")
            alert.addButton(withTitle: L10n.text("Replace")); alert.addButton(withTitle: L10n.text("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        var options = SearchQuery(); options.filePatterns = patterns; options.excludePatterns = exclusions; options.recursive = recursive
        let snapshots = SearchCoordinator.snapshots(scope: scope, editor: editor, root: folder, query: options)
        let root = scope == .directory ? folder : nil
        let excluded = Set(SearchCoordinator.documents.compactMap { $0.fileURL?.standardizedFileURL.resolvingSymlinksInPath() })
        busy = true; report = SearchReport()
        work = Task {
            if replacing {
                let result = await SearchCoordinator.batch(active, snapshots: snapshots, root: root, options: options, editor: editor)
                report.failures = result.failures
                message = L10n.format("Replacements: %ld · Open documents: %ld · Saved files: %ld", result.occurrences, result.changedOpenDocuments, result.changedClosedFiles)
            } else {
                for rule in active {
                    let request = rule.query(from: options)
                    let task = Task.detached { await SearchCoordinator.find(snapshots, root: root, query: request, excludedURLs: excluded) }
                    let found = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
                    report.results += found.results; report.failures += found.failures; report.truncated = report.truncated || found.truncated
                    if Task.isCancelled { break }
                }
                message = L10n.format("Matches: %ld", report.results.count) + (report.truncated ? L10n.text(" · result limit reached; narrow the search") : "")
            }
            if Task.isCancelled { message += L10n.text(" · cancelled") }
            busy = false
        }
    }
    func cancel() { work?.cancel() }
    deinit { work?.cancel() }
}

struct BatchSearchPanel: View {
    @ObservedObject var model: BatchSearchModel
    var body: some View {
        VStack {
            HStack {
                Button(L10n.text("Add Rule")) { model.rules.append(BatchSearchRule()) }
                Button(L10n.text("Import…")) { model.load() }
                Button(L10n.text("Export…")) { model.save() }
                Button(L10n.text("Swap Find and Replace")) { for index in model.rules.indices { let value = model.rules[index].find; model.rules[index].find = model.rules[index].replace; model.rules[index].replace = value } }
                Spacer()
            }.disabled(model.busy)
            ScrollView {
                VStack {
                    ForEach($model.rules) { $rule in
                        HStack {
                            Toggle("", isOn: $rule.enabled).accessibilityLabel(L10n.text("Enable Rule"))
                            TextField(L10n.text("Find"), text: $rule.find)
                            TextField(L10n.text("Replace with"), text: $rule.replace)
                            Picker(L10n.text("Mode"), selection: $rule.mode) { ForEach(SearchMode.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }.frame(width: 170)
                            Toggle(L10n.text("Case"), isOn: $rule.caseSensitive)
                            Toggle(L10n.text("Whole word"), isOn: $rule.wholeWord)
                            Button("↑") { if let i = model.rules.firstIndex(where: { $0.id == rule.id }), i > 0 { model.rules.swapAt(i, i - 1) } }.accessibilityLabel(L10n.text("Move Rule Up"))
                            Button("↓") { if let i = model.rules.firstIndex(where: { $0.id == rule.id }), i + 1 < model.rules.count { model.rules.swapAt(i, i + 1) } }.accessibilityLabel(L10n.text("Move Rule Down"))
                            Button("−") { model.rules.removeAll { $0.id == rule.id } }.accessibilityLabel(L10n.text("Remove Rule"))
                        }.toggleStyle(.checkbox)
                    }
                }
            }.frame(minHeight: 110).disabled(model.busy)
            HStack {
                Picker(L10n.text("Scope"), selection: $model.scope) { ForEach(SearchScope.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }.frame(width: 270)
                if model.scope == .directory {
                    Button(model.folder?.lastPathComponent ?? L10n.text("Choose Folder…")) { model.chooseFolder() }
                    TextField(L10n.text("File patterns"), text: $model.patterns)
                    TextField(L10n.text("Exclude patterns"), text: $model.exclusions)
                    Toggle(L10n.text("Subfolders"), isOn: $model.recursive)
                }
                Button(L10n.text("Find All")) { model.run(replacing: false) }.disabled(model.busy)
                Button(L10n.text("Batch Replace")) { model.run(replacing: true) }.disabled(model.busy)
                if model.busy { Button(L10n.text("Cancel")) { model.cancel() } }
            }
            Text(model.message).textSelection(.enabled)
            SearchResultsView(report: model.report) { result in
                do { try SearchCoordinator.activate(result, editor: model.editor) } catch { model.message = error.localizedDescription }
            }
        }.padding().frame(minWidth: 1000, minHeight: 550).onDisappear { model.cancel() }
    }
}

@MainActor
final class BatchSearchWindowController: NSWindowController {
    init(editor: EditorController?) {
        let model = BatchSearchModel(); model.editor = editor
        let window = NSWindow(contentViewController: NSHostingController(rootView: BatchSearchPanel(model: model)))
        window.title = L10n.text("Batch Find and Replace"); window.setContentSize(NSSize(width: 1050, height: 620))
        super.init(window: window); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
