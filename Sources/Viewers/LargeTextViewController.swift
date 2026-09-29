import AppKit

@MainActor
class LargeTextViewController: NSViewController {
    let url: URL
    let textView = ReadOnlyTextView(usingTextLayoutManager: true)
    let scrollView = NSScrollView()
    let offsetField = NSTextField(string: "0")
    let searchField = NSSearchField()
    let status = NSTextField(labelWithString: "")
    var reader: PagedFileReader?
    var offset: UInt64 = 0
    var nextOffset: UInt64 = 0
    var history: [UInt64] = []
    var operation: Task<Void, Never>?
    var searchOperation: Task<UInt64?, Error>?
    var lineIndex: LineIndex?
    private var indexOperation: Task<LineIndex, Error>?
    private var lastNeedle = ""
    private var lastMatch: UInt64?
    var isHex: Bool { false }
    private var settingsObserver: NSObjectProtocol?
    private var pageLines: [UInt64: UInt64] = [0: 1]
    private var ruler: PagedLineNumberRuler?
    private var wraps: Bool { !isHex && SettingsStore.shared.wrapLines }

    init(url: URL) { self.url = url; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func loadView() {
        let root = NSView()
        let previous = NSButton(title: L10n.text("Previous"), target: self, action: #selector(previousPage))
        let next = NSButton(title: L10n.text("Next"), target: self, action: #selector(nextPage))
        let go = NSButton(title: L10n.text("Go"), target: self, action: #selector(goToOffset))
        let cancel = NSButton(title: L10n.text("Cancel"), target: self, action: #selector(cancelWork))
        offsetField.placeholderString = isHex ? L10n.text("Hex byte address") : L10n.text("Byte address or line:123")
        offsetField.target = self; offsetField.action = #selector(goToOffset)
        searchField.placeholderString = isHex ? L10n.text("Hex bytes, e.g. 00 FF 41") : L10n.text("Find text in file")
        searchField.target = self; searchField.action = #selector(findText)
        let bar = NSStackView(views: [previous, next, offsetField, go, searchField, cancel])
        bar.spacing = 8
        let scroll = scrollView
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = isHex
        textView.isEditable = false; textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = isHex
        textView.autoresizingMask = isHex ? [] : .width
        textView.textContainer?.widthTracksTextView = !isHex
        textView.textContainerInset = NSSize(width: 14, height: 12)
        scroll.documentView = textView
        if !isHex {
            let ruler = PagedLineNumberRuler(scrollView: scroll, textView: textView)
            self.ruler = ruler; scroll.verticalRulerView = ruler; scroll.hasVerticalRuler = true; scroll.rulersVisible = true
        }
        for child in [bar, scroll, status] { child.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(child) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor, constant: 8), bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10), bar.heightAnchor.constraint(equalToConstant: 28),
            offsetField.widthAnchor.constraint(equalToConstant: 170), searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6), status.heightAnchor.constraint(equalToConstant: 20)
        ])
        view = root
        applySettings()
        settingsObserver = NotificationCenter.default.addObserver(forName: SettingsStore.changed, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.applySettings() } }
        do { reader = try PagedFileReader(url: url); loadPage(0) } catch { status.stringValue = error.localizedDescription }
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        let size = scrollView.contentView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        textView.gutterWidth = NSIntersectionRect(scrollView.verticalRulerView?.frame ?? .zero, scrollView.contentView.frame).width
        let width = wraps ? size.width : max(size.width, isHex ? 850 : textView.frame.width)
        textView.minSize = NSSize(width: 0, height: size.height)
        textView.setFrameSize(NSSize(width: width, height: max(size.height, textView.frame.height)))
        textView.textContainer?.containerSize = NSSize(width: wraps ? max(1, width - 2 * textView.textContainerInset.width) : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if wraps { scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y)) }
    }
    private func applySettings() {
        let settings = SettingsStore.shared
        textView.font = NSFont(name: settings.fontName, size: settings.fontSize) ?? .monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
        textView.textColor = settings.currentTheme.foreground; textView.backgroundColor = settings.currentTheme.background
        textView.isHorizontallyResizable = !wraps; textView.autoresizingMask = wraps ? .width : []
        textView.textContainer?.widthTracksTextView = wraps; scrollView.hasHorizontalScroller = !wraps
        textView.textContainer?.containerSize = NSSize(width: wraps ? max(1, scrollView.contentSize.width - 2 * textView.textContainerInset.width) : .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        ruler?.updateMetrics(); view.needsLayout = true; textView.needsDisplay = true
    }
    func loadPage(_ start: UInt64) {
        guard let reader else { return }
        do {
            if isHex {
                let data = try reader.raw(at: start, count: 16 * 1024)
                textView.string = HexViewController.format(data, offset: start)
                offset = start; nextOffset = start + UInt64(data.count)
            } else {
                let page = try reader.page(at: start)
                textView.string = page.text
                offset = page.start; nextOffset = page.end
                let baseLine = pageLines[start] ?? pageLines[page.start]
                let source = page.text as NSString
                let lines = TextRanges.lines(source)
                var address = page.start
                var metadata = DocumentMetadata(); metadata.encoding = reader.encoding
                ruler?.labels = lines.enumerated().map { index, line in
                    let label = baseLine.map { String($0 + UInt64(index)) } ?? "@\(address)"
                    address += UInt64((try? FileCodec.encode(source.substring(with: line), metadata: metadata).count) ?? 0)
                    return label
                }
                if let baseLine { pageLines[page.start] = baseLine; pageLines[page.end] = baseLine + UInt64(max(0, lines.count - 1)) }
            }
            offsetField.stringValue = isHex ? String(offset, radix: 16).uppercased() : String(offset)
            status.stringValue = L10n.format("Read Only · %@ · %llu–%llu / %llu bytes", reader.encoding.title, offset, nextOffset, reader.size)
            textView.scrollToBeginningOfDocument(nil)
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc func previousPage() { loadPage(history.popLast() ?? 0) }
    @objc func nextPage() {
        guard let reader, nextOffset < reader.size else { return }
        history.append(offset); loadPage(nextOffset)
    }
    @objc func goToOffset() {
        guard let reader else { return }
        let value = offsetField.stringValue.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("line:"), let line = UInt64(value.dropFirst(5)), !isHex {
            operation?.cancel()
            status.stringValue = L10n.text("Building line index…")
            operation = Task {
                do {
                    let index: LineIndex
                    if let saved = lineIndex { index = saved } else {
                        indexOperation?.cancel()
                        indexOperation = Task.detached(priority: .userInitiated) { try await LineIndex.build(reader: reader) }
                        index = try await indexOperation!.value
                    }
                    try Task.checkCancellation()
                    lineIndex = index
                    let address = try await index.offset(for: line, reader: reader)
                    pageLines[address] = min(max(1, line), index.count)
                    history.append(offset); loadPage(address)
                } catch { status.stringValue = error.localizedDescription }
            }
        } else if let target = UInt64(value.replacingOccurrences(of: "0x", with: ""), radix: isHex ? 16 : 10) {
            history.append(offset); loadPage(min(target, reader.size))
        }
    }
    @objc func findText() {
        guard let reader, !searchField.stringValue.isEmpty else { return }
        let needle = searchField.stringValue
        var metadata = DocumentMetadata(); metadata.encoding = reader.encoding
        let advance = UInt64(max(1, (try? FileCodec.encode(needle, metadata: metadata).count) ?? 1))
        let start = needle == lastNeedle ? (lastMatch.map { $0 + advance } ?? 0) : 0
        lastNeedle = needle
        searchOperation?.cancel()
        searchOperation = Task.detached(priority: .userInitiated) {
            if let match = try await reader.find(needle, after: start) { return match }
            return start > 0 ? try await reader.find(needle, after: 0) : nil
        }
        operation?.cancel()
        operation = Task {
            do {
                guard let result = try await searchOperation?.value else { status.stringValue = L10n.text("No further matches"); return }
                try Task.checkCancellation()
                lastMatch = result
                history.append(offset); loadPage(result)
                status.stringValue += L10n.format(" · Match at %llu", result)
            } catch { status.stringValue = error.localizedDescription }
        }
    }
    @objc func cancelWork() { operation?.cancel(); searchOperation?.cancel(); indexOperation?.cancel(); status.stringValue = L10n.text("Cancelled") }
    deinit { operation?.cancel(); searchOperation?.cancel(); indexOperation?.cancel(); if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) } }
}
