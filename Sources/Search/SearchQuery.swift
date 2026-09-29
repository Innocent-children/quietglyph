import Foundation

enum SearchMode: String, CaseIterable, Codable, Sendable { case literal = "Literal", extended = "Extended", regex = "Regex (ICU)" }
enum SearchScope: String, CaseIterable, Sendable { case document = "This Document", selection = "Selection", openDocuments = "All Open Documents", directory = "Folder" }

struct SearchQuery: Sendable, Equatable {
    var text = ""
    var replacement = ""
    var regularExpression = false
    var caseSensitive = false
    var wholeWord = false
    var filePatterns = "*"
    var includeHidden = false
    var extended = false
    var recursive = true
    var excludePatterns = ""
    var skipBinary = true
    var maximumBytes: UInt64 = 100 * 1024 * 1024

    func regex() throws -> NSRegularExpression {
        var pattern = regularExpression ? text : NSRegularExpression.escapedPattern(for: extended ? SearchService.expand(text) : text)
        if wholeWord { pattern = "(?<![\\p{L}\\p{N}_])(?:" + pattern + ")(?![\\p{L}\\p{N}_])" }
        return try NSRegularExpression(pattern: pattern, options: caseSensitive ? [.anchorsMatchLines] : [.anchorsMatchLines, .caseInsensitive])
    }
    func includes(_ name: String) -> Bool {
        filePatterns.split(separator: ",").contains { pattern in
            NSPredicate(format: "SELF LIKE[c] %@", String(pattern).trimmingCharacters(in: .whitespaces)).evaluate(with: name)
        }
    }
    func excludes(_ path: String) -> Bool {
        excludePatterns.split(separator: ",").contains { pattern in
            let value = String(pattern).trimmingCharacters(in: .whitespaces)
            return NSPredicate(format: "SELF LIKE[c] %@", value).evaluate(with: path) || path.split(separator: "/").contains { NSPredicate(format: "SELF LIKE[c] %@", value).evaluate(with: String($0)) }
        }
    }
}
