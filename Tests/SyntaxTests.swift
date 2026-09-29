import XCTest
@testable import QuietGlyph

final class SyntaxTests: XCTestCase {
    @MainActor func testActualLexerLanguageFixtures() throws {
        struct Fixture: Decodable { var language: String; var source: String; var role: String; var multiline: Bool; var minimumFolds: Int }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/language-behavior.json")
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        var languages = Dictionary(uniqueKeysWithValues: LanguageRegistry.shared.languages.map { ($0.id, $0) })
        if var php = languages["php"] { php.embedded = []; languages["php-code"] = php }
        for fixture in fixtures {
            let language = try XCTUnwrap(languages[fixture.language])
            let parsed = NativeLexer.parse(fixture.source, language: language, languages: languages)
            if !fixture.role.isEmpty { XCTAssertTrue(parsed.flatMap(\.tokens).contains { $0.role.rawValue == fixture.role }, fixture.language) }
            if fixture.multiline { XCTAssertTrue(parsed.contains { !$0.outgoing.delimiter.isEmpty }, fixture.language) }
            XCTAssertEqual(parsed.last?.outgoing.delimiter, "", fixture.language)
            XCTAssertGreaterThanOrEqual(FoldingController.regions(in: fixture.source, language: language, parsed: parsed).count, fixture.minimumFolds, fixture.language)
        }
        XCTAssertEqual(Set(fixtures.map(\.language)), Set(languages.keys.filter { $0 != "php-code" }))
    }
    @MainActor func testHeredocEndMustOccupyTheWholeLineAndPythonStringDoesNotEndFold() {
        let shell = NativeLexer.parse("cat <<EOF\nEOF_text\nEOF\n", language: LanguageRegistry.shared.language("bash"))
        XCTAssertEqual(shell[1].outgoing.delimiter, "EOF"); XCTAssertEqual(shell[2].outgoing.delimiter, "")
        let python = LanguageRegistry.shared.language("python")
        let source = "def f():\n    text = \"\"\"first\nno indent\n\"\"\"\n    return text\nafter = 1\n"
        let folds = FoldingController.regions(in: source, language: python)
        XCTAssertTrue(folds.contains { $0.header.location == 0 && (source as NSString).substring(with: $0.hidden).contains("return text") })
    }
    func testMultilineCommentsAndStringsCarryState() {
        var language = LanguageDefinition.plain
        language.id = "test"; language.keywords = ["let"]; language.lineComment = "//"
        language.blockCommentStart = "/*"; language.blockCommentEnd = "*/"
        let first = NativeLexer.line("let x = /* comment\n", language: language, incoming: LexicalState())
        XCTAssertEqual(first.outgoing.delimiter, "*/")
        XCTAssertTrue(first.tokens.contains { $0.role == .keyword })
        let second = NativeLexer.line("continued */ \"value\"\n", language: language, incoming: first.outgoing)
        XCTAssertTrue(second.outgoing.delimiter.isEmpty)
        XCTAssertTrue(second.tokens.contains { $0.role == .comment })
        XCTAssertTrue(second.tokens.contains { $0.role == .string })
    }
    @MainActor func testEveryBundledLanguageValidates() throws {
        XCTAssertGreaterThanOrEqual(LanguageRegistry.shared.languages.count, 47)
        for language in LanguageRegistry.shared.languages { try language.validate() }
        XCTAssertEqual(LanguageRegistry.shared.detect(URL(fileURLWithPath: "/tmp/file.py")).id, "python")
    }
}
