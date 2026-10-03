import XCTest
import AppKit
@testable import Inkline

final class StyleSettingsTests: XCTestCase {
    @MainActor func testSemanticStylesInheritAndRoundTrip() throws {
        let store = SettingsStore.shared, original = SettingsStore.shared.values
        defer { store.values = original }
        store.values.syntaxStyles["*"] = ["keyword": SyntaxStyle(foreground: "#123456", fontSize: 19, bold: true)]
        store.values.syntaxStyles["lua"] = ["keyword": SyntaxStyle(italic: true)]
        let style = store.syntaxAttributes(language: "lua", role: .keyword)
        XCTAssertEqual((style[.font] as? NSFont)?.pointSize, 19)
        XCTAssertEqual(style[.foregroundColor] as? NSColor, NSColor(hex: "#123456"))
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(store.values))
        XCTAssertEqual(decoded.syntaxStyles, store.values.syntaxStyles)
        store.values.largeFileThresholdMB = 50
        XCTAssertEqual(DocumentIO.editableLimit, 50 * 1024 * 1024)
        store.values.largeFileThresholdMB = 600
        XCTAssertEqual(DocumentIO.editableLimit, 600 * 1024 * 1024)
    }
}
