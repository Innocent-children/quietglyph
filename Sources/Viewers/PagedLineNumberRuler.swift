import AppKit

@MainActor
final class PagedLineNumberRuler: NSRulerView {
    weak var textView: ReadOnlyTextView?
    var labels: [String] = [] { didSet { updateMetrics() } }
    init(scrollView: NSScrollView, textView: ReadOnlyTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView; ruleThickness = 80
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func updateMetrics() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: textView?.font?.pointSize ?? 13, weight: .regular)
        let width = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 55
        ruleThickness = ceil(width) + 18; needsDisplay = true
    }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        guard let view = textView else { return }
        let lines = TextRanges.lines(view.string as NSString)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: view.font?.pointSize ?? 13, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        for (index, line) in lines.enumerated() where labels.indices.contains(index) {
            guard let local = view.localRect(NSRange(location: line.location, length: 0)) else { continue }
            let rect = convert(local, from: view)
            guard rect.intersects(bounds) else { continue }
            let text = labels[index] as NSString
            text.draw(at: NSPoint(x: ruleThickness - text.size(withAttributes: attributes).width - 8, y: rect.minY), withAttributes: attributes)
        }
    }
}
