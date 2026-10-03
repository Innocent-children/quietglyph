import AppKit

@MainActor
final class ExternalChangeBanner: NSStackView {
    private let message = NSTextField(wrappingLabelWithString: "")
    private let reloadButton: NSButton
    private let saveAsButton: NSButton

    init(target: AnyObject, reload: Selector, saveAs: Selector) {
        reloadButton = NSButton(title: L10n.text("Reload"), target: target, action: reload)
        saveAsButton = NSButton(title: L10n.text("Save As…"), target: target, action: saveAs)
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6
        edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        message.setAccessibilityIdentifier("externalChangeMessage")
        reloadButton.setAccessibilityIdentifier("reloadExternalChange")
        saveAsButton.setAccessibilityIdentifier("saveExternalChangeAs")
        addArrangedSubview(message)
        message.widthAnchor.constraint(equalTo: widthAnchor, constant: -24).isActive = true
        addArrangedSubview(NSStackView(views: [reloadButton, saveAsButton]))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(state: TextDocument.ExternalFileState, edited: Bool, editable: Bool) {
        isHidden = state == .unchanged
        if state == .unavailable {
            message.stringValue = L10n.text("The file was moved, deleted, or cannot be accessed. Your open content is preserved.")
        } else if edited {
            message.stringValue = L10n.text("The file changed on disk. Your unsaved edits are preserved. Reload or save them to another file.")
        } else {
            message.stringValue = L10n.text("The file changed on disk. Reload to see the latest version.")
        }
        reloadButton.isEnabled = state == .changed
        saveAsButton.isHidden = !editable
    }
}
