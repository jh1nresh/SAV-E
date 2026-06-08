import Foundation
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(Vision)
import Vision
#endif

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

enum SocialPlaceEvidenceResolverOutcome: String, Codable, Hashable {
    case mapStamp
    case reviewCandidate
    case sourceOnly
}

struct SocialPlaceEvidenceResolverInput {
    var sourceURL: String
    var resolvedURL: String?
    var caption: String?
    var authorHandle: String?
    var visibleLocationTags: [String]
    var taggedHandles: [String]
    var cityClues: [String]
    var categoryClues: [String]
    var ocrLines: [String]

    init(
        sourceURL: String,
        resolvedURL: String? = nil,
        caption: String? = nil,
        authorHandle: String? = nil,
        visibleLocationTags: [String] = [],
        taggedHandles: [String] = [],
        cityClues: [String] = [],
        categoryClues: [String] = [],
        ocrLines: [String] = []
    ) {
        self.sourceURL = sourceURL
        self.resolvedURL = resolvedURL
        self.caption = caption
        self.authorHandle = authorHandle
        self.visibleLocationTags = visibleLocationTags
        self.taggedHandles = taggedHandles
        self.cityClues = cityClues
        self.categoryClues = categoryClues
        self.ocrLines = ocrLines
    }
}

struct SocialPlaceRawSource {
    var sourceURL: String
    var resolvedURL: String?
    var caption: String?
    var authorHandle: String?
    var ocrLines: [String]
}

struct SocialPlaceExtractedClues {
    var caption: String?
    var authorHandle: String?
    var visibleLocationTags: [String]
    var taggedHandles: [String]
    var cityClues: [String]
    var categoryClues: [String]
    var placeClues: [String]
}

struct SocialPlaceEvidenceResolverResult {
    var rawSource: SocialPlaceRawSource
    var extracted: SocialPlaceExtractedClues
    var searchQueries: [String]
    var outcome: SocialPlaceEvidenceResolverOutcome
    var candidate: PendingReviewCandidate
    var evidence: [String]
    var missingFields: [String]
    var confidence: Double
    var confidenceReason: String
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

    private let placeResolverService: PlaceResolverServiceProtocol
    private let publicSourceSearchService: PublicSourceSearchServiceProtocol
    private let thumbnailImageByteLimit = 6_000_000

    init(
        googlePlacesService: GooglePlacesServiceProtocol = GooglePlacesService.shared,
        publicSourceSearchService: PublicSourceSearchServiceProtocol = PublicSourceSearchService.shared,
        placeResolverService: PlaceResolverServiceProtocol? = nil
    ) {
        self.placeResolverService = placeResolverService ?? PlaceResolverService(googlePlacesService: googlePlacesService)
        self.publicSourceSearchService = publicSourceSearchService
    }

    func resolveEvidence(_ input: SocialPlaceEvidenceResolverInput) async -> SocialPlaceEvidenceResolverResult {
        let evidenceText = resolverEvidenceText(from: input)
        let sourceURL = input.resolvedURL ?? input.sourceURL
        let analysis = analyze(evidenceText: evidenceText, sourceURL: sourceURL)
        let generatedQueries = sourceRecoverySearchQueries(evidenceText: evidenceText, sourceURL: sourceURL, analysis: analysis)
        let candidates = (try? await recoverReviewCandidates(fromEvidenceText: evidenceText, sourceURL: sourceURL)) ??
            reviewCandidatesOrSourceOnly(fromEvidenceText: evidenceText, sourceURL: sourceURL)
        let candidate = candidates.first ?? sourceOnlyCandidate(evidenceText: evidenceText, sourceURL: sourceURL)
        let outcome = resolverOutcome(for: candidate)
        let extracted = extractedClues(from: input, analysis: analysis, candidate: candidate)
        let confidenceReason = resolverConfidenceReason(outcome: outcome, candidate: candidate, analysis: analysis)
        let missingFields = appendUnique(candidate.evidenceDiagnostic?.missingFields ?? [], candidate.missingInfo)
        let evidence = resolverEvidence(
            input: input,
            extracted: extracted,
            candidate: candidate,
            outcome: outcome,
            confidenceReason: confidenceReason
        )

        return SocialPlaceEvidenceResolverResult(
            rawSource: SocialPlaceRawSource(
                sourceURL: input.sourceURL,
                resolvedURL: input.resolvedURL,
                caption: input.caption,
                authorHandle: extracted.authorHandle,
                ocrLines: input.ocrLines
            ),
            extracted: extracted,
            searchQueries: appendUnique(generatedQueries, candidate.evidenceDiagnostic?.suggestedSearchQueries ?? []),
            outcome: outcome,
            candidate: candidate,
            evidence: evidence,
            missingFields: missingFields,
            confidence: candidate.confidence,
            confidenceReason: confidenceReason
        )
    }

    private struct PublicMetadata {
        var resolvedURL: String?
        var title: String?
        var description: String?
        var imageURL: URL?
        var videoURL: URL?
        var jsonCaption: String?

