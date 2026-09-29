import Foundation

enum TextCommand: String, CaseIterable {
    case uppercase = "UPPERCASE", lowercase = "lowercase", title = "Title Case", sentence = "Sentence case"
    case titleBlend = "Title Case (Preserve Capitals)", sentenceBlend = "Sentence Case (Preserve Capitals)"
    case invert = "Invert Case", random = "Random Case", tabsToSpaces = "Tabs to Spaces"
    case spacesToTabs = "Spaces to Tabs", leadingSpacesToTabs = "Leading Spaces to Tabs"
    case trimHead = "Remove Leading Whitespace", trimTail = "Remove Trailing Whitespace", trimBoth = "Trim Lines"
    case indent = "Indent", outdent = "Outdent"
    func apply(_ text: String, tabWidth: Int = 4) -> String {
        let width = max(1, tabWidth)
        switch self {
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .title, .titleBlend:
            let characters = Array(text)
            return characters.indices.map { i in
                let ch = characters[i]
                guard ch.isLetter else { return String(ch) }
                if i >= 2, characters[i - 1] == "'", characters[i - 2].isLetter { return String(ch).lowercased() }
                if i == 0 || (!characters[i - 1].isLetter && !characters[i - 1].isNumber) { return String(ch).uppercased() }
                return self == .title ? String(ch).lowercased() : String(ch)
            }.joined()
        case .sentence, .sentenceBlend:
            var start = true
            var newline = false
            let characters = Array(text)
            return characters.indices.map { i in
                let ch = characters[i]
                var value = String(ch)
                if ch.isLetter {
                    value = start ? value.uppercased() : self == .sentence ? value.lowercased() : value
                    start = false; newline = false
                    if value == "i", i > 0, i + 1 < characters.count,
                       characters[i - 1].isWhitespace || "(\"".contains(characters[i - 1]),
                       characters[i + 1].isWhitespace || characters[i + 1] == "'" { value = "I" }
                } else if ch.isNewline { if newline { start = true }; newline = true }
                else if ".!?。！？".contains(ch) {
                    start = i + 1 < characters.count && !characters[i + 1].isLetter && !characters[i + 1].isNumber
                }
                return value
            }.joined()
        case .invert: return text.map { $0.isUppercase ? String($0).lowercased() : String($0).uppercased() }.joined()
        case .random: return text.map { Bool.random() ? String($0).uppercased() : String($0).lowercased() }.joined()
        default:
            return LineCommands.mapLines(text) { line in
                switch self {
                case .trimHead: return String(line.drop(while: { $0 == " " || $0 == "\t" }))
                case .trimTail: return String(line.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
                case .trimBoth: return line.trimmingCharacters(in: .whitespaces)
                case .indent: return String(repeating: " ", count: width) + line
                case .outdent:
                    if line.hasPrefix("\t") { return String(line.dropFirst()) }
                    return String(line.dropFirst(min(width, line.prefix(while: { $0 == " " }).count)))
                case .tabsToSpaces:
                    var column = 0
                    return line.map { ch in
                        if ch == "\t" {
                            let count = width - column % width
                            column += count
                            return String(repeating: " ", count: count)
                        }
                        column += 1
                        return String(ch)
                    }.joined()
                case .leadingSpacesToTabs:
                    let count = line.prefix(while: { $0 == " " }).count
                    return String(repeating: "\t", count: count / width) + String(repeating: " ", count: count % width) + line.dropFirst(count)
                case .spacesToTabs: return line.replacingOccurrences(of: String(repeating: " ", count: width), with: "\t")
                default: return line
                }
            }
        }
    }
}
