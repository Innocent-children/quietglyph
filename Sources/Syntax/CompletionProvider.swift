import Foundation

enum CompletionProvider {
    static func words(prefix: String, text: String, language: LanguageDefinition) -> [String] {
        guard !prefix.isEmpty else { return [] }
        var words = Set(language.keywords)
        if let regex = try? NSRegularExpression(pattern: "[\\p{L}_][\\p{L}\\p{N}_]{2,}") {
            let length = min((text as NSString).length, 500_000)
            for item in regex.matches(in: text, range: NSRange(location: 0, length: length)) {
                words.insert((text as NSString).substring(with: item.range))
            }
        }
        return words.filter { $0 != prefix && $0.lowercased().hasPrefix(prefix.lowercased()) }.sorted().prefix(100).map { $0 }
    }
}
