import SwiftUI
import AppKit

struct ShortcutSettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @State private var filter = ""
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading) {
            TextField(L10n.text("Filter commands"), text: $filter)
            Text(L10n.text("Click a shortcut to record it. Use Command or Control with a key. Escape cancels; Delete restores the default."))
                .font(.caption).foregroundStyle(.secondary)
            List(MenuController.shortcutEntries.filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) }) { item in
                HStack {
                    Text(item.title).lineLimit(1)
                    Spacer()
                    ShortcutRecorder(value: settings.values.shortcuts[item.id]) { binding in
                        if let binding, let conflict = settings.values.shortcuts.first(where: { $0.key != item.id && $0.value == binding }) {
                            message = L10n.format("This shortcut is assigned to %@", MenuController.shortcutEntries.first { $0.id == conflict.key }?.title ?? conflict.key)
                            return
                        }
                        settings.values.shortcuts[item.id] = binding
                        message = ""
                    }.frame(width: 130, height: 25)
                }
            }
            Text(message).font(.caption).foregroundStyle(.red)
            Button(L10n.text("Reset Shortcuts")) { settings.values.shortcuts = [:]; message = "" }
        }.padding(12)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    var value: KeyBinding?
    var onRecord: (KeyBinding?) -> Void
    func makeNSView(context: Context) -> ShortcutCaptureButton { ShortcutCaptureButton() }
    func updateNSView(_ view: ShortcutCaptureButton, context: Context) {
        view.onRecord = onRecord
        view.binding = value
        if !view.recording { view.updateTitle() }
    }
}

@MainActor
private final class ShortcutCaptureButton: NSButton {
    var onRecord: ((KeyBinding?) -> Void)?
    var binding: KeyBinding?
    private var monitor: Any?
    private(set) var recording = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self; action = #selector(record)
        bezelStyle = .rounded
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func updateTitle() {
        guard let binding else { title = L10n.text("Default"); return }
        let flags = NSEvent.ModifierFlags(rawValue: binding.modifiers)
        title = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") +
            (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + binding.key.uppercased()
    }
    @objc private func record() {
        guard !recording else { return }
        recording = true; title = L10n.text("Press shortcut…")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window == self.window else { return false }
                if event.keyCode == 53 { self.finish(); return true }
                if event.keyCode == 51 { self.onRecord?(nil); self.finish(); return true }
                let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard flags.contains(.command) || flags.contains(.control), let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else { NSSound.beep(); return true }
                self.onRecord?(KeyBinding(key: key, modifiers: flags.rawValue))
                self.finish()
                return true
            }
            return handled ? nil : event
        }
    }
    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; recording = false; updateTitle()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { finish() }
        super.viewWillMove(toWindow: newWindow)
    }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