        var evidenceLines: [String] {
            [title, description, jsonCaption]
                .compactMap { $0 }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    func reviewCandidates(from url: URL) async throws -> [PendingReviewCandidate] {
        let metadata = await fetchMetadata(from: url)
        let ocrLines = await thumbnailOCRLines(from: metadata.imageURL)
        let ocrEvidence = ocrLines.isEmpty ? nil : ocrLines.joined(separator: "\n")
        let videoEvidence = metadata.videoURL.map { "Video metadata URL: \($0.absoluteString)" }
        let evidenceText = (metadata.evidenceLines + [videoEvidence, ocrEvidence])
            .compactMap { $0 }
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let sourceURL = metadata.resolvedURL ?? url.absoluteString
        let candidates = try await recoverReviewCandidates(fromEvidenceText: evidenceText, sourceURL: sourceURL)
        guard !ocrLines.isEmpty else { return candidates }
        return candidates.map { candidate in
            candidate.withThumbnailOCREvidence(ocrLines)
        }
    }

    func recoverReviewCandidates(fromEvidenceText evidenceText: String, sourceURL: String) async throws -> [PendingReviewCandidate] {
        let initial = reviewCandidatesOrSourceOnly(fromEvidenceText: evidenceText, sourceURL: sourceURL)
        let shouldRunRecovery = initial.contains {
            $0.isPlaceBearingSource || $0.isSourceOnly || $0.reviewState == "unresolved_place_candidate"
        }
        guard shouldRunRecovery else {
            return await refineCandidates(initial, evidenceText: evidenceText)
        }

        let analysis = analyze(evidenceText: evidenceText, sourceURL: sourceURL)
        let hasUnresolvedInitialCandidate = initial.contains { $0.reviewState == "unresolved_place_candidate" }
        guard analysis.isPlaceBearing || analysis.resolverDecision.shouldRunPublicSearch || hasUnresolvedInitialCandidate else { return initial }

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
            let matches = try await placeResolverMatches(for: candidate, evidenceText: evidenceText ?? candidate.sourceText ?? "")
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
                    "\(match.provider.displayName) refined match: \(match.name)",
                    "\(match.provider.displayName) address: \(match.address)",
                    "\(match.coordinateEvidenceLabel): \(match.latitude), \(match.longitude)"
                ]
            )
            refined.missingInfo = SocialPlaceEvidenceScorer.missingInfo(
                tier: .likely,
                hasAddress: !match.address.isEmpty,
                source: "\(match.provider.displayName) refined; user must confirm before saving"
            )
            refined.evidenceDiagnostic = refinedDiagnosticAfterPlacesMatch(
                existing: refined.evidenceDiagnostic,
                match: match
            )
            refined.reviewState = "map_match_ready"
            return refined
        } catch {
            var unresolved = candidate
            let failureMessages = containsCJK(query)
                ? [
                    PlaceMatchProvider.googlePlaces.refinementFailureMessage,
                    PlaceMatchProvider.amap.refinementFailureMessage,
                    PlaceMatchProvider.baidu.refinementFailureMessage
                ]
                : [PlaceMatchProvider.googlePlaces.refinementFailureMessage]
            unresolved.missingInfo = appendUnique(
                unresolved.missingInfo,
                failureMessages
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

    private func resolverEvidenceText(from input: SocialPlaceEvidenceResolverInput) -> String {
        [
            input.caption,
            input.visibleLocationTags.joined(separator: " "),
            input.taggedHandles.map { "@\($0)" }.joined(separator: " "),
            input.cityClues.joined(separator: " "),
            input.categoryClues.joined(separator: " "),
            input.ocrLines.joined(separator: "\n")
        ]
        .compactMap { $0 }
        .map(cleanHTMLText)
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private func resolverOutcome(for candidate: PendingReviewCandidate) -> SocialPlaceEvidenceResolverOutcome {
        if candidate.isSourceOnly { return .sourceOnly }
        if candidate.evidenceDiagnostic?.canSaveAsMapStamp == true || (candidate.hasReliableCoordinates && !candidate.address.isEmpty) {
            return .mapStamp
        }
        return .reviewCandidate
    }

    private func extractedClues(
        from input: SocialPlaceEvidenceResolverInput,
        analysis: SocialPlaceAgentAnalysis,
        candidate: PendingReviewCandidate
    ) -> SocialPlaceExtractedClues {
        let authorHandle = cleanHandle(input.authorHandle) ?? analysis.sourceActors.first(where: { $0.role == .creatorHandle || $0.role == .sourceAccount })?.handle
        let taggedHandles = appendUnique(
            input.taggedHandles.compactMap(cleanHandle),
            analysis.placesFound.flatMap(\.venueHandles) + analysis.groups.flatMap(\.venueHandles)
        )
        let cityClues = appendUnique(input.cityClues, analysis.regionClues + [candidate.address].filter { !$0.isEmpty })
        let categoryClues = appendUnique(input.categoryClues, [candidate.category, analysis.sourceIntent.rawValue])
        let placeClues = appendUnique(
            analysis.placesFound.map(\.displayName),
            [candidate.candidateName].filter { !$0.isEmpty && !candidate.isSourceOnly }
        )

        return SocialPlaceExtractedClues(
            caption: input.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
            authorHandle: authorHandle,
            visibleLocationTags: appendUnique(input.visibleLocationTags, analysis.regionClues),
            taggedHandles: taggedHandles,
            cityClues: cityClues,
            categoryClues: categoryClues,
            placeClues: placeClues
        )
    }

    private func resolverConfidenceReason(
        outcome: SocialPlaceEvidenceResolverOutcome,
        candidate: PendingReviewCandidate,
        analysis: SocialPlaceAgentAnalysis
    ) -> String {
        switch outcome {
        case .mapStamp:
            return "Places resolver verified a matching address/coordinates; user still confirms before Map Stamp."
        case .reviewCandidate:
            let reason = analysis.placeBearingReason ?? "source has place-bearing caption/tag/location clues"
            return "\(reason); kept as Review Candidate until address/coordinates are verified."
        case .sourceOnly:
            return "Raw source was preserved, but SAV-E found no verified place identity yet."
        }
    }

    private func resolverEvidence(
        input: SocialPlaceEvidenceResolverInput,
        extracted: SocialPlaceExtractedClues,
        candidate: PendingReviewCandidate,
        outcome: SocialPlaceEvidenceResolverOutcome,
        confidenceReason: String
    ) -> [String] {
        var evidence = [
            "Raw source saved: \(input.sourceURL)",
            "Resolver outcome: \(outcome.rawValue)",
            "Confidence reason: \(confidenceReason)"
        ]
        if let caption = extracted.caption, !caption.isEmpty {
            evidence.append("Caption captured: \(String(caption.prefix(220)))")
        }
        if let authorHandle = extracted.authorHandle {
            evidence.append("Author handle: @\(authorHandle)")
        }
        evidence.append(contentsOf: extracted.taggedHandles.map { "Tagged/venue handle: @\($0)" })
        evidence.append(contentsOf: extracted.visibleLocationTags.map { "Visible location/tag: \($0)" })
        evidence.append(contentsOf: extracted.placeClues.map { "Place clue: \($0)" })
        evidence.append(contentsOf: candidate.evidence)
        if let diagnostic = candidate.evidenceDiagnostic {
            evidence.append(contentsOf: diagnostic.found)
            evidence.append(contentsOf: diagnostic.attempts)
        }
        return appendUnique([], evidence)
    }

    private func cleanHandle(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .trimmingCharacters(in: CharacterSet(charactersIn: " @\n\t\r"))
            .lowercased()
        return cleaned.isEmpty ? nil : cleaned
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
            let recoveredAddress = sourceRecoveryAddress(from: result)
            let address = recoveredAddress ?? region ?? ""
            let tier = SocialPlaceEvidenceTier.weakCandidate
            let evidence = appendUnique(
                [],
                [
                    "Source URL: \(sourceURL)",
                    "Evidence tier: \(tier.rawValue)",
                    "Recovered venue candidate: \(name)",
                    recoveredAddress.map { "Recovered address evidence: \($0)" } ?? "",
                    "Public web search result: \(result.title) — \(result.snippet)",
                    result.url.isEmpty ? "" : "Public web search URL: \(result.url)"
                ]
            )
            return PendingReviewCandidate(
                candidateName: name,
                address: address,
                category: category(for: analysis.sourceIntent),
                sourceURL: sourceURL,
                sourceText: combinedText,
                evidence: evidence,
                confidence: recoveredAddress == nil ? 0.58 : 0.64,
                missingInfo: appendUnique(
                    recoveredAddress == nil ? ["Verified address"] : [],
                    ["Google Places match required", "Verified coordinates", "User confirmation required"]
                ),
                savedAt: Date(),
                evidenceDiagnostic: sourceRecoveryDiagnostic(
                    analysis: analysis,
                    sourceURL: sourceURL,
                    result: result,
                    recoveredName: name,
                    recoveredAddress: recoveredAddress
                ),
                reviewState: "source_recovered_candidate"
            )
        }
    }

    private func recoveredVenueName(from result: PublicSourceSearchResult, analysis: SocialPlaceAgentAnalysis) -> String? {
        let text = "\(result.title)\n\(result.snippet)"
        if let hinted = sourceRecoveryVenueNameHint(phrase: nil, topic: analysis.topic, evidenceText: analysis.recoveryHints.map(\.queryFragment).joined(separator: "\n")),
           text.localizedCaseInsensitiveContains(hinted) {
            return hinted
        }
        let patterns = [
            #"(?i)favorite restaurants? in [A-Za-z .'-]{2,40}\s+is\s+([A-Z][A-Za-z0-9 &'’'\-.]{2,70})"#,
            #"(?i)favorite restaurants? in [A-Za-z .'-]{2,40}\s*[:\-–—]\s*([A-Z][A-Za-z0-9 &'’'\-.]{2,70})"#,
            #"(?i)(?:at|try|visit|saved?|spot is|restaurant is|cafe is)\s+([A-Z][A-Za-z0-9 &'’'\-.]{2,70})"#,
            #"(?:店名|餐廳|餐厅|餐館|餐馆)\s*[：:]\s*([^\n\r，,。]{2,50})"#
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
        if let titleName = recoveredVenueNameFromSearchTitle(result.title) {
            return titleName
        }
        return nil
    }

    private func recoveredVenueNameFromSearchTitle(_ title: String) -> String? {
        let cleanedTitle = cleanHTMLText(title)
        let candidates = cleanedTitle
            .components(separatedBy: CharacterSet(charactersIn: "|｜-–—"))
            .map(cleanRecoveredVenueName)
        for candidate in candidates where isUsableCandidateName(candidate) && !looksLikeMarketingLine(candidate) {
            return candidate
        }
        return nil
    }

    private func sourceRecoveryAddress(from result: PublicSourceSearchResult) -> String? {
        let text = "\(result.title)\n\(result.snippet)"
        let patterns = [
            #"((?:台灣)?(?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)市[^\n\r，,。；;]{0,40}\d{1,6}\s*(?:號|号)?(?:B\d|[0-9一二三四五六七八九十]+樓)?)"#,
            #"((?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)市[^\n\r，,。；;]{0,50})"#,
            #"(\b\d{1,6}\s+[A-Za-z0-9 .'-]{2,80}\b(?:Street|St\.?|Road|Rd\.?|Avenue|Ave\.?|Boulevard|Blvd\.?|Lane|Ln\.?|Drive|Dr\.?|Way|Highway|Hwy\.?|Coast Hwy)\b(?:,\s*[A-Za-z .'-]{2,40})?)"#
        ]
        for pattern in patterns {
            guard let match = firstCapture(in: text, pattern: pattern) else { continue }
            let cleaned = cleanLocationMarker(from: match)
                .replacingOccurrences(of: #"^(?:餐廳地點|餐厅地点|地點|地点|地址)\s*[:：]?\s*"#, with: "", options: .regularExpression)
            if !cleaned.isEmpty { return cleaned }
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
        recoveredName: String,
        recoveredAddress: String?
    ) -> SocialPlaceEvidenceDiagnostic {
        SocialPlaceEvidenceDiagnostic(
            found: appendUnique(
                [],
                [
                    "Source URL: \(sourceURL)",
                    "Place-bearing source: \(analysis.placeBearingReason ?? analysis.sourceIntent.rawValue)",
                    "Recovered venue candidate: \(recoveredName)",
                    recoveredAddress.map { "Recovered address evidence: \($0)" } ?? "",
                    "Public web search result: \(result.title)",
                    result.url.isEmpty ? "" : "Public web search URL: \(result.url)"
                ]
            ),
            attempts: appendUnique(
                analysisMethodAttempts(evidenceText: result.snippet, sourceURL: sourceURL),
                [
                    "Checked public metadata/caption/OCR text for place-bearing intent",
                    "Ran public web search recovery queries",
                "Extracted venue candidate from public search snippets",
                    "Prepared map provider refinement query",
                    "Did not use logged-in social scraping"
                ]
            ),
            missingFields: appendUnique(recoveredAddress == nil ? ["Verified address"] : [], ["Verified coordinates"]),
            nextBestClue: "Confirm the map provider match before saving this as a Map Stamp."
        )
    }

    func reviewCandidatesOrSourceOnly(fromEvidenceText evidenceText: String, sourceURL: String) -> [PendingReviewCandidate] {
        if let directMapCandidate = directChinaMapCandidate(evidenceText: evidenceText, sourceURL: sourceURL) {
            return [directMapCandidate]
        }

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
        let parserCandidates = analyze(evidenceText: evidenceText, sourceURL: sourceURL)
            .placesFound
            .filter { $0.displayName != "Address-only place clue" }
            .map { pendingReviewCandidate(from: $0, sourceURL: sourceURL, sourceText: evidenceText) }
        let heuristicCandidates = analyzedCandidates(from: evidenceText, sourceURL: sourceURL)
        return rankedCandidates(parserCandidates + heuristicCandidates)
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
            .map { candidate in
                var normalized = candidate
                normalized.address = cleanLocationMarker(from: candidate.address)
                return normalized
            }
            .filter { !isTransitAccessCandidate($0) }
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

    private func isTransitAccessCandidate(_ candidate: PendingReviewCandidate) -> Bool {
        let name = candidate.candidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = candidate.address.trimmingCharacters(in: .whitespacesAndNewlines)
        if SocialPlaceEvidenceScorer.looksLikeTransitAccessLine(name) {
            return true
        }
        if SocialPlaceEvidenceScorer.looksLikeTransitAccessLine(address) {
            return true
        }
        return name == "Address-only place clue" &&
            (address.contains("出口") || address.localizedCaseInsensitiveContains("exit"))
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

    private func directChinaMapCandidate(evidenceText: String, sourceURL: String) -> PendingReviewCandidate? {
        let mapURLStrings = ([sourceURL] + embeddedURLStrings(in: evidenceText))
            .filter { !$0.isEmpty }
        for urlString in mapURLStrings {
            guard let match = ChinaMapDeepLinkParser.match(from: urlString) else { continue }
            let diagnostic = SocialPlaceEvidenceDiagnostic(
                found: appendUnique(
                    [],
                    [
                        "Source URL: \(sourceURL)",
                        "Direct \(match.provider.displayName) map link: \(match.name)",
                        match.address.isEmpty ? "" : "Verified address: \(match.address)",
                        "Verified coordinates: \(match.latitude), \(match.longitude)",
                        "Coordinate system: \(match.coordinateSystem.rawValue)"
                    ]
                ),
                attempts: appendUnique(
                    analysisMethodAttempts(evidenceText: evidenceText, sourceURL: sourceURL),
                    ["Parsed shared map deep link before public metadata recovery"]
                ),
                missingFields: [],
                nextBestClue: "Confirm this \(match.provider.displayName) deep-link match before saving it as a Map Stamp."
            )
            return PendingReviewCandidate(
                candidateName: match.name,
                address: match.address,
                category: category(from: "\(match.name) \(match.address)"),
                latitude: match.latitude,
                longitude: match.longitude,
                sourceURL: sourceURL,
                sourceText: evidenceText.isEmpty ? nil : evidenceText,
                evidence: diagnostic.found + diagnostic.attempts + ["Map provider: \(match.provider.rawValue)", "\(match.coordinateEvidenceLabel): \(match.latitude), \(match.longitude)"],
                confidence: 0.86,
                missingInfo: ["User confirmation required"],
                savedAt: Date(),
                evidenceDiagnostic: diagnostic,
                reviewState: "map_match_ready"
            )
        }
        return nil
    }

    private func embeddedURLStrings(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>\"]+|(?:iosamap|amapuri|baidumap)://[^\s<>\"]+"#, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;。；，)）]】\"'"))
        }
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
            let imageURL = metadataImageURL(in: html, baseURL: response.url ?? url)
            let videoURL = metadataVideoURL(in: html, baseURL: response.url ?? url)
            let jsonCaption = embeddedSocialCaption(in: html)
            return PublicMetadata(
                resolvedURL: response.url?.absoluteString ?? url.absoluteString,
                title: title,
                description: description,
                imageURL: imageURL,
                videoURL: videoURL,
                jsonCaption: jsonCaption
            )
        } catch {
            return PublicMetadata(resolvedURL: url.absoluteString, title: nil, description: nil, imageURL: nil, videoURL: nil, jsonCaption: nil)
        }
    }

    private func metadataImageURL(in html: String, baseURL: URL) -> URL? {
        guard let value = metadataValue(in: html, keys: ["og:image:secure_url", "og:image", "twitter:image"]) else {
            return nil
        }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        return isSafePublicHTTPURL(url) ? url : nil
    }

    private func metadataVideoURL(in html: String, baseURL: URL) -> URL? {
        guard let value = metadataValue(in: html, keys: [
            "og:video:secure_url",
            "og:video:url",
            "og:video",
            "twitter:player:stream",
            "twitter:player"
        ]) else {
            return nil
        }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        return isSafePublicHTTPURL(url) ? url : nil
    }

    private func embeddedSocialCaption(in html: String) -> String? {
        let patterns = [
            #"\"caption\"\s*:\s*\{[^{}]*\"text\"\s*:\s*\"((?:\\.|[^\"])*)\""#,
            #"\"edge_media_to_caption\"\s*:\s*\{.*?\"text\"\s*:\s*\"((?:\\.|[^\"])*)\""#,
            #"\"accessibility_caption\"\s*:\s*\"((?:\\.|[^\"])*)\""#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: html) else { continue }
            let decoded = decodeJSONStringFragment(String(html[valueRange]))
            let cleaned = cleanHTMLText(decoded)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    private func thumbnailOCRLines(from imageURL: URL?) async -> [String] {
        guard let imageURL, isSafePublicHTTPURL(imageURL) else { return [] }
        do {
            var request = URLRequest(url: imageURL)
            request.timeoutInterval = 8
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
            let fetcher = SafeThumbnailDataFetcher(maxBytes: thumbnailImageByteLimit, isSafeURL: isSafePublicHTTPURL)
            let (data, _) = try await fetcher.fetch(request)
            return await recognizedThumbnailTextLines(from: data)
        } catch {
            return []
        }
    }

    private func isSafePublicHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".localhost") { return false }
        if host == "0.0.0.0" || host == "::1" { return false }
        let privateIPv4Patterns = [
            #"^127\."#,
            #"^10\."#,
            #"^192\.168\."#,
            #"^169\.254\."#,
            #"^172\.(1[6-9]|2[0-9]|3[0-1])\."#
        ]
        return !privateIPv4Patterns.contains { pattern in
            host.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private final class SafeThumbnailDataFetcher: NSObject, URLSessionDataDelegate {
        private enum FetchError: Error {
            case invalidResponse
            case unsafeRedirect
            case tooLarge
        }

        private let maxBytes: Int
        private let isSafeURL: (URL) -> Bool
        private let lock = NSLock()
        private var data = Data()
        private var response: HTTPURLResponse?
        private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        private var didFinish = false
        private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

        init(maxBytes: Int, isSafeURL: @escaping (URL) -> Bool) {
            self.maxBytes = maxBytes
            self.isSafeURL = isSafeURL
        }

        func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()

                session.dataTask(with: request).resume()
            }
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            guard let url = request.url, isSafeURL(url) else {
                completionHandler(nil)
                task.cancel()
                finish(.failure(FetchError.unsafeRedirect))
                return
            }
            completionHandler(request)
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard let http = response as? HTTPURLResponse,
                  let finalURL = http.url,
                  isSafeURL(finalURL),
                  (200..<300).contains(http.statusCode) else {
                completionHandler(.cancel)
                finish(.failure(FetchError.invalidResponse))
                return
            }

            if response.expectedContentLength > Int64(maxBytes) {
                completionHandler(.cancel)
                finish(.failure(FetchError.tooLarge))
                return
            }

            lock.lock()
            self.response = http
            lock.unlock()
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            lock.lock()
            self.data.append(data)
            let isTooLarge = self.data.count > maxBytes
            lock.unlock()

            if isTooLarge {
                dataTask.cancel()
                finish(.failure(FetchError.tooLarge))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error {
                finish(.failure(error))
                return
            }

            lock.lock()
            let data = self.data
            let response = self.response
            lock.unlock()

            guard let response else {
                finish(.failure(FetchError.invalidResponse))
                return
            }
            finish(.success((data, response)))
        }

        private func finish(_ result: Result<(Data, HTTPURLResponse), Error>) {
            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return
            }
            didFinish = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()

            session.invalidateAndCancel()
            continuation?.resume(with: result)
        }
    }

    private func recognizedThumbnailTextLines(from imageData: Data) async -> [String] {
        #if canImport(Vision) && canImport(ImageIO)
        guard let cgImage = downsampledCGImage(from: imageData) else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations
                    .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
        #else
        return []
        #endif
    }

    #if canImport(ImageIO)
    private func downsampledCGImage(from imageData: Data, maxPixelSize: CGFloat = 1_024) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions) else { return nil }
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions)
    }
    #endif

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
        if isAddressOnlyPlaceClue(candidate), !candidate.address.isEmpty {
            return [candidate.address]
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

    private func placeResolverMatches(for candidate: PendingReviewCandidate, evidenceText: String) async throws -> [PlaceProviderMatch] {
        var allMatches: [PlaceProviderMatch] = []
        var seenIDs = Set<String>()
        for query in refinementQueries(for: candidate, evidenceText: evidenceText).prefix(4) {
            let matches = try await placeResolverService.searchPlace(query: query, near: nil)
            for match in matches {
                let key = "\(match.provider.rawValue):\(match.id)"
                guard !seenIDs.contains(key) else { continue }
                seenIDs.insert(key)
                allMatches.append(match)
            }
        }
        return allMatches
    }

    private func bestAcceptableRefinement(in matches: [PlaceProviderMatch], for candidate: PendingReviewCandidate) -> PlaceProviderMatch? {
        matches
            .map { (match: $0, score: refinementScore($0, for: candidate)) }
            .filter { $0.score >= 0.62 }
            .sorted { $0.score > $1.score }
            .first?.match
    }

    private func refinementScore(_ match: PlaceProviderMatch, for candidate: PendingReviewCandidate) -> Double {
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
            if matchAddress == candidateAddress { score += isAddressOnlyPlaceClue(candidate) ? 0.78 : 0.45 }
            else if matchAddress.contains(candidateAddress) || candidateAddress.contains(matchAddress) { score += isAddressOnlyPlaceClue(candidate) ? 0.72 : 0.38 }
            else { score += tokenOverlap(candidateAddress, matchAddress) * (isAddressOnlyPlaceClue(candidate) ? 0.72 : 0.38) }
        }
        if match.rating != nil { score += 0.02 }
        return min(score, 1.0)
    }

    private func isAddressOnlyPlaceClue(_ candidate: PendingReviewCandidate) -> Bool {
        candidate.candidateName == "Address-only place clue"
    }

    private func tokenOverlap(_ left: String, _ right: String) -> Double {
        let minimumTokenLength = 2
        let leftTokens = Set(left.split(separator: " ").map(String.init).filter { $0.count >= minimumTokenLength })
        let rightTokens = Set(right.split(separator: " ").map(String.init).filter { $0.count >= minimumTokenLength })
        guard !leftTokens.isEmpty else { return 0 }
        return Double(leftTokens.intersection(rightTokens).count) / Double(leftTokens.count)
    }

    private func isAcceptableRefinement(_ match: PlaceProviderMatch, for candidate: PendingReviewCandidate) -> Bool {
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

    private func containsCJK(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value)) ||
                (0x3400...0x4DBF).contains(Int(scalar.value))
        }
    }

