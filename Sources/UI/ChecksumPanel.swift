import SwiftUI

@MainActor
final class ChecksumModel: ObservableObject {
    @Published var text: String
    @Published var file: URL?
    @Published var output = ""
    @Published var progress = ""
    @Published var busy = false
    private var work: Task<Void, Never>?
    init(text: String) { self.text = text }
    func chooseFile() { let panel = NSOpenPanel(); if panel.runModal() == .OK { file = panel.url } }
    func calculate() {
        guard !busy else { return }; busy = true; output = ""
        let file = file, data = Data(text.utf8)
        work = Task {
            defer { busy = false }
            do {
                let task = Task.detached { [weak self] () async throws -> String in
                    if let file { return try await ChecksumService.file(file) { done, total in await MainActor.run { self?.progress = L10n.format("%llu / %llu bytes", done, total) } } }
                    try Task.checkCancellation(); return ChecksumService.digest(data)
                }
                output = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            } catch { output = error.localizedDescription }
        }
    }
    func cancel() { work?.cancel() }
    deinit { work?.cancel() }
}

struct ChecksumPanel: View {
    @ObservedObject var model: ChecksumModel
    var body: some View {
        VStack {
            HStack { Button(L10n.text("Choose File…")) { model.chooseFile() }; Text(model.file?.path ?? L10n.text("Text as UTF-8")); if model.file != nil { Button(L10n.text("Use Text")) { model.file = nil } }; Spacer() }.disabled(model.busy)
            if model.file == nil { TextEditor(text: $model.text).font(.system(.body, design: .monospaced)).frame(height: 140).disabled(model.busy) }
            ScrollView { Text(model.output).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack { Button(L10n.text("Calculate")) { model.calculate() }.disabled(model.busy); Button(L10n.text("Copy")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.output, forType: .string) }; if model.busy { Button(L10n.text("Cancel")) { model.cancel() }; ProgressView().controlSize(.small) }; Text(model.progress); Spacer() }
        }.padding().frame(minWidth: 760, minHeight: 440).onDisappear { model.cancel() }
    }
}
