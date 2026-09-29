import SwiftUI

@MainActor
final class BatchRenameModel: ObservableObject {
    @Published var root: URL?
    @Published var options = BatchRenameOptions()
    @Published var items: [BatchRenameItem] = []
    @Published var busy = false
    @Published var message = ""
    private var previewOptions: BatchRenameOptions?
    private var previewRoot: URL?
    private var work: Task<Void, Never>?
    var canExecute: Bool { !busy && root == previewRoot && options == previewOptions && items.contains { $0.error == nil && $0.status == "Ready" } }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK { root = panel.url; items = [] }
    }
    func preview() {
        guard let root else { return }
        let options = options
        busy = true
        work = Task {
            defer { busy = false }
            do {
                let task = Task.detached { try BatchRenameService.preview(root: root, options: options) }
                items = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                previewRoot = root; previewOptions = options; message = L10n.format("Files: %ld", items.count)
            } catch { message = error.localizedDescription }
        }
    }
    func execute() {
        guard canExecute else { return }
        let alert = NSAlert(); alert.messageText = L10n.text("Rename the previewed files?")
        alert.informativeText = L10n.text("Each successful rename takes effect immediately. Conflicts and failures remain listed.")
        alert.addButton(withTitle: L10n.text("Rename")); alert.addButton(withTitle: L10n.text("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy = true
        work = Task {
            defer { busy = false }
            for i in items.indices where items[i].error == nil && items[i].status == "Ready" {
                if Task.isCancelled { for j in items.indices where items[j].status == "Ready" { items[j].status = "Not processed" }; break }
                do { try await BatchRenameService.execute(items[i], documents: SearchCoordinator.documents); items[i].status = "Renamed" }
                catch { items[i].error = error.localizedDescription; items[i].status = "Failed" }
                message = L10n.format("Processed: %ld / %ld", i + 1, items.count)
            }
        }
    }
    func cancel() { work?.cancel() }
    deinit { work?.cancel() }
}

struct BatchRenamePanel: View {
    @StateObject private var model = BatchRenameModel()
    var body: some View {
        VStack {
            HStack { Button(model.root?.path ?? L10n.text("Choose Folder…")) { model.chooseFolder() }; Spacer() }.disabled(model.busy)
            HStack { TextField(L10n.text("Prefix"), text: $model.options.prefix); TextField(L10n.text("Suffix"), text: $model.options.suffix); Picker(L10n.text("Case"), selection: $model.options.letterCase) { ForEach(BatchRenameOptions.LetterCase.allCases, id: \.self) { Text(L10n.text($0.rawValue)).tag($0) } } }.disabled(model.busy)
            HStack { Toggle(L10n.text("Change Extension"), isOn: $model.options.changeExtension); TextField(L10n.text("Extension"), text: $model.options.fileExtension).disabled(!model.options.changeExtension); TextField(L10n.text("File patterns"), text: $model.options.patterns); Toggle(L10n.text("Subfolders"), isOn: $model.options.recursive) }.disabled(model.busy)
            Table(model.items) {
                TableColumn(L10n.text("Original Path")) { Text($0.source.path).textSelection(.enabled) }
                TableColumn(L10n.text("New Path")) { Text($0.destination.path).textSelection(.enabled) }
                TableColumn(L10n.text("Status")) { Text($0.error ?? L10n.text($0.status)).foregroundStyle($0.error == nil ? Color.primary : .red) }
            }
            HStack { Button(L10n.text("Preview")) { model.preview() }.disabled(model.busy || model.root == nil); Button(L10n.text("Rename")) { model.execute() }.disabled(!model.canExecute); Button(L10n.text("Cancel")) { model.cancel() }.disabled(!model.busy); Text(model.message); Spacer(); if model.busy { ProgressView().controlSize(.small) } }
        }.padding().frame(minWidth: 850, minHeight: 500).onDisappear { model.cancel() }
    }
}
