import Foundation

enum SocialLinkReviewCandidateError: LocalizedError {
    case noUsableCandidates

    var errorDescription: String? {
        switch self {
        case .noUsableCandidates:
            return "SAV-E could not find reviewable place evidence in this link. Add a caption, screenshot, or map link."
        }
    }
}

final class SocialLinkReviewCandidateService {
    static let shared = SocialLinkReviewCandidateService()

    private struct PublicMetadata {
        var resolvedURL: String?
        var title: String?
        var description: String?
    }

    func reviewCandidates(from url: URL) async throws -> [PendingReviewCandidate] {
        let metadata = await fetchMetadata(from: url)
        let evidenceText = [metadata.title, metadata.description]
            .compactMap { $0 }
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let sourceURL = metadata.resolvedURL ?? url.absoluteString
        let candidates = reviewCandidates(fromEvidenceText: evidenceText, sourceURL: sourceURL)

        if candidates.isEmpty {
            throw SocialLinkReviewCandidateError.noUsableCandidates
        }

        return candidates
    }

    func reviewCandidates(fromEvidenceText evidenceText: String, sourceURL: String) -> [PendingReviewCandidate] {
        var candidates = numberedCandidates(from: evidenceText, sourceURL: sourceURL)
        if candidates.isEmpty, let captionCandidate = captionNamedCandidate(from: evidenceText, sourceURL: sourceURL) {
            candidates = [captionCandidate]
        }
        if candidates.isEmpty, let titleCandidate = chineseSocialTitleCandidate(from: evidenceText, sourceURL: sourceURL) {
            candidates = [titleCandidate]
        }
        if candidates.isEmpty, let lineCandidate = captionLineCandidate(from: evidenceText, sourceURL: sourceURL) {
            candidates = [lineCandidate]
        }
        if candidates.isEmpty, let handleCandidate = handleCandidate(from: evidenceText, sourceURL: sourceURL) {
            candidates = [handleCandidate]
        }

        return candidates
    }

