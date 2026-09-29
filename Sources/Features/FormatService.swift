import Foundation

enum FormatService {
    static func json(_ text: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
    static func xml(_ text: String) throws -> String {
        let document = try XMLDocument(xmlString: text, options: .nodeLoadExternalEntitiesNever)
        return document.xmlString(options: .nodePrettyPrint)
    }
}
