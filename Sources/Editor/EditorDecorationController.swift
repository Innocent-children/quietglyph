import AppKit

@MainActor
final class EditorDecorationController {
    weak var editor: EditorController?
    private var occurrences: [NSRange] = []
    private var pairs: [NSRange] = []
    private var parsed: [HighlightLine] = []
    func setParsed(_ lines: [HighlightLine]) { parsed = lines; refresh() }
    func refresh() {
        guard let editor else { return }
        occurrences = []; pairs = []
        let text = editor.source, selected = editor.textView.selectedRange(), settings = SettingsStore.shared.values
        if settings.highlightOccurrences {
            let word = selected.length > 0 ? selected : editor.textView.selectionRange(forProposedRange: selected, granularity: .selectByWord)
            if word.length > 0, word.length < 256, TextRanges.valid(word, in: text) {
                let value = text.substring(with: word)
                if value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" }) {
                    var query = SearchQuery(); query.text = value; query.wholeWord = true; query.caseSensitive = true
                    occurrences = (try? SearchService.matches(query, in: text as String).map(\.range)) ?? []
                }
            }
        }
        if settings.matchBrackets {
            let positions = [selected.location, selected.location - 1].filter { $0 >= 0 && $0 < text.length }
            let bracketPairs: [unichar: unichar] = [40: 41, 91: 93, 123: 125]
            let excluded: [NSRange] = zip(TextRanges.lines(text), parsed).flatMap { line, parsed in parsed.tokens.filter { $0.role == .string || $0.role == .comment }.map { NSRange(location: line.location + $0.range.location, length: $0.range.length) } }
            for position in positions {
                guard !excluded.contains(where: { NSLocationInRange(position, $0) }) else { continue }
                let symbol = text.character(at: position)
                let forward = bracketPairs[symbol] != nil
                guard let partner = bracketPairs[symbol] ?? bracketPairs.first(where: { $0.value == symbol })?.key else { continue }
                var level = 0, index = position
                while index >= 0 && index < text.length {
                    if !excluded.contains(where: { NSLocationInRange(index, $0) }) {
                        let c = text.character(at: index)
                        if c == symbol { level += 1 }
                        if c == partner { level -= 1; if level == 0 { pairs = [NSRange(location: position, length: 1), NSRange(location: index, length: 1)]; break } }
                    }
                    index += forward ? 1 : -1
                }
                if !pairs.isEmpty { break }
            }
            if pairs.isEmpty, editor.language.folding == "markup", let regex = try? NSRegularExpression(pattern: "<(/?)([A-Za-z_:][\\w:.-]*)(?:\"[^\"]*\"|'[^']*'|[^'\">])*>") {
                let tags = regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).filter { tag in !excluded.contains { NSLocationInRange(tag.range.location, $0) } }
                if let index = tags.firstIndex(where: { selected.location >= $0.range.location && selected.location <= NSMaxRange($0.range) }) {
                    let tag = tags[index], name = text.substring(with: tag.range(at: 2)).lowercased(), closing = tag.range(at: 1).length > 0
                    var depth = 0, i = index
                    while tags.indices.contains(i) {
                        let candidate = tags[i]
                        if text.substring(with: candidate.range(at: 2)).lowercased() == name, !text.substring(with: candidate.range).hasSuffix("/>") {
                            depth += (candidate.range(at: 1).length > 0) == closing ? 1 : -1
                            if depth == 0 { pairs = [tag.range, candidate.range]; break }
                        }
                        i += closing ? -1 : 1
                    }
                }
            }
        }
        editor.textView.needsDisplay = true
    }
    func draw(in view: EditorTextView, dirty: NSRect) {
        guard let editor else { return }
        let settings = SettingsStore.shared.values
        if settings.highlightCurrentLine, let rect = view.localRect(NSRange(location: view.selectedRange().location, length: 0)) {
            NSColor.controlAccentColor.withAlphaComponent(0.05).setFill()
            NSRect(x: view.textContainerOrigin.x, y: rect.minY, width: max(view.bounds.width, dirty.maxX) - view.textContainerOrigin.x, height: rect.height).fill()
        }
        let source = editor.source
        let start = min(source.length, view.characterIndexForInsertion(at: view.visibleRect.origin))
        let end = min(source.length, view.characterIndexForInsertion(at: NSPoint(x: view.visibleRect.maxX, y: view.visibleRect.maxY)) + 1)
        let visible = NSRange(location: start, length: max(0, end - start))
        func paint(_ range: NSRange, color: NSColor) {
            guard NSIntersectionRange(range, visible).length > 0, TextRanges.valid(range, in: source) else { return }
            var position = max(range.location, visible.location)
            color.setFill()
            while position < min(NSMaxRange(range), NSMaxRange(visible)) {
                let character = source.rangeOfComposedCharacterSequence(at: position)
                if let rect = view.localRect(character), rect.intersects(dirty) { rect.fill() }
                position = NSMaxRange(character)
            }
        }
        for range in occurrences { paint(range, color: NSColor.controlAccentColor.withAlphaComponent(0.12)) }
        let colors: [String: NSColor] = ["Yellow": .systemYellow, "Red": .systemRed, "Blue": .systemBlue, "Green": .systemGreen, "Purple": .systemPurple]
        for mark in editor.marks.marks { paint(mark.range, color: (colors[mark.color] ?? .systemYellow).withAlphaComponent(0.3)) }
        for range in pairs { paint(range, color: NSColor.systemGreen.withAlphaComponent(0.25)) }
        if settings.indentGuides {
            let width = SettingsStore.shared.tabWidth
            NSColor.separatorColor.setStroke()
            for line in editor.lineRanges where NSIntersectionRange(line, visible).length > 0 {
                let content = TextRanges.lineContent(line, in: source), value = source.substring(with: content)
                let indent = String(value.prefix(while: { $0 == " " || $0 == "\t" }))
                let columns = ColumnGeometry.column(at: indent.utf16.count, in: indent, tabWidth: width)
                guard columns >= width, let rect = view.localRect(NSRange(location: line.location, length: 0)) else { continue }
                let cell = (" " as NSString).size(withAttributes: [.font: view.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]).width
                for column in stride(from: width, through: columns, by: width) {
                    let x = rect.minX + CGFloat(column) * cell
                    let path = NSBezierPath(); path.move(to: NSPoint(x: x, y: rect.minY)); path.line(to: NSPoint(x: x, y: rect.maxY)); path.lineWidth = 0.5; path.stroke()
                }
            }
        }
    }
}