    private func fetchMetadata(from url: URL) async -> PublicMetadata {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let html = String(data: data.prefix(300_000), encoding: .utf8) ?? ""
            return PublicMetadata(
                resolvedURL: response.url?.absoluteString ?? url.absoluteString,
                title: metadataValue(in: html, keys: ["og:title", "twitter:title", "title"]),
                description: metadataValue(in: html, keys: ["og:description", "twitter:description", "description"])
            )
        } catch {
            return PublicMetadata(resolvedURL: url.absoluteString, title: nil, description: nil)
        }
    }

    private func numberedCandidates(from evidenceText: String, sourceURL: String) -> [PendingReviewCandidate] {
        let lines = evidenceText
            .components(separatedBy: .newlines)
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }

        var sections: [(name: String, details: [String])] = []
        var currentName: String?
        var currentDetails: [String] = []

        for line in lines {
            if let name = numberedName(from: line) {
                if let currentName {
                    sections.append((currentName, currentDetails))
                }
                currentName = name
                currentDetails = []
            } else if currentName != nil {
                currentDetails.append(line)
            }
        }
        if let currentName {
            sections.append((currentName, currentDetails))
        }

        let parsedCandidates: [PendingReviewCandidate] = sections.compactMap { section in
            let name = cleanCandidateName(section.name)
            guard isUsableCandidateName(name) else { return nil }

            let detailsText = section.details.joined(separator: "\n")
            let address = firstLocationPin(in: detailsText) ?? locatedCity(in: detailsText) ?? cityAddress(in: detailsText) ?? ""
            let confidence = address.isEmpty ? 0.48 : 0.58
            var evidence = [
                "Source URL: \(sourceURL)",
                "Public metadata candidate: \(name)"
            ]
            if !address.isEmpty {
                evidence.append("Location clue: \(address)")
            }
            if !detailsText.isEmpty {
                evidence.append(String(detailsText.prefix(500)))
            }

            return PendingReviewCandidate(
                candidateName: name,
                address: address,
                category: "stay",
                sourceURL: sourceURL,
                sourceText: evidenceText,
                evidence: evidence,
                confidence: confidence,
                missingInfo: missingInfo(hasAddress: !address.isEmpty),
                savedAt: Date()
            )
        }

        var seenKeys = Set<String>()
        return parsedCandidates.filter { candidate in
            let key = "\(candidate.candidateName.lowercased())|\(candidate.address.lowercased())"
            guard !seenKeys.contains(key) else { return false }
            seenKeys.insert(key)
            return true
        }
    }

    private func captionNamedCandidate(from evidenceText: String, sourceURL: String) -> PendingReviewCandidate? {
        guard let name = bracketedPlaceName(in: evidenceText) else { return nil }
        let address = firstLocationPin(in: evidenceText) ?? streetAddressLine(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? ""
        var evidence = [
            "Source URL: \(sourceURL)",
            "Public metadata named place: \(name)"
        ]
        if !address.isEmpty {
            evidence.append("Location clue: \(address)")
        }
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(500)))
        }

        return PendingReviewCandidate(
            candidateName: name,
            address: address,
            category: category(from: "\(name) \(evidenceText)"),
            sourceURL: sourceURL,
            sourceText: evidenceText,
            evidence: evidence,
            confidence: address.isEmpty ? 0.5 : 0.62,
            missingInfo: missingInfo(hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func captionLineCandidate(from evidenceText: String, sourceURL: String) -> PendingReviewCandidate? {
        guard let inferred = inferredPlaceLineBeforeAddress(in: evidenceText) else { return nil }
        var evidence = [
            "Source URL: \(sourceURL)",
            "Public metadata place line: \(inferred.name)",
            "Location clue: \(inferred.address)"
        ]
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(500)))
        }

        return PendingReviewCandidate(
            candidateName: inferred.name,
            address: inferred.address,
            category: category(from: "\(inferred.name) \(evidenceText)"),
            sourceURL: sourceURL,
            sourceText: evidenceText,
            evidence: evidence,
            confidence: 0.6,
            missingInfo: missingInfo(hasAddress: true),
            savedAt: Date()
        )
    }

    private func chineseSocialTitleCandidate(from evidenceText: String, sourceURL: String) -> PendingReviewCandidate? {
        guard let name = chineseVenueName(in: evidenceText) else { return nil }
        let address = firstLocationPin(in: evidenceText) ?? streetAddressLine(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? ""
        var evidence = [
            "Source URL: \(sourceURL)",
            "Public metadata named venue: \(name)"
        ]
        if !address.isEmpty {
            evidence.append("Location clue: \(address)")
        }
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(500)))
        }

        return PendingReviewCandidate(
            candidateName: name,
            address: address,
            category: category(from: "\(name) \(evidenceText)"),
            sourceURL: sourceURL,
            sourceText: evidenceText,
            evidence: evidence,
            confidence: address.isEmpty ? 0.56 : 0.66,
            missingInfo: missingInfo(hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func handleCandidate(from evidenceText: String, sourceURL: String) -> PendingReviewCandidate? {
        guard let handle = firstSocialHandle(in: evidenceText) else { return nil }

        let address = firstLocationPin(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? ""
        var evidence = ["Social handle @\(handle)", "Source URL: \(sourceURL)"]
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(500)))
        }

        return PendingReviewCandidate(
            candidateName: displayName(fromSocialHandle: handle),
            address: address,
            category: category(from: evidenceText),
            sourceURL: sourceURL,
            sourceText: evidenceText,
            evidence: evidence,
            confidence: address.isEmpty ? 0.52 : 0.6,
            missingInfo: missingInfo(hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func numberedName(from line: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(?:\d{1,2}[\.)]|[①②③④⑤⑥⑦⑧⑨])\s*([^\n\r]+)"#) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 1,
              let nameRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[nameRange])
    }

    private func bracketedPlaceName(in text: String) -> String? {
        let patterns = [
            #"[\[【]\s*([^\]】]{2,80})\s*[\]】]"#,
            #"(?i)\b(?:at|spot|place)\s+([A-Z][A-Za-z0-9 &'._-]{2,60})\s*(?:[-–—|,]|\n)"#
        ]
        for pattern in patterns {
            if let match = firstCapture(in: text, pattern: pattern) {
                let cleaned = cleanCandidateName(match)
                if isUsableCandidateName(cleaned) {
                    return cleaned
                }
            }
        }
        return nil
    }

    private func chineseVenueName(in text: String) -> String? {
        let patterns = [
            #"(?:^|[\n\r])[-\s]*(?:[\u4e00-\u9fff]{0,4})?(?:全新開幕|新開幕|開幕)\s*([^\s新主题主題\-－—–:]{2,16})\s*(?:新主題|主题|主題)\s*[-－—–:]\s*([\u4e00-\u9fffA-Za-z0-9]{2,24})"#,
            #"([\u4e00-\u9fffA-Za-z0-9]{2,24})\s*[·・‧]\s*([\u4e00-\u9fffA-Za-z0-9]{2,24})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 2,
                  let brandRange = Range(match.range(at: 1), in: text),
                  let themeRange = Range(match.range(at: 2), in: text) else { continue }
            let brand = cleanCandidateName(String(text[brandRange]))
            let theme = cleanCandidateName(String(text[themeRange]))
            let name = "\(brand)·\(theme)"
            if isUsableCandidateName(name), !looksLikeMarketingLine(name) {
                return name
            }
        }
        return nil
    }

    private func firstLocationPin(in text: String) -> String? {
        let patterns = [
            #"📍\s*([^\n\r\.]+)"#,
            #"\bLocation:\s*([^\n\r\.]+)"#
        ]
        for pattern in patterns {
            if let match = firstCapture(in: text, pattern: pattern) {
                let cleaned = cleanHTMLText(match)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    private func inferredPlaceLineBeforeAddress(in text: String) -> (name: String, address: String)? {
        let lines = text
            .components(separatedBy: .newlines)
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else { return nil }

        for (index, line) in lines.enumerated() where looksLikeAddressLine(line) {
            var previousIndex = index - 1
            while previousIndex >= 0 {
                let candidate = candidateNameFromCaptionLine(lines[previousIndex]) ?? cleanCandidateName(lines[previousIndex])
                if isLikelyCaptionPlaceName(candidate) {
                    return (candidate, line)
                }
                previousIndex -= 1
            }
        }
        return nil
    }

    private func streetAddressLine(in text: String) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }
        return lines.first(where: looksLikeAddressLine)
    }

    private func looksLikeAddressLine(_ line: String) -> Bool {
        let patterns = [
            #"\b(?:No\.?|#)\s*\d+[A-Za-z]?\b"#,
            #"\b\d{1,6}\s+[A-Za-z0-9 .'-]{2,80}\b(?:Street|St\.?|Road|Rd\.?|Avenue|Ave\.?|Boulevard|Blvd\.?|Lane|Ln\.?|Drive|Dr\.?|Way|Old Street|District|County|City)\b"#,
            #"\b[A-Z][A-Za-z .'-]{2,40},\s*(?:CA|NY|TX|FL|WA|IL|NV|AZ|OR|MA|HI|UT|CO|Bali|Indonesia|Chongqing|China)\b"#,
            #"[\u4e00-\u9fff]{2,}(?:市|区|區|路|街|道)[\u4e00-\u9fffA-Za-z0-9\-－\s]{0,40}\d{1,6}\s*(?:号|號)?"#,
            #"\d{1,6}\s*(?:号|號)"#
        ]
        return patterns.contains { pattern in
            line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private func isLikelyCaptionPlaceName(_ value: String) -> Bool {
        guard isUsableCandidateName(value) else { return false }
        let lowered = value.lowercased()
        guard !looksLikeAddressLine(value),
              !looksLikeOperatingHoursLine(value),
              !looksLikeReviewMetricLine(value),
              !looksLikeMarketingLine(value),
              !lowered.contains("likes"),
              !lowered.contains("comments"),
              !lowered.contains(" on instagram"),
              !lowered.contains("casual"),
              !lowered.contains("dream"),
              !lowered.contains("follow"),
              !lowered.contains("save this"),
              !lowered.contains("located") else {
            return false
        }
        return value.range(of: #"[A-Za-z\u4e00-\u9fff]"#, options: .regularExpression) != nil
    }

    private func candidateNameFromCaptionLine(_ line: String) -> String? {
        if let leadingName = firstCapture(in: line, pattern: #"^([^/\n]{2,60})\s*/"#) {
            let cleaned = cleanCandidateName(leadingName)
            if isUsableCandidateName(cleaned),
               !looksLikeAddressLine(cleaned),
               !looksLikeOperatingHoursLine(cleaned),
               !looksLikeReviewMetricLine(cleaned),
               !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }

        let isVenueIntroLine = line.range(of: #"@|名店|插旗|開幕|新店|店名|餐廳|餐厅|restaurant"#, options: [.regularExpression, .caseInsensitive]) != nil
        if isVenueIntroLine,
           let quoted = firstCapture(in: line, pattern: #"[「\"]\s*([^」\"]{2,60})\s*[」\"]"#) {
            let cleaned = cleanCandidateName(quoted)
            if isUsableCandidateName(cleaned), !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }
        if let handle = firstCapture(in: line, pattern: #"@([A-Za-z0-9._]{3,30})"#) {
            let cleaned = displayName(fromSocialHandle: handle)
            if isUsableCandidateName(cleaned), !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }
        return nil
    }

    private func looksLikeOperatingHoursLine(_ value: String) -> Bool {
        value.range(of: #"(?i)(營業|营业|hours?|open|closed|週[一二三四五六日天]|周[一二三四五六日天]|星期|\b\d{1,2}:\d{2}\s*[-–—~至]\s*\d{1,2}:\d{2})"#, options: [.regularExpression]) != nil
    }

    private func looksLikeReviewMetricLine(_ value: String) -> Bool {
        value.range(of: #"(美味程度|環境衛生|服务态度|服務態度|再訪意願|再访意愿|評分|评分|rating|review)\s*[：:]"#, options: [.regularExpression, .caseInsensitive]) != nil ||
        value.range(of: #"^[^\n]{0,16}[：:].*[🌕🌖🌗🌘🌑⭐★]"#, options: [.regularExpression]) != nil
    }

    private func looksLikeMarketingLine(_ value: String) -> Bool {
        let patterns = [
            #"最難訂|更難搶|不是米其林|不是餐廳|文化盛宴|文化大秀|門票|時段|位置交給|短短\d+分鐘|從.+到.+"#,
            #"(?i)follow|save this|likes|comments|instagram"#
        ]
        return patterns.contains { pattern in
            value.range(of: pattern, options: [.regularExpression]) != nil
        }
    }

    private func cityAddress(in text: String) -> String? {
        let pattern = #"\b([A-Z][A-Za-z .'-]{2,40},\s*(?:CA|NY|TX|FL|WA|IL|NV|AZ|OR|MA|HI|UT|CO|Bali|Indonesia))\b"#
        return firstCapture(in: text, pattern: pattern).map(cleanHTMLText)
    }

    private func locatedCity(in text: String) -> String? {
        let pattern = #"(?i)\b(?:located|based)\s+in\s+([A-Z][A-Za-z .'-]{2,40})(?:[.!?,\n\r]|$)"#
        return firstCapture(in: text, pattern: pattern).map(cleanHTMLText)
    }

    private func firstSocialHandle(in text: String) -> String? {
        let ignoredHandles: Set<String> = [
            "instagram", "reels", "reel", "explore", "threads", "tiktok", "xiaohongshu", "wanderly", "save", "media"
        ]
        guard let regex = try? NSRegularExpression(pattern: #"@([A-Za-z0-9._]{3,30})"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)

        for match in matches {
            guard match.numberOfRanges > 1,
                  let handleRange = Range(match.range(at: 1), in: text) else { continue }
            let handle = String(text[handleRange]).lowercased()
            guard !ignoredHandles.contains(handle),
                  !handle.contains("instagram"),
                  handle.range(of: #"\d{5,}"#, options: .regularExpression) == nil else {
                continue
            }
            return handle
        }
        return nil
    }

    private func displayName(fromSocialHandle handle: String) -> String {
        let citySuffixes = ["bali", "tokyo", "paris", "london", "nyc", "la", "sf", "hk", "sg", "seoul"]
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
            .map { $0.uppercased() == "nyc" ? "NYC" : $0.capitalized }
            .joined(separator: " ")
    }

    private func cleanCandidateName(_ value: String) -> String {
        cleanHTMLText(value)
            .replacingOccurrences(of: #"^[\-\–\—]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”.,:;! "))
    }

    private func isUsableCandidateName(_ value: String) -> Bool {
        let lowered = value.lowercased()
        guard value.count >= 2,
              value.count <= 80,
              !lowered.contains("comment "),
              !lowered.contains("instagram"),
              !lowered.contains("like") else {
            return false
        }
        return true
    }

    private func missingInfo(hasAddress: Bool) -> [String] {
        var values = ["Confirm exact address", "Confirm coordinates", "Cross-check official source or map listing"]
        if !hasAddress {
            values.append("No structured location metadata")
        }
        return values
    }

    private func category(from text: String) -> String {
        let lowered = text.lowercased()
        if lowered.range(of: #"airbnb|stay|hotel|resort|villa|home|cabin"#, options: .regularExpression) != nil {
            return "stay"
        }
        if lowered.range(of: #"restaurant|food|eat|cafe|coffee|tea|bar"#, options: .regularExpression) != nil {
            return "food"
        }
        if text.range(of: #"晚餐|餐廳|餐厅|美食|咖啡|茶|酒吧|料理|餐|燒肉|烧肉|火鍋|火锅|牛舌"#, options: .regularExpression) != nil {
            return "food"
        }
        return "attraction"
    }

    private func metadataValue(in html: String, keys: [String]) -> String? {
        guard !html.isEmpty else { return nil }

        for key in keys {
            if key == "title",
               let start = html.range(of: "<title", options: [.caseInsensitive]),
               let openEnd = html[start.upperBound...].range(of: ">"),
               let close = html[openEnd.upperBound...].range(of: "</title>", options: [.caseInsensitive]) {
                return cleanHTMLText(String(html[openEnd.upperBound..<close.lowerBound]))
            }

            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let patterns = [
                #"<meta[^>]+(?:property|name)=["']\#(escapedKey)["'][^>]+content=["']([^"']+)["'][^>]*>"#,
                #"<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']\#(escapedKey)["'][^>]*>"#
            ]

            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(html.startIndex..<html.endIndex, in: html)
                guard let match = regex.firstMatch(in: html, range: range),
                      match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: html) else {
                    continue
                }
                let value = cleanHTMLText(String(html[valueRange]))
                if !value.isEmpty { return value }
            }
        }

        return nil
    }

    private func cleanHTMLText(_ value: String) -> String {
        decodeNumericHTMLEntities(in: value)
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

    private func decodeNumericHTMLEntities(in value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&#(x[0-9A-Fa-f]+|\d+);"#) else {
            return value
        }

        let nsValue = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: nsValue.length))
        var decoded = value

        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let entityRange = Range(match.range(at: 1), in: value),
                  let fullRange = Range(match.range, in: decoded) else {
                continue
            }

            let entity = String(value[entityRange])
            let codePoint: UInt32?
            if entity.lowercased().hasPrefix("x") {
                codePoint = UInt32(entity.dropFirst(), radix: 16)
            } else {
                codePoint = UInt32(entity)
            }

            guard let codePoint,
                  let scalar = UnicodeScalar(codePoint) else {
                continue
            }

            decoded.replaceSubrange(fullRange, with: String(Character(scalar)))
        }

        return decoded
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}
