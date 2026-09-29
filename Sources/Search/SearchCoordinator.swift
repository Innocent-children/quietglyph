import AppKit

struct SearchDocumentSnapshot: Sendable {
    let id: UUID
    let title: String
    let url: URL?
    let text: String
    let revision: Int
    let ranges: [NSRange]
}

@MainActor
enum SearchCoordinator {
    static var documents: [TextDocument] { NSDocumentController.shared.documents.compactMap { $0 as? TextDocument } }
    static func activate(_ result: SearchResult, editor: EditorController?) throws {
        if let id = result.documentID {
            guard let document = (documents + [editor?.document].compactMap { $0 }).first(where: { $0.recoveryID == id }), document.revision == result.revision else { throw EditorError.externalChange }
            document.showWindows(); document.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
            document.editor?.setSelections([result.range], scroll: true)
        } else if let url = result.url {
            if let stamp = result.stamp, try DocumentIO.stamp(url) != stamp { throw EditorError.externalChange }
            (NSDocumentController.shared as? DocumentController)?.open(url) { document in
                if let stamp = result.stamp, (try? DocumentIO.stamp(url)) != stamp { NSApp.presentError(EditorError.externalChange); return }
                document.editor?.setSelections([result.range], scroll: true)
            }
        } else { editor?.setSelections([result.range], scroll: true) }
    }
    static func snapshots(scope: SearchScope, editor: EditorController?, root: URL?, query: SearchQuery) -> [SearchDocumentSnapshot] {
        var candidates = scope == .document || scope == .selection ? [editor?.document].compactMap { $0 } : documents
        if let document = editor?.document, !candidates.contains(where: { $0 === document }) { candidates.append(document) }
        var seen = Set<URL>()
        return candidates.compactMap { document in
            guard document.mode == .text else { return nil }
            let url = document.fileURL?.standardizedFileURL.resolvingSymlinksInPath()
            if let url, !seen.insert(url).inserted { return nil }
            if scope == .directory {
                guard let root = root?.standardizedFileURL.resolvingSymlinksInPath(), let url, url.path.hasPrefix(root.path + "/") else { return nil }
                let relative = String(url.path.dropFirst(root.path.count + 1))
                guard query.includes(url.lastPathComponent), !query.excludes(relative), query.recursive || !relative.contains("/"), query.includeHidden || !relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { return nil }
            }
            let text = document.editor?.textView.string ?? document.initialText
            if scope == .directory && (UInt64(text.utf8.count) > query.maximumBytes || query.skipBinary && text.contains("\0")) { return nil }
            return SearchDocumentSnapshot(id: document.recoveryID, title: document.displayName, url: url, text: text, revision: document.revision,
                ranges: scope == .selection ? editor?.selections.ranges ?? [] : [NSRange(location: 0, length: text.utf16.count)])
        }
    }

    nonisolated static func find(_ snapshots: [SearchDocumentSnapshot], root: URL?, query: SearchQuery, limit: Int = 20_000, excludedURLs: Set<URL> = []) async -> SearchReport {
        var report = SearchReport()
        for snapshot in snapshots {
            if Task.isCancelled { report.cancelled = true; return report }
            do {
                var results = try snapshot.ranges.flatMap { range -> [SearchResult] in
                    let matches = try SearchService.matches(query, in: snapshot.text, range: range)
                    return SearchService.results(matches, text: snapshot.text, url: snapshot.url).map { result in var item = result; item.searchRange = range; return item }
                }
                for index in results.indices {
                    results[index].documentID = snapshot.id; results[index].revision = snapshot.revision; results[index].documentTitle = snapshot.title
                }
                let capacity = max(0, limit - report.results.count)
                report.results += results.prefix(capacity); report.scanned += 1
                if results.count > capacity { report.truncated = true; return report }
            } catch is CancellationError { report.cancelled = true; return report }
            catch { report.failures.append(snapshot.title + ": " + error.localizedDescription) }
        }
        if let root, report.results.count < limit {
            let disk = await SearchService.directory(root, query: query, limit: limit - report.results.count, excluding: excludedURLs.union(snapshots.compactMap(\.url)))
            report.results += disk.results; report.scanned += disk.scanned; report.failures += disk.failures
            report.truncated = disk.truncated; report.cancelled = disk.cancelled
        } else if root != nil { report.truncated = true }
        return report
    }

