import Foundation

struct LanguageDefinition: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var extensions: [String]
    var keywords: [String]
    var lineComment: String
    var blockCommentStart: String
    var blockCommentEnd: String
    var multilineStrings: [String]
    var caseSensitive: Bool
    var folding: String
    var rules: [SyntaxRule]
    var blocks: [LexicalBlock] = []
    var foldPairs: [KeywordFold] = []
    var embedded: [EmbeddedLanguage] = []

    static let plain = LanguageDefinition(id: "txt", name: "Plain Text", extensions: ["txt", "log"], keywords: [],
        lineComment: "", blockCommentStart: "", blockCommentEnd: "", multilineStrings: [], caseSensitive: true,
        folding: "none", rules: [])

    func validate() throws {
        guard !id.isEmpty, !name.isEmpty, !id.contains("/"), !id.contains("..") else { throw EditorError.invalidDefinition("A name and a simple identifier are required.") }
        guard blockCommentStart.isEmpty == blockCommentEnd.isEmpty else { throw EditorError.invalidDefinition("Both block comment delimiters are required.") }
        for rule in rules { _ = try NSRegularExpression(pattern: rule.pattern) }
        for block in blocks {
            _ = try NSRegularExpression(pattern: block.startPattern)
            guard !block.endTemplate.isEmpty else { throw EditorError.invalidDefinition("A string delimiter cannot be empty.") }
        }
        for pair in foldPairs { _ = try NSRegularExpression(pattern: pair.open); _ = try NSRegularExpression(pattern: pair.close) }
        for region in embedded { _ = try NSRegularExpression(pattern: region.start); _ = try NSRegularExpression(pattern: region.end) }
        guard !multilineStrings.contains("") else { throw EditorError.invalidDefinition("A string delimiter cannot be empty.") }
    }
}

struct SyntaxRule: Codable, Equatable, Sendable {
    var pattern: String
    var role: TokenRole
}

struct LexicalBlock: Codable, Equatable, Sendable {
    var startPattern: String
    var endTemplate: String
    var role: TokenRole
    var escaped: Bool = false
    var doubled: Bool = false
    var nested: Bool = false
    var endAtLineStart: Bool = false
}
struct KeywordFold: Codable, Equatable, Sendable { var open: String; var close: String }
struct EmbeddedLanguage: Codable, Equatable, Sendable { var start: String; var end: String; var language: String }
enum TokenRole: String, Codable, CaseIterable, Sendable { case keyword, string, comment, number, type, heading, added, removed }
struct SyntaxToken: Sendable { var range: NSRange; var role: TokenRole }
struct LexicalState: Equatable, Sendable {
    var delimiter = ""
    var role: TokenRole = .comment
    var escaped = false
    var doubled = false
    var opener = ""
    var nesting = 0
    var endAtLineStart = false
    var embeddedLanguage = ""
    var embeddedEnd = ""
}
struct HighlightLine: Sendable {
    var text: String
    var incoming: LexicalState
    var outgoing: LexicalState
    var tokens: [SyntaxToken]
}
