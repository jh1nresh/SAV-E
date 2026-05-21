import Foundation

struct SocialOCRCandidateResult {
    var name: String
    var confidence: Double
}

enum SocialOCRCandidateHeuristics {
    static func candidate(from lines: [String]) -> SocialOCRCandidateResult? {
        let cleanedLines = lines
            .map(cleanLine)
            .filter(isUsableLine)

        if let cafeLine = cleanedLines.first(where: { line in
            line.range(of: #"(?i)\b(coffee|cafe|bakery|bistro|restaurant|bar|tea)\b"#, options: .regularExpression) != nil &&
            !looksLikeMarketingOrProductLine(line)
        }) {
            return SocialOCRCandidateResult(name: cafeLine, confidence: 0.44)
        }

        if let uppercaseBrand = cleanedLines.first(where: { line in
            line.range(of: #"^[A-Z][A-Z0-9 &'._-]{2,30}$"#, options: .regularExpression) != nil &&
            !looksLikeMarketingOrProductLine(line)
        }) {
            return SocialOCRCandidateResult(name: uppercaseBrand, confidence: 0.4)
        }

        return nil
    }

    private static func cleanLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”.,:;! "))
    }

    private static func isUsableLine(_ value: String) -> Bool {
        value.count >= 2 && value.count <= 60
    }

    private static func looksLikeMarketingOrProductLine(_ value: String) -> Bool {
        let patterns = [
            #"台南爆漿巴斯克|巴斯克控不能錯過|不要說你吃過巴斯克蛋糕|一入口直接幸福感爆棚"#,
            #"(?i)must try|don't miss|best|viral|save this|follow|like|comment"#,
            #"(?i)\b(basque|cake|dessert)\b(?!.*\b(coffee|cafe|bakery|bistro|restaurant|bar|tea)\b)"#
        ]
        return patterns.contains { pattern in
            value.range(of: pattern, options: [.regularExpression]) != nil
        }
    }
}
