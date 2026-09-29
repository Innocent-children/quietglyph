import AppKit
import SwiftUI

@MainActor
final class AppearancePolicy: ObservableObject {
    static let shared = AppearancePolicy()
    @Published private(set) var reduceMotion = false
    @Published private(set) var reduceTransparency = false
    private var observer: NSObjectProtocol?
    var duration: Double {
        if reduceMotion || SettingsStore.shared.values.reduceMotion { return 0 }
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? 0.18 :
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? 0.10 : 0
    }
    var animation: Animation? { duration == 0 ? nil : .easeInOut(duration: duration) }
    init() {
        refresh()
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
    private func refresh() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }
}
