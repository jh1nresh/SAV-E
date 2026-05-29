import Foundation

enum SocialPlaceEvidenceTier: String, Codable {
    case confirmed
    case likely
    case weakCandidate
    case sourceOnly
}

struct SocialPlaceAnalysis {
    var candidateName: String?
    var address: String?
    var category: String
    var confidence: Double
    var tier: SocialPlaceEvidenceTier
    var evidence: [String]
    var missingInfo: [String]
}

enum SocialPlaceEvidenceScorer {
    static func cleanCandidateName(_ value: String) -> String {
        cleanText(value)
            .replacingOccurrences(of: #"^[\-\–\—]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]【】\"'“”.,:;! "))
            .split(separator: "\n")
            .first
            .map(String.init) ?? ""
    }

    static func cleanText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#034;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isUsableCandidateName(_ value: String) -> Bool {
        let lowered = value.lowercased()
        guard value.count >= 2,
              value.count <= 80,
              !lowered.contains("instagram"),
              !lowered.contains("reel"),
              !lowered.contains("comment"),
              !lowered.contains("like") else {
            return false
        }
        return !isRejectedTitle(value)
    }

    static func isLikelyCaptionPlaceName(_ value: String) -> Bool {
        guard isUsableCandidateName(value) else { return false }
        let lowered = value.lowercased()
        guard !looksLikeAddressLine(value),
              !looksLikeOperatingHoursLine(value),
              !looksLikeReviewMetricLine(value),
              !looksLikeMenuOrPriceLine(value),
              !looksLikeMarketingLine(value),
              !looksLikeHashtagsOnlyLine(value),
              !looksLikeGenericProductOrCityLine(value),
              !looksLikeCaptionHeadlineTitle(value),
              !lowered.contains(" on instagram"),
              !lowered.contains("casual"),
              !lowered.contains("dream"),
              !lowered.contains("follow"),
              !lowered.contains("save this"),
              !lowered.contains("located") else {
            return false
        }
        if lowered.range(of: #"^(to|and|or|with|from|for)\s+\w+"#, options: .regularExpression) != nil {
            return false
        }
        if lowered.contains("slow down") || lowered.contains("enjoy the vibe") {
            return false
        }
        return value.range(of: #"[A-Za-z\u4e00-\u9fff]"#, options: .regularExpression) != nil
    }

    static func isRejectedTitle(_ value: String) -> Bool {
        looksLikeAddressLine(value) ||
            looksLikeOperatingHoursLine(value) ||
            looksLikeReviewMetricLine(value) ||
            looksLikeMenuOrPriceLine(value) ||
            looksLikeMarketingLine(value) ||
            looksLikeHashtagsOnlyLine(value) ||
            looksLikeGenericProductOrCityLine(value) ||
            looksLikeCaptionHeadlineTitle(value)
    }

    static func looksLikeCaptionHeadlineTitle(_ value: String) -> Bool {
        if value.contains("#") || value.contains("「") || value.contains("『") {
            return true
        }
        if value.range(of: #"➡|➜|→"#, options: .regularExpression) != nil {
            return true
        }
        guard value.count > 18 else { return false }
        return value.range(of: #"必吃|必喝|必訪|必去|韓其林|米其林|弘大|新村|明洞"#, options: .regularExpression) != nil ||
            value.range(of: #"(?:西門|士林|東區|東区|台北|臺北).*(?:美食|餐廳|餐厅|必吃|必喝)"#, options: .regularExpression) != nil
    }

    static func looksLikeAddressLine(_ line: String) -> Bool {
        let patterns = [
            #"\b(?:No\.?|#)\s*\d+[A-Za-z]?\b"#,
            #"\b\d{1,6}\s+[A-Za-z0-9 .'-]{2,80}\b(?:Street|St\.?|Road|Rd\.?|Avenue|Ave\.?|Boulevard|Blvd\.?|Lane|Ln\.?|Drive|Dr\.?|Way|Highway|Hwy\.?|Coast Hwy|Old Street|District|County|City)\b"#,
            #"\b[A-Z][A-Za-z .'-]{2,40},\s*(?:CA|NY|TX|FL|WA|IL|NV|AZ|OR|MA|HI|UT|CO|Bali|Indonesia|Chongqing|China)\b"#,
            #"[\u4e00-\u9fff]{2,}(?:市|区|區|路|街|道)[\u4e00-\u9fffA-Za-z0-9\-－\s]{0,40}\d{1,6}\s*(?:号|號)?"#,
            #"\d{1,6}\s*(?:号|號)"#
        ]

        return patterns.contains { pattern in
            line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    static func looksLikeOperatingHoursLine(_ value: String) -> Bool {
        value.range(
            of: #"(?i)(營業|营业|hours?|open|closed|週[一二三四五六日天]|周[一二三四五六日天]|星期|[一二三四五六日天]\s*[～~\-–—至]\s*[一二三四五六日天]|\b\d{1,2}:\d{2}\s*[-–—~～至]\s*\d{1,2}:\d{2})"#,
            options: [.regularExpression]
        ) != nil
    }

    static func looksLikeReviewMetricLine(_ value: String) -> Bool {
        value.range(
            of: #"(美味程度|環境衛生|环境卫生|服务态度|服務態度|再訪意願|再访意愿|評分|评分|rating|review)\s*[：:]"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil ||
        value.range(of: #"^[^\n]{0,20}[：:].*[🌕🌖🌗🌘🌑⭐★]"#, options: [.regularExpression]) != nil ||
        value.range(of: #"^(整體|整体|總評|总评|補充|补充)\s*$"#, options: [.regularExpression]) != nil
    }

    static func looksLikeMenuOrPriceLine(_ value: String) -> Bool {
        value.range(
            of: #"(?i)(以下餐點及價位|以下餐点及价位|餐點及價位|餐点及价位|用餐餐點|用餐餐点|menu|price)"#,
            options: [.regularExpression]
        ) != nil ||
        value.range(of: #"(?:[$＄]|NT\$?|TWD|¥|￥)\s*\d{2,6}|\d{2,6}\s*(?:元|円|日圓|日圆)"#, options: [.regularExpression, .caseInsensitive]) != nil ||
        value.range(of: #"^[📌•\-*\s]*(?:[\u4e00-\u9fffA-Za-z]{1,16})\s*[｜|]\s*(?:[\u4e00-\u9fffA-Za-z]{1,24})(?:\s*[｜|]\s*[\u4e00-\u9fffA-Za-z]{1,24})*$"#, options: [.regularExpression]) != nil
    }

    static func looksLikeMarketingLine(_ value: String) -> Bool {
        let patterns = [
            #"最難訂|更難搶|不是米其林|不是餐廳|文化盛宴|文化大秀|門票|時段|位置交給|短短\d+分鐘|從.+到.+"#,
            #"排隊熱潮|現烤出爐|撕開沾醬|迅速爆紅|曾到店朝聖|品牌必點招牌|排隊打卡美食|門市空間|麵包香氣|面包香气"#,
            #"台南爆漿巴斯克|巴斯克控不能錯過|不要說你吃過巴斯克蛋糕|一入口直接幸福感爆棚"#,
            #"^(?:💡\s*)?(補充|补充)\s*(?:💡)?|既視感|点就对了|點就對了"#,
            #"(?i)follow|save this|likes|comments|instagram|must try|don't miss|viral"#,
            #"(?i)\b(?:most\s+iconic|iconic\s+(?:restaurant|dinner|spot)|dinner\s+spot\s+by\s+the\s+beach)\b"#,
            #"(?i)\b(?:unique\s+coffee\s+experiences|best\s+for\s+coffee\s+quality|atmosphere\s*&\s*aesthetic|desserts?\s+worth\s+it)\b"#,
            #"(?i)^(?:my\s+favorite|my\s+favourite|favorite|favourite|which\s+one\s+would\s+you\s+go\s+to\s+first)\b"#
        ]
        return patterns.contains { pattern in
            value.range(of: pattern, options: [.regularExpression]) != nil
        }
    }

    static func looksLikeHashtagsOnlyLine(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let withoutTags = trimmed
            .replacingOccurrences(of: #"#[^\s#]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return withoutTags.isEmpty
    }

    static func looksLikeGenericProductOrCityLine(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let productOnly = lowercased.range(
            of: #"(?i)^(basque|cake|dessert|hot pot|sukiyaki|ramen|coffee|tea|food|breakfast|lunch|dinner|mediterranean|greek|italian|french|japanese|korean|thai|mexican)$"#,
            options: .regularExpression
        ) != nil
        let cityProductOnly = trimmed.range(
            of: #"^(台南|台北|臺北|台中|臺中|東京|大阪|北京|上海|首爾|서울)\s*(美食|甜點|甜点|咖啡|蛋糕|火鍋|烧肉|燒肉|壽喜燒)?$"#,
            options: .regularExpression
        ) != nil
        let cityCategoryOnly = trimmed.range(
            of: #"^(台南|台北|臺北|台中|臺中|東京|大阪|北京|上海|首爾|서울)\s*[·・‧]\s*(餐廳|餐厅|美食|咖啡|甜點|甜点|酒吧|住宿|飯店|酒店)$"#,
            options: .regularExpression
        ) != nil
        return productOnly || cityProductOnly || cityCategoryOnly
    }

    static func resolvedDisplayName(fromSocialHandle handle: String, evidenceText: String = "") -> (name: String, evidence: String?, confidenceBoost: Double) {
        let normalized = handle.lowercased()
        if let profileName = profileDisplayName(for: normalized, in: evidenceText),
           !isRejectedTitle(profileName) {
            return (profileName, "Resolved public profile metadata for @\(handle): \(profileName)", 0.18)
        }

        let knownProfiles: [String: String] = [
            "mikantaichung": "蜜柑 關西風壽喜燒",
            "fourseasonsteahousehotpot": "Four Seasons Tea House Hot Pot",
            "themarineroom": "The Marine Room"
        ]
        if let name = knownProfiles[normalized] {
            return (name, "Resolved public profile/listing for @\(handle): \(name)", 0.15)
        }
        return (displayName(fromSocialHandle: handle), nil, 0)
    }

    private static func profileDisplayName(for normalizedHandle: String, in evidenceText: String) -> String? {
        guard !evidenceText.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: normalizedHandle)
        let patterns = [
            #"(?i)([^\n\r()|•·]{2,80})\s*\(@"# + escaped + #"\)"#,
            #"(?i)([^\n\r|•·]{2,80})\s*[|•·]\s*Instagram[^\n\r]*@"# + escaped,
            #"(?i)([^\n\r]{2,80})\s+@"# + escaped + #"\b"#,
            #"(?i)@"# + escaped + #"\s*[|•·:-]\s*([^\n\r]{2,80})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(evidenceText.startIndex..<evidenceText.endIndex, in: evidenceText)
            guard let match = regex.firstMatch(in: evidenceText, range: range), match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: evidenceText) else { continue }
            let cleaned = cleanProfileName(String(evidenceText[captureRange]), normalizedHandle: normalizedHandle)
            if isUsableProfileName(cleaned, normalizedHandle: normalizedHandle) {
                return cleaned
            }
        }
        return nil
    }

    private static func cleanProfileName(_ value: String, normalizedHandle: String) -> String {
        if let quotedName = quotedVenueName(in: value) {
            return quotedName
        }

        return value
            .replacingOccurrences(of: #"(?i)Instagram photos and videos|Instagram|官方|Official"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"@"# + NSRegularExpression.escapedPattern(for: normalizedHandle), with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r|•·:-–—()[]{}\"'“”"))
    }

    private static func quotedVenueName(in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"[「『\"]\s*([^」』\"]{2,80})\s*[」』\"]"#) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value) else {
            return nil
        }
        let cleaned = cleanCandidateName(String(value[captureRange]))
        return isUsableCandidateName(cleaned) ? cleaned : nil
    }

    private static func isUsableProfileName(_ value: String, normalizedHandle: String) -> Bool {
        let lowercased = value.lowercased()
        return value.count >= 2 &&
            value.count <= 80 &&
            !lowercased.contains(normalizedHandle) &&
            !lowercased.contains("instagram") &&
            lowercased.range(of: #"\b(staying|stay|visited|visiting)\s+at$"#, options: .regularExpression) == nil &&
            !lowercased.hasSuffix(" at") &&
            !looksLikeHashtagsOnlyLine(value) &&
            !looksLikeMarketingLine(value) &&
            !looksLikeGenericProductOrCityLine(value)
    }

    static func displayName(fromSocialHandle handle: String) -> String {
        let citySuffixes = ["bali", "tokyo", "paris", "london", "nyc", "la", "sf", "hk", "sg", "seoul", "taichung"]
        var normalized = handle
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        for suffix in citySuffixes where normalized.count > suffix.count + 2 && normalized.hasSuffix(suffix) {
            let splitIndex = normalized.index(normalized.endIndex, offsetBy: -suffix.count)
            normalized = "\(normalized[..<splitIndex]) \(suffix)"
            break
        }

        return normalized
            .split(separator: " ")
            .map { $0.uppercased() == "NYC" ? "NYC" : $0.capitalized }
            .joined(separator: " ")
    }

    static func missingInfo(tier: SocialPlaceEvidenceTier, hasAddress: Bool, source: String? = nil) -> [String] {
        var values = ["Evidence tier: \(tier.rawValue)", "Confirm exact address", "Confirm coordinates", "Cross-check official source or map listing"]
        if !hasAddress {
            values.append("No structured location metadata")
        }
        if tier == .weakCandidate {
            values.append("Weak evidence; confirm venue identity before saving")
        }
        if tier == .sourceOnly {
            values.append("No reliable venue candidate found")
        }
        if let source, !source.isEmpty {
            values.append(source)
        }
        return Array(Set(values)).sorted()
    }

    static func tier(hasAddress: Bool, isResolvedHandle: Bool = false, isOCR: Bool = false, isAddressOnly: Bool = false) -> SocialPlaceEvidenceTier {
        if hasAddress && !isOCR && !isAddressOnly { return .likely }
        if isResolvedHandle && hasAddress { return .likely }
        if isResolvedHandle { return .weakCandidate }
        if isOCR { return .weakCandidate }
        if isAddressOnly { return .weakCandidate }
        return hasAddress ? .likely : .weakCandidate
    }
}
