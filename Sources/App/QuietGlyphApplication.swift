import AppKit

@MainActor
final class NativeApplication: NSApplication {
    override func terminate(_ sender: Any?) {
        (delegate as? AppDelegate)?.prepareTermination()
        super.terminate(sender)
        (delegate as? AppDelegate)?.cancelTermination()
    }
}

@main
enum QuietGlyphApplication {
    static let isTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing") ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    @MainActor static func main() {
        L10n.configureApplication()
        if isTesting {
            var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            arguments["ApplePersistenceIgnoreState"] = true
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        let application = NativeApplication.shared
        let documents = DocumentController()
        let delegate = AppDelegate(documents: documents)
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}
