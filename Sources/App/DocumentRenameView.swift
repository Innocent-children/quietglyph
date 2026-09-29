import SwiftUI

struct DocumentRenameView: View {
    let document: NativeTextDocument
    let dismiss: () -> Void
    @State private var name: String
    @State private var errorMessage: String?
    @State private var isRenaming = false
    @FocusState private var nameIsFocused: Bool

    init(document: NativeTextDocument, dismiss: @escaping () -> Void) {
        self.document = document
        self.dismiss = dismiss
        _name = State(initialValue: document.fileURL?.lastPathComponent ?? document.displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("Name:"))
                TextField("", text: $name)
                    .accessibilityLabel(L10n.text("Name:"))
                    .accessibilityIdentifier("documentName")
                    .focused($nameIsFocused)
                    .onSubmit(rename)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(L10n.text("Cancel"), action: dismiss).keyboardShortcut(.cancelAction)
                Button(L10n.text("Rename"), action: rename)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("confirmDocumentRename")
            }
        }
        .padding(20)
        .frame(width: 360)
        .disabled(isRenaming)
        .onAppear { nameIsFocused = true }
    }

    private func rename() {
        guard !isRenaming else { return }
        isRenaming = true
        document.rename(to: name) { error in
            isRenaming = false
            if let error { errorMessage = error.localizedDescription }
            else { dismiss() }
        }
    }
}
