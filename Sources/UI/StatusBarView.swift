import SwiftUI

@MainActor
final class EditorStatus: ObservableObject {
    @Published var position = L10n.format("Ln %ld, Col %ld", 1, 1)
    @Published var selection = ""
    @Published var encoding = "UTF-8"
    @Published var lineEnding = "LF"
    @Published var language = L10n.text("Plain Text")
    @Published var size = ""
}

struct StatusBarView: View {
    @ObservedObject var status: EditorStatus
    var body: some View {
        HStack(spacing: 16) {
            Text(status.position)
            Text(status.selection).foregroundStyle(.secondary)
            Spacer()
            Text(status.size).foregroundStyle(.secondary)
            Text(status.encoding)
            Text(status.lineEnding)
            Text(status.language)
        }.font(.system(size: 11, design: .monospaced)).padding(.horizontal, 12)
            .frame(height: 26).background(.bar).accessibilityElement(children: .combine)
    }
}
