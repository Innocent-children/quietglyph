import Foundation

enum SearchService {
    static func expand(_ value: String) -> String {
        let units = Array(value.utf16)
        var output: [UInt16] = [], index = 0
        let simple: [UInt16: UInt16] = [114: 13, 110: 10, 48: 0, 116: 9, 92: 92]
        let numeric: [UInt16: (Int, Int)] = [98: (8, 2), 111: (3, 8), 100: (3, 10), 120: (2, 16), 117: (4, 16)]
        while index < units.count {
            if units[index] == 92, index + 1 < units.count {
                let code = units[index + 1]
                if let escaped = simple[code] { output.append(escaped); index += 2; continue }
                if let (size, base) = numeric[code], index + 2 + size <= units.count {
                    let digits = String(decoding: units[(index + 2)..<(index + 2 + size)], as: UTF16.self)
                    if let number = UInt16(digits, radix: base) { output.append(number); index += 2 + size; continue }
                }
            }
            output.append(units[index]); index += 1
        }
        return String(decoding: output, as: UTF16.self)
    }
    static func matches(_ query: SearchQuery, in text: String, range: NSRange? = nil) throws -> [NSTextCheckingResult] {
        guard !query.text.isEmpty else { return [] }
        let source = text as NSString
        let selected = range ?? NSRange(location: 0, length: source.length)
        guard TextRanges.valid(selected, in: source) else { throw EditorError.invalidRange }
        var results: [NSTextCheckingResult] = []
        var cancelled = false
        try query.regex().enumerateMatches(in: text, options: .reportProgress, range: selected) { result, _, stop in
            if Task.isCancelled { cancelled = true; stop.pointee = true }
            else if let result { results.append(result) }
        }
        if cancelled { throw CancellationError() }
        return results
    }
    static func edits(_ query: SearchQuery, in text: String, range: NSRange? = nil) throws -> [TextEdit] {
        let regex = try query.regex()
        return try matches(query, in: text, range: range).map {
            TextEdit(range: $0.range, replacement: query.regularExpression ?
                     regex.replacementString(for: $0, in: text, offset: 0, template: query.replacement) : query.extended ? expand(query.replacement) : query.replacement)
        }
    }
    static func results(_ matches: [NSTextCheckingResult], text: String, url: URL? = nil, stamp: FileStamp? = nil) -> [SearchResult] {
        let source = text as NSString
        let lines = TextRanges.lines(source)
        return matches.map { match in
            var low = 0, high = lines.count
            while low < high {
                let mid = (low + high) / 2
                if lines[mid].location <= match.range.location { low = mid + 1 } else { high = mid }
            }
            let index = max(0, low - 1)
            let lineRange = TextRanges.lineContent(lines[index], in: source)
            let display = NSRange(location: lineRange.location, length: min(300, lineRange.length))
            return SearchResult(url: url, range: match.range, line: index + 1,
                                column: match.range.location - lineRange.location + 1,
                                preview: source.substring(with: TextRanges.composed(display, in: source)), stamp: stamp,
                                matchedText: source.substring(with: match.range))
        }
    }

    static func directory(_ root: URL, query: SearchQuery, limit: Int = 20_000, excluding openURLs: Set<URL> = []) async -> SearchReport {
        var report = SearchReport()
        do { _ = try query.regex() } catch { report.failures = [error.localizedDescription]; return report }
        let options: FileManager.DirectoryEnumerationOptions = query.includeHidden ? [.skipsPackageDescendants] : [.skipsPackageDescendants, .skipsHiddenFiles]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey], options: options, errorHandler: { url, error in
            report.failures.append(url.path + ": " + error.localizedDescription); return true
        }) else { return report }
        var seen = Set<URL>()
        while let url = walker.nextObject() as? URL {
            if Task.isCancelled { report.cancelled = true; break }
            do {
                let flags = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
                let path = String(url.path.dropFirst(root.path.count + 1))
                if query.excludes(path) || !query.recursive && flags.isDirectory == true { walker.skipDescendants(); continue }
                guard flags.isRegularFile == true, flags.isSymbolicLink != true, query.includes(url.lastPathComponent) else { continue }
                let identity = url.standardizedFileURL.resolvingSymlinksInPath()
                guard seen.insert(identity).inserted, !openURLs.contains(identity) else { continue }
                let stamp = try DocumentIO.stamp(url)
                guard stamp.size <= query.maximumBytes else {
                    report.failures.append(L10n.format("%@: exceeds the search size limit", url.path))
                    continue
                }
                let decoded = try DocumentIO.read(url)
                guard !query.skipBinary || !decoded.text.contains("\0") else { continue }
                let found = try matches(query, in: decoded.text)
                guard try DocumentIO.stamp(url) == stamp else { throw EditorError.externalChange }
                report.scanned += 1
                let remaining = max(0, limit - report.results.count)
                report.results += results(Array(found.prefix(remaining)), text: decoded.text, url: url, stamp: stamp)
                if found.count > remaining || report.results.count >= limit { report.truncated = true; break }
            } catch { report.failures.append("\(url.path): \(error.localizedDescription)") }
        }
        return report
    }
}
