import AppKit

@MainActor
final class EditorController: NSViewController, NSTextViewDelegate, NSGestureRecognizerDelegate {
    weak var document: TextDocument?
    let textView = EditorTextView(usingTextLayoutManager: true)
    let scrollView = NSScrollView()
    let selections = SelectionController()
    let bookmarks = BookmarkStore()
    let marks = TextMarkStore()
    let navigation = NavigationHistory()
    let decorations = EditorDecorationController()
    let folding = FoldingController()
    let highlighter = IncrementalHighlighter()
    let observer = EditorTextStorageObserver()
    var onStatusChange: (() -> Void)?
    private(set) var lineRanges: [NSRange] = [NSRange(location: 0, length: 0)]
    private(set) var textAttributes: [NSAttributedString.Key: Any] = [:]
    private var adjustingSelection = false
    private var applyingEdit = false
    private final class TypingUndo {
        var edits: [TextEdit]
        let selections: [NSRange]
        var carets: [NSRange]
        var timestamp: TimeInterval
        var rectangle: ClosedRange<Int>?
        var bookmarks: [Int] = []
        var marks: [TextMarkStore.Mark] = []
        init(edits: [TextEdit], selections: [NSRange], carets: [NSRange]) {
            self.edits = edits; self.selections = selections; self.carets = carets
            timestamp = Date.timeIntervalSinceReferenceDate
        }
    }
    private var typingUndo: TypingUndo?
    private var refresh: Task<Void, Never>?
    private var settingsToken: NSObjectProtocol?
    var language: LanguageDefinition = .plain {
        didSet { highlighter.language = language; highlighter.reset() }
    }
    var source: NSString { textView.string as NSString }

