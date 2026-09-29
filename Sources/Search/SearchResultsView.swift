import SwiftUI

struct SearchResultsView: View {
    let report: SearchReport
    var onSelect: ((SearchResult) -> Void)?
    @State private var collapsed = Set<String>()
    @State private var wrap = false
    private struct Group: Identifiable { let id: String; let results: [SearchResult] }
    private var groups: [Group] {
        Dictionary(grouping: report.results, by: \.groupID).map { Group(id: $0.key, results: $0.value) }
            .sorted { ($0.results.first?.title ?? "") < ($1.results.first?.title ?? "") }
    }
    private func copy(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(L10n.text("Expand All")) { collapsed = [] }
                Button(L10n.text("Collapse All")) { collapsed = Set(report.results.map(\.groupID)) }
                Button(L10n.text("Copy Matches")) { copy(report.results.map(\.matchedText).joined(separator: "\n")) }
                Button(L10n.text("Copy Result Lines")) { copy(report.results.map { "\($0.title):\($0.line):\($0.column) \($0.preview)" }.joined(separator: "\n")) }
                Toggle(L10n.text("Wrap lines"), isOn: $wrap).toggleStyle(.checkbox)
                Spacer()
            }.font(.caption)
            List {
                ForEach(groups) { group in
                    DisclosureGroup(isExpanded: Binding(get: { !collapsed.contains(group.id) }, set: { if $0 { collapsed.remove(group.id) } else { collapsed.insert(group.id) } })) {
                        ForEach(group.results) { result in
                            Button { onSelect?(result) } label: {
                                HStack(alignment: .top) {
                                    Text("\(result.line):\(result.column)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                                    Text(result.preview).lineLimit(wrap ? nil : 1).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.buttonStyle(.plain)
                        }
                    } label: { Text("\(group.results[0].title) (\(group.results.count))").help(group.results[0].url?.path ?? group.results[0].title) }
                }
                ForEach(Array(report.failures.enumerated()), id: \.offset) { _, failure in
                    Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }.listStyle(.inset).frame(minHeight: 70)
        }
    }
}
