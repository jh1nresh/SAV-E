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

    private let googlePlacesService: GooglePlacesServiceProtocol

    init(googlePlacesService: GooglePlacesServiceProtocol = GooglePlacesService.shared) {
        self.googlePlacesService = googlePlacesService
    }

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
        let candidates = await refineCandidates(
            reviewCandidates(fromEvidenceText: evidenceText, sourceURL: sourceURL),
            evidenceText: evidenceText
        )

        if candidates.isEmpty {
            throw SocialLinkReviewCandidateError.noUsableCandidates
        }

        return candidates
    }

    func refineCandidate(_ candidate: PendingReviewCandidate, evidenceText: String? = nil) async -> PendingReviewCandidate {
        guard !candidate.hasReliableCoordinates else { return candidate }
        let query = refinementQuery(for: candidate, evidenceText: evidenceText ?? candidate.sourceText ?? "")
        guard !query.isEmpty else { return candidate }

        do {
            let matches = try await googlePlacesService.searchPlace(query: query, near: nil)
            guard let match = matches.first(where: { isAcceptableRefinement($0, for: candidate) }) else {
                return candidate
            }

            var refined = candidate
            refined.candidateName = match.name.isEmpty ? refined.candidateName : match.name
            refined.address = match.address
            refined.latitude = match.latitude
            refined.longitude = match.longitude
            refined.confidence = max(refined.confidence, 0.74)
            refined.evidence = appendUnique(
                refined.evidence,
                [
                    "Evidence tier: \(SocialPlaceEvidenceTier.likely.rawValue)",
                    "Google Places refined match: \(match.name)",
                    "Google Places address: \(match.address)",
                    "Google Places coordinates: \(match.latitude), \(match.longitude)"
                ]
            )
            refined.missingInfo = SocialPlaceEvidenceScorer.missingInfo(
                tier: .likely,
                hasAddress: !match.address.isEmpty,
                source: "Google Places refined; user must confirm before saving"
            )
            return refined
        } catch {
            var unresolved = candidate
            unresolved.missingInfo = appendUnique(
                unresolved.missingInfo,
                ["Google Places refine skipped or failed; confirm exact address/coordinates"]
            )
            return unresolved
        }
    }

    private func refineCandidates(_ candidates: [PendingReviewCandidate], evidenceText: String) async -> [PendingReviewCandidate] {
        var refined: [PendingReviewCandidate] = []
        for candidate in candidates {
            refined.append(await refineCandidate(candidate, evidenceText: evidenceText))
        }
        return refined
    }

    func reviewCandidates(fromEvidenceText evidenceText: String, sourceURL: String) -> [PendingReviewCandidate] {
        let candidates = analyzedCandidates(from: evidenceText, sourceURL: sourceURL)
        return rankedCandidates(candidates)
    }

    private func analyzedCandidates(from evidenceText: String, sourceURL: String) -> [PendingReviewCandidate] {
        var candidates: [PendingReviewCandidate] = []
        candidates.append(contentsOf: numberedCandidates(from: evidenceText, sourceURL: sourceURL))
        if let captionCandidate = captionNamedCandidate(from: evidenceText, sourceURL: sourceURL) {
            candidates.append(captionCandidate)
        }
        if let titleCandidate = chineseSocialTitleCandidate(from: evidenceText, sourceURL: sourceURL) {
            candidates.append(titleCandidate)
        }
        if let lineCandidate = captionLineCandidate(from: evidenceText, sourceURL: sourceURL) {
            candidates.append(lineCandidate)
        }
        if let handleCandidate = handleCandidate(from: evidenceText, sourceURL: sourceURL) {
            candidates.append(handleCandidate)
        }

        return candidates.map(markAsAnalyzedCandidate)
    }

    private func rankedCandidates(_ candidates: [PendingReviewCandidate]) -> [PendingReviewCandidate] {
        var seenKeys = Set<String>()
        return candidates
            .sorted { lhs, rhs in
                socialAnalysisScore(lhs) > socialAnalysisScore(rhs)
            }
            .filter { candidate in
                let key = "\(candidate.candidateName.lowercased())|\(candidate.address.lowercased())"
                guard !seenKeys.contains(key) else { return false }
                seenKeys.insert(key)
                return true
            }
    }

    private func socialAnalysisScore(_ candidate: PendingReviewCandidate) -> Double {
        var score = candidate.confidence
        let evidence = candidate.evidence.joined(separator: " ").lowercased()
        if !candidate.address.isEmpty { score += 0.18 }
        if evidence.contains("venue anchor") || evidence.contains("named place") { score += 0.16 }
        if evidence.contains("resolved public profile") { score += 0.12 }
        if evidence.contains("social handle") { score += 0.04 }
        if evidence.contains("source url") { score += 0.01 }
        if SocialPlaceEvidenceScorer.isRejectedTitle(candidate.candidateName) { score -= 1.0 }
        return score
    }

    private func markAsAnalyzedCandidate(_ candidate: PendingReviewCandidate) -> PendingReviewCandidate {
        var analyzed = candidate
        analyzed.evidence = appendUnique(
            analyzed.evidence,
            ["Analysis pipeline: collected metadata/caption anchors, scored candidate evidence, and kept unresolved fields for review"]
        )
        return analyzed
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
            let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
            var evidence = [
                "Source URL: \(sourceURL)",
                "Evidence tier: \(tier.rawValue)",
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
                missingInfo: missingInfo(tier: tier, hasAddress: !address.isEmpty),
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
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
        var evidence = [
            "Source URL: \(sourceURL)",
            "Evidence tier: \(tier.rawValue)",
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
            missingInfo: missingInfo(tier: tier, hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func captionLineCandidate(from evidenceText: String, sourceURL: String) -> PendingReviewCandidate? {
        guard let inferred = inferredPlaceLineBeforeAddress(in: evidenceText) else { return nil }
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: true)
        var evidence = [
            "Source URL: \(sourceURL)",
            "Evidence tier: \(tier.rawValue)",
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
            missingInfo: missingInfo(tier: tier, hasAddress: true),
            savedAt: Date()
        )
    }

    private func chineseSocialTitleCandidate(from evidenceText: String, sourceURL: String) -> PendingReviewCandidate? {
        guard let name = chineseVenueName(in: evidenceText) else { return nil }
        let address = firstLocationPin(in: evidenceText) ?? streetAddressLine(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? ""
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
        var evidence = [
            "Source URL: \(sourceURL)",
            "Evidence tier: \(tier.rawValue)",
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
            missingInfo: missingInfo(tier: tier, hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func handleCandidate(from evidenceText: String, sourceURL: String) -> PendingReviewCandidate? {
        guard let handle = firstSocialHandle(in: evidenceText) else { return nil }

        let address = firstLocationPin(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? ""
        let resolved = SocialPlaceEvidenceScorer.resolvedDisplayName(fromSocialHandle: handle, evidenceText: evidenceText)
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty, isResolvedHandle: resolved.evidence != nil)
        var evidence = [
            "Social handle @\(handle)",
            "Source URL: \(sourceURL)",
            "Evidence tier: \(tier.rawValue)"
        ]
        if let profileEvidence = resolved.evidence {
            evidence.append(profileEvidence)
        }
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(500)))
        }

        return PendingReviewCandidate(
            candidateName: resolved.name,
            address: address,
            category: category(from: evidenceText),
            sourceURL: sourceURL,
            sourceText: evidenceText,
            evidence: evidence,
            confidence: min((address.isEmpty ? 0.52 : 0.6) + resolved.confidenceBoost, 0.85),
            missingInfo: missingInfo(tier: tier, hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func refinementQuery(for candidate: PendingReviewCandidate, evidenceText: String) -> String {
        let cityClues = [
            firstLocationPin(in: evidenceText),
            locatedCity(in: evidenceText),
            cityAddress(in: evidenceText),
            chineseCityClue(in: evidenceText)
        ]
        let categoryClue = category(from: "\(candidate.category) \(evidenceText)")
        return ([candidate.candidateName, candidate.address] + cityClues + [categoryClue])
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "attraction" }
            .joined(separator: " ")
    }

    private func isAcceptableRefinement(_ match: GooglePlaceMatch, for candidate: PendingReviewCandidate) -> Bool {
        guard match.latitude != 0 || match.longitude != 0 else { return false }

        // Refinement still requires similarity; address evidence may support a
        // match, but it must not accept the first non-zero Places result.
        let minimumComparableLength = 3
        let minimumTokenLength = 3
        let nameTokenOverlapThreshold = 0.6
        let addressTokenOverlapThreshold = 0.6

        let candidateName = normalizedName(candidate.candidateName)
        let matchName = normalizedName(match.name)
        let candidateAddress = normalizedName(candidate.address)
        let matchAddress = normalizedName(match.address)

        if candidateName.count >= minimumComparableLength, matchName.count >= minimumComparableLength {
            if matchName.contains(candidateName) || candidateName.contains(matchName) { return true }

            let candidateTokens = Set(candidateName.split(separator: " ").map(String.init).filter { $0.count >= minimumTokenLength })
            let matchTokens = Set(matchName.split(separator: " ").map(String.init).filter { $0.count >= minimumTokenLength })
            if !candidateTokens.isEmpty {
                let overlap = candidateTokens.intersection(matchTokens).count
                if Double(overlap) / Double(candidateTokens.count) >= nameTokenOverlapThreshold { return true }
            }
        }

        guard candidateAddress.count >= minimumComparableLength, matchAddress.count >= minimumComparableLength else { return false }
        if matchAddress.contains(candidateAddress) || candidateAddress.contains(matchAddress) { return true }

        let candidateAddressTokens = Set(candidateAddress.split(separator: " ").map(String.init).filter { $0.count >= minimumTokenLength })
        let matchAddressTokens = Set(matchAddress.split(separator: " ").map(String.init).filter { $0.count >= minimumTokenLength })
        guard !candidateAddressTokens.isEmpty else { return false }
        let addressOverlap = candidateAddressTokens.intersection(matchAddressTokens).count
        return Double(addressOverlap) / Double(candidateAddressTokens.count) >= addressTokenOverlapThreshold
    }

    private func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\u4e00-\u9fff]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chineseCityClue(in text: String) -> String? {
        let cities = ["台北", "臺北", "台中", "臺中", "台南", "臺南", "高雄", "東京", "大阪", "京都", "北京", "上海", "首爾"]
        return cities.first { text.contains($0) }
    }

    private func appendUnique(_ values: [String], _ newValues: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values + newValues {
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
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
            let priorLines = Array(lines.prefix(index))

            // Prefer structural venue anchors over the closest freeform line.
            // This mirrors the manual analysis flow: first look for an explicit
            // venue token (`Venue / menu`, quoted venue, or handle), then use the
            // address as corroborating evidence. It avoids treating review-section
            // headers, dishes, or prose near the address as place names.
            for priorLine in priorLines {
                guard let candidate = candidateNameFromCaptionLine(priorLine) else { continue }
                if isLikelyCaptionPlaceName(candidate) {
                    return (candidate, line)
                }
            }

            var previousIndex = index - 1
            while previousIndex >= 0 {
                let candidate = cleanCandidateName(lines[previousIndex])
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
        SocialPlaceEvidenceScorer.looksLikeAddressLine(line)
    }

    private func isLikelyCaptionPlaceName(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(value)
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
            let cleaned = SocialPlaceEvidenceScorer.resolvedDisplayName(fromSocialHandle: handle).name
            if isUsableCandidateName(cleaned), !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }
        return nil
    }

    private func looksLikeOperatingHoursLine(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.looksLikeOperatingHoursLine(value)
    }

    private func looksLikeReviewMetricLine(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.looksLikeReviewMetricLine(value)
    }

    private func looksLikeMarketingLine(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.looksLikeMarketingLine(value)
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
        SocialPlaceEvidenceScorer.displayName(fromSocialHandle: handle)
    }

    private func cleanCandidateName(_ value: String) -> String {
        SocialPlaceEvidenceScorer.cleanCandidateName(value)
    }

    private func isUsableCandidateName(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.isUsableCandidateName(value)
    }

    private func missingInfo(tier: SocialPlaceEvidenceTier, hasAddress: Bool) -> [String] {
        SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: hasAddress)
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
