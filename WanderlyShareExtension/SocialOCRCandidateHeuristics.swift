import Foundation

struct SocialOCRCandidateResult {
    var name: String
    var confidence: Double
    var supportingLines: [String] = []
}

enum SocialOCRCandidateHeuristics {
    static func candidate(from lines: [String]) -> SocialOCRCandidateResult? {
        let cleanedLines = lines
            .map(cleanLine)
            .filter(isUsableLine)

        if let pairedBrand = bestPairedBrand(in: cleanedLines) {
            return pairedBrand
        }

        if let cjkVenue = cleanedLines.first(where: looksLikeCJKVenueName) {
            return SocialOCRCandidateResult(name: cjkVenue, confidence: 0.48, supportingLines: [cjkVenue])
        }

        if let cafeLine = cleanedLines.first(where: { line in
            line.range(of: #"(?i)\b(coffee|cafe|bakery|bistro|restaurant|bar|tea)\b"#, options: .regularExpression) != nil &&
            !SocialPlaceEvidenceScorer.isRejectedTitle(line)
        }) {
            return SocialOCRCandidateResult(name: cafeLine, confidence: 0.46, supportingLines: [cafeLine])
        }

        if let uppercaseBrand = cleanedLines.first(where: { line in
            line.range(of: #"^[A-Z][A-Z0-9 &'._-]{2,30}$"#, options: .regularExpression) != nil &&
            !SocialPlaceEvidenceScorer.isRejectedTitle(line)
        }) {
            return SocialOCRCandidateResult(name: uppercaseBrand, confidence: 0.42, supportingLines: [uppercaseBrand])
        }

        return nil
    }

    private static func bestPairedBrand(in lines: [String]) -> SocialOCRCandidateResult? {
        guard lines.count > 1 else { return nil }
        for index in lines.indices {
            let line = lines[index]
            guard line.range(of: #"^[A-Z][A-Z0-9 &'._-]{2,30}$"#, options: .regularExpression) != nil,
                  !SocialPlaceEvidenceScorer.isRejectedTitle(line) else { continue }
            let neighbors = [index - 1, index + 1]
                .filter { lines.indices.contains($0) }
                .map { lines[$0] }
            if neighbors.contains(where: looksLikeVenueDescriptor) {
                return SocialOCRCandidateResult(name: line, confidence: 0.5, supportingLines: [line] + neighbors)
            }
        }
        return nil
    }

    private static func looksLikeVenueDescriptor(_ value: String) -> Bool {
        value.range(of: #"(?i)\b(coffee|cafe|bakery|bistro|restaurant|bar|tea|brunch|basque|dessert)\b"#, options: .regularExpression) != nil
    }

    private static func looksLikeCJKVenueName(_ value: String) -> Bool {
        let cjkScriptPattern = #"[\p{Han}\u3040-\u30FF\uAC00-\uD7AF]"#
        let stayKeywordPattern = #"\b(hotel|resort|inn|guest ?house|ryokan|motel)\b|酒店|飯店|饭店|旅館|旅馆|旅店|旅宿|民宿|客棧|客栈|度假村|ホテル|ゲストハウス|료칸|호텔|리조트|모텔|여관|여인숙|게스트하우스"#
        guard !SocialPlaceEvidenceScorer.isRejectedTitle(value) else { return false }
        guard value.range(of: cjkScriptPattern, options: .regularExpression) != nil else { return false }
        guard value.range(of: stayKeywordPattern, options: [.regularExpression, .caseInsensitive]) != nil else { return false }

        let rejectedFragments = [
            #"\d{1,2}:\d{2}"#,
            #"早餐|午餐|晚餐|吃到|泳池|海景|浴缸|退房|入住|不用早起|推薦|攻略|必住|開箱"#
        ]
        return !rejectedFragments.contains { pattern in
            value.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func cleanLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”.,:;! "))
    }

    private static func isUsableLine(_ value: String) -> Bool {
        value.count >= 2 && value.count <= 60
    }
}
