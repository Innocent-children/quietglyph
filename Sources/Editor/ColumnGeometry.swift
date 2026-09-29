import Foundation

enum ColumnGeometry {
    struct Position {
        var offset: Int
        var column: Int
        var width: Int
        var length: Int
        var isTab: Bool
    }

    static func width(of character: Character, column: Int, tabWidth: Int) -> Int {
        if character == "\t" { return max(1, tabWidth) - column % max(1, tabWidth) }
        let scalars = character.unicodeScalars
        if scalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }) { return 2 }
        guard let value = scalars.first?.value else { return 0 }
        return (0x1100...0x115F).contains(value) || (0x2E80...0xA4CF).contains(value) ||
            (0xAC00...0xD7A3).contains(value) || (0xF900...0xFAFF).contains(value) ||
            (0xFE10...0xFE6F).contains(value) || (0xFF01...0xFF60).contains(value) ||
            (0x20000...0x3FFFF).contains(value) ? 2 : 1
    }

    static func positions(_ text: String, tabWidth: Int = 4) -> [Position] {
        var offset = 0, column = 0
        var result: [Position] = []
        for character in text {
            let length = String(character).utf16.count
            let cells = width(of: character, column: column, tabWidth: tabWidth)
            result.append(Position(offset: offset, column: column, width: cells, length: length, isTab: character == "\t"))
            offset += length; column += cells
        }
        result.append(Position(offset: offset, column: column, width: 0, length: 0, isTab: false))
        return result
    }

    static func column(at offset: Int, in text: String, tabWidth: Int = 4) -> Int {
        positions(text, tabWidth: tabWidth).last(where: { $0.offset <= offset })?.column ?? 0
    }

    static func position(at column: Int, in text: String, tabWidth: Int = 4) -> Position {
        positions(text, tabWidth: tabWidth).last(where: { $0.column <= max(0, column) })!
    }

    static func range(_ columns: ClosedRange<Int>, in text: String, tabWidth: Int = 4) -> NSRange {
        let start = position(at: columns.lowerBound, in: text, tabWidth: tabWidth)
        let end = position(at: columns.upperBound, in: text, tabWidth: tabWidth)
        let upper = end.offset + (columns.upperBound > end.column && columns.upperBound > columns.lowerBound ? end.length : 0)
        return NSRange(location: start.offset, length: max(0, upper - start.offset))
    }

    /**
     * Split a tab only when writing through it; selecting virtual space never changes the document.
     */
    static func edit(_ columns: ClosedRange<Int>, in text: String, replacement: String, tabWidth: Int = 4) -> TextEdit {
        let start = position(at: columns.lowerBound, in: text, tabWidth: tabWidth)
        let end = position(at: columns.upperBound, in: text, tabWidth: tabWidth)
        var range = range(columns, in: text, tabWidth: tabWidth)
        var prefix = "", suffix = ""
        if start.length == 0 {
            if !replacement.isEmpty { prefix = String(repeating: " ", count: max(0, columns.lowerBound - start.column)) }
        } else if start.isTab && columns.lowerBound > start.column {
            prefix = String(repeating: " ", count: columns.lowerBound - start.column)
        }
        if end.isTab && columns.upperBound > end.column {
            range.length = max(range.length, end.offset + end.length - range.location)
            suffix = String(repeating: " ", count: max(0, end.column + end.width - columns.upperBound))
        }
        return TextEdit(range: range, replacement: prefix + replacement + suffix)
    }
}
