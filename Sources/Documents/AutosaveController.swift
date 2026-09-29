import AppKit

@MainActor
final class AutosaveController {
    private let documents: () -> [TextDocument]
    private let now: () -> TimeInterval
    private var timer: Timer?
    private var lastRun: TimeInterval = 0
    private(set) var enabled = false
    private var saving = false
    var onError: (TextDocument, Error) -> Void = { document, error in document.presentError(error) }
    init(documents: @escaping () -> [TextDocument], now: @escaping () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }) {
        self.documents = documents; self.now = now
    }
    func configure(enabled: Bool, scheduleTimer: Bool = true) {
        guard self.enabled != enabled || enabled && timer == nil else { return }
        timer?.invalidate(); timer = nil
        self.enabled = enabled; lastRun = now()
        if enabled && scheduleTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in guard let self else { return }; await self.tick(at: self.now()) }
            }
        }
    }
    func tick(at time: TimeInterval) async {
        guard enabled, !saving, time - lastRun >= 180 else { return }
        lastRun = time; saving = true
        defer { saving = false }
        for document in documents() {
            guard enabled, documents().contains(where: { $0 === document }), document.mode == .text,
                  document.isDocumentEdited, document.fileURL != nil, document.editor?.textView.isComposing != true else { continue }
            if let error = await document.saveTimed() { onError(document, error) }
        }
    }
    func stop() { timer?.invalidate(); timer = nil; enabled = false }
    deinit { timer?.invalidate() }
}