    init(document: TextDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        textView.editor = self
        decorations.editor = self
        textView.delegate = self
        textView.isRichText = false
        textView.isEditable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isVerticallyResizable = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        scrollView.verticalRulerView = LineNumberRuler(scrollView: scrollView, editor: self)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        view = scrollView
        textView.string = document?.initialText ?? ""
        textView.textStorage?.delegate = observer
        observer.editor = self
        folding.textView = textView
        folding.beforeFolding = { [weak self] in self?.highlighter.parseNow() }
        textView.textContentStorage?.delegate = folding
        highlighter.textView = textView
        highlighter.onParsed = { [weak self] parsed in
            guard let self else { return }
            self.folding.rebuild(language: self.language, parsed: parsed)
            self.decorations.setParsed(parsed)
        }
        lineRanges = TextRanges.lines(source)
        language = LanguageRegistry.shared.language(document?.metadata.languageID ?? "txt")
        applySettings()
        settingsToken = NotificationCenter.default.addObserver(forName: SettingsStore.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
        let click = NSClickGestureRecognizer(target: self, action: #selector(addCaret(_:)))
        click.numberOfClicksRequired = 1
        click.buttonMask = 0x1
        click.delegate = self
        textView.addGestureRecognizer(click)
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        let size = scrollView.contentView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let rulerFrame = scrollView.verticalRulerView?.frame ?? .zero
        textView.gutterWidth = NSIntersectionRect(rulerFrame, scrollView.contentView.frame).width
        textView.minSize = NSSize(width: 0, height: size.height)
        if SettingsStore.shared.wrapLines {
            textView.setFrameSize(NSSize(width: size.width, height: max(size.height, textView.frame.height)))
            textView.textContainer?.containerSize = NSSize(width: max(1, size.width - 2 * textView.textContainerInset.width), height: CGFloat.greatestFiniteMagnitude)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y))
        }
    }
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        event.modifierFlags.contains([.command, .option])
    }
    private func applySettings() {
        let settings = SettingsStore.shared
        textView.font = NSFont(name: settings.fontName, size: settings.fontSize) ?? .monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
        textView.textColor = settings.currentTheme.foreground
        textView.backgroundColor = settings.currentTheme.background
        textView.insertionPointColor = settings.currentTheme.foreground
        textView.isHorizontallyResizable = !settings.wrapLines
        textView.isAutomaticLinkDetectionEnabled = settings.values.detectLinks
        scrollView.hasHorizontalScroller = !settings.wrapLines
        textView.autoresizingMask = settings.wrapLines ? [.width] : []
        textView.textContainer?.widthTracksTextView = settings.wrapLines
        textView.textContainer?.containerSize = NSSize(width: settings.wrapLines ? max(1, scrollView.contentView.bounds.width - 2 * textView.textContainerInset.width) : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let paragraph = NSMutableParagraphStyle()
        paragraph.defaultTabInterval = (textView.font?.maximumAdvancement.width ?? 8) * CGFloat(settings.tabWidth)
        paragraph.tabStops = []
        textView.defaultParagraphStyle = paragraph
        textAttributes = [.font: textView.font!, .foregroundColor: settings.currentTheme.foreground, .paragraphStyle: paragraph]
        textView.typingAttributes = textAttributes
        if let storage = textView.textStorage {
            storage.addAttributes([.font: textView.font!, .paragraphStyle: paragraph], range: NSRange(location: 0, length: storage.length))
        }
        highlighter.reset()
        (scrollView.verticalRulerView as? LineNumberRuler)?.updateMetrics()
        textView.needsDisplay = true
    }
    @objc private func addCaret(_ recognizer: NSClickGestureRecognizer) {
        guard NSEvent.modifierFlags.contains([.command, .option]) else { return }
        let index = textView.characterIndexForInsertion(at: recognizer.location(in: textView))
        setSelections(selections.ranges + [NSRange(location: index, length: 0)])
    }

    func breakTypingCoalescing() { typingUndo = nil }
    func setSelections(_ ranges: [NSRange], scroll: Bool = false, preservingTyping: Bool = false, recordingNavigation: Bool = true) {
        if scroll && recordingNavigation && !preservingTyping, let from = selections.ranges.first?.location, let to = ranges.first?.location { navigation.record(from: from, to: to) }
        if !preservingTyping { breakTypingCoalescing() }
        selections.set(ranges, text: source)
        displaySelections(scroll: scroll)
    }
    private func displaySelections(scroll: Bool = false) {
        adjustingSelection = true
        let nonempty = selections.ranges.filter { $0.length > 0 }
        if nonempty.count == selections.ranges.count {
            textView.selectedRanges = nonempty.map { NSValue(range: $0) }
        } else if let primary = selections.ranges.first { textView.setSelectedRange(primary) }
        adjustingSelection = false
        if scroll, let first = selections.ranges.first { folding.reveal(first); textView.scrollRangeToVisible(first) }
        textView.needsDisplay = true
        onStatusChange?()
        decorations.refresh()
    }
    func moveSelections(_ direction: SelectionController.Movement, extending: Bool) {
        breakTypingCoalescing()
        selections.move(direction, extending: extending, text: source, tabWidth: SettingsStore.shared.tabWidth)
        displaySelections(scroll: true)
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        guard !adjustingSelection, !applyingEdit, !textView.isComposing else { return }
        let nativeRanges = textView.selectedRanges.map(\.rangeValue)
        if nativeRanges == selections.ranges { return }
        if selections.ranges.count > 1, selections.ranges.allSatisfy({ $0.length == 0 }), nativeRanges == Array(selections.ranges.prefix(1)) { return }
        breakTypingCoalescing()
        if selections.columnMode, textView.selectedRanges.count == 1 {
            let range = textView.selectedRange()
            let lines = TextRanges.lines(source)
            let first = lines.lastIndex(where: { $0.location <= range.location }) ?? 0
            let last = lines.lastIndex(where: { $0.location <= NSMaxRange(range) }) ?? first
            let a = ColumnGeometry.column(at: range.location - lines[first].location, in: source.substring(with: TextRanges.lineContent(lines[first], in: source)), tabWidth: SettingsStore.shared.tabWidth)
            let b = ColumnGeometry.column(at: NSMaxRange(range) - lines[last].location, in: source.substring(with: TextRanges.lineContent(lines[last], in: source)), tabWidth: SettingsStore.shared.tabWidth)
            selections.rectangle(from: first, to: last, columns: min(a, b)...max(a, b), text: source, tabWidth: SettingsStore.shared.tabWidth)
            setSelections(selections.ranges)
            return
        }
        selections.set(nativeRanges, text: source)
        onStatusChange?()
        decorations.refresh()
    }
    func textDidMutate() {
        lineRanges = TextRanges.lines(source)
        (scrollView.verticalRulerView as? LineNumberRuler)?.updateMetrics()
        if !applyingEdit && !textView.isComposing { breakTypingCoalescing() }
        document?.contentDidChange(provisional: textView.isComposing)
        refresh?.cancel()
        refresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            if !self.textView.isComposing {
                self.highlighter.schedule()
            }
            self.scrollView.verticalRulerView?.needsDisplay = true
            self.onStatusChange?()
        }
    }

    func apply(_ edits: [TextEdit], name: String, restoring selectionsAfter: [NSRange]? = nil) throws {
        guard let storage = textView.textStorage, document?.mode == .text else { throw EditorError.readOnly }
        let normalized = try EditTransaction.normalized(edits, in: source).filter { source.substring(with: $0.range) != $0.replacement }
        guard !normalized.isEmpty else { return }
        let before = selections.ranges
        var inverse: [TextEdit] = []
        var after: [NSRange] = []
        var delta = 0
        for edit in normalized {
            let length = (edit.replacement as NSString).length
            inverse.append(TextEdit(range: NSRange(location: edit.range.location + delta, length: length), replacement: source.substring(with: edit.range)))
            after.append(NSRange(location: edit.range.location + delta + length, length: 0))
            delta += length - edit.range.length
            folding.reveal(edit.range)
        }
        let undo = document?.undoManager
        let isTyping = name == "Typing" && undo?.isUndoing != true && undo?.isRedoing != true
        if isTyping, let previous = typingUndo,
           Date.timeIntervalSinceReferenceDate - previous.timestamp < 1,
           before == previous.carets, normalized.count == previous.edits.count,
           normalized.allSatisfy({ $0.range.length == 0 && !$0.replacement.contains(where: \.isNewline) }) {
            var shift = 0
            for i in normalized.indices {
                let length = (normalized[i].replacement as NSString).length
                previous.edits[i].range.location += shift
                previous.edits[i].range.length += length
                shift += length
            }
            previous.carets = after
            previous.timestamp = Date.timeIntervalSinceReferenceDate
        } else {
            let operation = TypingUndo(edits: inverse, selections: before, carets: after)
            operation.rectangle = selections.rectangleColumns
            operation.bookmarks = bookmarks.offsets; operation.marks = marks.marks
            undo?.registerUndo(withTarget: self) { target in
                do {
                    try target.apply(operation.edits, name: name, restoring: operation.selections)
                    target.selections.restoreRectangle(operation.rectangle)
                    target.bookmarks.restore(operation.bookmarks); target.marks.restore(operation.marks)
                    target.textView.needsDisplay = true
                }
                catch { NSApp.presentError(error) }
            }
            undo?.setActionName(L10n.text(name))
            typingUndo = isTyping ? operation : nil
        }
        applyingEdit = true
        storage.beginEditing()
        for edit in normalized.reversed() {
            storage.replaceCharacters(in: edit.range, with: NSAttributedString(string: edit.replacement, attributes: textAttributes))
        }
        storage.endEditing()
        bookmarks.apply(normalized)
        marks.apply(normalized)
        navigation.apply(normalized)
        folding.apply(normalized)
        applyingEdit = false
        setSelections(selectionsAfter ?? after, scroll: true, preservingTyping: true)
        textView.typingAttributes = textAttributes
        textView.didChangeText()
    }
    func replaceSelections(with text: String, name: String) {
        replaceSelections(with: Array(repeating: text, count: selections.ranges.count), name: name)
    }
    func mark(_ ranges: [NSRange], color: String) {
        let valid = ranges.filter { TextRanges.valid($0, in: source) }
        if color == "Clear" { marks.clear(in: valid) } else { marks.set(valid, color: color) }
        textView.needsDisplay = true
    }
    func replaceSelections(with values: [String], name: String) {
        do { try apply(selections.replacements(values, text: source, tabWidth: SettingsStore.shared.tabWidth), name: name) }
        catch { NSApp.presentError(error) }
    }
    func paste(_ text: String) {
        let rows = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        if selections.ranges.count > 1, rows.count == selections.ranges.count {
            replaceSelections(with: rows, name: "Paste")
        } else { replaceSelections(with: text, name: "Paste") }
    }
    func deleteSelections(backwards: Bool) {
        let text = source
        let edits = selections.ranges.compactMap { selection -> TextEdit? in
            if selection.length > 0 { return TextEdit(range: selection, replacement: "") }
            if backwards, selection.location > 0 {
                return TextEdit(range: text.rangeOfComposedCharacterSequence(at: selection.location - 1), replacement: "")
            }
            if !backwards, selection.location < text.length {
                return TextEdit(range: text.rangeOfComposedCharacterSequence(at: selection.location), replacement: "")
            }
            return nil
        }
        var merged: [TextEdit] = []
        for edit in edits.sorted(by: { $0.range.location < $1.range.location }) {
            if let last = merged.last, edit.range.location <= NSMaxRange(last.range) {
                merged[merged.count - 1].range = NSUnionRange(last.range, edit.range)
            } else { merged.append(edit) }
        }
        do { try apply(merged, name: "Delete") } catch { NSApp.presentError(error) }
    }
    func selectedOrAll() -> [NSRange] {
        selections.ranges.contains(where: { $0.length > 0 }) ? selections.ranges : [NSRange(location: 0, length: source.length)]
    }
    func selectedLines() -> NSRange {
        let start = selections.ranges.first?.location ?? 0
        let last = selections.ranges.last ?? NSRange(location: start, length: 0)
        let end = last.length > 0 ? max(start, NSMaxRange(last) - 1) : NSMaxRange(last)
        let firstLine = source.lineRange(for: NSRange(location: start, length: 0))
        let finalLine = source.lineRange(for: NSRange(location: min(end, source.length), length: 0))
        return NSRange(location: firstLine.location, length: NSMaxRange(finalLine) - firstLine.location)
    }
    func run(_ command: TextCommand) {
        if command == .indent || command == .outdent { indentSelections(outdent: command == .outdent); return }
        let ranges = [.indent, .outdent, .trimHead, .trimTail, .trimBoth].contains(command) ? [selectedLines()] : selectedOrAll()
        do { try apply(ranges.map { TextEdit(range: $0, replacement: command.apply(source.substring(with: $0), tabWidth: SettingsStore.shared.tabWidth)) }, name: command.rawValue) }
        catch { NSApp.presentError(error) }
    }
    func run(_ command: LineCommand) {
        let local: [LineCommand] = [.duplicate, .delete, .join, .split]
        let range = !local.contains(command) && selections.ranges.allSatisfy({ $0.length == 0 }) && selections.rectangleColumns == nil ? NSRange(location: 0, length: source.length) : selectedLines()
        let text = source.substring(with: range)
        let ending = document?.metadata.lineEnding ?? .lf
        let replacement = command == .split ? splitAtDisplayWidth(text, ending: ending) : LineCommands.apply(command, to: text, ending: ending, columns: selections.rectangleColumns, tabWidth: SettingsStore.shared.tabWidth)
        do { try apply([TextEdit(range: range, replacement: replacement)], name: command.rawValue) }
        catch { NSApp.presentError(error) }
    }
    func indentSelections(outdent: Bool = false) {
        let text = source, settings = SettingsStore.shared
        let lines = TextRanges.lines(text)
        let affected = lines.filter { line in
            selections.ranges.contains { selection in
                let end = selection.length == 0 ? selection.location : NSMaxRange(selection) - 1
                return line.location <= end && (NSMaxRange(line) > selection.location || line.location == text.length && selection.location == text.length)
            }
        }
        let edits = affected.map { line -> TextEdit in
            let value = text.substring(with: TextRanges.lineContent(line, in: text))
            if outdent {
                let count = value.hasPrefix("\t") ? 1 : min(settings.tabWidth, value.prefix(while: { $0 == " " }).count)
                return TextEdit(range: NSRange(location: line.location, length: count), replacement: "")
            }
            return TextEdit(range: NSRange(location: line.location, length: 0), replacement: settings.useSpaces ? String(repeating: " ", count: settings.tabWidth) : "\t")
        }
        let after = selections.ranges.map { range -> NSRange in
            let start = edits.reversed().reduce(range.location) { EditTransaction.transformed($0, by: $1) }
            let end = edits.reversed().reduce(NSMaxRange(range)) { EditTransaction.transformed($0, by: $1) }
            return NSRange(location: start, length: max(0, end - start))
        }
        do { try apply(edits, name: outdent ? "Outdent" : "Indent", restoring: after) }
        catch { NSApp.presentError(error) }
    }
    func insertTab() {
        if selections.ranges.contains(where: { range in
            range.length > 0 && TextRanges.lineNumber(at: range.location, in: source) != TextRanges.lineNumber(at: NSMaxRange(range), in: source)
        }) { indentSelections(); return }
        let settings = SettingsStore.shared
        let values = selections.ranges.map { range -> String in
            guard settings.useSpaces else { return "\t" }
            let line = TextRanges.lineContent(source.lineRange(for: NSRange(location: range.location, length: 0)), in: source)
            let column = selections.rectangleColumns?.lowerBound ?? ColumnGeometry.column(at: range.location - line.location, in: source.substring(with: line), tabWidth: settings.tabWidth)
            return String(repeating: " ", count: settings.tabWidth - column % settings.tabWidth)
        }
        replaceSelections(with: values, name: "Indent")
    }
    func insertNewline() {
        let values = selections.ranges.map { selection -> String in
            let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
            let before = source.substring(with: NSRange(location: line.location, length: selection.location - line.location))
            let indent = SettingsStore.shared.autoIndent ? String(before.prefix(while: { $0 == " " || $0 == "\t" })) : ""
            return (document?.metadata.lineEnding.text ?? "\n") + indent
        }
        replaceSelections(with: values, name: "New Line")
    }
    func selectColumnToEnd() {
        guard selections.ranges.count == 1, let caret = selections.ranges.first else { return }
        let lines = TextRanges.lines(source)
        let first = lines.lastIndex(where: { $0.location <= caret.location }) ?? 0
        let column = ColumnGeometry.column(at: caret.location - lines[first].location, in: source.substring(with: TextRanges.lineContent(lines[first], in: source)), tabWidth: SettingsStore.shared.tabWidth)
        selections.rectangle(from: first, to: lines.count - 1, columns: column...column, text: source, tabWidth: SettingsStore.shared.tabWidth)
        displaySelections()
    }
    private func splitAtDisplayWidth(_ text: String, ending: LineEnding) -> String {
        let storage = NSTextStorage(string: text, attributes: textAttributes)
        let layout = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: max(1, scrollView.contentSize.width - 2 * textView.textContainerInset.width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = textView.textContainer?.lineFragmentPadding ?? 5
        storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
        var offsets: [Int] = []
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, _, _, glyphRange, _ in
            let range = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let end = NSMaxRange(range)
            if end < storage.length, end > 0, ![10, 13].contains((text as NSString).character(at: end - 1)) { offsets.append(end) }
        }
        let result = NSMutableString(string: text)
        for offset in offsets.reversed() { result.insert(ending.text, at: offset) }
        return result as String
    }
    func transform(name: String, _ body: (String) throws -> String) {
        do { try apply(selectedOrAll().map { TextEdit(range: $0, replacement: try body(source.substring(with: $0))) }, name: name) }
        catch { NSApp.presentError(error) }
    }
    func commentLines() {
        let range = selectedLines()
        let replacement = ColumnCommands.comment(source.substring(with: range), prefix: language.lineComment)
        do { try apply([TextEdit(range: range, replacement: replacement)], name: "Comment") }
        catch { NSApp.presentError(error) }
    }
    func goTo(line: Int, column: Int = 1) {
        let lines = TextRanges.lines(source)
        let index = min(max(0, line - 1), lines.count - 1)
        let content = TextRanges.lineContent(lines[index], in: source)
        let position = ColumnGeometry.position(at: max(0, column - 1), in: source.substring(with: content), tabWidth: SettingsStore.shared.tabWidth)
        setSelections([NSRange(location: content.location + position.offset, length: 0)], scroll: true)
    }
    func navigate(backwards: Bool) {
        if let offset = navigation.move(backwards: backwards) { setSelections([NSRange(location: min(source.length, offset), length: 0)], scroll: true, recordingNavigation: false) }
    }
    func removeBlockComment() {
        do { try apply(ColumnCommands.removeBlockComment(textView.string, selections: selections.ranges, start: language.blockCommentStart, end: language.blockCommentEnd), name: "Remove Block Comment") }
        catch { NSApp.presentError(error) }
    }
    func addNextOccurrence(all: Bool = false) {
        var selected = textView.selectedRange()
        if selected.length == 0 {
            let range = textView.selectionRange(forProposedRange: selected, granularity: .selectByWord)
            selected = range
            setSelections([range])
        }
        guard selected.length > 0 else { return }
        var query = SearchQuery(); query.text = source.substring(with: selected); query.caseSensitive = true
        guard let matches = try? SearchService.matches(query, in: textView.string) else { return }
        if all { setSelections(matches.map(\.range)) }
        else if let next = matches.first(where: { $0.range.location >= NSMaxRange(selections.ranges.last ?? selected) }) ??
                    matches.first(where: { !selections.ranges.contains($0.range) }) {
            setSelections(selections.ranges + [next.range], scroll: true)
        }
    }
    func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
        index?.pointee = 0
        return CompletionProvider.words(prefix: source.substring(with: charRange), text: textView.string, language: language)
    }
    deinit { if let settingsToken { NotificationCenter.default.removeObserver(settingsToken) }; refresh?.cancel() }
}