    static func replace(_ results: [SearchResult], query: SearchQuery, editor: EditorController?) async -> ReplacementReport {
        var report = ReplacementReport()
        let groups = Dictionary(grouping: results, by: \.groupID)
        for key in groups.keys.sorted() {
            if Task.isCancelled { report.cancelled = true; break }
            guard let group = groups[key], let first = group.first else { continue }
            do {
                if let id = first.documentID {
                    guard let document = (documents + [editor?.document].compactMap { $0 }).first(where: { $0.recoveryID == id }),
                          document.revision == first.revision, let target = document.editor, !target.textView.isComposing else { throw EditorError.externalChange }
                    let allowed = Set(group.map { "\($0.range.location):\($0.range.length)" })
                    var searched = Set<String>()
                    let ranges = group.compactMap(\.searchRange).filter { searched.insert("\($0.location):\($0.length)").inserted }
                    let edits = try (ranges.isEmpty ? [NSRange(location: 0, length: target.source.length)] : ranges).flatMap { range in
                        try SearchService.edits(query, in: target.textView.string, range: range)
                    }.filter { allowed.contains("\($0.range.location):\($0.range.length)") }
                    try target.apply(edits, name: "Replace All")
                    if !edits.isEmpty { report.changed += 1; report.changedOpenDocuments += 1; report.occurrences += edits.count }
                } else if let url = first.url, let stamp = first.stamp {
                    let prepared = Task.detached {
                        try ReplacementOperation.prepare(url, expected: stamp) { text in
                            let edits = try SearchService.edits(query, in: text); return (edits, edits.count)
                        }
                    }
                    let change = try await withTaskCancellationHandler { try await prepared.value } onCancel: { prepared.cancel() }
                    try Task.checkCancellation()
                    guard !documents.contains(where: { $0.fileURL?.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath() }) else { throw EditorError.externalChange }
                    try ReplacementOperation.commit(change)
                    if change.changed { report.changed += 1; report.changedClosedFiles += 1; report.occurrences += change.occurrences }
                }
            } catch is CancellationError { report.cancelled = true; break }
            catch { report.failures.append(first.title + ": " + error.localizedDescription) }
        }
        return report
    }

    static func batch(_ rules: [BatchSearchRule], snapshots: [SearchDocumentSnapshot], root: URL?, options: SearchQuery, editor: EditorController?) async -> ReplacementReport {
        var report = ReplacementReport()
        var candidates = Set<URL>()
        let excluded = Set(documents.compactMap { $0.fileURL?.standardizedFileURL.resolvingSymlinksInPath() })
        for snapshot in snapshots {
            if Task.isCancelled { report.cancelled = true; return report }
            do {
                let task = Task.detached { try BatchSearchRule.edits(rules, text: snapshot.text, ranges: snapshot.ranges) }
                let prepared = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation()
                guard let document = (documents + [editor?.document].compactMap { $0 }).first(where: { $0.recoveryID == snapshot.id }), document.revision == snapshot.revision,
                      let target = document.editor, !target.textView.isComposing else { throw EditorError.externalChange }
                try target.apply(prepared.edits, name: "Batch Replace")
                if !prepared.edits.isEmpty { report.changed += 1; report.changedOpenDocuments += 1; report.occurrences += prepared.occurrences }
            } catch is CancellationError { report.cancelled = true; return report }
            catch { report.failures.append(snapshot.title + ": " + error.localizedDescription) }
        }
        guard let root else { return report }
        for rule in rules where rule.enabled {
            let query = rule.query(from: options)
            let task = Task.detached { await SearchService.directory(root, query: query, limit: Int.max, excluding: excluded) }
            let found = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            report.failures += found.failures
            if found.cancelled { report.cancelled = true; return report }
            candidates.formUnion(found.results.compactMap(\.url))
        }
        for url in candidates.sorted(by: { $0.path < $1.path }) {
            do {
                try Task.checkCancellation()
                let task = Task.detached {
                    try ReplacementOperation.prepare(url, expected: DocumentIO.stamp(url)) { text in
                        try BatchSearchRule.edits(rules, text: text, ranges: [NSRange(location: 0, length: text.utf16.count)])
                    }
                }
                let change = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
                try Task.checkCancellation()
                guard !documents.contains(where: { $0.fileURL?.standardizedFileURL.resolvingSymlinksInPath() == url.standardizedFileURL.resolvingSymlinksInPath() }) else { throw EditorError.externalChange }
                try ReplacementOperation.commit(change)
                if change.changed { report.changed += 1; report.changedClosedFiles += 1; report.occurrences += change.occurrences }
            } catch is CancellationError { report.cancelled = true; return report }
            catch { report.failures.append(url.path + ": " + error.localizedDescription) }
        }
        return report
    }
}
