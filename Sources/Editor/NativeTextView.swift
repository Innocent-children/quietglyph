import AppKit

@MainActor
final class NativeTextView: NSTextView {
    weak var editor: EditorController?
    private var rectangleAnchor: (line: Int, column: Int)?
    private func rectanglePosition(_ point: NSPoint) -> (line: Int, column: Int)? {
        guard let editor else { return nil }
        let offset = min(editor.source.length, characterIndexForInsertion(at: point))
        let lines = editor.lineRanges
        let index = lines.lastIndex(where: { $0.location <= offset }) ?? 0
        let line = lines[index]
        let origin = localRect(NSRange(location: line.location, length: 0))?.minX ?? textContainerOrigin.x
        let cell = max(1, (" " as NSString).size(withAttributes: [.font: font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]).width)
        return (index, max(0, Int(((point.x - origin) / cell).rounded())))
    }
    override func mouseDown(with event: NSEvent) {
        if editor?.selections.columnMode == true, !event.modifierFlags.contains([.command, .option]),
           let position = rectanglePosition(convert(event.locationInWindow, from: nil)) {
            rectangleAnchor = position
            selectRectangle(to: position); return
        }
        rectangleAnchor = nil; super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        if rectangleAnchor != nil, let position = rectanglePosition(convert(event.locationInWindow, from: nil)) {
            autoscroll(with: event); selectRectangle(to: position)
        } else { super.mouseDragged(with: event) }
    }
    private func selectRectangle(to position: (line: Int, column: Int)) {
        guard let anchor = rectangleAnchor, let editor else { return }
        editor.selections.rectangle(from: anchor.line, to: position.line, columns: min(anchor.column, position.column)...max(anchor.column, position.column), text: editor.source, tabWidth: SettingsStore.shared.tabWidth)
        editor.setSelections(editor.selections.ranges)
    }
    var gutterWidth: CGFloat = 0 {
        didSet {
            guard oldValue != gutterWidth else { return }
            // Insets are symmetric; shifting the origin by the other half reserves the gutter only on the left.
            textContainerInset = NSSize(width: 12 + gutterWidth / 2, height: 12)
            invalidateTextContainerOrigin()
        }
    }
    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x + gutterWidth / 2, y: origin.y)
    }
    override func layout() {
        super.layout()
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    private struct Composition {
        var ranges: [NSRange]
        var original: String
        var start: Int
    }
    private var composition: Composition?
    private var completingComposition = false
    var isComposing: Bool { composition != nil }

    override var undoManager: UndoManager? { editor?.document?.undoManager ?? super.undoManager }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if completingComposition { super.insertText(insertString, replacementRange: replacementRange); return }
        guard let editor else { super.insertText(insertString, replacementRange: replacementRange); return }
        let value = (insertString as? NSAttributedString)?.string ?? (insertString as? String) ?? ""
        if composition != nil {
            finishComposition(committing: value)
            return
        }
        if replacementRange.location != NSNotFound {
            editor.selections.set([replacementRange], text: string as NSString)
        }
        editor.replaceSelections(with: value, name: "Typing")
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if composition == nil, let editor {
            let range = replacementRange.location == NSNotFound ? self.selectedRange() : replacementRange
            guard TextRanges.valid(range, in: self.string as NSString) else { return }
            composition = Composition(ranges: editor.selections.ranges, original: (self.string as NSString).substring(with: range), start: range.location)
            allowsUndo = false
            undoManager?.disableUndoRegistration()
            editor.document?.beginProvisionalEdit()
        }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func unmarkText() {
        if completingComposition { super.unmarkText(); return }
        guard let pending = composition else { super.unmarkText(); return }
        let marked = markedRange()
        let end = marked.location == NSNotFound ? selectedRange().location : NSMaxRange(marked)
        let range = NSRange(location: pending.start, length: max(0, end - pending.start))
        let committed = TextRanges.valid(range, in: string as NSString) ? (string as NSString).substring(with: range) : pending.original
        finishComposition(committing: committed)
    }

    private func finishComposition(committing text: String?) {
        guard let pending = composition else { return }
        completingComposition = true
        let marked = markedRange()
        let end = marked.location == NSNotFound ? selectedRange().location : NSMaxRange(marked)
        let range = NSRange(location: pending.start, length: max(0, end - pending.start))
        super.unmarkText()
        if TextRanges.valid(range, in: string as NSString) {
            textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: pending.original, attributes: editor?.textAttributes ?? typingAttributes))
        }
        composition = nil
        allowsUndo = true
        undoManager?.enableUndoRegistration()
        editor?.document?.endProvisionalEdit()
        editor?.setSelections(pending.ranges)
        if let text { editor?.replaceSelections(with: text, name: "Typing") }
        completingComposition = false
    }

    override func deleteBackward(_ sender: Any?) {
        if hasMarkedText() { super.deleteBackward(sender) } else { editor?.deleteSelections(backwards: true) }
    }
    override func deleteForward(_ sender: Any?) {
        if hasMarkedText() { super.deleteForward(sender) } else { editor?.deleteSelections(backwards: false) }
    }
    override func insertNewline(_ sender: Any?) {
        if hasMarkedText() { super.insertNewline(sender) } else { editor?.insertNewline() }
    }
    override func insertTab(_ sender: Any?) {
        if hasMarkedText() { super.insertTab(sender) } else { editor?.insertTab() }
    }
    override func doCommand(by selector: Selector) {
        let moves: [String: SelectionController.Movement] = ["moveLeft:": .left, "moveBackward:": .left, "moveRight:": .right, "moveForward:": .right,
            "moveUp:": .up, "moveDown:": .down, "moveToBeginningOfLine:": .lineStart, "moveToEndOfLine:": .lineEnd,
            "moveToBeginningOfParagraph:": .lineStart, "moveToEndOfParagraph:": .lineEnd,
            "moveToBeginningOfDocument:": .documentStart, "moveToEndOfDocument:": .documentEnd,
            "moveWordLeft:": .wordLeft, "moveWordBackward:": .wordLeft, "moveWordRight:": .wordRight, "moveWordForward:": .wordRight]
        let name = NSStringFromSelector(selector)
        let base = name.replacingOccurrences(of: "AndModifySelection:", with: ":")
        if !hasMarkedText(), let editor, editor.selections.ranges.count > 1, let direction = moves[base] {
            editor.moveSelections(direction, extending: base != name)
        } else { super.doCommand(by: selector) }
    }
    override func insertBacktab(_ sender: Any?) { editor?.run(.outdent) }
    override func copy(_ sender: Any?) {
        guard let editor else { super.copy(sender); return }
        let source = string as NSString
        let values = editor.selections.ranges.filter { TextRanges.valid($0, in: source) }.map { source.substring(with: $0) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(values.joined(separator: editor.document?.metadata.lineEnding.text ?? "\n"), forType: .string)
    }
    override func cut(_ sender: Any?) { copy(sender); editor?.replaceSelections(with: "", name: "Cut") }
    override func paste(_ sender: Any?) {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        editor?.paste(value)
    }
    override func selectAll(_ sender: Any?) {
        editor?.setSelections([NSRange(location: 0, length: (string as NSString).length)])
    }
    override func cancelOperation(_ sender: Any?) {
        if composition != nil { finishComposition(committing: nil); inputContext?.discardMarkedText(); return }
        editor?.selections.columnMode = false
        editor?.setSelections([selectedRange()])
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        editor?.decorations.draw(in: self, dirty: rect)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let editor, window != nil else { return }
        NSColor.controlAccentColor.setFill()
        for selection in editor.selections.ranges.dropFirst() {
            if selection.length == 0 {
                guard var rect = localRect(selection) else { continue }
                if let target = editor.selections.rectangleColumns?.lowerBound {
                    let line = TextRanges.lineContent(editor.source.lineRange(for: selection), in: editor.source)
                    let actual = ColumnGeometry.column(at: selection.location - line.location, in: editor.source.substring(with: line), tabWidth: SettingsStore.shared.tabWidth)
                    rect.origin.x += CGFloat(max(0, target - actual)) * (" " as NSString).size(withAttributes: [.font: font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)]).width
                }
                if rect.intersects(visibleRect) { NSRect(x: rect.minX, y: rect.minY, width: 1.5, height: max(12, rect.height)).fill() }
            }
        }
        if SettingsStore.shared.showWhitespace {
            let source = string as NSString
            let start = min(source.length, characterIndexForInsertion(at: visibleRect.origin))
            let end = min(source.length, characterIndexForInsertion(at: NSPoint(x: visibleRect.maxX, y: visibleRect.maxY)) + 1)
            guard end >= start else { return }
            for i in start..<end {
                let c = source.character(at: i)
                let mark: String? = c == 32 ? "·" : c == 9 ? "→" : SettingsStore.shared.showLineEndings && (c == 10 || c == 13) ? "¶" : nil
                if let mark {
                    guard let rect = localRect(NSRange(location: i, length: 0)) else { continue }
                    (mark as NSString).draw(at: rect.origin, withAttributes: [.font: font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor])
                }
            }
        }
    }
    func localRect(_ range: NSRange) -> NSRect? {
        guard let window else { return nil }
        var actual = NSRange()
        let screenRect = firstRect(forCharacterRange: range, actualRange: &actual)
        guard screenRect.height > 0 else { return nil }
        return convert(window.convertFromScreen(screenRect), from: nil)
    }
}
