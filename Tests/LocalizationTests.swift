import XCTest
@testable import QuietGlyph

final class LocalizationTests: XCTestCase {
    @MainActor func testFileNamesAreNotTranslatedAsCommands() {
        let file = AppKitControlFactory.menuItem(title: "Copy", selector: nil, localizeTitle: false)
        let command = AppKitControlFactory.menuItem(title: "Copy", selector: nil)
        XCTAssertEqual(file.title, "Copy")
        XCTAssertEqual(command.title, L10n.text("Copy"))
    }

    func testLanguageDefaultsToChineseAndPersistsSelection() {
        let suite = "quietglyph.localization.unit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(InterfaceLanguage.saved(in: defaults), .simplifiedChinese)
        defaults.set(InterfaceLanguage.english.rawValue, forKey: InterfaceLanguage.defaultsKey)
        XCTAssertEqual(InterfaceLanguage.saved(in: UserDefaults(suiteName: suite)!), .english)
    }

    func testBothBundlesContainTheSameKeysAndFormatArguments() throws {
        func strings(_ language: InterfaceLanguage) throws -> [String: String] {
            let url = try XCTUnwrap(L10n.bundle(for: language).url(forResource: "Localizable", withExtension: "strings"))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
        }
        let english = try strings(.english)
        let chinese = try strings(.simplifiedChinese)
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        let placeholders = try NSRegularExpression(pattern: "%(?:[0-9]+\\$)?(?:ll|l)?[@du]")
        func arguments(_ text: String) -> [String] {
            placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }
        }
        for (key, value) in english {
            let translated = try XCTUnwrap(chinese[key])
            XCTAssertFalse(translated.isEmpty, key)
            XCTAssertEqual(arguments(value), arguments(translated), key)
        }
        for command in TextCommand.allCases { XCTAssertNotNil(chinese[command.rawValue], command.rawValue) }
        for command in LineCommand.allCases { XCTAssertNotNil(chinese[command.rawValue], command.rawValue) }
        XCTAssertEqual(chinese["Settings"], "设置")
        XCTAssertEqual(english["Settings"], "Settings")
        XCTAssertEqual(String(format: try XCTUnwrap(chinese["Ln %ld, Col %ld"]), 12, 3), "第 12 行，第 3 列")
    }
}
