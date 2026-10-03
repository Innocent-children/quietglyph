import Foundation

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var title: String { self == .simplifiedChinese ? "简体中文" : "English" }

    static let defaultsKey = "interfaceLanguage"
    static func saved(in defaults: UserDefaults) -> InterfaceLanguage {
        InterfaceLanguage(rawValue: defaults.string(forKey: defaultsKey) ?? "") ?? .simplifiedChinese
    }
}

enum L10n {
    static let defaults: UserDefaults = {
        if InklineApplication.isTesting {
            let suite = ProcessInfo.processInfo.environment["INKLINE_TEST_DEFAULTS"] ?? "com.innocentchildren.inkline.testing"
            return UserDefaults(suiteName: suite)!
        }
        return .standard
    }()

    // Keep one language for the process, including AppKit's cached system panels.
    static let language = InterfaceLanguage.saved(in: defaults)

    static func configureApplication() {
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["AppleLanguages"] = [language.rawValue]
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }

    static func bundle(for language: InterfaceLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    private static let currentBundle = bundle(for: language)

    static func text(_ key: String) -> String {
        currentBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}
