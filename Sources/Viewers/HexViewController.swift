import AppKit

@MainActor
final class HexViewController: LargeTextViewController {
    override var isHex: Bool { true }
    private var lastBytes = Data()
    private var matchOffset: UInt64?
    override func findText() {
        guard let reader else { return }
        let raw = searchField.stringValue.filter { !$0.isWhitespace }
        guard !raw.isEmpty, raw.count % 2 == 0 else { status.stringValue = L10n.text("Enter complete hexadecimal bytes."); return }
        var bytes = Data()
        var cursor = raw.startIndex
        while cursor < raw.endIndex {
            let end = raw.index(cursor, offsetBy: 2)
            guard let byte = UInt8(raw[cursor..<end], radix: 16) else { status.stringValue = L10n.text("Invalid hexadecimal byte."); return }
            bytes.append(byte); cursor = end
        }
        let start = bytes == lastBytes ? (matchOffset.map { $0 + 1 } ?? 0) : 0
        lastBytes = bytes
        searchOperation?.cancel()
        let needle = bytes
        searchOperation = Task.detached {
            if let found = try await reader.findBytes(needle, after: start) { return found }
            return start > 0 ? try await reader.findBytes(needle, after: 0) : nil
        }
        operation?.cancel()
        operation = Task {
            do {
                guard let result = try await searchOperation?.value else { status.stringValue = L10n.text("No matches"); return }
                try Task.checkCancellation()
                matchOffset = result; history.append(offset); loadPage(result)
            } catch { status.stringValue = error.localizedDescription }
        }
    }
    nonisolated static func format(_ data: Data, offset: UInt64) -> String {
        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count, by: 16).map { start in
            let row = Array(bytes[start..<min(bytes.count, start + 16)])
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ").padding(toLength: 47, withPad: " ", startingAt: 0)
            let ascii = row.map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            return String(format: "%012llX", offset + UInt64(start)) + "  " + hex + "  │" + ascii + "│"
        }.joined(separator: "\n")
    }
}
