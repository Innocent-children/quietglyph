import SwiftUI

@MainActor
final class SearchPanelModel: ObservableObject {
    @Published var pattern = ""
    @Published var replacement = ""
    @Published var mode = SearchMode.literal
    @Published var scope = SearchScope.document { didSet { selectionBounds = []; lastNavigationSelection = nil } }
    @Published var caseSensitive = false
    @Published var wholeWord = false
    @Published var wrap = L10n.defaults.object(forKey: "searchWrap") as? Bool ?? true {
        didSet { L10n.defaults.set(wrap, forKey: "searchWrap") }
    }
    @Published var patterns = "*"
    @Published var exclusions = ""
    @Published var recursive = true
    @Published var includeHidden = false
    @Published var skipBinary = true
    @Published var maximumMB = 100
    @Published var folder: URL?
    @Published var report = SearchReport()
    @Published var message = ""
    @Published var busy = false
    @Published var isVisible = false
    weak var editor: EditorController?
    var onOpenResult: ((SearchResult) -> Void)?
    private var work: Task<Void, Never>?
    private var worker: Task<SearchReport, Never>?
    private var lastQuery: SearchQuery?
    private var lastFolder: URL?
    private var lastScope: SearchScope?
    private var generation = 0
    private var pendingNavigation: Bool?
    private var selectionBounds: [NSRange] = []
    private var selectionRevision: Int?
    private var lastNavigationSelection: NSRange?
    private func matchesSavedSearch(_ request: SearchQuery) -> Bool {
        var previous = lastQuery; previous?.replacement = request.replacement
        return previous == request && lastScope == scope && (scope != .directory || lastFolder == folder) && !report.truncated && !report.cancelled
    }
    var query: SearchQuery {
        SearchQuery(text: pattern, replacement: replacement, regularExpression: mode == .regex, caseSensitive: caseSensitive,
                    wholeWord: wholeWord, filePatterns: patterns, includeHidden: includeHidden, extended: mode == .extended,
                    recursive: recursive, excludePatterns: exclusions, skipBinary: skipBinary, maximumBytes: UInt64(max(1, maximumMB)) * 1024 * 1024)
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK { folder = panel.url; scope = .directory }
    }
    func find() {
        cancel()
        let request = query
        guard !request.text.isEmpty else { report = SearchReport(); return }
        if scope == .directory && folder == nil { chooseFolder(); if folder == nil { return } }
        do { _ = try request.regex() } catch { message = error.localizedDescription; return }
        SearchHistoryStore.shared.remember(request)
        lastQuery = request; lastFolder = folder; lastScope = scope
        let snapshots = SearchCoordinator.snapshots(scope: scope, editor: editor, root: folder, query: request)
        let excluded = Set(SearchCoordinator.documents.compactMap { $0.fileURL?.standardizedFileURL.resolvingSymlinksInPath() })
        let root = scope == .directory ? folder : nil
        busy = true; message = L10n.text("Searching…")
        let version = generation
        let operation = Task.detached(priority: .userInitiated) { await SearchCoordinator.find(snapshots, root: root, query: request, excludedURLs: excluded) }
        worker = operation
        work = Task { [weak self] in
            let result = await operation.value
            guard let self, !Task.isCancelled, self.generation == version else { return }
            self.report = result; self.busy = false
            self.message = L10n.format("Matches: %ld · Files: %ld", result.results.count, result.scanned) + (result.truncated ? L10n.text(" · result limit reached; narrow the search") : "") + (result.cancelled ? L10n.text(" · cancelled") : "")
            if let backwards = self.pendingNavigation { self.pendingNavigation = nil; self.navigateResults(backwards: backwards) }
        }
    }
    func next(backwards: Bool = false) {
        if scope == .openDocuments || scope == .directory {
            if matchesSavedSearch(query) { navigateResults(backwards: backwards) }
            else { find(); pendingNavigation = backwards }
            return
        }
        guard let editor else { return }
        do {
            SearchHistoryStore.shared.remember(query)
            let current = editor.textView.selectedRange()
            let capture = scope == .selection && (selectionBounds.isEmpty || selectionRevision != editor.document?.revision || lastNavigationSelection != current)
            if capture { selectionBounds = editor.selections.ranges; selectionRevision = editor.document?.revision }
            let ranges = scope == .selection ? selectionBounds : [NSRange(location: 0, length: editor.source.length)]
            let matches = try ranges.flatMap { try SearchService.matches(query, in: editor.textView.string, range: $0) }
            let match = capture ? (backwards ? matches.last : matches.first) : backwards ? matches.last(where: { $0.range.location < current.location }) ?? (wrap ? matches.last : nil) :
                matches.first(where: { $0.range.location >= NSMaxRange(current) && $0.range != current }) ?? (wrap ? matches.first : nil)
            if let match { editor.setSelections([match.range], scroll: true); lastNavigationSelection = match.range }
            message = match == nil ? L10n.text("No further matches.") : L10n.format("Matches: %ld", matches.count)
        } catch { message = error.localizedDescription }
    }
    private func navigateResults(backwards: Bool) {
        let currentDocument = NSDocumentController.shared.currentDocument as? TextDocument ?? editor?.document
        let current = currentDocument?.editor?.textView.selectedRange() ?? NSRange(location: 0, length: 0)
        let id = currentDocument?.recoveryID
        let results = report.results
        let matching = results.indices.filter { results[$0].documentID == id }
        var index: Int?
        if backwards {
            index = matching.last(where: { results[$0].range.location < current.location })
            if index == nil, let first = matching.first, first > 0 { index = first - 1 }
            if index == nil && (wrap || matching.isEmpty) { index = results.indices.last }
        } else {
            index = matching.first(where: { results[$0].range.location >= NSMaxRange(current) && results[$0].range != current })
            if index == nil, let last = matching.last, last + 1 < results.count { index = last + 1 }
            if index == nil && (wrap || matching.isEmpty) { index = results.indices.first }
        }
        guard let index else { message = L10n.text("No further matches."); return }
        do { try SearchCoordinator.activate(results[index], editor: editor) } catch { message = error.localizedDescription }
    }
    func replaceOne() {
        guard let editor else { return }
        do {
            let selected = editor.textView.selectedRange()
            if let edit = try SearchService.edits(query, in: editor.textView.string).first(where: { $0.range == selected }) {
                try editor.apply([edit], name: "Replace")
                selectionBounds = selectionBounds.map { range in
                    let start = range.location == edit.range.location ? range.location : EditTransaction.transformed(range.location, by: edit)
                    return NSRange(location: start, length: max(0, EditTransaction.transformed(NSMaxRange(range), by: edit) - start))
                }
                selectionRevision = editor.document?.revision; lastNavigationSelection = editor.textView.selectedRange()
            }
            next()
        } catch { message = error.localizedDescription }
    }
    func replaceAll() {
        guard !busy else { return }
        let request = query
        let useResults = matchesSavedSearch(request)
        if scope == .directory {
            guard useResults else { message = L10n.text("Run a complete search with these options before replacing."); return }
            guard !report.results.isEmpty else { return }
            let alert = NSAlert(); alert.messageText = L10n.text("Replace All")
            alert.informativeText = L10n.text("Open documents will be changed with Undo and remain unsaved. Closed files will be saved immediately. Changed files will be skipped and reported.")
            alert.addButton(withTitle: L10n.text("Replace")); alert.addButton(withTitle: L10n.text("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let snapshots = useResults ? [] : SearchCoordinator.snapshots(scope: scope, editor: editor, root: folder, query: request)
        let found = report.results
        busy = true
        SearchHistoryStore.shared.remember(request)
        work = Task { [weak self] in
            guard let self else { return }
            var results = found
            if !useResults {
                let operation = Task.detached { await SearchCoordinator.find(snapshots, root: nil, query: request) }
                let search = await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
                if search.cancelled || search.truncated || !search.failures.isEmpty {
                    self.report = search; self.busy = false; self.message = L10n.text("Run a complete search with these options before replacing."); return
                }
                results = search.results
            }
            let result = await SearchCoordinator.replace(results, query: request, editor: self.editor)
            self.busy = false; self.report.failures = result.failures; self.lastQuery = nil
            self.message = L10n.format("Replacements: %ld · Open documents: %ld · Saved files: %ld", result.occurrences, result.changedOpenDocuments, result.changedClosedFiles) + (result.cancelled ? L10n.text(" · cancelled") : "")
        }
    }
    func markAll(bookmark: Bool = false) {
        guard let editor else { return }
        do {
            let ranges = try SearchService.matches(query, in: editor.textView.string, range: scope == .selection ? editor.textView.selectedRange() : nil).map(\.range)
            editor.mark(ranges, color: "Yellow")
            if bookmark { editor.bookmarks.add(ranges.map { editor.source.lineRange(for: NSRange(location: $0.location, length: 0)).location }) }
            message = L10n.format("Matches: %ld", ranges.count)
        } catch { message = error.localizedDescription }
    }
    func cancel() { generation += 1; work?.cancel(); worker?.cancel(); pendingNavigation = nil; busy = false }
    deinit { work?.cancel(); worker?.cancel() }
}

struct SearchPanel: View {
    @ObservedObject var model: SearchPanelModel
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField(L10n.text("Find"), text: $model.pattern).focused($searchFocused).onSubmit { model.next() }.accessibilityIdentifier("findField")
                Menu(L10n.text("History")) { ForEach(SearchHistoryStore.shared.searches, id: \.self) { value in Button(value) { model.pattern = value } } }
                Button(L10n.text("Previous")) { model.next(backwards: true) }
                Button(L10n.text("Next")) { model.next() }
                Button(L10n.text("Find All")) { model.find() }.disabled(model.busy)
                if model.busy { Button(L10n.text("Cancel")) { model.cancel() } }
            }
            HStack {
                TextField(L10n.text("Replace with"), text: $model.replacement).accessibilityIdentifier("replaceField")
                Button(L10n.text("Replace")) { model.replaceOne() }.disabled(model.scope == .directory || model.busy)
                Button(L10n.text("Replace All")) { model.replaceAll() }.disabled(model.busy)
            }
            HStack {
                Toggle(L10n.text("Case"), isOn: $model.caseSensitive)
                Toggle(L10n.text("Whole word"), isOn: $model.wholeWord)
                Picker(L10n.text("Mode"), selection: $model.mode) { ForEach(SearchMode.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Picker(L10n.text("Scope"), selection: $model.scope) { ForEach(SearchScope.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } }
                Toggle(L10n.text("Wrap Search"), isOn: $model.wrap)
                Spacer()
                Button(model.folder?.lastPathComponent ?? L10n.text("Choose Folder…")) { model.chooseFolder() }
                if model.scope == .directory {
                    TextField("*.swift,*.txt", text: $model.patterns).frame(width: 115)
                    Button(L10n.text("This Document")) { model.scope = .document }
                }
            }.toggleStyle(.checkbox).font(.callout)
            HStack {
                Text(model.message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            HStack {
                Button(L10n.text("Mark All")) { model.markAll() }
                Button(L10n.text("Mark and Bookmark")) { model.markAll(bookmark: true) }
                Button(L10n.text("Clear Results")) { model.report = SearchReport() }
                Menu(L10n.text("Replacement History")) { ForEach(SearchHistoryStore.shared.replacements, id: \.self) { value in Button(value.isEmpty ? L10n.text("Empty") : value) { model.replacement = value } } }
                Spacer()
            }
            if model.scope == .directory {
                HStack {
                    TextField(L10n.text("Exclude patterns"), text: $model.exclusions).frame(width: 160)
                    Toggle(L10n.text("Subfolders"), isOn: $model.recursive)
                    Toggle(L10n.text("Hidden files"), isOn: $model.includeHidden)
                    Toggle(L10n.text("Skip binary"), isOn: $model.skipBinary)
                    TextField("MB", value: $model.maximumMB, format: .number).frame(width: 55).accessibilityLabel(L10n.text("Maximum file size (MB)"))
                    Text("MB")
                }.toggleStyle(.checkbox).font(.caption)
            }
            SearchResultsView(report: model.report, onSelect: model.onOpenResult)
        }
        .padding(12)
        .onAppear { searchFocused = model.isVisible }
        .onChange(of: model.isVisible) { _, visible in searchFocused = visible }
        .background(.background)
    }
}
