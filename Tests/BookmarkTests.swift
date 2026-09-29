import XCTest
@testable import QuietGlyph

final class BookmarkTests: XCTestCase {
    func testBookmarksTrackInsertionAndDeletion() {
        let store = BookmarkStore()
        store.toggle(4); store.toggle(8)
        store.apply([TextEdit(range: NSRange(location: 0, length: 0), replacement: "🙂")])
        XCTAssertEqual(store.offsets, [6, 10])
        store.apply([TextEdit(range: NSRange(location: 4, length: 4), replacement: "")])
        XCTAssertEqual(store.offsets, [4, 6])
        XCTAssertEqual(store.next(after: 6), 4)
        XCTAssertEqual(store.next(after: 4, backwards: true), 6)
    }
}
