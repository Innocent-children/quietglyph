import AppKit

@MainActor
final class ReadOnlyTextView: NSTextView {
    var gutterWidth: CGFloat = 0 {
        didSet { textContainerInset = NSSize(width: 14 + gutterWidth / 2, height: 12); invalidateTextContainerOrigin() }
    }
    override var textContainerOrigin: NSPoint { let origin = super.textContainerOrigin; return NSPoint(x: origin.x + gutterWidth / 2, y: origin.y) }
    override func layout() { super.layout(); enclosingScrollView?.verticalRulerView?.needsDisplay = true }
    func localRect(_ range: NSRange) -> NSRect? {
        guard let window else { return nil }
        var actual = NSRange()
        let screen = firstRect(forCharacterRange: range, actualRange: &actual)
        guard screen.height > 0 else { return nil }
        return convert(window.convertFromScreen(screen), from: nil)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let settings = SettingsStore.shared
        guard settings.showWhitespace else { return }
        let source = string as NSString
        let start = min(source.length, characterIndexForInsertion(at: visibleRect.origin))
        let end = min(source.length, characterIndexForInsertion(at: NSPoint(x: visibleRect.maxX, y: visibleRect.maxY)) + 1)
        guard end > start else { return }
        for index in start..<end {
            let unit = source.character(at: index)
            let symbol = unit == 32 ? "·" : unit == 9 ? "→" : settings.showLineEndings && [10, 13].contains(unit) ? "¶" : ""
            if !symbol.isEmpty, let rect = localRect(NSRange(location: index, length: 0)) {
                (symbol as NSString).draw(at: rect.origin, withAttributes: [.font: font ?? .monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor])
            }
        }
    }
}
