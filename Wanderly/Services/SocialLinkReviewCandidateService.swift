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

struct PublicSourceSearchResult: Hashable {
    var title: String
    var url: String
    var snippet: String
}

protocol PublicSourceSearchServiceProtocol {
    func search(query: String) async throws -> [PublicSourceSearchResult]
}

final class PublicSourceSearchService: PublicSourceSearchServiceProtocol {
    static let shared = PublicSourceSearchService()

    func search(query: String) async throws -> [PublicSourceSearchResult] {
        var components = URLComponents(string: "https://duckduckgo.com/html/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)
        let html = String(data: data.prefix(250_000), encoding: .utf8) ?? ""
        return parseDuckDuckGoResults(from: html)
    }

    private func parseDuckDuckGoResults(from html: String) -> [PublicSourceSearchResult] {
        let blocks = html.components(separatedBy: "result__body")
        var results: [PublicSourceSearchResult] = []
        for block in blocks.dropFirst().prefix(5) {
            let title = firstCapture(in: block, pattern: #"result__a[^>]*>(.*?)</a>"#)
            let url = firstCapture(in: block, pattern: #"result__url[^>]*>(.*?)</a>"#) ?? ""
            let snippet = firstCapture(in: block, pattern: #"result__snippet[^>]*>(.*?)</a>"#) ??
                firstCapture(in: block, pattern: #"result__snippet[^>]*>(.*?)</div>"#) ?? ""
            let cleanedTitle = cleanHTMLText(title ?? "")
            let cleanedSnippet = cleanHTMLText(snippet)
            guard !cleanedTitle.isEmpty || !cleanedSnippet.isEmpty else { continue }
            results.append(PublicSourceSearchResult(title: cleanedTitle, url: cleanHTMLText(url), snippet: cleanedSnippet))
        }
        return results
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }

    private func cleanHTMLText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class SocialLinkReviewCandidateService {
    static let shared = SocialLinkReviewCandidateService()

    private let googlePlacesService: GooglePlacesServiceProtocol
    private let publicSourceSearchService: PublicSourceSearchServiceProtocol

    init(
        googlePlacesService: GooglePlacesServiceProtocol = GooglePlacesService.shared,
        publicSourceSearchService: PublicSourceSearchServiceProtocol = PublicSourceSearchService.shared
    ) {
        self.googlePlacesService = googlePlacesService
        self.publicSourceSearchService = publicSourceSearchService
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
        return try await recoverReviewCandidates(fromEvidenceText: evidenceText, sourceURL: sourceURL)
    }

    func recoverReviewCandidates(fromEvidenceText evidenceText: String, sourceURL: String) async throws -> [PendingReviewCandidate] {
        let initial = reviewCandidatesOrSourceOnly(fromEvidenceText: evidenceText, sourceURL: sourceURL)
        let shouldRunRecovery = initial.contains { $0.isPlaceBearingSource || $0.isSourceOnly }
        guard shouldRunRecovery else {
            return await refineCandidates(initial, evidenceText: evidenceText)
        }

        let analysis = analyze(evidenceText: evidenceText, sourceURL: sourceURL)
        guard analysis.isPlaceBearing || analysis.resolverDecision.shouldRunPublicSearch else { return initial }

        let queries = sourceRecoverySearchQueries(evidenceText: evidenceText, sourceURL: sourceURL, analysis: analysis)
        let searchResults = await publicSearchResults(for: queries)
        let recovered = sourceRecoveryCandidates(
            from: searchResults,
            analysis: analysis,
            evidenceText: evidenceText,
            sourceURL: sourceURL
        )
        let refinedRecovered = await refineCandidates(recovered, evidenceText: sourceRecoveryEvidenceText(evidenceText: evidenceText, results: searchResults))
        let mapReady = refinedRecovered.filter { $0.hasReliableCoordinates }
        if !mapReady.isEmpty { return rankedCandidates(mapReady) }
        if !refinedRecovered.isEmpty { return rankedCandidates(refinedRecovered) }
        return initial
    }

    func refineCandidate(_ candidate: PendingReviewCandidate, evidenceText: String? = nil) async -> PendingReviewCandidate {
        guard !candidate.isSourceOnly else { return candidate }
        guard !candidate.isPlaceBearingSource else { return candidate }
        guard !candidate.hasReliableCoordinates else { return candidate }
        let query = refinementQuery(for: candidate, evidenceText: evidenceText ?? candidate.sourceText ?? "")
        guard !query.isEmpty else { return candidate }

        do {
            let matches = try await googlePlacesMatches(for: candidate, evidenceText: evidenceText ?? candidate.sourceText ?? "")
            guard let match = bestAcceptableRefinement(in: matches, for: candidate) else {
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
            refined.evidenceDiagnostic = refinedDiagnosticAfterPlacesMatch(
                existing: refined.evidenceDiagnostic,
                match: match
            )
            refined.reviewState = "map_match_ready"
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

    private func publicSearchResults(for queries: [String]) async -> [PublicSourceSearchResult] {
        var results: [PublicSourceSearchResult] = []
        var seen = Set<PublicSourceSearchResult>()
        for query in queries.prefix(4) {
            do {
                for result in try await publicSourceSearchService.search(query: query).prefix(5) where !seen.contains(result) {
                    seen.insert(result)
                    results.append(result)
                }
            } catch {
                continue
            }
        }
        return results
    }

    private func sourceRecoveryCandidates(
        from results: [PublicSourceSearchResult],
        analysis: SocialPlaceAgentAnalysis,
        evidenceText: String,
        sourceURL: String
    ) -> [PendingReviewCandidate] {
        let region = primaryRegion(from: analysis.regionClues)
        return results.compactMap { result in
            guard let name = recoveredVenueName(from: result, analysis: analysis), isUsableCandidateName(name) else { return nil }
            let combinedText = sourceRecoveryEvidenceText(evidenceText: evidenceText, results: [result])
            let tier = SocialPlaceEvidenceTier.weakCandidate
            let evidence = appendUnique(
                [],
                [
                    "Source URL: \(sourceURL)",
                    "Evidence tier: \(tier.rawValue)",
                    "Recovered venue candidate: \(name)",
                    "Public web search result: \(result.title) — \(result.snippet)",
                    result.url.isEmpty ? "" : "Public web search URL: \(result.url)"
                ]
            )
            return PendingReviewCandidate(
                candidateName: name,
                address: region ?? "",
                category: category(for: analysis.sourceIntent),
                sourceURL: sourceURL,
                sourceText: combinedText,
                evidence: evidence,
                confidence: 0.58,
                missingInfo: ["Google Places match required", "User confirmation required"],
                savedAt: Date(),
                evidenceDiagnostic: sourceRecoveryDiagnostic(
                    analysis: analysis,
                    sourceURL: sourceURL,
                    result: result,
                    recoveredName: name
                ),
                reviewState: "source_recovered_candidate"
            )
        }
    }

    private func recoveredVenueName(from result: PublicSourceSearchResult, analysis: SocialPlaceAgentAnalysis) -> String? {
        let text = "\(result.title)\n\(result.snippet)"
        let patterns = [
            #"(?i)favorite restaurants? in [A-Za-z .'-]{2,40}\s+is\s+([A-Z][A-Za-z0-9 &'’'\-.]{2,70})"#,
            #"(?i)favorite restaurants? in [A-Za-z .'-]{2,40}\s*[:\-–—]\s*([A-Z][A-Za-z0-9 &'’'\-.]{2,70})"#,
            #"(?i)(?:at|try|visit|saved?|spot is|restaurant is|cafe is)\s+([A-Z][A-Za-z0-9 &'’'\-.]{2,70})"#
        ]
        for pattern in patterns {
            if let match = firstCapture(in: text, pattern: pattern) {
                let cleaned = cleanRecoveredVenueName(match)
                if isUsableCandidateName(cleaned) { return cleaned }
            }
        }
        if let quoted = firstCapture(in: text, pattern: #"[“\"]([A-Z][A-Za-z0-9 &'’'\-.]{2,70})[”\"]"#) {
            let cleaned = cleanRecoveredVenueName(quoted)
            if isUsableCandidateName(cleaned) { return cleaned }
        }
        return nil
    }

    private func cleanRecoveredVenueName(_ value: String) -> String {
        cleanCandidateName(value)
            .replacingOccurrences(of: #"(?i)\s+(?:save this|for a|with|because|near|in)\b.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.,:;!?'\"“”"))
    }

    private func sourceRecoveryEvidenceText(evidenceText: String, results: [PublicSourceSearchResult]) -> String {
        ([evidenceText] + results.map { "\($0.title)\n\($0.snippet)" })
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func sourceRecoveryDiagnostic(
        analysis: SocialPlaceAgentAnalysis,
        sourceURL: String,
        result: PublicSourceSearchResult,
        recoveredName: String
    ) -> SocialPlaceEvidenceDiagnostic {
        SocialPlaceEvidenceDiagnostic(
            found: appendUnique(
                [],
                [
                    "Source URL: \(sourceURL)",
                    "Place-bearing source: \(analysis.placeBearingReason ?? analysis.sourceIntent.rawValue)",
                    "Recovered venue candidate: \(recoveredName)",
                    "Public web search result: \(result.title)",
                    result.url.isEmpty ? "" : "Public web search URL: \(result.url)"
                ]
            ),
            attempts: [
                "Checked public metadata/caption/OCR text for place-bearing intent",
                "Ran public web search recovery queries",
                "Extracted venue candidate from public search snippets",
                "Prepared Google Places refinement query",
                "Did not use logged-in Instagram scraping"
            ],
            missingFields: ["Verified address", "Verified coordinates"],
            nextBestClue: "Confirm the Google Places match before saving this as a Map Stamp."
        )
    }

    func reviewCandidatesOrSourceOnly(fromEvidenceText evidenceText: String, sourceURL: String) -> [PendingReviewCandidate] {
        let analysis = analyze(evidenceText: evidenceText, sourceURL: sourceURL)
        let candidates = rankedCandidates(
            analysis.placesFound.map { pendingReviewCandidate(from: $0, sourceURL: sourceURL, sourceText: evidenceText) }
        )
            .map { candidate in
                var diagnosed = candidate
                diagnosed.evidenceDiagnostic = candidateDiagnostic(for: candidate, evidenceText: evidenceText, sourceURL: sourceURL)
                if diagnosed.address.isEmpty {
                    diagnosed.missingInfo = appendUnique(diagnosed.missingInfo, ["Confirm address"])
                }
                return diagnosed
            }

        guard candidates.isEmpty else { return candidates }
        if analysis.isPlaceBearing {
            return [placeBearingSourceCandidate(from: analysis, evidenceText: evidenceText, sourceURL: sourceURL)]
        }
        return [sourceOnlyCandidate(evidenceText: evidenceText, sourceURL: sourceURL)]
    }

    func reviewCandidates(fromEvidenceText evidenceText: String, sourceURL: String) -> [PendingReviewCandidate] {
        let candidates = analyze(evidenceText: evidenceText, sourceURL: sourceURL)
            .placesFound
            .map { pendingReviewCandidate(from: $0, sourceURL: sourceURL, sourceText: evidenceText) }
        return rankedCandidates(candidates)
    }

    private func analyze(evidenceText: String, sourceURL: String) -> SocialPlaceAgentAnalysis {
        SocialPlaceParser().analyze(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: sourceURL,
                resolvedURL: sourceURL,
                sharedTitle: nil,
                sharedText: evidenceText,
                metadataTitle: nil,
                metadataDescription: nil,
                ocrLines: []
            )
        )
    }

    private func analyzedCandidates(from evidenceText: String, sourceURL: String) -> [PendingReviewCandidate] {
        var candidates: [PendingReviewCandidate] = []
        candidates.append(contentsOf: numberedCandidates(from: evidenceText, sourceURL: sourceURL))
        if let captionCandidate = captionNamedCandidate(from: evidenceText, sourceURL: sourceURL) {
            candidates.append(captionCandidate)
        }
        if let venueIntroCandidate = captionVenueIntroCandidate(from: evidenceText, sourceURL: sourceURL) {
            candidates.append(venueIntroCandidate)
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
                let key = "\(SocialPlaceParser.canonicalPlaceName(candidate.candidateName))|\(SocialPlaceParser.canonicalPlaceName(candidate.address))"
                guard !seenKeys.contains(key) else { return false }
                seenKeys.insert(key)
                return true
            }
    }

    private func socialAnalysisScore(_ candidate: PendingReviewCandidate) -> Double {
        var score = candidate.confidence
        let evidence = candidate.evidence.joined(separator: " ").lowercased()
        if !candidate.address.isEmpty { score += 0.18 }
        if evidence.contains("venue anchor") || evidence.contains("named place") || evidence.contains("venue name") { score += 0.16 }
        if evidence.contains("venue handle") { score += 0.08 }
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

    private func pendingReviewCandidate(
        from draft: SocialPlaceCandidateDraft,
        sourceURL: String,
        sourceText: String
    ) -> PendingReviewCandidate {
        PendingReviewCandidate(
            candidateName: draft.displayName,
            address: draft.locationClues.first ?? "",
            category: draft.category,
            sourceURL: sourceURL,
            sourceText: sourceText.isEmpty ? nil : sourceText,
            evidence: evidenceStrings(from: draft, sourceURL: sourceURL),
            confidence: draft.confidence,
            missingInfo: draft.missingInfo,
            savedAt: Date()
        )
    }

    private func evidenceStrings(from draft: SocialPlaceCandidateDraft, sourceURL: String) -> [String] {
        var values = ["Source URL: \(sourceURL)"]
        values.append(contentsOf: draft.evidenceChips)
        values.append(contentsOf: draft.evidence.compactMap { atom in
            atom.line.contains("Resolved public profile") ? atom.line : nil
        })
        if !draft.locationClues.isEmpty {
            values.append(contentsOf: draft.locationClues.map { "Location clue: \($0)" })
        }
        if !draft.venueHandles.isEmpty {
            values.append(contentsOf: draft.venueHandles.map { "Venue handle: @\($0)" })
        }
        if !draft.creatorHandles.isEmpty {
            values.append(contentsOf: draft.creatorHandles.map { "Creator handle: @\($0)" })
        }
        if !draft.bookingLinks.isEmpty {
            values.append(contentsOf: draft.bookingLinks.map { "Booking link: \($0)" })
        }
        return appendUnique([], values)
    }

    private func fetchMetadata(from url: URL) async -> PublicMetadata {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-TW,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let html = String(data: data.prefix(300_000), encoding: .utf8) ?? ""
            let title = metadataValue(in: html, keys: ["og:title", "twitter:title", "title"])
            let description = metadataValue(in: html, keys: ["og:description", "twitter:description", "description"])
            return PublicMetadata(
                resolvedURL: response.url?.absoluteString ?? url.absoluteString,
                title: title,
                description: description
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

    private func captionVenueIntroCandidate(from evidenceText: String, sourceURL: String) -> PendingReviewCandidate? {
        guard let name = venueIntroName(in: evidenceText) else { return nil }
        let address = firstLocationPin(in: evidenceText) ?? streetAddressLine(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? ""
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
        var evidence = [
            "Source URL: \(sourceURL)",
            "Evidence tier: \(tier.rawValue)",
            "Public metadata venue anchor: \(name)"
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
        refinementQueries(for: candidate, evidenceText: evidenceText).first ?? ""
    }

    private func refinementQueries(for candidate: PendingReviewCandidate, evidenceText: String) -> [String] {
        let cityClues = [
            firstLocationPin(in: evidenceText),
            locatedCity(in: evidenceText),
            cityAddress(in: evidenceText),
            chineseCityClue(in: evidenceText)
        ]
        let categoryClue = category(from: "\(candidate.category) \(evidenceText)")
        guard !candidate.candidateName.isEmpty,
              !SocialPlaceEvidenceScorer.isRejectedTitle(candidate.candidateName) else {
            return []
        }
        let cityText = cityClues
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let seeds: [[String?]] = [
            [candidate.candidateName, candidate.address, cityText, categoryClue],
            [candidate.candidateName, cityText, categoryClue],
            [candidate.candidateName, candidate.address]
        ]
        var seen = Set<String>()
        return seeds.compactMap { parts in
            let query = parts
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != "attraction" }
                .joined(separator: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            guard !query.isEmpty, !seen.contains(query.lowercased()) else { return nil }
            seen.insert(query.lowercased())
            return query
        }
    }

    private func googlePlacesMatches(for candidate: PendingReviewCandidate, evidenceText: String) async throws -> [GooglePlaceMatch] {
        var allMatches: [GooglePlaceMatch] = []
        var seenIDs = Set<String>()
        for query in refinementQueries(for: candidate, evidenceText: evidenceText).prefix(4) {
            let matches = try await googlePlacesService.searchPlace(query: query, near: nil)
            for match in matches where !seenIDs.contains(match.id) {
                seenIDs.insert(match.id)
                allMatches.append(match)
            }
        }
        return allMatches
    }

    private func bestAcceptableRefinement(in matches: [GooglePlaceMatch], for candidate: PendingReviewCandidate) -> GooglePlaceMatch? {
        matches
            .map { (match: $0, score: refinementScore($0, for: candidate)) }
            .filter { $0.score >= 0.62 }
            .sorted { $0.score > $1.score }
            .first?.match
    }

    private func refinementScore(_ match: GooglePlaceMatch, for candidate: PendingReviewCandidate) -> Double {
        guard match.latitude != 0 || match.longitude != 0 else { return 0 }
        var score = 0.0
        let candidateName = normalizedName(candidate.candidateName)
        let matchName = normalizedName(match.name)
        let candidateAddress = normalizedName(candidate.address)
        let matchAddress = normalizedName(match.address)

        if !candidateName.isEmpty, !matchName.isEmpty {
            if matchName == candidateName { score += 0.75 }
            else if matchName.contains(candidateName) || candidateName.contains(matchName) { score += 0.68 }
            else { score += tokenOverlap(candidateName, matchName) * 0.62 }
        }
        if !candidateAddress.isEmpty, !matchAddress.isEmpty {
            if matchAddress == candidateAddress { score += 0.45 }
            else if matchAddress.contains(candidateAddress) || candidateAddress.contains(matchAddress) { score += 0.38 }
            else { score += tokenOverlap(candidateAddress, matchAddress) * 0.38 }
        }
        if match.rating != nil { score += 0.02 }
        return min(score, 1.0)
    }

    private func tokenOverlap(_ left: String, _ right: String) -> Double {
        let minimumTokenLength = 2
        let leftTokens = Set(left.split(separator: " ").map(String.init).filter { $0.count >= minimumTokenLength })
        let rightTokens = Set(right.split(separator: " ").map(String.init).filter { $0.count >= minimumTokenLength })
        guard !leftTokens.isEmpty else { return 0 }
        return Double(leftTokens.intersection(rightTokens).count) / Double(leftTokens.count)
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

    private func sourceOnlyCandidate(evidenceText: String, sourceURL: String) -> PendingReviewCandidate {
        let diagnostic = sourceOnlyDiagnostic(evidenceText: evidenceText, sourceURL: sourceURL)
        if let candidateName = unresolvedPlaceCandidateName(from: diagnostic.suggestedSearchQueries ?? []) {
            let upgradedDiagnostic = unresolvedPlaceDiagnostic(from: diagnostic, candidateName: candidateName)
            return PendingReviewCandidate(
                candidateName: candidateName,
                address: "",
                category: category(from: "\(candidateName) \(evidenceText)"),
                latitude: nil,
                longitude: nil,
                sourceURL: sourceURL,
                sourceText: evidenceText.isEmpty ? nil : evidenceText,
                evidence: upgradedDiagnostic.found + upgradedDiagnostic.attempts + diagnosticSearchEvidence(upgradedDiagnostic) + ["Next best clue: \(upgradedDiagnostic.nextBestClue)"],
                confidence: 0.32,
                missingInfo: upgradedDiagnostic.missingFields,
                savedAt: Date(),
                evidenceDiagnostic: upgradedDiagnostic,
                reviewState: "unresolved_place_candidate"
            )
        }
        return PendingReviewCandidate(
            candidateName: sourceOnlyDisplayName(for: sourceURL),
            address: "",
            category: "attraction",
            latitude: nil,
            longitude: nil,
            sourceURL: sourceURL,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: diagnostic.found + diagnostic.attempts + diagnosticSearchEvidence(diagnostic),
            confidence: 0,
            missingInfo: diagnostic.missingFields,
            savedAt: Date(),
            evidenceDiagnostic: diagnostic,
            isSourceOnly: true
        )
    }

    private func placeBearingSourceCandidate(
        from analysis: SocialPlaceAgentAnalysis,
        evidenceText: String,
        sourceURL: String
    ) -> PendingReviewCandidate {
        var diagnostic = placeBearingDiagnostic(from: analysis, evidenceText: evidenceText, sourceURL: sourceURL)
        let candidateName = unresolvedPlaceCandidateName(from: diagnostic.suggestedSearchQueries ?? [], analysis: analysis)
        if let candidateName {
            diagnostic = unresolvedPlaceDiagnostic(from: diagnostic, candidateName: candidateName)
        }
        return PendingReviewCandidate(
            candidateName: candidateName ?? placeBearingCandidateName(from: analysis),
            address: "",
            category: category(for: analysis.sourceIntent),
            sourceURL: sourceURL,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: diagnostic.found + diagnostic.attempts + diagnosticSearchEvidence(diagnostic) + ["Next best clue: \(diagnostic.nextBestClue)"],
            confidence: confidence(for: analysis.sourceIntent),
            missingInfo: diagnostic.missingFields,
            savedAt: Date(),
            evidenceDiagnostic: diagnostic,
            reviewState: candidateName == nil ? "place_bearing_source" : "unresolved_place_candidate"
        )
    }

    private func unresolvedPlaceDiagnostic(
        from diagnostic: SocialPlaceEvidenceDiagnostic,
        candidateName: String
    ) -> SocialPlaceEvidenceDiagnostic {
        var upgraded = diagnostic
        upgraded.found = appendUnique(upgraded.found, ["Candidate place name: \(candidateName)"])
        upgraded.attempts = appendUnique(upgraded.attempts, ["Promoted source clue to unresolved place candidate instead of showing the source as the title"])
        upgraded.missingFields = appendUnique(
            upgraded.missingFields.filter { missing in
                let lowered = missing.lowercased()
                return !lowered.contains("place name") &&
                    !lowered.contains("exact restaurant name") &&
                    !lowered.contains("exact venue")
            },
            ["Verified address", "Verified coordinates"]
        )
        upgraded.nextBestClue = "Confirm the address or Google Places match before saving this as a Map Stamp."
        return upgraded
    }

    private func placeBearingDiagnostic(
        from analysis: SocialPlaceAgentAnalysis,
        evidenceText: String,
        sourceURL: String
    ) -> SocialPlaceEvidenceDiagnostic {
        var found = ["Source URL: \(sourceURL)"]
        if let reason = analysis.placeBearingReason {
            found.append("Place-bearing source: \(reason)")
        }
        found.append("Source intent: \(analysis.sourceIntent.rawValue)")
        found.append("Resolver decision: \(analysis.resolverDecision.kind.rawValue)")
        if let topic = analysis.topic {
            found.append("Topic clue: \(topic)")
        }
        found.append(contentsOf: analysis.regionClues.map { "Region clue: \($0)" })
        found.append(contentsOf: analysis.recoveryHints.map { "Recovery hint: \($0.label)=\($0.queryFragment)" })

        return SocialPlaceEvidenceDiagnostic(
            found: appendUnique([], found),
            attempts: [
                "Checked public metadata/caption text for explicit place names",
                "Applied bounded resolver decision before any save action",
                "Classified the source as place-bearing even though no exact venue was verified",
                "Kept this in Review instead of inventing a map pin",
                "Prepared public source-recovery search queries",
                "Did not use logged-in Instagram scraping"
            ],
            missingFields: appendUnique(
                [],
                [
                    exactVenueMissingField(for: analysis.sourceIntent),
                    "Verified address",
                    "Verified coordinates"
                ]
            ),
            nextBestClue: "Run source recovery search or add the exact place name/map link before saving as a Map Stamp.",
            suggestedSearchQueries: sourceRecoverySearchQueries(evidenceText: evidenceText, sourceURL: sourceURL, analysis: analysis)
        )
    }

    private func sourceOnlyDiagnostic(evidenceText: String, sourceURL: String) -> SocialPlaceEvidenceDiagnostic {
        var found = ["Source URL: \(sourceURL)"]
        if !evidenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            found.append("Shared text/caption was present but did not contain a verified place candidate")
        }
        let searchQueries = sourceRecoverySearchQueries(evidenceText: evidenceText, sourceURL: sourceURL)
        return SocialPlaceEvidenceDiagnostic(
            found: found,
            attempts: [
                "Checked public metadata/caption text for explicit place names",
                "Checked social handles without treating creator handles as places",
                "Prepared public web search fallback queries for source-only recovery",
                "Did not use logged-in Instagram scraping"
            ],
            missingFields: [
                "Verified place name",
                "Verified address",
                "Verified coordinates"
            ],
            nextBestClue: "Run the suggested public searches, or share a caption, screenshot/OCR frame, map link, or visible venue handle.",
            suggestedSearchQueries: searchQueries.isEmpty ? nil : searchQueries
        )
    }

    private func diagnosticSearchEvidence(_ diagnostic: SocialPlaceEvidenceDiagnostic) -> [String] {
        (diagnostic.suggestedSearchQueries ?? []).map { "Suggested public search: \($0)" }
    }

    private func sourceRecoverySearchQueries(
        evidenceText: String,
        sourceURL: String,
        analysis: SocialPlaceAgentAnalysis? = nil
    ) -> [String] {
        var queries: [String] = []
        let url = URL(string: sourceURL)
        let host = url?.host()?.lowercased() ?? ""
        let reelID = instagramReelID(in: url)
        let cleanedEvidence = cleanHTMLText(evidenceText)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let analysis, analysis.isPlaceBearing {
            let keyword = searchKeyword(for: analysis.sourceIntent)
            let region = primaryRegion(from: analysis.regionClues)
            let topic = analysis.topic
            let phrase = meaningfulPlacePhrase(from: evidenceText)
            if let reelID {
                if let region {
                    queries.append("\"\(reelID)\" \(keyword) \(region)")
                }
                if let topic {
                    queries.append("\"\(reelID)\" \"\(topic)\"")
                } else if let phrase {
                    queries.append("\"\(reelID)\" \"\(phrase)\"")
                }
                queries.append("site:instagram.com/reel/\(reelID) \(keyword)")
            } else if let url, !host.isEmpty {
                queries.append("\(host) \(url.lastPathComponent) \(keyword)")
            }
            if let region, let phrase {
                queries.append("\"\(phrase)\" \(region) \(keyword)")
            }
            if let canonicalURL = canonicalSearchURL(from: url) {
                queries.append("\"\(canonicalURL)\"")
            }
            return Array(appendUnique([], queries).prefix(4))
        }

        if let reelID {
            queries.append("instagram reel \(reelID) place")
            queries.append("\(reelID) restaurant venue")
        } else if let url, !host.isEmpty {
            queries.append("\(host) \(url.lastPathComponent) place")
        }

        if let handle = firstSocialHandle(in: evidenceText) {
            queries.append("@\(handle) address")
        }

        if !cleanedEvidence.isEmpty {
            let snippet = String(cleanedEvidence.prefix(80))
            queries.append("\"\(snippet)\" place")
        }

        if let canonicalURL = canonicalSearchURL(from: url) {
            queries.append("\"\(canonicalURL)\"")
        }

        return Array(appendUnique([], queries).prefix(4))
    }

    private func placeBearingCandidateName(from analysis: SocialPlaceAgentAnalysis) -> String {
        let region = primaryRegion(from: analysis.regionClues)
        switch analysis.sourceIntent {
        case .restaurantRecommendation:
            return region.map { "\($0) restaurant recommendation clue" } ?? "Restaurant recommendation clue"
        case .cafeRecommendation:
            return region.map { "\($0) coffee shop clue" } ?? "Coffee shop clue"
        case .stayRecommendation:
            return region.map { "\($0) stay recommendation clue" } ?? "Stay recommendation clue"
        case .travelRecommendation:
            return region.map { "\($0) travel place clue" } ?? "Travel place clue"
        case .multiPlaceList:
            return analysis.topic ?? "Place list clue"
        case .singleVenuePost:
            return "Venue clue"
        case .unknownPlaceBearing:
            return region.map { "\($0) place clue" } ?? "Place clue"
        case .nonPlace, .creatorOnly:
            return "Social link"
        }
    }

    private func unresolvedPlaceCandidateName(
        from searchQueries: [String],
        analysis: SocialPlaceAgentAnalysis? = nil
    ) -> String? {
        let analysisHints = analysis.map { current in
            ([current.topic].compactMap { $0 } + current.recoveryHints
                .filter { $0.label != "region" && $0.label != "category" }
                .map(\.queryFragment))
        } ?? []

        for rawValue in analysisHints + searchQueries {
            guard let candidate = unresolvedPlaceCandidateName(fromRawSearchText: rawValue) else { continue }
            return candidate
        }
        return nil
    }

    private func unresolvedPlaceCandidateName(fromRawSearchText rawValue: String) -> String? {
        var candidate = cleanHTMLText(rawValue)
            .replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"site:\S+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\bD[A-Za-z0-9_-]{6,}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\binstagram\s+reel\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:restaurant|venue|place|address|cafe|coffee|hotel|map)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'“”"))

        if candidate.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil {
            for marker in [" 台北", " 臺北", " Taipei", " Taiwan", " 士林站", " Shilin Station"] {
                if let range = candidate.range(of: marker, options: [.caseInsensitive]) {
                    candidate = String(candidate[..<range.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        candidate = candidate
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，\"'“”"))

        guard candidate.count >= 2, candidate.count <= 80 else { return nil }
        let hasCJK = candidate.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil
        if !hasCJK && candidate.count <= 3 { return nil }
        guard isUsableCandidateName(candidate) else { return nil }
        guard !looksLikeMarketingLine(candidate) else { return nil }

        let lowered = candidate.lowercased()
        if ["la", "oc", "nyc", "sf", "taipei", "tokyo"].contains(lowered) { return nil }
        let genericValues = [
            "instagram",
            "social link",
            "restaurant recommendation",
            "restaurants in",
            "restaurant in",
            "coffee shops in",
            "coffee shop in",
            "cafes in",
            "cafe in",
            "where to eat",
            "favorite restaurants",
            "best restaurants",
            "top restaurants",
            "hidden gems",
            "coffee shop clue",
            "place clue",
            "source clue"
        ]
        if genericValues.contains(where: { lowered.contains($0) }) { return nil }
        if lowered.range(of: #"^(favorite|favourite|best|top|must-try|must try|iconic)\b"#, options: .regularExpression) != nil {
            return nil
        }
        return candidate
    }

    private func category(for intent: SocialPlaceSourceIntent) -> String {
        switch intent {
        case .restaurantRecommendation:
            return "food"
        case .cafeRecommendation:
            return "cafe"
        case .stayRecommendation:
            return "stay"
        case .travelRecommendation, .multiPlaceList, .singleVenuePost, .unknownPlaceBearing, .nonPlace, .creatorOnly:
            return "attraction"
        }
    }

    private func confidence(for intent: SocialPlaceSourceIntent) -> Double {
        switch intent {
        case .restaurantRecommendation, .cafeRecommendation, .stayRecommendation, .travelRecommendation:
            return 0.35
        case .multiPlaceList, .singleVenuePost:
            return 0.4
        case .unknownPlaceBearing:
            return 0.25
        case .nonPlace, .creatorOnly:
            return 0
        }
    }

    private func exactVenueMissingField(for intent: SocialPlaceSourceIntent) -> String {
        switch intent {
        case .restaurantRecommendation:
            return "Exact restaurant name"
        case .cafeRecommendation:
            return "Exact cafe name"
        case .stayRecommendation:
            return "Exact hotel/stay name"
        default:
            return "Exact place name"
        }
    }

    private func searchKeyword(for intent: SocialPlaceSourceIntent) -> String {
        switch intent {
        case .restaurantRecommendation:
            return "restaurant"
        case .cafeRecommendation:
            return "cafe"
        case .stayRecommendation:
            return "hotel resort"
        case .travelRecommendation, .multiPlaceList, .singleVenuePost, .unknownPlaceBearing:
            return "place"
        case .nonPlace, .creatorOnly:
            return "place"
        }
    }

    private func primaryRegion(from regionClues: [String]) -> String? {
        guard let clue = regionClues.first else { return nil }
        let lowered = clue.lowercased()
        if lowered == "losangeles" || lowered == "la" || lowered == "lacoffee" { return "LA" }
        if lowered == "orangecounty" || lowered == "oc" || lowered == "ocfood" { return "Orange County" }
        if lowered == "newyork" { return "New York" }
        return clue
    }

    private func meaningfulPlacePhrase(from evidenceText: String) -> String? {
        let patterns = [
            #"(?i)\b((?:favorite|favourite|best|top|must-try|must try|iconic|hidden gems?|where to eat)[^.\n\r]{0,90})"#,
            #"(?i)\b((?:restaurants?|cafes?|coffee shops?|hotels?|resorts?|things to do|places to visit)\s+in\s+(?:LA|Los Angeles|OC|Orange County|Tokyo|Taipei|Seoul|Paris|London|New York|[A-Z][A-Za-z .'-]{2,60}))\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(evidenceText.startIndex..<evidenceText.endIndex, in: evidenceText)
            guard let match = regex.firstMatch(in: evidenceText, range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: evidenceText) else { continue }
            let cleaned = cleanHTMLText(String(evidenceText[captureRange]))
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，\"'“”"))
            if cleaned.count >= 8, cleaned.count <= 120 {
                return cleaned
            }
        }
        return nil
    }

    private func instagramReelID(in url: URL?) -> String? {
        guard let url,
              url.host()?.lowercased().contains("instagram") == true else { return nil }
        let components = url.pathComponents
        guard let markerIndex = components.firstIndex(where: { $0.lowercased() == "reel" || $0.lowercased() == "reels" }),
              components.indices.contains(markerIndex + 1) else { return nil }
        let id = components[markerIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return id.isEmpty ? nil : id
    }

    private func canonicalSearchURL(from url: URL?) -> String? {
        guard let url else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let value = components?.url?.absoluteString ?? url.absoluteString
        return value.isEmpty ? nil : value
    }

    private func candidateDiagnostic(for candidate: PendingReviewCandidate, evidenceText: String, sourceURL: String) -> SocialPlaceEvidenceDiagnostic {
        var found = [
            "Source URL: \(sourceURL)",
            "Candidate place name: \(candidate.candidateName)"
        ]
        if !candidate.address.isEmpty {
            found.append("Address/location clue: \(candidate.address)")
        }
        if !candidate.evidence.isEmpty {
            found.append(contentsOf: candidate.evidence.prefix(3))
        }

        var missing: [String] = []
        if candidate.address.isEmpty { missing.append("Verified address") }
        if !candidate.hasReliableCoordinates { missing.append("Verified coordinates") }
        missing.append(contentsOf: candidate.missingInfo)

        return SocialPlaceEvidenceDiagnostic(
            found: appendUnique([], found),
            attempts: [
                "Checked public metadata/caption text for explicit place names",
                "Kept plausible venue evidence in Review instead of inventing map coordinates",
                "Did not use logged-in Instagram scraping"
            ],
            missingFields: appendUnique([], missing),
            nextBestClue: candidate.address.isEmpty
                ? "Confirm the exact address or share a map link before saving this as a Map Stamp."
                : "Confirm coordinates or choose a Google Places match before saving this as a Map Stamp."
        )
    }

    private func refinedDiagnosticAfterPlacesMatch(
        existing: SocialPlaceEvidenceDiagnostic?,
        match: GooglePlaceMatch
    ) -> SocialPlaceEvidenceDiagnostic {
        let base = existing ?? SocialPlaceEvidenceDiagnostic(found: [], attempts: [], missingFields: [], nextBestClue: "")
        var newFound = [
            "Google Places match: \(match.name)",
            "Verified coordinates: \(match.latitude), \(match.longitude)"
        ]
        if !match.address.isEmpty {
            newFound.insert("Verified address: \(match.address)", at: 1)
        }
        let found = appendUnique(base.found, newFound)
        let attempts = appendUnique(
            base.attempts,
            ["Checked Google Places for a matching place record"]
        )
        let missing = base.missingFields.filter { field in
            field != "Verified address" &&
            field != "Confirm address" &&
            field != "Verified coordinates" &&
            field != "Confirm coordinates"
        }
        return SocialPlaceEvidenceDiagnostic(
            found: found,
            attempts: attempts,
            missingFields: appendUnique([], missing),
            nextBestClue: "Confirm this Google Places match before saving it as a Map Stamp."
        )
    }

    private func sourceOnlyDisplayName(for sourceURL: String) -> String {
        guard let url = URL(string: sourceURL) else { return "Social link" }
        let path = url.path.lowercased()
        if path.contains("/reel/") || path.contains("/reels/") { return "Instagram reel" }
        if url.host?.lowercased().contains("instagram") == true { return "Instagram link" }
        return "Social link"
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

    private func venueIntroName(in text: String) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }

        for line in lines where looksLikeVenueIntroLine(line) {
            if let quoted = firstCapture(in: line, pattern: #"[「『\"]\s*([^」』\"]{2,80})\s*[」』\"]"#) {
                let cleaned = cleanCandidateName(quoted)
                if isUsableCandidateName(cleaned), !looksLikeMarketingLine(cleaned) {
                    return cleaned
                }
            }
        }
        return nil
    }

    private func looksLikeVenueIntroLine(_ line: String) -> Bool {
        let pattern = #"名店|餐廳|餐厅|正式插旗|插旗|開幕|新店|店名|restaurant|from\s+tokyo|來自東京|頂級燒肉"#
        return line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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
            let patterns: [(pattern: String, valueCaptureIndex: Int)] = [
                (#"<meta[^>]+(?:property|name)=["']\#(escapedKey)["'][^>]+content=(["'])(.*?)\1[^>]*>"#, 2),
                (#"<meta[^>]+content=(["'])(.*?)\1[^>]+(?:property|name)=["']\#(escapedKey)["'][^>]*>"#, 2)
            ]

            for (pattern, valueCaptureIndex) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
                let range = NSRange(html.startIndex..<html.endIndex, in: html)
                guard let match = regex.firstMatch(in: html, range: range),
                      match.numberOfRanges > valueCaptureIndex,
                      let valueRange = Range(match.range(at: valueCaptureIndex), in: html) else {
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
