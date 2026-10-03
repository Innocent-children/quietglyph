import Foundation

@MainActor
final class DocumentFileMonitor {
    private let url: URL
    private let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pendingCheck: Task<Void, Never>?
    private var stopped = false

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        attachSources()
    }

    private func attachSources() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        // The directory survives atomic replacement and deletion of the watched file.
        for path in [url, url.deletingLastPathComponent()] {
            let descriptor = open(path.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke], queue: .main)
            source.setCancelHandler { Darwin.close(descriptor) }
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleCheck() }
            }
            source.resume()
            sources.append(source)
        }
    }

    private func scheduleCheck() {
        guard !stopped else { return }
        // Coalesce a writer's replace/rename sequence without postponing checks indefinitely.
        guard pendingCheck == nil else { return }
        pendingCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, !self.stopped else { return }
            self.pendingCheck = nil
            self.attachSources()
            self.onChange()
        }
    }

    func stop() {
        stopped = true
        pendingCheck?.cancel()
        pendingCheck = nil
        sources.forEach { $0.cancel() }
        sources.removeAll()
    }

    deinit { sources.forEach { $0.cancel() }; pendingCheck?.cancel() }
}