    private func chineseCityClue(in text: String) -> String? {
        let cities = ["台北", "臺北", "台中", "臺中", "台南", "臺南", "高雄", "東京", "大阪", "京都", "北京", "上海", "首爾"]
        return cities.first { text.contains($0) }
    }

    private func sourceOnlyCandidate(evidenceText: String, sourceURL: String) -> PendingReviewCandidate {
        let diagnostic = sourceOnlyDiagnostic(evidenceText: evidenceText, sourceURL: sourceURL)
        if xiaohongshuLinkContext(sourceURL: sourceURL)?.isShortLink != true,
           let candidateName = unresolvedPlaceCandidateName(from: diagnostic.suggestedSearchQueries ?? []),
           candidateName != socialPostDescriptor(in: URL(string: sourceURL))?.id {
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
        var found = appendUnique(
            ["Source URL: \(sourceURL)"],
            evidenceContentFindings(evidenceText: evidenceText)
        )
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

        let searchQueries = sourceRecoverySearchQueries(evidenceText: evidenceText, sourceURL: sourceURL, analysis: analysis)
        let missingFields = appendUnique(
            [],
            [
                exactVenueMissingField(for: analysis.sourceIntent),
                "Verified address",
                "Verified coordinates"
            ]
        )

        return SocialPlaceEvidenceDiagnostic(
            found: appendUnique([], found),
            attempts: appendUnique(
                analysisMethodAttempts(evidenceText: evidenceText, sourceURL: sourceURL),
                [
                    "Checked public metadata/caption text for explicit place names",
                    "Applied bounded resolver decision before any save action",
                    "Classified the source as place-bearing even though no exact venue was verified",
                    "Kept this in Review instead of inventing a map pin",
                    "Prepared public source-recovery search queries",
                    "Did not use logged-in social scraping"
                ]
            ),
            missingFields: missingFields,
            nextBestClue: "Run source recovery search or add the exact place name/map link before saving as a Map Stamp.",
            suggestedSearchQueries: searchQueries,
            recoveryPlan: recoveryPlan(
                sourceURL: sourceURL,
                evidenceText: evidenceText,
                queries: searchQueries,
                requiredEvidence: analysis.resolverDecision.requiredEvidence,
                decision: analysis.resolverDecision.kind,
                allowsDirectSave: analysis.resolverDecision.allowsDirectSave
            ),
            rejectedEvidence: [
                SocialPlaceRejectedEvidence(value: "creator profile or generic social shell", reason: "not venue proof"),
                SocialPlaceRejectedEvidence(value: "tracking-only share token", reason: "not a place identity")
            ]
        )
    }

    private func analysisMethodAttempts(evidenceText: String, sourceURL: String) -> [String] {
        [
            "Analysis method: classified the shared URL/platform and canonical post id before trusting content",
            "Analysis method: inspected readable metadata/caption/OCR for venue anchors, address pins, map links, and social handles",
            "Analysis method: pairs venue-looking lines with nearby strong evidence such as a pinned/street address before creating a Review Candidate",
            "Analysis method: accepts explicit venue anchors including labels, quotes/brackets, generic emoji/symbol markers, and standalone CJK/Latin venue lines before an address",
            "Analysis method: rejects creator profiles, hashtags, marketing headlines, menu/price items, operating hours, transit/access lines, review metrics, and generic social shells as venue names",
            "Analysis method: falls back to source-only when readable metadata is missing/blocked, only a creator handle exists, only OCR/headline text exists, only menu/items exist, multiple list places need selection, or no address/map-provider match is available",
            "Analysis method: requires a place name plus address or map-provider match before saving directly; otherwise keeps it in Review",
            "Analysis method: records unresolved details internally so SAV-E can keep trying instead of guessing"
        ]
    }

    private func evidenceContentFindings(evidenceText: String) -> [String] {
        let cleaned = cleanHTMLText(evidenceText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return ["Readable metadata/caption/OCR: none received"]
        }
        if streetAddressLine(in: cleaned) != nil || cleaned.contains("📍") || cleaned.contains("🏠") || cleaned.localizedCaseInsensitiveContains("address") {
            return ["Readable metadata/caption/OCR: present with location clues"]
        }
        return ["Readable metadata/caption/OCR: present but no verified address/map link"]
    }

    private func sourceOnlyDiagnostic(evidenceText: String, sourceURL: String) -> SocialPlaceEvidenceDiagnostic {
        var found = appendUnique(["Source URL: \(sourceURL)"], evidenceContentFindings(evidenceText: evidenceText))
        if !evidenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            found.append("Shared text/caption was present but did not contain a verified place candidate")
        }
        var attempts = appendUnique(
            analysisMethodAttempts(evidenceText: evidenceText, sourceURL: sourceURL),
            [
                "Checked public metadata/caption text for explicit place names",
                "Checked social handles without treating creator handles as places",
                "Prepared public web search fallback queries for source-only recovery",
                "Did not use logged-in social scraping"
            ]
        )
        var missingFields = [
            "Verified place name",
            "Verified address",
            "Verified coordinates"
        ]
        var nextBestClue = "Run the suggested public searches, or share a caption, screenshot/OCR frame, map link, or visible venue handle."

        if let xhs = xiaohongshuLinkContext(sourceURL: sourceURL) {
            found = appendUnique(found, [
                xhs.identifierEvidence,
                xhs.urlEvidence
            ])
            attempts = appendUnique(attempts, [
                xhs.resolutionAttempt,
                "Detected blocked or generic Xiaohongshu metadata shell instead of usable caption text"
            ])
            missingFields = appendUnique(missingFields, [
                "Readable Xiaohongshu caption or screenshot OCR",
                "Xiaohongshu map link or copied place address"
            ])
            nextBestClue = "Share a Xiaohongshu screenshot/OCR frame, copied caption, or map link so SAV-E can turn this source into a Review Candidate."
        }

        let searchQueries = sourceRecoverySearchQueries(evidenceText: evidenceText, sourceURL: sourceURL)
        return SocialPlaceEvidenceDiagnostic(
            found: found,
            attempts: attempts,
            missingFields: missingFields,
            nextBestClue: nextBestClue,
            suggestedSearchQueries: searchQueries.isEmpty ? nil : searchQueries,
            recoveryPlan: recoveryPlan(
                sourceURL: sourceURL,
                evidenceText: evidenceText,
                queries: searchQueries,
                requiredEvidence: missingFields,
                decision: .sourceOnly,
                allowsDirectSave: false
            ),
            rejectedEvidence: [
                SocialPlaceRejectedEvidence(value: "creator handle", reason: "not promoted to venue without venue proof"),
                SocialPlaceRejectedEvidence(value: "generic social metadata", reason: "source receipt only until caption, OCR, map, or official place evidence appears")
            ]
        )
    }

