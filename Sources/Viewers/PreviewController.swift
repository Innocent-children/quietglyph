import AppKit

@MainActor
final class PreviewController: NSWindowController {
    let textView = NSTextView(usingTextLayoutManager: true)
    init() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        textView.isEditable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = .width
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 28, height: 24)
        scroll.documentView = textView
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L10n.text("Markdown Preview")
        window.contentView = scroll
        super.init(window: window)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func render(_ source: String, baseURL: URL? = nil) {
        do { textView.textStorage?.setAttributedString(try MarkdownRenderer.render(source, baseURL: baseURL)) }
        catch { textView.string = error.localizedDescription }
    }
}
