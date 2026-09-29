import SwiftUI

struct LanguageDefinitionEditor: View {
    @ObservedObject var registry = LanguageRegistry.shared
    @State private var selected = "txt"
    @State private var json = ""
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker(L10n.text("Language"), selection: $selected) {
                    ForEach(registry.languages) { Text(L10n.text($0.name)).tag($0.id) }
                }.onChange(of: selected) { _, value in load(value) }
                Button(L10n.text("New")) {
                    var definition = LanguageDefinition.plain
                    definition.id = "custom"; definition.name = L10n.text("Custom"); definition.extensions = ["custom"]
                    show(definition)
                }
                Button(L10n.text("Save")) {
                    do {
                        let language = try JSONDecoder().decode(LanguageDefinition.self, from: Data(json.utf8))
                        try registry.save(language); selected = language.id; message = L10n.text("Saved")
                    } catch { message = error.localizedDescription }
                }
            }
            Text(L10n.text("Edit extensions, keywords, comment delimiters and regular-expression rules for syntax highlighting."))
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $json).font(.system(.body, design: .monospaced)).border(Color(nsColor: .separatorColor))
            Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(10).onAppear { load(selected) }
    }
    private func load(_ id: String) { show(registry.language(id)) }
    private func show(_ definition: LanguageDefinition) {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        json = (try? String(data: encoder.encode(definition), encoding: .utf8)) ?? ""
    }
}