    private func diagnosticSearchEvidence(_ diagnostic: SocialPlaceEvidenceDiagnostic) -> [String] {
        var evidence = (diagnostic.suggestedSearchQueries ?? []).map { "Suggested public search: \($0)" }
        if let recoveryPlan = diagnostic.recoveryPlan {
            evidence.append("Recovery decision: \(recoveryPlan.decision.rawValue); direct save \(recoveryPlan.allowsDirectSave ? "allowed" : "blocked")")
            evidence.append(contentsOf: recoveryPlan.requiredEvidence.prefix(3).map { "Required proof: \($0)" })
            evidence.append(contentsOf: recoveryPlan.blockedResultHints.prefix(2).map { "Rejected clue type: \($0)" })
        }
        evidence.append(contentsOf: (diagnostic.rejectedEvidence ?? []).prefix(2).map { "Rejected evidence: \($0.value) — \($0.reason)" })
        return appendUnique([], evidence)
    }

    private func recoveryPlan(
        sourceURL: String,
        evidenceText: String,
        queries: [String],
        requiredEvidence: [String],
        decision: SocialPlaceResolverDecisionKind,
        allowsDirectSave: Bool
    ) -> SocialPlaceEvidenceRecoveryPlan {
        SocialPlaceEvidenceRecoveryPlan(
            sourceURL: sourceURL,
            evidenceAtoms: evidenceAtoms(sourceURL: sourceURL, evidenceText: evidenceText),
            queriesToTry: queries,
            blockedResultHints: [
                "creator profile without venue name/address",
                "generic social shell or login wall",
                "aggregator/list page without address or map coordinates",
                "map home/directions page without canonical place identity"
            ],
            requiredEvidence: appendUnique([], requiredEvidence),
            decision: decision,
            allowsDirectSave: allowsDirectSave
        )
    }

