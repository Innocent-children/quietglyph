import AppKit

struct FoldRegion: Equatable, Sendable {
    var header: NSRange
    var hidden: NSRange
}

@MainActor
final class FoldingController: NSObject, @preconcurrency NSTextContentStorageDelegate {
    weak var textView: NSTextView?
    private(set) var collapsed: [NSRange] = []
    private(set) var regions: [FoldRegion] = []
    var beforeFolding: (() -> Void)?

    func rebuild(language: LanguageDefinition, parsed: [HighlightLine]? = nil) {
        guard let view = textView else { return }
        let oldRegions = regions
        let oldCollapsed = collapsed
        regions = Self.regions(in: view.string, language: language, parsed: parsed)
        collapsed = collapsed.filter { old in regions.contains { $0.hidden == old } && !NSLocationInRange(view.selectedRange().location, old) }
        if regions != oldRegions || collapsed != oldCollapsed { invalidate() }
    }
    nonisolated static func regions(in string: String, language: LanguageDefinition, parsed: [HighlightLine]? = nil) -> [FoldRegion] {
        let text = string as NSString
        let lines = TextRanges.lines(text)
        let parsed = parsed ?? NativeLexer.parse(string, language: language)
        let maskedLines = parsed.map { line -> String in
            let result = NSMutableString(string: line.text)
            for token in line.tokens where token.role == .comment || token.role == .string {
                result.replaceCharacters(in: token.range, with: String(repeating: " ", count: token.range.length))
            }
            return result as String
        }
        let masked = maskedLines.joined()
        var result: [FoldRegion] = []
        if language.folding == "indent" {
            for (i, line) in lines.enumerated() where i + 1 < lines.count {
                let current = maskedLines[i].trimmingCharacters(in: .newlines)
                if current.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                let indent = current.prefix(while: { $0 == " " || $0 == "\t" }).count
                var end = i + 1
                while end < lines.count {
                    let next = maskedLines[end].trimmingCharacters(in: .newlines)
                    if !next.trimmingCharacters(in: .whitespaces).isEmpty && next.prefix(while: { $0 == " " || $0 == "\t" }).count <= indent { break }
                    end += 1
                }
                if end > i + 1 {
                    result.append(FoldRegion(header: line, hidden: NSRange(location: NSMaxRange(line), length: lines[end - 1].location + lines[end - 1].length - NSMaxRange(line))))
                }
            }
        } else if language.folding == "markup" {
            let pattern = "<(/?)([A-Za-z_:][\\w:.-]*)(?:\"[^\"]*\"|'[^']*'|[^'\">])*>"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                var stack: [(String, NSRange)] = []
                let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]
                for tag in regex.matches(in: masked, range: NSRange(location: 0, length: text.length)) {
                    let name = text.substring(with: tag.range(at: 2)).lowercased()
                    let whole = text.substring(with: tag.range)
                    let line = text.lineRange(for: NSRange(location: tag.range.location, length: 0))
                    if tag.range(at: 1).length > 0 {
                        if let index = stack.lastIndex(where: { $0.0 == name }) {
                            let header = stack[index].1
                            stack.removeSubrange(index...)
                            if line.location > NSMaxRange(header) { result.append(FoldRegion(header: header, hidden: NSRange(location: NSMaxRange(header), length: line.location - NSMaxRange(header)))) }
                        }
                    } else if !whole.hasSuffix("/>"), !voidTags.contains(name) { stack.append((name, line)) }
                }
            }
        } else if language.folding != "none" {
            var stack: [(Int, NSRange)] = []
            for (lineIndex, line) in lines.enumerated() {
                let local = maskedLines[lineIndex] as NSString
                for i in 0..<local.length {
                    let ch = local.character(at: i)
                    if ch == 123 || ch == 91 || ch == 40 { stack.append((Int(ch), line)) }
                    if ch == 125 || ch == 93 || ch == 41 {
                        let opener = ch == 125 ? 123 : ch == 93 ? 91 : 40
                        guard let top = stack.last, top.0 == opener else { continue }
                        stack.removeLast()
                        let start = NSMaxRange(top.1)
                        if line.location > start { result.append(FoldRegion(header: top.1, hidden: NSRange(location: start, length: line.location - start))) }
                    }
                }
            }
        }
        for pair in language.foldPairs {
            let options: NSRegularExpression.Options = language.caseSensitive ? [.anchorsMatchLines] : [.anchorsMatchLines, .caseInsensitive]
            guard let open = try? NSRegularExpression(pattern: pair.open, options: options), let close = try? NSRegularExpression(pattern: pair.close, options: options) else { continue }
            var stack: [NSRange] = []
            for (index, line) in lines.enumerated() {
                let content = maskedLines[index]
                let range = NSRange(location: 0, length: content.utf16.count)
                let events = (open.matches(in: content, range: range).map { ($0.range.location, true) } + close.matches(in: content, range: range).map { ($0.range.location, false) }).sorted { $0.0 < $1.0 }
                for (_, opening) in events {
                    if opening { stack.append(line) }
                    else if let header = stack.popLast(), line.location > NSMaxRange(header) {
                        result.append(FoldRegion(header: header, hidden: NSRange(location: NSMaxRange(header), length: line.location - NSMaxRange(header))))
                    }
                }
            }
        }
        var blockStart: NSRange?
        for (index, line) in parsed.enumerated() {
            if line.incoming.delimiter.isEmpty && !line.outgoing.delimiter.isEmpty { blockStart = lines[index] }
            if !line.incoming.delimiter.isEmpty && line.outgoing.delimiter.isEmpty, let header = blockStart {
                if lines[index].location > NSMaxRange(header) { result.append(FoldRegion(header: header, hidden: NSRange(location: NSMaxRange(header), length: lines[index].location - NSMaxRange(header)))) }
                blockStart = nil
            }
        }
        var seen = Set<String>()
        result = result.filter { seen.insert("\($0.hidden.location):\($0.hidden.length)").inserted }
        return result.sorted { $0.header.location < $1.header.location }
    }

    func toggle(at offset: Int) {
        beforeFolding?()
        if let region = regions.first(where: { NSLocationInRange(offset, $0.header) || offset == $0.header.location }) ??
            regions.last(where: { NSLocationInRange(offset, $0.hidden) }) {
            if let index = collapsed.firstIndex(of: region.hidden) { collapsed.remove(at: index) }
            else { collapsed.append(region.hidden); textView?.setSelectedRange(NSRange(location: region.header.location, length: 0)) }
            invalidate()
        }
    }
    func collapseAll() { beforeFolding?(); collapsed = regions.map(\.hidden); invalidate() }
    func expandAll() { collapsed.removeAll(); invalidate() }
    func reveal(_ range: NSRange) {
        let old = collapsed
        collapsed.removeAll { NSIntersectionRange($0, range).length > 0 || NSLocationInRange(range.location, $0) }
        if collapsed != old { invalidate() }
    }
    func apply(_ edits: [TextEdit]) {
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            collapsed = collapsed.map { range in
                let start = EditTransaction.transformed(range.location, by: edit)
                let end = EditTransaction.transformed(NSMaxRange(range), by: edit)
                return NSRange(location: start, length: max(0, end - start))
            }
        }
    }
    func textContentManager(_ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement, options: NSTextContentManager.EnumerationOptions = []) -> Bool {
        guard let range = textElement.elementRange else { return true }
        let start = textContentManager.offset(from: textContentManager.documentRange.location, to: range.location)
        return !collapsed.contains { NSLocationInRange(start, $0) }
    }
    private func invalidate() {
        if let manager = textView?.textLayoutManager, let content = manager.textContentManager {
            manager.invalidateLayout(for: content.documentRange)
            manager.textViewportLayoutController.layoutViewport()
        }
        textView?.needsDisplay = true
        textView?.enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }
}
