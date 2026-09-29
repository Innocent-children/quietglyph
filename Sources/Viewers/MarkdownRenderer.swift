import AppKit

@MainActor
enum MarkdownRenderer {
    static func render(_ source: String, baseURL: URL? = nil) throws -> NSAttributedString {
        let markdown = try AttributedString(markdown: source, options: .init(interpretedSyntax: .full), baseURL: baseURL)
        let output = NSMutableAttributedString()
        var previousBlock: Int?, listItems = Set<Int>(), tables: [Int: NSTextTable] = [:]
        for run in markdown.runs {
            let intent = run[AttributeScopes.FoundationAttributes.PresentationIntentAttribute.self]
            let components = intent?.components ?? []
            let blockID = components.first?.identity ?? 0
            let newBlock = previousBlock != blockID
            if newBlock && output.length > 0 && !output.string.hasSuffix("\n") { output.append(NSAttributedString(string: "\n")) }
            previousBlock = blockID
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 10
            paragraph.lineSpacing = 3
            let depth = components.filter { $0.kind == .orderedList || $0.kind == .unorderedList }.count
            let ordered = components.first(where: { $0.kind == .orderedList || $0.kind == .unorderedList })?.kind == .orderedList
            var font = NSFont.systemFont(ofSize: 15)
            var prefix = "", codeBlock = false, quote = false, divider = false, handledList = false, italic = false, tableID: Int?, tableColumns: [PresentationIntent.TableColumn] = [], row = 0, column = 0, header = false
            for component in components {
                switch component.kind {
                case .header(let level): font = .boldSystemFont(ofSize: CGFloat(max(16, 30 - 3 * level))); paragraph.paragraphSpacingBefore = 12
                case .codeBlock: codeBlock = true; font = .monospacedSystemFont(ofSize: 14, weight: .regular); paragraph.headIndent = 14; paragraph.firstLineHeadIndent = 14
                case .blockQuote: quote = true; paragraph.headIndent += 22; paragraph.firstLineHeadIndent += 22
                case .listItem(let ordinal):
                    if handledList { break }; handledList = true
                    if newBlock && listItems.insert(component.identity).inserted { prefix = ordered ? "\(ordinal).\t" : "•\t" }
                    paragraph.headIndent = CGFloat(depth * 24); paragraph.firstLineHeadIndent = CGFloat(max(0, depth - 1) * 24)
                    paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
                    paragraph.paragraphSpacing = 4
                case .table(let columns): tableID = component.identity; tableColumns = columns
                case .tableHeaderRow: header = true; row = 0
                case .tableRow(let index): row = index
                case .tableCell(let index): column = index
                case .thematicBreak: divider = true
                default: break
                }
            }
            if let tableID {
                let table = tables[tableID] ?? NSTextTable()
                table.numberOfColumns = max(1, tableColumns.count); table.collapsesBorders = true
                tables[tableID] = table
                let cell = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setWidth(1, type: .absoluteValueType, for: .border)
                cell.setWidth(7, type: .absoluteValueType, for: .padding)
                cell.setBorderColor(.separatorColor)
                if header { cell.backgroundColor = .controlBackgroundColor; font = .boldSystemFont(ofSize: 15) }
                paragraph.textBlocks = [cell]; paragraph.paragraphSpacing = 0
                if tableColumns.indices.contains(column) {
                    switch tableColumns[column].alignment { case .left: paragraph.alignment = .left; case .center: paragraph.alignment = .center; case .right: paragraph.alignment = .right }
                }
            }
            let part = NSMutableAttributedString(attributedString: NSAttributedString(AttributedString(markdown[run.range])))
            if let inline = run[AttributeScopes.FoundationAttributes.InlinePresentationIntentAttribute.self] {
                if inline.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if inline.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask); italic = true }
                if inline.contains(.code) { font = .monospacedSystemFont(ofSize: 14, weight: .regular) }
            }
            if divider { part.mutableString.setString("────────────────────") }
            if !prefix.isEmpty { part.insert(NSAttributedString(string: prefix), at: 0) }
            let range = NSRange(location: 0, length: part.length)
            part.addAttributes([.font: font, .foregroundColor: quote ? NSColor.secondaryLabelColor : NSColor.textColor, .paragraphStyle: paragraph], range: range)
            if italic && !NSFontManager.shared.traits(of: font).contains(.italicFontMask) { part.addAttribute(.obliqueness, value: 0.2, range: range) }
            if codeBlock { part.addAttribute(.backgroundColor, value: NSColor.controlBackgroundColor, range: range) }
            if let url = run[AttributeScopes.FoundationAttributes.ImageURLAttribute.self] {
                let resolved = url.scheme == nil ? URL(string: url.relativeString, relativeTo: baseURL)?.absoluteURL : url
                if let resolved, resolved.isFileURL, let image = NSImage(contentsOf: resolved) {
                    let scaled = (image.copy() as? NSImage) ?? image
                    let factor = min(1, 580 / max(1, scaled.size.width)); scaled.size = NSSize(width: scaled.size.width * factor, height: scaled.size.height * factor)
                    let attachment = NSTextAttachment(); attachment.attachmentCell = NSTextAttachmentCell(imageCell: scaled)
                    let attributed = NSMutableAttributedString(attachment: attachment)
                    attributed.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attributed.length))
                    output.append(attributed); continue
                } else if let resolved { part.addAttribute(.link, value: resolved, range: range) }
            }
            output.append(part)
        }
        return output
    }
}
