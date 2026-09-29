import Foundation
import CoreFoundation

enum TextEncoding: String, Codable, CaseIterable, Identifiable, Sendable {
    case utf8, utf16LE, utf16BE, gbk, gb18030, big5
    var id: String { rawValue }
    var title: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf16LE: return "UTF-16 LE"
        case .utf16BE: return "UTF-16 BE"
        case .gbk: return "GBK"
        case .gb18030: return "GB18030"
        case .big5: return "Big5"
        }
    }
    var value: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .utf16LE: return .utf16LittleEndian
        case .utf16BE: return .utf16BigEndian
        case .gbk: return Self.cf(CFStringEncodings.GBK_95.rawValue)
        case .gb18030: return Self.cf(CFStringEncodings.GB_18030_2000.rawValue)
        case .big5: return Self.cf(CFStringEncodings.big5.rawValue)
        }
    }
    private static func cf(_ value: Int) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(value)))
    }
    var bom: Data {
        switch self {
        case .utf8: return Data([0xEF, 0xBB, 0xBF])
        case .utf16LE: return Data([0xFF, 0xFE])
        case .utf16BE: return Data([0xFE, 0xFF])
        default: return Data()
        }
    }
}

enum LineEnding: String, Codable, CaseIterable, Identifiable, Sendable {
    case lf, crlf, cr
    var id: String { rawValue }
    var text: String { self == .crlf ? "\r\n" : self == .cr ? "\r" : "\n" }
    var title: String { self == .crlf ? "CRLF" : self == .cr ? "CR" : "LF" }
    static func detect(_ text: String) -> LineEnding {
        let s = text as NSString
        let r = s.rangeOfCharacter(from: .newlines)
        guard r.location != NSNotFound else { return .lf }
        if s.character(at: r.location) == 13 {
            return r.location + 1 < s.length && s.character(at: r.location + 1) == 10 ? .crlf : .cr
        }
        return .lf
    }
    func converting(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: self.text)
    }
}

enum DocumentMode: String, Codable, Sendable { case text, largeText, hex }

struct DocumentMetadata: Codable, Equatable, Sendable {
    var encoding: TextEncoding = .utf8
    var hasBOM = false
    var lineEnding: LineEnding = .lf
    var languageID = "txt"
}

enum EditorError: LocalizedError {
    case decoding, encoding(String), invalidRange, readOnly, externalChange, invalidDefinition(String)
    var errorDescription: String? {
        switch self {
        case .decoding: return L10n.text("The file cannot be decoded. Choose an encoding or open it as hexadecimal.")
        case .encoding(let name): return L10n.format("Some characters cannot be saved as %@. Choose a Unicode encoding.", name)
        case .invalidRange: return L10n.text("The selection is no longer valid. Try the command again.")
        case .readOnly: return L10n.text("This document is open in read-only mode.")
        case .externalChange: return L10n.text("The file changed on disk. Reload it or use Save As to preserve both versions.")
        case .invalidDefinition(let reason): return L10n.format("Invalid language definition: %@", L10n.text(reason))
        }
    }
}
