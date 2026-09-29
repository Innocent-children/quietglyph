import SwiftUI

@MainActor
final class BatchEncodingModel: ObservableObject {
    @Published var root: URL?
    @Published var patterns = "*.txt"
    @Published var recursive = false
    @Published var encoding = TextEncoding.utf8
    @Published var bom = false
    @Published var items: [BatchEncodingItem] = []
    @Published var busy = false
    @Published var message = ""
    private var work: Task<Void, Never>?
    private var scanIdentity = ""
    private var identity: String { (root?.path ?? "") + "|" + patterns + "|" + String(recursive) }
    var canExecute: Bool { !busy && identity == scanIdentity && items.contains { $0.error == nil && $0.status == "Ready" } }
    func chooseFolder() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; if panel.runModal() == .OK { root = panel.url; items = [] } }
    func scan() {
        guard let root else { return }
        let patterns = patterns, recursive = recursive, identity = identity
        let open = Set(SearchCoordinator.documents.compactMap { $0.fileURL?.standardizedFileURL.resolvingSymlinksInPath() })
        busy = true
        work = Task {
            defer { busy = false }
            do {
                let task = Task.detached { try BatchEncodingService.scan(root: root, patterns: patterns, recursive: recursive, openURLs: open) }
                items = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                scanIdentity = identity; message = L10n.format("Files: %ld", items.count)
            } catch { message = error.localizedDescription }
        }
    }
    func execute() {
        guard canExecute else { return }
        let alert = NSAlert(); alert.messageText = L10n.text("Convert the scanned files?"); alert.informativeText = L10n.text("Files are saved immediately. Open or changed files will be skipped. Line endings are preserved.")
        alert.addButton(withTitle: L10n.text("Convert")); alert.addButton(withTitle: L10n.text("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let encoding = encoding, bom = bom
        busy = true
        work = Task {
            defer { busy = false }
            for i in items.indices where items[i].error == nil && items[i].status == "Ready" {
                if Task.isCancelled { for j in items.indices where items[j].status == "Ready" { items[j].status = "Not processed" }; break }
                let item = items[i]
                do {
                    let task = Task.detached { try BatchEncodingService.prepare(item, encoding: encoding, bom: bom) }
                    let data = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                    try Task.checkCancellation()
                    guard !SearchCoordinator.documents.contains(where: { $0.fileURL?.standardizedFileURL.resolvingSymlinksInPath() == item.url.standardizedFileURL.resolvingSymlinksInPath() }), let stamp = item.stamp else { throw EditorError.externalChange }
                    try DocumentIO.replace(item.url, data: data, expected: stamp); items[i].status = "Converted"
                } catch { items[i].error = error.localizedDescription; items[i].status = "Failed" }
                message = L10n.format("Processed: %ld / %ld", i + 1, items.count)
            }
        }
    }
    func cancel() { work?.cancel() }
    deinit { work?.cancel() }
}

struct BatchEncodingPanel: View {
    @StateObject private var model = BatchEncodingModel()
    var body: some View {
        VStack {
            HStack { Button(model.root?.path ?? L10n.text("Choose Folder…")) { model.chooseFolder() }; TextField(L10n.text("File patterns"), text: $model.patterns); Toggle(L10n.text("Subfolders"), isOn: $model.recursive) }.disabled(model.busy)
            HStack { Picker(L10n.text("Target Encoding"), selection: $model.encoding) { ForEach(TextEncoding.allCases) { Text($0.title).tag($0) } }; Toggle("BOM", isOn: $model.bom).disabled(model.encoding.bom.isEmpty) }.disabled(model.busy)
            Table(model.items) {
                TableColumn(L10n.text("File")) { Text($0.url.path).textSelection(.enabled) }
                TableColumn(L10n.text("Original Encoding")) { Text(($0.metadata?.encoding.title ?? "—") + ($0.metadata?.hasBOM == true ? " BOM" : "")) }
                TableColumn(L10n.text("Status")) { Text($0.error ?? L10n.text($0.status)).foregroundStyle($0.error == nil ? Color.primary : .red) }
            }
            HStack { Button(L10n.text("Scan")) { model.scan() }.disabled(model.busy || model.root == nil); Button(L10n.text("Convert")) { model.execute() }.disabled(!model.canExecute); Button(L10n.text("Cancel")) { model.cancel() }.disabled(!model.busy); Text(model.message); Spacer(); if model.busy { ProgressView().controlSize(.small) } }
        }.padding().frame(minWidth: 800, minHeight: 500).onDisappear { model.cancel() }
    }
}
