import AppKit

@MainActor
final class LineNumberRuler: NSRulerView {
    weak var editor: EditorController?
    var labelFont: NSFont { .monospacedDigitSystemFont(ofSize: editor?.textView.font?.pointSize ?? SettingsStore.shared.fontSize, weight: .regular) }
    private var foldingWidth: CGFloat { max(20, ceil(labelFont.pointSize) + 8) }
    private var numberRightEdge: CGFloat { ruleThickness - foldingWidth - 4 }

    func updateMetrics() {
        let digits = String(repeating: "8", count: max(3, String(editor?.lineRanges.count ?? 1).count)) as NSString
        let width = ceil(digits.size(withAttributes: [.font: labelFont]).width) + 18 + foldingWidth + 4
        if ruleThickness != width { ruleThickness = width }
        needsDisplay = true
    }
    struct VisibleLine {
        let number: Int
        let range: NSRange
        let rect: NSRect
        let baseline: CGFloat
    }
    init(scrollView: NSScrollView, editor: EditorController) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor.textView
        ruleThickness = 58
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func visibleLines() -> [VisibleLine] {
        guard let editor, let manager = editor.textView.textLayoutManager,
              let content = manager.textContentManager,
              let viewport = manager.textViewportLayoutController.viewportRange else { return [] }
        let view = editor.textView
        let lines = editor.lineRanges
        let start = content.offset(from: content.documentRange.location, to: viewport.location)
        var index = lines.lastIndex(where: { $0.location <= start }) ?? 0
        var result: [VisibleLine] = []
        manager.enumerateTextLayoutFragments(from: viewport.location, options: [.ensuresExtraLineFragment]) { fragment in
            if fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedDescending { return false }
            guard fragment.state == .layoutAvailable, let elementRange = fragment.textElement?.elementRange else { return true }
            let elementStart = content.offset(from: content.documentRange.location, to: elementRange.location)
            for line in fragment.textLineFragments {
                let offset = elementStart + line.characterRange.location
                while index + 1 < lines.count && lines[index + 1].location <= offset { index += 1 }
                guard lines[index].location == offset,
                      !editor.folding.collapsed.contains(where: { NSLocationInRange(offset, $0) }) else { continue }
                let local = line.typographicBounds.offsetBy(dx: fragment.layoutFragmentFrame.minX + view.textContainerOrigin.x,
                                                            dy: fragment.layoutFragmentFrame.minY + view.textContainerOrigin.y)
                let rect = self.convert(local, from: view)
                guard rect.height > 0, rect.maxY > self.bounds.minY, rect.minY < self.bounds.maxY else { continue }
                result.append(VisibleLine(number: index + 1, range: lines[index], rect: rect,
                                          baseline: rect.minY + line.glyphOrigin.y))
            }
            return true
        }
        return result
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        guard let editor else { return }
        let font = labelFont
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        for line in visibleLines() {
            let range = line.range
            let label = String(line.number) as NSString
            let y = line.baseline - font.ascender
            label.draw(at: NSPoint(x: numberRightEdge - label.size(withAttributes: attrs).width, y: y), withAttributes: attrs)
            if editor.bookmarks.offsets.contains(where: { NSLocationInRange($0, range) || $0 == range.location }) {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: 4, y: y + 3, width: 6, height: 6)).fill()
            }
            if editor.folding.regions.contains(where: { $0.header.location == range.location }) {
                let collapsed = editor.folding.regions.filter { $0.header.location == range.location }.contains { editor.folding.collapsed.contains($0.hidden) }
                ((collapsed ? "▸" : "▾") as NSString).draw(at: NSPoint(x: ruleThickness - foldingWidth, y: y), withAttributes: attrs)
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let editor else { return }
        let point = editor.textView.convert(event.locationInWindow, from: nil)
        let offset = editor.textView.characterIndexForInsertion(at: point)
        let range = (editor.textView.string as NSString).lineRange(for: NSRange(location: min(offset, (editor.textView.string as NSString).length), length: 0))
        if convert(event.locationInWindow, from: nil).x > ruleThickness - foldingWidth - 2 { editor.folding.toggle(at: range.location) }
        else { editor.bookmarks.toggle(range.location) }
        needsDisplay = true
        editor.onStatusChange?()
    }
}
