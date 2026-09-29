import Foundation

struct DecodedText: Sendable {
    var text: String
    var metadata: DocumentMetadata
}

enum FileCodec {
    static func decode(_ data: Data, preferred: TextEncoding? = nil) throws -> DecodedText {
        var encoding = preferred
        var payload = data
        var hasBOM = false
        for candidate in [TextEncoding.utf8, .utf16LE, .utf16BE] {
            if data.starts(with: candidate.bom), preferred == nil || preferred == candidate {
                encoding = candidate
                payload = data.dropFirst(candidate.bom.count)
                hasBOM = true
                break
            }
        }
        if encoding == nil {
            let sample = [UInt8](data.prefix(4096))
            if sample.count >= 4 {
                let pairs = sample.count / 2
                let oddZeros = stride(from: 1, to: pairs * 2, by: 2).filter { sample[$0] == 0 }.count
                let evenZeros = stride(from: 0, to: pairs * 2, by: 2).filter { sample[$0] == 0 }.count
                if oddZeros > pairs / 3 { encoding = .utf16LE }
                else if evenZeros > pairs / 3 { encoding = .utf16BE }
            }
        }
        let candidates = encoding.map { [$0] } ?? [.utf8, .gb18030, .big5]
        for candidate in candidates {
            guard let text = String(data: payload, encoding: candidate.value) else { continue }
            var metadata = DocumentMetadata()
            metadata.encoding = candidate
            metadata.hasBOM = hasBOM
            metadata.lineEnding = .detect(text)
            return DecodedText(text: text, metadata: metadata)
        }
        throw EditorError.decoding
    }

    static func encode(_ text: String, metadata: DocumentMetadata) throws -> Data {
        guard let encoded = text.data(using: metadata.encoding.value, allowLossyConversion: false) else {
            throw EditorError.encoding(metadata.encoding.title)
        }
        var result = metadata.hasBOM ? metadata.encoding.bom : Data()
        result.append(encoded)
        return result
    }

}
