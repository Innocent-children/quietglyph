import AppKit

@MainActor
final class EditorTextStorageObserver: NSObject, @preconcurrency NSTextStorageDelegate {
    weak var editor: EditorController?
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        editor?.textDidMutate()
    }
}
