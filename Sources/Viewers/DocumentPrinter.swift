import AppKit

@MainActor
enum DocumentPrinter {
    static func printDocument(_ document: TextDocument, window: NSWindow) {
        let info = document.printInfo
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        text.isRichText = false
        text.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        text.string = document.editor?.textView.string ?? document.initialText
        text.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.sizeToFit()
        let operation = NSPrintOperation(view: text, printInfo: info)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
