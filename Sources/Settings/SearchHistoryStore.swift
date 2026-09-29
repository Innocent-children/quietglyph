import Foundation

@MainActor
final class SearchHistoryStore {
    static let shared = SearchHistoryStore()
    private let defaults: UserDefaults
    init(defaults: UserDefaults? = nil) { self.defaults = defaults ?? L10n.defaults }
    var searches: [String] { defaults.stringArray(forKey: "searchHistory") ?? [] }
    var replacements: [String] { defaults.stringArray(forKey: "replacementHistory") ?? [] }
    func remember(_ query: SearchQuery) {
        if !query.text.isEmpty { defaults.set(Array(([query.text] + searches.filter { $0 != query.text }).prefix(30)), forKey: "searchHistory") }
        defaults.set(Array(([query.replacement] + replacements.filter { $0 != query.replacement }).prefix(30)), forKey: "replacementHistory")
    }
}
