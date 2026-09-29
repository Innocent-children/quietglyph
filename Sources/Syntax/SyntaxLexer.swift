import Foundation

enum SyntaxLexer {
    struct Context {
        let keywords: Set<String>
        let rules: [(NSRegularExpression, TokenRole)]
        let blocks: [(NSRegularExpression, LexicalBlock)]
        let languages: [String: LanguageDefinition]
        init(_ language: LanguageDefinition, languages: [String: LanguageDefinition] = [:]) {
            self.languages = languages
            let options: NSRegularExpression.Options = language.caseSensitive ? [.anchorsMatchLines] : [.anchorsMatchLines, .caseInsensitive]
            var definitions = language.blocks
            if !language.blockCommentStart.isEmpty {
                definitions.append(LexicalBlock(startPattern: NSRegularExpression.escapedPattern(for: language.blockCommentStart), endTemplate: language.blockCommentEnd, role: .comment, nested: language.id == "rust"))
            }
            definitions += language.multilineStrings.map { LexicalBlock(startPattern: NSRegularExpression.escapedPattern(for: $0), endTemplate: $0, role: .string, escaped: $0 != "'" && $0 != String(UnicodeScalar(96))) }
            blocks = definitions.compactMap { block in (try? NSRegularExpression(pattern: block.startPattern, options: options)).map { ($0, block) } }
            keywords = Set(language.keywords.map { language.caseSensitive ? $0 : $0.lowercased() })
            rules = language.rules.compactMap { rule in
                guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: language.caseSensitive ? [] : .caseInsensitive) else { return nil }
                return (regex, rule.role)
            }
        }
    }
    private static func scan(_ line: String, language: LanguageDefinition, incoming: LexicalState, context: Context? = nil) -> HighlightLine {
        if language.id == "txt", language.keywords.isEmpty, language.rules.isEmpty {
            return HighlightLine(text: line, incoming: incoming, outgoing: LexicalState(), tokens: [])
        }
        let text = line as NSString
        var state = incoming
        var tokens: [SyntaxToken] = []
        let prepared = context ?? Context(language)
        let keywords = prepared.keywords
        var position = 0
        func starts(_ value: String, at offset: Int) -> Bool {
            !value.isEmpty && offset + (value as NSString).length <= text.length &&
            text.compare(value, options: language.caseSensitive ? [] : .caseInsensitive, range: NSRange(location: offset, length: (value as NSString).length)) == .orderedSame
        }
        func add(_ start: Int, _ end: Int, _ role: TokenRole) { if end > start { tokens.append(SyntaxToken(range: NSRange(location: start, length: end - start), role: role)) } }
        func consumeBlock(from start: Int) {
            while position < text.length {
                if position % 4096 == 0 && Task.isCancelled { break }
                if state.escaped && text.character(at: position) == 92 { position = min(text.length, position + 2); continue }
                if !state.opener.isEmpty && starts(state.opener, at: position) {
                    state.nesting += 1; position += state.opener.utf16.count; continue
                }
                if starts(state.delimiter, at: position), !state.endAtLineStart || text.substring(to: position).trimmingCharacters(in: .whitespaces).isEmpty {
                    var length = state.delimiter.utf16.count
                    if state.endAtLineStart && state.role == .string {
                        if let unit = state.delimiter.utf16.first, [96, 126].contains(unit), state.delimiter.utf16.allSatisfy({ $0 == unit }) {
                            while position + length < text.length && text.character(at: position + length) == unit { length += 1 }
                        }
                        if !text.substring(from: position + length).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { position += 1; continue }
                    }
                    if state.doubled && starts(state.delimiter, at: position + length) { position += 2 * length; continue }
                    position += length
                    if state.nesting > 1 { state.nesting -= 1; continue }
                    add(start, position, state.role); state = LexicalState(); return
                }
                position += 1
            }
            add(start, text.length, state.role)
        }
        while position < text.length {
            if position % 4096 == 0 && Task.isCancelled { break }
            let start = position
            if !state.delimiter.isEmpty { consumeBlock(from: start); continue }
            if let (match, block) = prepared.blocks.compactMap({ regex, block -> (NSTextCheckingResult, LexicalBlock)? in
                regex.firstMatch(in: line, options: .anchored, range: NSRange(location: position, length: text.length - position)).map { ($0, block) }
            }).first {
                guard match.range.length > 0 else { position += 1; continue }
                var delimiter = block.endTemplate
                if match.numberOfRanges > 1 {
                    for i in (1..<match.numberOfRanges).reversed() {
                        let range = match.range(at: i)
                        delimiter = delimiter.replacingOccurrences(of: "$\(i)", with: range.location == NSNotFound ? "" : text.substring(with: range))
                    }
                }
                guard !delimiter.isEmpty else { position += match.range.length; continue }
                state = LexicalState(delimiter: delimiter, role: block.role, escaped: block.escaped, doubled: block.doubled,
                    opener: block.nested ? text.substring(with: match.range) : "", nesting: 1, endAtLineStart: block.endAtLineStart)
                position = NSMaxRange(match.range); consumeBlock(from: start); continue
            }
            if starts(language.lineComment, at: position) {
                let after = position + language.lineComment.utf16.count
                let boundary = position == 0 || [9, 32].contains(text.character(at: position - 1))
                if language.lineComment.first?.isLetter != true || boundary && (after == text.length || [9, 10, 13, 32].contains(text.character(at: after))) {
                    add(position, text.length, .comment); position = text.length; continue
                }
            }
            let ch = text.character(at: position)
            if ch == 34 || ch == 39 || ch == 96 {
                position += 1
                while position < text.length {
                    let current = text.character(at: position)
                    if current == 92 { position = min(text.length, position + 2); continue }
                    position += 1
                    if current == ch { break }
                }
                add(start, position, .string); continue
            }
            if (48...57).contains(ch) {
                position += 1
                while position < text.length {
                    let c = text.character(at: position)
                    if (48...57).contains(c) || (65...70).contains(c) || (97...102).contains(c) || [46, 95, 120, 88].contains(c) { position += 1 } else { break }
                }
                add(start, position, .number); continue
            }
            if (65...90).contains(ch) || (97...122).contains(ch) || ch == 95 || ch > 127 {
                position += 1
                while position < text.length {
                    let c = text.character(at: position)
                    if (65...90).contains(c) || (97...122).contains(c) || (48...57).contains(c) || c == 95 || c > 127 { position += 1 } else { break }
                }
                let word = text.substring(with: NSRange(location: start, length: position - start))
                if keywords.contains(language.caseSensitive ? word : word.lowercased()) { add(start, position, .keyword) }
                continue
            }
            position += 1
        }
        let protected = tokens.filter { $0.role == .comment || $0.role == .string }
        for (regex, role) in prepared.rules {
            tokens += regex.matches(in: line, range: NSRange(location: 0, length: text.length)).filter { match in
                !protected.contains { NSIntersectionRange($0.range, match.range).length > 0 }
            }.map { SyntaxToken(range: $0.range, role: role) }
        }
        return HighlightLine(text: line, incoming: incoming, outgoing: state, tokens: tokens)
    }

    static func line(_ line: String, language: LanguageDefinition, incoming: LexicalState, context: Context? = nil) -> HighlightLine {
        let prepared = context ?? Context(language)
        guard !language.embedded.isEmpty || !incoming.embeddedLanguage.isEmpty else { return scan(line, language: language, incoming: incoming, context: prepared) }
        let text = line as NSString
        var state = incoming, tokens: [SyntaxToken] = [], offset = 0
        while offset < text.length {
            let remaining = NSRange(location: offset, length: text.length - offset)
            if !state.embeddedLanguage.isEmpty {
                let match = (try? NSRegularExpression(pattern: state.embeddedEnd, options: .caseInsensitive))?.firstMatch(in: line, range: remaining)
                let end = match?.range.location ?? text.length
                var innerState = state; innerState.embeddedLanguage = ""; innerState.embeddedEnd = ""
                let inner = prepared.languages[state.embeddedLanguage] ?? .plain
                let parsed = scan(text.substring(with: NSRange(location: offset, length: end - offset)), language: inner, incoming: innerState, context: Context(inner, languages: prepared.languages))
                tokens += parsed.tokens.map { SyntaxToken(range: NSRange(location: offset + $0.range.location, length: $0.range.length), role: $0.role) }
                let embeddedID = state.embeddedLanguage, embeddedEnd = state.embeddedEnd
                state = parsed.outgoing; state.embeddedLanguage = embeddedID; state.embeddedEnd = embeddedEnd
                if let match { tokens.append(SyntaxToken(range: match.range, role: .keyword)); state = LexicalState(); offset = NSMaxRange(match.range) }
                else { offset = text.length }
            } else {
                let parsed = scan(text.substring(from: offset), language: language, incoming: state, context: prepared)
                let candidate = language.embedded.compactMap { region -> (NSTextCheckingResult, EmbeddedLanguage)? in
                    (try? NSRegularExpression(pattern: region.start, options: .caseInsensitive))?.firstMatch(in: line, range: remaining).map { ($0, region) }
                }.sorted { $0.0.range.location < $1.0.range.location }.first { match, _ in
                    !parsed.tokens.contains { $0.role == .comment && NSLocationInRange(match.range.location - offset, $0.range) }
                }
                guard let (match, region) = candidate else {
                    tokens += parsed.tokens.map { SyntaxToken(range: NSRange(location: offset + $0.range.location, length: $0.range.length), role: $0.role) }
                    state = parsed.outgoing; offset = text.length; continue
                }
                let prefix = scan(text.substring(with: NSRange(location: offset, length: match.range.location - offset)), language: language, incoming: state, context: prepared)
                tokens += prefix.tokens.map { SyntaxToken(range: NSRange(location: offset + $0.range.location, length: $0.range.length), role: $0.role) }
                tokens.append(SyntaxToken(range: match.range, role: .keyword))
                state = LexicalState(); state.embeddedLanguage = region.language; state.embeddedEnd = region.end
                offset = NSMaxRange(match.range)
            }
        }
        return HighlightLine(text: line, incoming: incoming, outgoing: state, tokens: tokens)
    }
    static func parse(_ string: String, language: LanguageDefinition, languages: [String: LanguageDefinition] = [:]) -> [HighlightLine] {
        let text = string as NSString, context = Context(language, languages: languages)
        var state = LexicalState()
        return TextRanges.lines(text).map { range in
            let result = line(text.substring(with: range), language: language, incoming: state, context: context)
            state = result.outgoing; return result
        }
    }
}
