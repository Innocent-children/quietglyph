import Foundation

@MainActor
final class LanguageRegistry: ObservableObject {
    static let shared = LanguageRegistry()
    @Published private(set) var languages: [LanguageDefinition] = []
    let userDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.innocentchildren.inkline").appendingPathComponent("Languages", isDirectory: true)

    init() { reload() }
    func reload() {
        let bundled = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Languages") ?? []
        let custom = (try? FileManager.default.contentsOfDirectory(at: userDirectory, includingPropertiesForKeys: nil)) ?? []
        var definitions = [LanguageDefinition.plain.id: LanguageDefinition.plain]
        for url in bundled + custom {
            guard let data = try? Data(contentsOf: url), let language = try? JSONDecoder().decode(LanguageDefinition.self, from: data),
                  (try? language.validate()) != nil else { continue }
            definitions[language.id] = language
        }
        languages = definitions.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func language(_ id: String) -> LanguageDefinition { languages.first { $0.id == id } ?? .plain }
    func detect(_ url: URL?, prefix: String = "") -> LanguageDefinition {
        guard let url else { return .plain }
        let filename = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()
        if filename == "makefile" { return language("makefile") }
        if filename == "cmakelists.txt" { return language("cmake") }
        if let item = languages.first(where: { $0.extensions.contains(ext) || $0.extensions.contains(filename) }) { return item }
        if prefix.hasPrefix("#!") {
            for id in ["python", "ruby", "perl", "bash"] where prefix.prefix(100).contains(id == "bash" ? "sh" : id) { return language(id) }
        }
        return .plain
    }
    func save(_ definition: LanguageDefinition) throws {
        try definition.validate()
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(definition).write(to: userDirectory.appendingPathComponent(definition.id).appendingPathExtension("json"), options: .atomic)
        reload()
    }
}
