import Foundation

struct BatchSearchRule: Identifiable, Equatable, Sendable {
    var id = UUID()
    var find = ""
    var replace = ""
    var mode = SearchMode.literal
    var caseSensitive = false
    var wholeWord = false
    var enabled = true
    func query(from options: SearchQuery = SearchQuery()) -> SearchQuery {
        var query = options
        query.text = find; query.replacement = replace; query.regularExpression = mode == .regex; query.extended = mode == .extended
        query.caseSensitive = caseSensitive; query.wholeWord = wholeWord
        return query
    }
    static func edits(_ rules: [BatchSearchRule], text: String, ranges: [NSRange]) throws -> (edits: [TextEdit], occurrences: Int) {
        let active = rules.filter(\.enabled)
        guard !active.isEmpty, active.allSatisfy({ !$0.find.isEmpty }) else { throw EditorError.invalidDefinition("Find text must not be empty.") }
        for rule in active { _ = try rule.query().regex() }
        var count = 0
        let source = text as NSString
        let edits = try ranges.map { range -> TextEdit in
            guard TextRanges.valid(range, in: source) else { throw EditorError.invalidRange }
            var value = source.substring(with: range)
            for rule in active {
                try Task.checkCancellation()
                let changes = try SearchService.edits(rule.query(), in: value)
                count += changes.count
                value = try EditTransaction.applying(changes, to: value).text
            }
            return TextEdit(range: range, replacement: value)
        }.filter { source.substring(with: $0.range) != $0.replacement }
        return (edits, count)
    }

    /**
     * The original rule file stores ordered find/replace string lists in the General INI group.
     * Per-rule search options are kept in the table; that file format only carries the two text columns.
     */
    static func exportText(_ rules: [BatchSearchRule]) throws -> String {
        let values = rules.filter { !$0.find.isEmpty }
        guard !values.isEmpty else { throw EditorError.invalidDefinition("Find text must not be empty.") }
        func quoted(_ value: String) -> String {
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t").replacingOccurrences(of: "\0", with: "\\0")
            return "\"" + (escaped.hasPrefix("@") ? "@" : "") + escaped + "\""
        }
        return "[General]\nfind=" + values.map { quoted($0.find) }.joined(separator: ", ") + "\nreplace=" + values.map { quoted($0.replace) }.joined(separator: ", ") + "\n"
    }
    static func importText(_ text: String) throws -> [BatchSearchRule] {
        var entries: [String: [String]] = [:], group = "General"
        for line in text.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("[") && value.hasSuffix("]") { group = String(value.dropFirst().dropLast()); continue }
            guard group == "General", !value.hasPrefix(";"), !value.hasPrefix("#"), let equals = value.firstIndex(of: "=") else { continue }
            let key = String(value[..<equals]).trimmingCharacters(in: .whitespaces)
            guard key == "find" || key == "replace", entries[key] == nil else { continue }
            var result: [String] = [], current = "", quoted = false, escaped = false
            let raw = String(value[value.index(after: equals)...])
            for character in raw {
                if escaped {
                    switch character { case "n": current += "\n"; case "r": current += "\r"; case "t": current += "\t"; case "0": current += "\0"; default: current.append(character) }
                    escaped = false
                } else if character == "\\" { escaped = true }
                else if character == "\"" { quoted.toggle() }
                else if character == "," && !quoted { result.append(current); current = "" }
                else if quoted || !current.isEmpty || !character.isWhitespace { current.append(character) }
            }
            guard !quoted, !escaped else { throw EditorError.invalidDefinition("Malformed rule file.") }
            result.append(current)
            entries[key] = result.map { $0.hasPrefix("@@") ? String($0.dropFirst()) : $0 }
        }
        guard let finds = entries["find"], let replaces = entries["replace"], !finds.isEmpty, finds.count == replaces.count, finds.allSatisfy({ !$0.isEmpty }) else { throw EditorError.invalidDefinition("Find and replace lists must have matching rows.") }
        return zip(finds, replaces).map { BatchSearchRule(find: $0, replace: $1) }
    }
}