    private func evidenceAtoms(sourceURL: String, evidenceText: String) -> [String] {
        var atoms = ["source_url: \(sourceURL)"]
        let cleaned = cleanHTMLText(evidenceText).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            atoms.append("readable_text: none")
        } else {
            atoms.append("readable_text: present")
            if streetAddressLine(in: cleaned) != nil {
                atoms.append("address_clue: present")
            }
            if cleaned.range(of: #"@\w+"#, options: .regularExpression) != nil {
                atoms.append("social_handle: present")
            }
        }
        if let host = URL(string: sourceURL)?.host?.lowercased() {
            atoms.append("source_host: \(host)")
        }
        return appendUnique([], atoms)
    }

    private func sourceRecoverySearchQueries(
        evidenceText: String,
        sourceURL: String,
        analysis: SocialPlaceAgentAnalysis? = nil
    ) -> [String] {
        var queries: [String] = []
        let url = xiaohongshuContentURL(from: URL(string: sourceURL)) ?? URL(string: sourceURL)
        let host = url?.host()?.lowercased() ?? ""
        let socialPost = socialPostDescriptor(in: url)
        let cleanedEvidence = cleanHTMLText(evidenceText)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let analysis, analysis.isPlaceBearing {
            let keyword = searchKeyword(for: analysis.sourceIntent)
            let region = primaryRegion(from: analysis.regionClues)
            let topic = analysis.topic
            let phrase = meaningfulPlacePhrase(from: evidenceText)
            let recoveredNameHint = sourceRecoveryVenueNameHint(phrase: phrase, topic: topic, evidenceText: evidenceText)
            if let recoveredNameHint, let region {
                queries.append("\(recoveredNameHint) \(region) 地址")
            }
            if let recoveredNameHint, let handle = firstSocialHandle(in: evidenceText) {
                queries.append("\(handle) \(recoveredNameHint)")
            }
            if let recoveredNameHint {
                queries.append("\(recoveredNameHint) 官方 餐廳 訂位")
            }
            if let socialPost {
                if let region {
                    queries.append("\"\(socialPost.id)\" \(keyword) \(region)")
                }
                if let phrase {
                    queries.append("\"\(socialPost.id)\" \"\(phrase)\"")
                }
                if let topic {
                    queries.append("\"\(socialPost.id)\" \"\(topic)\"")
                }
                queries.append("\(socialPost.siteQuery) \(keyword)")
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

        if let socialPost {
            queries.append("\(socialPost.platformName) \(socialPost.id) place")
            queries.append("\(socialPost.id) restaurant venue")
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
            .replacingOccurrences(of: #"@[A-Za-z0-9._]{3,30}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:instagram\s+reel|xiaohongshu|xhs|douyin)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?:小红书|小紅書|抖音)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:restaurant|venue|place|address|cafe|coffee|hotel|map)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'“”"))

        if candidate.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil {
            if candidate.range(of: #"^(?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)的(?!(?:那間店|那家店|這間店|这间店|這家店|这家店|那個地方|那个地方))"#, options: .regularExpression) != nil {
                guard let cityScopedName = venueNameFromCityQualifiedPhrase(candidate) else { return nil }
                candidate = cityScopedName
            }
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
        if !hasCJK,
           candidate.range(of: #"^[A-Za-z0-9_-]{6,}$"#, options: .regularExpression) != nil,
           candidate.range(of: #"\d"#, options: .regularExpression) != nil {
            return nil
        }
        guard isUsableCandidateName(candidate) else { return nil }
        guard !looksLikeMarketingLine(candidate) else { return nil }

        let lowered = candidate.lowercased()
        if ["la", "oc", "nyc", "sf", "taipei", "tokyo"].contains(lowered) { return nil }
        if [
            "士林", "西門", "大安", "信義", "萬華", "中山", "松山", "內湖", "板橋", "新莊", "蘆洲",
            "台北", "臺北", "台南", "臺南", "台中", "臺中", "高雄", "新北", "桃園"
        ].contains(candidate) {
            return nil
        }
        let genericValues = [
            "instagram",
            "xiaohongshu",
            "douyin",
            "小红书",
            "小紅書",
            "抖音",
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
            #"(?i)\b((?:restaurants?|cafes?|coffee shops?|hotels?|resorts?|things to do|places to visit)\s+in\s+(?:LA|Los Angeles|OC|Orange County|Tokyo|Taipei|Seoul|Paris|London|New York|[A-Z][A-Za-z .'-]{2,60}))\b"#,
            #"((?:士林|西門|大安|信義|萬華|中山|松山|內湖|板橋|新莊|蘆洲)[^\n\r]{0,60}(?:壽喜燒|寿喜烧|漢堡排|日本料理|日式料理|餐廳|餐厅|美食))"#,
            #"((?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)的(?!(?:那間店|那家店|這間店|这间店|這家店|这家店|那個地方|那个地方))[^\n\r，,。！!？?@#]{2,24})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(evidenceText.startIndex..<evidenceText.endIndex, in: evidenceText)
            guard let match = regex.firstMatch(in: evidenceText, range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: evidenceText) else { continue }
            let cleaned = cleanHTMLText(String(evidenceText[captureRange]))
                .replacingOccurrences(of: #"[📍👣🗺]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，\"'“”"))
            if cleaned.count >= 8, cleaned.count <= 120 {
                return cleaned
            }
        }
        return nil
    }

    private func sourceRecoveryVenueNameHint(phrase: String?, topic: String?, evidenceText: String) -> String? {
        for value in [phrase, topic, cityQualifiedVenuePhrase(in: evidenceText)] {
            guard let value, let name = venueNameFromCityQualifiedPhrase(value) else { continue }
            return name
        }
        return nil
    }

    private func cityQualifiedVenuePhrase(in text: String) -> String? {
        firstCapture(in: text, pattern: #"((?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)的(?!(?:那間店|那家店|這間店|这间店|這家店|这家店|那個地方|那个地方))[^\n\r，,。！!？?@#]{2,24})"#)
            .map(cleanHTMLText)
    }

    private func venueNameFromCityQualifiedPhrase(_ value: String) -> String? {
        guard let rawName = firstCapture(in: value, pattern: #"^(?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)的(?!(?:那間店|那家店|這間店|这间店|這家店|这家店|那個地方|那个地方))([^\n\r，,。！!？?@#]{2,24})"#) else {
            return nil
        }
        let name = cleanRecoveredVenueName(rawName)
        let genericNames = ["那間店", "那家店", "這間店", "这间店", "這家店", "这家店", "那個地方", "那个地方"]
        guard !genericNames.contains(name) else { return nil }
        guard isUsableCandidateName(name), !looksLikeMarketingLine(name) else { return nil }
        return name
    }

    private struct SocialPostDescriptor {
        var platformName: String
        var id: String
        var siteQuery: String
    }

    private struct XiaohongshuLinkContext {
        var identifier: String
        var canonicalURL: String
        var isShortLink: Bool

        var identifierEvidence: String {
            isShortLink ? "Xiaohongshu short link code: \(identifier)" : "Xiaohongshu note id: \(identifier)"
        }

        var urlEvidence: String {
            isShortLink ? "Original Xiaohongshu short URL: \(canonicalURL)" : "Canonical Xiaohongshu URL: \(canonicalURL)"
        }

        var resolutionAttempt: String {
            isShortLink
                ? "Detected Xiaohongshu short link but public redirect did not expose a canonical note id"
                : "Resolved canonical Xiaohongshu URL and extracted the note id"
        }
    }

    private func xiaohongshuLinkContext(sourceURL: String) -> XiaohongshuLinkContext? {
        guard let url = URL(string: sourceURL) else { return nil }
        let analysisURL = xiaohongshuContentURL(from: url) ?? url
        let host = analysisURL.host()?.lowercased() ?? ""
        guard host.matchesSocialDomain("xiaohongshu.com") || host.matchesSocialDomain("xhslink.com") else { return nil }
        guard let descriptor = socialPostDescriptor(in: analysisURL) else { return nil }
        return XiaohongshuLinkContext(
            identifier: descriptor.id,
            canonicalURL: canonicalSearchURL(from: analysisURL) ?? sourceURL,
            isShortLink: host.matchesSocialDomain("xhslink.com")
        )
    }

    private func socialPostDescriptor(in url: URL?) -> SocialPostDescriptor? {
        guard let url else { return nil }
        let descriptorURL = xiaohongshuContentURL(from: url) ?? url
        let host = descriptorURL.host()?.lowercased() ?? ""
        let components = descriptorURL.pathComponents
        if host.contains("instagram"),
           let markerIndex = components.firstIndex(where: { $0.lowercased() == "reel" || $0.lowercased() == "reels" }),
           components.indices.contains(markerIndex + 1) {
            let id = components[markerIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            return id.isEmpty ? nil : SocialPostDescriptor(platformName: "instagram reel", id: id, siteQuery: "site:instagram.com/reel/\(id)")
        }
        if host.matchesSocialDomain("xiaohongshu.com") || host.matchesSocialDomain("xhslink.com") {
            guard let id = components.reversed().first(where: { $0.count >= 4 && $0 != "/" })?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")),
                  !id.isEmpty else { return nil }
            if host.matchesSocialDomain("xhslink.com") {
                return SocialPostDescriptor(platformName: "xiaohongshu short link", id: id, siteQuery: "\"\(canonicalSearchURL(from: descriptorURL) ?? descriptorURL.absoluteString)\"")
            }
            return SocialPostDescriptor(platformName: "xiaohongshu", id: id, siteQuery: "site:xiaohongshu.com \(id)")
        }
        if host.matchesSocialDomain("douyin.com") || host.matchesSocialDomain("iesdouyin.com") {
            guard let id = components.reversed().first(where: { $0.count >= 4 && $0 != "/" })?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")),
                  !id.isEmpty else { return nil }
            return SocialPostDescriptor(platformName: "douyin", id: id, siteQuery: "site:douyin.com \(id)")
        }
        return nil
    }

    private func canonicalSearchURL(from url: URL?) -> String? {
        guard let url else { return nil }
        let searchURL = xiaohongshuContentURL(from: url) ?? url
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        let value = components?.url?.absoluteString ?? searchURL.absoluteString
        return value.isEmpty ? nil : value
    }

    private func xiaohongshuContentURL(from url: URL?) -> URL? {
        guard let url else { return nil }
        let host = url.host()?.lowercased() ?? ""
        guard host.matchesSocialDomain("xiaohongshu.com") else { return url }
        guard url.path.lowercased().hasPrefix("/404/"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let originalURLString = components.queryItems?.first(where: { $0.name == "originalUrl" })?.value,
              let originalURL = URL(string: originalURLString) else {
            return url
        }
        return originalURL
    }

    private func candidateDiagnostic(for candidate: PendingReviewCandidate, evidenceText: String, sourceURL: String) -> SocialPlaceEvidenceDiagnostic {
        var found = appendUnique(
            [
                "Source URL: \(sourceURL)",
                "Candidate place name: \(candidate.candidateName)"
            ],
            evidenceContentFindings(evidenceText: evidenceText)
        )
        if let xhs = xiaohongshuLinkContext(sourceURL: sourceURL) {
            found = appendUnique(found, [
                xhs.identifierEvidence,
                xhs.urlEvidence
            ])
        }
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

        var attempts = appendUnique(
            analysisMethodAttempts(evidenceText: evidenceText, sourceURL: sourceURL),
            [
                "Checked public metadata/caption text for explicit place names",
                "Kept plausible venue evidence in Review instead of inventing map coordinates",
                "Did not use logged-in social scraping"
            ]
        )
        if let xhs = xiaohongshuLinkContext(sourceURL: sourceURL) {
            attempts = appendUnique(attempts, [
                xhs.resolutionAttempt,
                "Used readable Xiaohongshu caption/metadata as place evidence"
            ])
        }

        return SocialPlaceEvidenceDiagnostic(
            found: appendUnique([], found),
            attempts: attempts,
            missingFields: appendUnique([], missing),
            nextBestClue: candidate.address.isEmpty
                ? "Confirm the exact address or share a map link before saving this as a Map Stamp."
                : "Confirm coordinates or choose a Google Places match before saving this as a Map Stamp."
        )
    }

    private func refinedDiagnosticAfterPlacesMatch(
        existing: SocialPlaceEvidenceDiagnostic?,
        match: PlaceProviderMatch
    ) -> SocialPlaceEvidenceDiagnostic {
        let base = existing ?? SocialPlaceEvidenceDiagnostic(found: [], attempts: [], missingFields: [], nextBestClue: "")
        var newFound = [
            "\(match.provider.displayName) match: \(match.name)",
            "Verified coordinates: \(match.latitude), \(match.longitude)"
        ]
        if !match.address.isEmpty {
            newFound.insert("Verified address: \(match.address)", at: 1)
        }
        let found = appendUnique(base.found, newFound)
        let attempts = appendUnique(
            base.attempts,
            ["Checked \(match.provider.displayName) for a matching place record"]
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
            nextBestClue: "Confirm this \(match.provider.displayName) match before saving it as a Map Stamp."
        )
    }

    private func sourceOnlyDisplayName(for sourceURL: String) -> String {
        guard let url = URL(string: sourceURL) else { return "Social link" }
        let path = url.path.lowercased()
        if path.contains("/reel/") || path.contains("/reels/") { return "Instagram reel" }
        if url.host?.lowercased().contains("instagram") == true { return "Instagram link" }
        if url.host?.lowercased().matchesSocialDomain("xiaohongshu.com") == true || url.host?.lowercased().matchesSocialDomain("xhslink.com") == true { return "Xiaohongshu link" }
        if url.host?.lowercased().matchesSocialDomain("douyin.com") == true || url.host?.lowercased().matchesSocialDomain("iesdouyin.com") == true { return "Douyin link" }
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
            #"[《]\s*([^》\n\r]{2,80})\s*[》]"#,
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
            if let quoted = firstCapture(in: line, pattern: #"[「『《\"]\s*([^」』》\"]{2,80})\s*[」』》\"]"#) {
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
            #"[📍📮]\s*(?:地點|地点|地址|Location|Address)?\s*[:：]?\s*([^\n\r\.]+)"#,
            #"(?:^|\b)(?:Location|Address|地點|地点|地址)\s*[:：]\s*([^\n\r\.]+)"#
        ]
        for pattern in patterns {
            if let match = firstCapture(in: text, pattern: pattern) {
                let cleaned = cleanHTMLText(match)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ：:"))
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
        guard let line = lines.first(where: looksLikeAddressLine) else { return nil }
        return cleanLocationMarker(from: line)
    }

    private func cleanLocationMarker(from value: String) -> String {
        cleanHTMLText(value)
            .replacingOccurrences(of: #"^[📍🗺👣🚩📮]\s*(?:地點|地点|地址|Location|Address)?\s*[:：]?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*(?:located\s+at|located|address|location|地點|地点|地址)\s*[:：]?\s*[📍🗺📮]?\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，:："))
    }

    private func looksLikeAddressLine(_ line: String) -> Bool {
        SocialPlaceEvidenceScorer.looksLikeAddressLine(line)
    }

    private func isLikelyCaptionPlaceName(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(value)
    }

    private func candidateNameFromCaptionLine(_ line: String) -> String? {
        if let venueMarkerName = firstCapture(in: line, pattern: #"^\s*[🏠🏡🏘️🏚️🏪🏬🏢🍽️🍴☕️📍🚩]\s*([^\n\r]{2,60})"#) {
            let cleaned = cleanCandidateName(venueMarkerName)
            if isUsableCandidateName(cleaned),
               !looksLikeAddressLine(cleaned),
               !looksLikeOperatingHoursLine(cleaned),
               !looksLikeReviewMetricLine(cleaned),
               !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }

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
        if let labeledName = firstCapture(in: line, pattern: #"^\s*(?:[👉➡→➜📌📍🚩🏠🏡]\s*)?(?:店名|店家|餐廳|餐厅|venue|restaurant)\s*[:：\-–—]?\s*([^\n\r]{2,60})"#) {
            let cleaned = cleanCandidateName(labeledName)
            if isUsableCandidateName(cleaned), !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }
        if isVenueIntroLine,
           let quoted = firstCapture(in: line, pattern: #"[「《\"]\s*([^」》\"]{2,60})\s*[」》\"]"#) {
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
            "instagram", "reels", "reel", "explore", "threads", "tiktok", "xiaohongshu", "xhs", "douyin", "save", "media"
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

    private func decodeJSONStringFragment(_ value: String) -> String {
        let wrapped = "\"\(value)\""
        guard let data = wrapped.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return value
                .replacingOccurrences(of: #"\n"#, with: "\n")
                .replacingOccurrences(of: #"\/"#, with: "/")
                .replacingOccurrences(of: #"\""#, with: "\"")
        }
        return decoded
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

private extension String {
    func matchesSocialDomain(_ domain: String) -> Bool {
        self == domain || hasSuffix(".\(domain)")
    }
}

private extension PendingReviewCandidate {
    func withThumbnailOCREvidence(_ lines: [String]) -> PendingReviewCandidate {
        guard !lines.isEmpty else { return self }
        var copy = self
        let ocrText = lines.joined(separator: "\n")
        copy.sourceText = [copy.sourceText, ocrText]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        copy.evidence = uniqueStrings(
            copy.evidence + [
                "Thumbnail OCR text: \(String(ocrText.prefix(300)))",
                "Analysis pipeline: included public metadata image OCR before source recovery"
            ]
        )
        if var diagnostic = copy.evidenceDiagnostic {
            diagnostic.found = uniqueStrings(diagnostic.found + ["Thumbnail OCR text: \(String(ocrText.prefix(300)))"])
            diagnostic.attempts = uniqueStrings(diagnostic.attempts + ["Ran OCR on public metadata image/thumbnail"])
            copy.evidenceDiagnostic = diagnostic
        }
        return copy
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for value in values {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
            seen.insert(cleaned)
            result.append(cleaned)
        }
        return result
    }
}
