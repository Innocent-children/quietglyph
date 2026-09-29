import AppKit

@MainActor
final class IncrementalHighlighter {
    private typealias Output = ([HighlightLine], [(NSRange, [SyntaxToken])])
    private var work: Task<Void, Never>?
    private var parsing: Task<Output, Never>?
    private var revision = 0
    private var cache: [HighlightLine] = []
    private var cachedLanguage = ""
    private var cachedText = ""
    var language: LanguageDefinition = .plain
    weak var textView: NSTextView?
    var onParsed: (([HighlightLine]) -> Void)?

    func schedule() {
        revision += 1
        let version = revision
        work?.cancel()
        parsing?.cancel()
        work = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self, let view = self.textView, let storage = view.textStorage else { return }
            let snapshot = storage.string
            let definition = self.language
            var languages = Dictionary(uniqueKeysWithValues: LanguageRegistry.shared.languages.map { ($0.id, $0) })
            if var php = languages["php"] { php.id = "php-code"; php.embedded = []; languages["php-code"] = php }
            let previous = self.cachedLanguage == definition.id ? self.cache : []
            self.parsing = Task.detached(priority: .utility) {
                let text = snapshot as NSString
                let context = SyntaxLexer.Context(definition, languages: languages)
                let ranges = TextRanges.lines(text)
                var state = LexicalState()
                var next: [HighlightLine] = []
                var changes: [(NSRange, [SyntaxToken])] = []
                for (index, range) in ranges.enumerated() {
                    if Task.isCancelled { break }
                    let content = text.substring(with: range)
                    if index < previous.count, previous[index].text == content, previous[index].incoming == state {
                        next.append(previous[index])
                    } else {
                        let parsed = SyntaxLexer.line(content, language: definition, incoming: state, context: context)
                        next.append(parsed); changes.append((range, parsed.tokens))
                    }
                    state = next.last!.outgoing
                }
                return (next, changes)
            }
            guard let output = await self.parsing?.value else { return }
            guard !Task.isCancelled, version == self.revision, storage.string == snapshot else { return }
            self.cache = output.0
            self.cachedLanguage = definition.id
            self.cachedText = snapshot
            self.applyStyles(output.1, storage: storage, language: definition.id)
            self.onParsed?(output.0)
        }
    }
    func parseNow() {
        guard let view = textView, let storage = view.textStorage else { return }
        if cachedText == view.string && cachedLanguage == language.id && !cache.isEmpty { onParsed?(cache); return }
        revision += 1; work?.cancel(); parsing?.cancel()
        var languages = Dictionary(uniqueKeysWithValues: LanguageRegistry.shared.languages.map { ($0.id, $0) })
        if var php = languages["php"] { php.id = "php-code"; php.embedded = []; languages["php-code"] = php }
        cache = SyntaxLexer.parse(view.string, language: language, languages: languages)
        cachedText = view.string; cachedLanguage = language.id
        let changes = zip(TextRanges.lines(view.string as NSString), cache).map { ($0.0, $0.1.tokens) }
        applyStyles(changes, storage: storage, language: language.id)
        onParsed?(cache)
    }
    private func applyStyles(_ changes: [(NSRange, [SyntaxToken])], storage: NSTextStorage, language: String) {
        let settings = SettingsStore.shared
        let base = settings.syntaxAttributes(language: language, role: nil)
        let styles = Dictionary(uniqueKeysWithValues: TokenRole.allCases.map { ($0, settings.syntaxAttributes(language: language, role: $0)) })
        storage.beginEditing()
        for (range, tokens) in changes where NSMaxRange(range) <= storage.length {
            for key in [NSAttributedString.Key.backgroundColor, .underlineStyle] { storage.removeAttribute(key, range: range) }
            storage.addAttributes(base, range: range)
            for token in tokens {
                if let style = styles[token.role] { storage.addAttributes(style, range: NSRange(location: range.location + token.range.location, length: token.range.length)) }
            }
        }
        storage.endEditing()
    }
    func reset() { cache = []; cachedLanguage = ""; cachedText = ""; schedule() }
    deinit { work?.cancel(); parsing?.cancel() }
}
