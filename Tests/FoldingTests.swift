import XCTest
import AppKit
@testable import QuietGlyph

final class FoldingTests: XCTestCase {
    func testMarkupFoldRangesKeepTagsInTheSource() {
        var language = LanguageDefinition.plain; language.id = "xml"; language.folding = "markup"
        let text = "<root>\n<child/>\n</root>\n"
        let regions = FoldingController.regions(in: text, language: language)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual((text as NSString).substring(with: regions[0].hidden), "<child/>\n")
    }
    func testFoldRangesExcludeBracesInStringsAndComments() {
        var language = LanguageDefinition.plain
        language.id = "test"; language.folding = "braces"; language.lineComment = "//"
        let source = "{\n  \"}\"\n  // }\n  value\n}\n"
        let folds = FoldingController.regions(in: source, language: language)
        XCTAssertEqual(folds.count, 1)
        XCTAssertEqual((source as NSString).substring(with: folds[0].hidden), "  \"}\"\n  // }\n  value\n")
    }
    @MainActor func testFoldingNeverChangesSavedText() throws {
        let document = TextDocument()
        document.initialText = "{\n  value\n}\n"
        let editor = EditorController(document: document); document.editor = editor; _ = editor.view
        var language = LanguageDefinition.plain; language.id = "braces"; language.folding = "braces"
        editor.language = language
        editor.folding.collapseAll()
        XCTAssertEqual(editor.textView.string, document.initialText)
        XCTAssertEqual(try TextFileCodec.decode(document.data(ofType: "public.plain-text")).text, document.initialText)
        editor.folding.expandAll()
        document.close()
    }
}
