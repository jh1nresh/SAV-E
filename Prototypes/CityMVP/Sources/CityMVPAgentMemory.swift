#if SAVVY_CITY_MVP || SAVVY_CITY_MCP
import Foundation

nonisolated struct CityMVPAgentMemory: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let address: String
    let category: String
    let state: String
}

nonisolated enum CityMVPAgentSearch {
    static func terms(_ query: String) -> [String] {
        guard query.count <= 240 else { return [] }
        let locale = Locale(identifier: "en_US_POSIX")
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var text = query.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .trimmingCharacters(in: separators)
        let prefixes = ["what did i save in ", "find my saved ", "show my saved ", "我在", "找我收藏的", "我收藏的"]
        for prefix in prefixes where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
            break
        }
        for suffix in ["收藏了什麼", "有哪些收藏", "有什麼收藏", "收藏的"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
            break
        }
        return text.components(separatedBy: separators)
            .filter { !$0.isEmpty && !["what", "did", "i", "save", "in", "find", "show", "my", "saved"].contains($0) }
    }

    static func matches(_ query: String, in memory: [CityMVPAgentMemory]) -> [CityMVPAgentMemory] {
        let tokens = terms(query)
        guard !tokens.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        let locale = Locale(identifier: "en_US_POSIX")
        return Array(memory.lazy.filter { place in
            guard place.state == "confirmed" else { return false }
            let fields = [place.name, place.address, place.category]
            return tokens.allSatisfy { term in
                fields.contains { $0.range(of: term, options: options, locale: locale) != nil }
            }
        }.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }.prefix(5))
    }
}
#endif
