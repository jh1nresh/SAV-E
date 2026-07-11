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
    /// LLM fallback for prose-only captions the deterministic marker parser
    /// rejects. `nil` when no LLM path is configured — the service then keeps its
    /// deterministic-only behavior. Injected as a fake (no network) in tests.
    private let captionVenueExtractor: SocialCaptionVenueExtractor?
    private let thumbnailImageByteLimit = 6_000_000

    init(
        googlePlacesService: GooglePlacesServiceProtocol = GooglePlacesService.shared,
        publicSourceSearchService: PublicSourceSearchServiceProtocol = PublicSourceSearchService.shared,
        placeResolverService: PlaceResolverServiceProtocol? = nil,
        captionVenueExtractor: SocialCaptionVenueExtractor? = GeminiCaptionVenueExtractor.liveFromConfig()
    ) {
        self.placeResolverService = placeResolverService ?? PlaceResolverService(googlePlacesService: googlePlacesService)
        self.publicSourceSearchService = publicSourceSearchService
        self.captionVenueExtractor = captionVenueExtractor
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
        var keywords: String?
        var imageURL: URL?
        var videoURL: URL?
        var jsonCaption: String?
        /// True when the fetch failed entirely (no caption AND no image), i.e.
        /// Instagram returned a logged-out wall or the network blipped. Lets the
        /// debug receipt distinguish "fetch returned nothing" from "fetch
        /// returned a caption the parser couldn't resolve".
        var fetchReturnedNothing: Bool = false

        var evidenceLines: [String] {
            [title, description, keywords.map { "Keywords: \($0)" }, jsonCaption]
                .compactMap { $0 }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        /// Lightweight, inspectable receipt of what the public fetch saw. Wired
        /// into candidate evidence so a future source-only degrade is
        /// diagnosable without re-running the fetch.
        var fetchDiagnosticLines: [String] {
            let decodedDescriptionLength = (description ?? jsonCaption ?? "").count
            return [
                "Social fetch: og_title_present=\(title?.isEmpty == false)",
                "Social fetch: og_description_present=\((description ?? jsonCaption)?.isEmpty == false)",
                "Social fetch: og_image_present=\(imageURL != nil)",
                "Social fetch: decoded_og_description_length=\(decodedDescriptionLength)",
                "Social fetch: fetch_returned_caption=\(!fetchReturnedNothing && (title != nil || description != nil || jsonCaption != nil))"
            ]
        }
    }

    func reviewCandidates(from url: URL) async throws -> [PendingReviewCandidate] {
        await reviewCandidates(from: url, sharedCaption: nil)
    }

    /// Entry point for messy pasted share text (caption + URLs + app-open
    /// boilerplate). Never hard-fails: a paste SAV-E cannot resolve degrades to
    /// a source-only receipt with a next action instead of throwing.
    func reviewCandidates(fromSharedText rawShareText: String) async -> [PendingReviewCandidate] {
        let bundle = SocialShareTextNormalizer.normalize(rawShareText)
        guard let url = bundle.primaryURL else {
            let evidenceText = bundle.captionEvidence.isEmpty ? cleanHTMLText(rawShareText) : bundle.captionEvidence
            return reviewCandidatesOrSourceOnly(fromEvidenceText: evidenceText, sourceURL: "")
        }
        return await reviewCandidates(from: url, sharedCaption: bundle.captionEvidence.isEmpty ? nil : bundle.captionEvidence)
    }

    private func reviewCandidates(from url: URL, sharedCaption: String?) async -> [PendingReviewCandidate] {
        let metadata = await fetchMetadata(from: url)
        let ocrLines = await thumbnailOCRLines(from: metadata.imageURL)
        let ocrEvidence = ocrLines.isEmpty ? nil : ocrLines.joined(separator: "\n")
        let videoEvidence = metadata.videoURL.map { "Video metadata URL: \($0.absoluteString)" }
        let evidenceText = ([sharedCaption] + metadata.evidenceLines + [videoEvidence, ocrEvidence])
            .compactMap { $0 }
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let sourceURL = metadata.resolvedURL ?? url.absoluteString
        // Never hard-fail a link the user pasted: if recovery search throws,
        // fall back to the deterministic local parse / source-only path.
        let resolved = (try? await recoverReviewCandidates(fromEvidenceText: evidenceText, sourceURL: sourceURL))
            ?? reviewCandidatesOrSourceOnly(fromEvidenceText: evidenceText, sourceURL: sourceURL)
        // Attach a lightweight fetch receipt to every candidate so a future
        // source-only degrade (Instagram's flaky logged-out wall) is
        // diagnosable: it records whether og:title/description/image were
        // present, the decoded caption length, and the parse stage reached.
        let candidates = resolved.map { candidate in
            candidate.withSocialFetchDiagnostic(metadata.fetchDiagnosticLines)
        }
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
            // Deterministic-first: a structured/marker candidate exists. But the
            // prose heuristics can still surface a low-confidence fragment (e.g.
            // "shop in LA" off a prose caption) with no address/coordinates — not
            // a real venue. When that's all we have, let the LLM read the prose
            // for the actual venue name before settling for the fragment.
            let refined = await refineCandidates(initial, evidenceText: evidenceText)
            // No extractor configured (no backend/API key): keep deterministic-only
            // behavior unchanged — never downgrade a fragment without an LLM.
            guard captionVenueExtractor != nil,
                  deterministicYieldedUnreliableProseFragment(refined) else {
                return refined
            }
            // The only deterministic output is a weak prose fragment. Try the LLM
            // for the real venue name; if it yields a guarded candidate, use it.
            if let llmCandidates = await llmCaptionFallbackCandidates(
                evidenceText: evidenceText,
                sourceURL: sourceURL,
                analysis: analyze(evidenceText: evidenceText, sourceURL: sourceURL)
            ) {
                return llmCandidates
            }
            // LLM named no usable venue (or hallucinated a name absent from the
            // caption). The fragment is a false positive, so degrade to a clean
            // source-only receipt rather than surfacing the fragment as a venue.
            return [forcedSourceOnlyCandidate(evidenceText: evidenceText, sourceURL: sourceURL)]
        }

        // Deterministic-first: the marker/structured paths above ran and found no
        // confirmed venue. Note this so the LLM prose fallback only fires when the
        // deterministic parser genuinely couldn't extract a usable venue name.
        let deterministicLacksVenue = initial.allSatisfy {
            $0.isPlaceBearingSource || $0.isSourceOnly
        }

        let analysis = analyze(evidenceText: evidenceText, sourceURL: sourceURL)
        let hasUnresolvedInitialCandidate = initial.contains { $0.reviewState == "unresolved_place_candidate" }
        // Age-restricted / login-walled social posts (e.g. an Instagram reel that
        // only returns a logged-out shell) carry no place-bearing caption, so the
        // analysis above stays non-place-bearing and would otherwise bail to
        // source-only. But a recognizable post shortcode plus a creator handle is
        // enough to run public-search recovery off the public web, where the
        // caption/venue is mirrored. Treat that as a recoverable thin source.
        let isRecoverableThinSocialSource = hasRecoverableThinSocialSource(evidenceText: evidenceText, sourceURL: sourceURL)
        guard analysis.isPlaceBearing
            || analysis.resolverDecision.shouldRunPublicSearch
            || hasUnresolvedInitialCandidate
            || isRecoverableThinSocialSource else { return initial }

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

        // Deterministic recovery (markers + public-search off thin signals) found
        // nothing usable. Last resort: ask the LLM to read the prose caption for a
        // venue name the marker parser deliberately rejects. Evidence-bound and
        // Review-Candidate only — see `llmCaptionFallbackCandidates`. Fires when the
        // deterministic result is source-only/place-bearing OR only an unreliable
        // prose fragment (e.g. "shop in LA") — never when a structured venue exists.
        let deterministicYieldedFragment = deterministicYieldedUnreliableProseFragment(initial)
        let deterministicHasNoReliableVenue = deterministicLacksVenue || deterministicYieldedFragment
        if deterministicHasNoReliableVenue {
            if let llmCandidates = await llmCaptionFallbackCandidates(
                evidenceText: evidenceText,
                sourceURL: sourceURL,
                analysis: analysis
            ) {
                return llmCandidates
            }
            // Only a prose fragment remained and the LLM produced nothing usable:
            // drop the fragment for a clean source-only receipt. Gated on an
            // extractor being present so deterministic-only behavior (no backend)
            // is unchanged. When the deterministic result was already
            // source-only/place-bearing, `initial` is returned unchanged below.
            if deterministicYieldedFragment, captionVenueExtractor != nil {
                return [forcedSourceOnlyCandidate(evidenceText: evidenceText, sourceURL: sourceURL)]
            }
        }
        return initial
    }

    /// True when the only deterministic output is a weak prose-fragment candidate
    /// with no address, no coordinates, and no structured recovery state — i.e.
    /// the heuristics grabbed a fragment off prose ("shop in LA") rather than a
    /// real venue. Structured candidates (recovered/map-ready/unresolved place
    /// stems like LS Hotel / Ulaman) are NOT unreliable and must never trigger the
    /// LLM fallback, preserving deterministic-first behavior.
    private func deterministicYieldedUnreliableProseFragment(_ candidates: [PendingReviewCandidate]) -> Bool {
        // A recovered/map-ready candidate is a confirmed-enough venue and must
        // never be second-guessed by the LLM. An `unresolved_place_candidate` is
        // only a *stem*, though — and when that stem is itself prose noise
        // ("shop in LA") with no address/coordinates, it's an unreliable fragment.
        let confirmedStates: Set<String> = ["source_recovered_candidate", "map_match_ready"]
        return !candidates.isEmpty && candidates.allSatisfy { candidate in
            // A real venue stem off a caption pin ("📍Ulaman" → "Ulaman") is a
            // legitimate place anchor, not prose noise — never treat it as a
            // fragment, so the no-search Ulaman/LS Hotel guards stay unchanged.
            guard !candidate.isCaptionPinVenueStem else { return false }
            return !candidate.hasReliableCoordinates
                && candidate.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !(candidate.reviewState.map(confirmedStates.contains) ?? false)
                && looksLikeProseFragmentName(candidate.candidateName)
        }
    }

    /// A deterministic candidate *name* that reads like a prose fragment rather
    /// than a proper venue name — e.g. "shop in LA", "spot to grab coffee". These
    /// slip through the heuristic extractor off prose captions. Proper names
    /// ("Ulaman", "Aquarela Coffee", "牛喜壽喜燒") start with a capital/CJK token and
    /// carry no prose connector, so they are NOT flagged.
    private func looksLikeProseFragmentName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if isProseFragmentCandidate(trimmed) { return true }
        if !isUsableCandidateName(trimmed) { return true }
        // A leading lowercase Latin word is a common noun / sentence fragment,
        // never a proper venue name ("shop in LA", "place near me").
        if let first = trimmed.unicodeScalars.first,
           CharacterSet.lowercaseLetters.contains(first) {
            return true
        }
        // "<word> in/near/by/at <place>" prepositional prose ("shop in LA").
        if trimmed.range(of: #"(?i)\b(?:in|near|by|at|around|next to)\s+[A-Za-z]"#, options: .regularExpression) != nil,
           trimmed.range(of: #"(?i)\b(?:restaurant|cafe|coffee|bar|hotel|resort|villa|inn|museum|gallery|park|market|kitchen|bakery|bistro|club|studio|house)\b"#, options: .regularExpression) == nil {
            return true
        }
        // A multi-clause sentence ("Such a magical little spot, the cozy vibes…")
        // is prose, not a venue name: a proper venue rarely runs past ~6 words and
        // never strings clauses with mid-sentence punctuation.
        let wordCount = trimmed.split { $0 == " " || $0 == "\u{3000}" }.count
        if wordCount > 6 { return true }
        if trimmed.range(of: #"[,;.!?]\s+\S"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// LLM prose-caption fallback. Fires only when the deterministic parser AND
    /// public-search recovery both failed to produce a usable venue. The LLM
    /// supplies *only* a name (the deterministic parser already owns markers); the
    /// name is then verified against the caption (anti-hallucination) and, if it
    /// survives, runs back through public search exactly like the LS Hotel/Ulaman
    /// path so the extracted name becomes the search stem.
    ///
    /// Returns `nil` (→ caller keeps the deterministic source-only receipt) when
    /// no extractor is configured, the LLM names no venue, the name is not
    /// present in the caption, or the name is a rejected generic/marketing label.
    /// Never produces coordinates or a Map Stamp.
    private func llmCaptionFallbackCandidates(
        evidenceText: String,
        sourceURL: String,
        analysis: SocialPlaceAgentAnalysis
    ) async -> [PendingReviewCandidate]? {
        guard let captionVenueExtractor else { return nil }
        let caption = evidenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !caption.isEmpty else { return nil }

        guard let extracted = await captionVenueExtractor.extractVenue(caption: caption, sourceURL: sourceURL) else {
            return nil
        }

        let name = cleanCandidateName(extracted.name)
        // GUARDRAIL 0: never accept a bare @handle or #hashtag as a venue name —
        // they search poorly and read as noise. Deterministic backstop in case the
        // model returns one despite the prompt.
        let firstChar = name.trimmingCharacters(in: .whitespaces).first
        guard firstChar != "@", firstChar != "#" else { return nil }
        // GUARDRAIL 1 (anti-hallucination): the extracted name MUST literally
        // appear in the caption (case/diacritic-insensitive). A name the LLM
        // invented or paraphrased is discarded → deterministic source-only.
        guard !name.isEmpty, captionContains(name, in: caption) else { return nil }
        // GUARDRAIL 2: reject generic labels / marketing lines / hashtags /
        // prose fragments — reuse the same rejection the deterministic path uses.
        guard isUsableCandidateName(name),
              !looksLikeMarketingLine(name),
              !SocialPlaceEvidenceScorer.isRejectedTitle(name),
              !isProseFragmentCandidate(name) else { return nil }

        let llmCandidate = llmCaptionVenueCandidate(
            name: name,
            extracted: extracted,
            evidenceText: evidenceText,
            sourceURL: sourceURL
        )

        // Let public-search recovery try to upgrade the LLM name (search
        // "<name> <area>" → provider match), exactly like the LS Hotel/Ulaman
        // path: the extracted name becomes the search stem.
        let upgradeQueries = appendUnique(
            [extracted.area.map { "\(name) \($0)" } ?? name],
            [name]
        )
        let upgradeResults = await publicSearchResults(for: upgradeQueries)
        if !upgradeResults.isEmpty {
            let upgradeAnalysis = analyze(evidenceText: "\(name) \(evidenceText)", sourceURL: sourceURL)
            let recovered = sourceRecoveryCandidates(
                from: upgradeResults,
                analysis: upgradeAnalysis,
                evidenceText: "\(name)\n\(evidenceText)",
                sourceURL: sourceURL
            )
            let refined = await refineCandidates(
                recovered,
                evidenceText: sourceRecoveryEvidenceText(evidenceText: "\(name)\n\(evidenceText)", results: upgradeResults)
            )
            let mapReady = refined.filter { $0.hasReliableCoordinates }
            if !mapReady.isEmpty { return rankedCandidates(mapReady) }
            if !refined.isEmpty { return rankedCandidates(refined) }
        }

        // Search found nothing — keep the LLM Review Candidate. Still useful: the
        // user gets a real venue name to confirm instead of a bare source link.
        return [llmCandidate]
    }

    /// Builds the Review Candidate for an LLM-extracted prose venue name. No
    /// coordinates, `hasReliableCoordinates == false`, a source_recovered-style
    /// `reviewState`, and `missingInfo` flagging provider/coordinate/user
    /// confirmation — so it can never be auto-saved as a Map Stamp.
    private func llmCaptionVenueCandidate(
        name: String,
        extracted: ExtractedVenue,
        evidenceText: String,
        sourceURL: String
    ) -> PendingReviewCandidate {
        let area = extracted.area?.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = canonicalCaptionCategory(extracted.category, name: name, evidenceText: evidenceText)
        let captionSnippet = String(evidenceText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(220))
        // Cap LLM confidence: this is an unverified prose extraction, not a
        // provider match. Stays below the refined/map-ready tiers.
        let confidence = min(max(extracted.confidence, 0), 0.6)
        let missingInfo = [
            "Google Places match required",
            "Verified coordinates",
            "User confirmation required"
        ]
        let evidence = appendUnique(
            [],
            [
                "Source URL: \(sourceURL)",
                "Evidence tier: \(SocialPlaceEvidenceTier.weakCandidate.rawValue)",
                "Extracted by SAV-E from caption: \(name)",
                area.map { "Caption area clue: \($0)" } ?? "",
                captionSnippet.isEmpty ? "" : "Caption snippet: \(captionSnippet)"
            ]
        )
        let diagnostic = SocialPlaceEvidenceDiagnostic(
            found: appendUnique(
                [],
                [
                    "Source URL: \(sourceURL)",
                    "Extracted by SAV-E from caption: \(name)",
                    area.map { "Caption area clue: \($0)" } ?? ""
                ]
            ),
            attempts: appendUnique(
                analysisMethodAttempts(evidenceText: evidenceText, sourceURL: sourceURL),
                [
                    "Deterministic marker parser found no venue in prose caption",
                    "Ran public web search recovery (no confirming match)",
                    "Extracted venue name from caption via SAV-E LLM fallback",
                    "Verified the extracted name appears literally in the caption",
                    "Did not use logged-in social scraping"
                ]
            ),
            missingFields: ["Verified address", "Verified coordinates"],
            nextBestClue: "Confirm this caption-extracted venue and its address before saving it as a Map Stamp."
        )
        return PendingReviewCandidate(
            candidateName: name,
            address: area ?? "",
            category: category,
            latitude: nil,
            longitude: nil,
            sourceURL: sourceURL,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: confidence,
            missingInfo: missingInfo,
            savedAt: Date(),
            evidenceDiagnostic: diagnostic,
            reviewState: "source_recovered_candidate"
        )
    }

    /// A guaranteed source-only receipt (`isSourceOnly == true`), bypassing the
    /// `unresolved_place_candidate` promotion in `sourceOnlyCandidate`. Used when a
    /// deterministic prose *fragment* must be dropped: re-running the normal
    /// source-only path would just re-promote the same prose noise to an
    /// unresolved candidate, so we force a clean clue receipt instead.
    private func forcedSourceOnlyCandidate(evidenceText: String, sourceURL: String) -> PendingReviewCandidate {
        let diagnostic = sourceOnlyDiagnostic(evidenceText: evidenceText, sourceURL: sourceURL)
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

    /// Case/diacritic-insensitive substring check: does the extracted venue name
    /// literally appear in the caption? The anti-hallucination guardrail.
    private func captionContains(_ name: String, in caption: String) -> Bool {
        let foldedName = name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !foldedName.isEmpty else { return false }
        let foldedCaption = caption.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
        return foldedCaption.contains(foldedName)
    }

    /// Maps the LLM's loose category hint to a canonical `PlaceCategory`-style
    /// string, falling back to the text-derived category when the hint is missing
    /// or unrecognized.
    private func canonicalCaptionCategory(_ hint: String?, name: String, evidenceText: String) -> String {
        let lowered = (hint ?? "").lowercased()
        switch lowered {
        case "cafe", "coffee":
            return "cafe"
        case "food", "restaurant", "eat":
            return "food"
        case "bar", "drinks", "pub":
            return "bar"
        case "hotel", "stay", "resort", "villa", "lodging", "accommodation":
            return "stay"
        case "shopping", "shop", "store", "market":
            return "shopping"
        case "attraction", "sight", "landmark", "viewpoint", "mirador", "park", "museum":
            return "attraction"
        default:
            return category(from: "\(name) \(evidenceText)")
        }
    }

    /// A thin/age-restricted social post (login-walled Instagram reel, etc.) that
    /// exposes no caption still carries a deterministic recovery signal: the post
    /// shortcode from the URL. If the share sheet also provides a visible creator
    /// handle, include that signal too. Do not require the handle, though: the main
    /// app often receives only a pasted/opened Instagram URL while the iMessage /
    /// share-extension path receives richer metadata. Both paths should attempt
    /// the same bounded public-search recovery instead of letting URL-only app
    /// imports degrade straight to source-only.
    private func hasRecoverableThinSocialSource(evidenceText: String, sourceURL: String) -> Bool {
        guard let descriptor = socialPostDescriptor(in: URL(string: sourceURL)),
              !descriptor.id.isEmpty else {
            return false
        }
        // Xiaohongshu short links only carry an opaque slug, not a real note id,
        // so they intentionally stay source-only (see existing short-link path).
        if xiaohongshuLinkContext(sourceURL: sourceURL)?.isShortLink == true {
            return false
        }
        if firstSocialHandle(in: evidenceText) != nil { return true }
        return descriptor.platformName == "instagram post" || descriptor.platformName == "instagram reel"
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
            // For a thin/non-place-bearing source the intent-based category is a
            // generic "attraction"; the recovered snippet (e.g. "5-star hotel")
            // is a stronger signal, so prefer a text-derived category when the
            // intent did not already classify the place.
            let intentCategory = category(for: analysis.sourceIntent)
            let textCategory = category(from: "\(name) \(combinedText)")
            let resolvedCategory = intentCategory == "attraction" && textCategory != "attraction"
                ? textCategory
                : intentCategory
            return PendingReviewCandidate(
                candidateName: name,
                address: address,
                category: resolvedCategory,
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
            .components(separatedBy: CharacterSet(charactersIn: "|｜-–—/／·"))
            .map(cleanRecoveredVenueName)
            .filter { isUsableCandidateName($0) && !looksLikeMarketingLine($0) }
        // Prefer a Latin-named segment (e.g. "LS Hotel Liangsu Yangshuo") over a
        // CJK-only segment so the candidate title is the international venue name;
        // the local-language name is still preserved in the recovery evidence.
        if let latinName = candidates.first(where: { segment in
            segment.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil
        }) {
            return latinName
        }
        return candidates.first
    }

    private func sourceRecoveryAddress(from result: PublicSourceSearchResult) -> String? {
        let text = "\(result.title)\n\(result.snippet)"
        let patterns = [
            #"((?:台灣)?(?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)市[^\n\r，,。；;]{0,40}\d{1,6}\s*(?:號|号)?(?:B\d|[0-9一二三四五六七八九十]+樓)?)"#,
            #"((?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)市[^\n\r，,。；;]{0,50})"#,
            #"(\b\d{1,6}\s+[A-Za-z0-9 .'-]{2,80}\b(?:Street|St\.?|Road|Rd\.?|Avenue|Ave\.?|Boulevard|Blvd\.?|Lane|Ln\.?|Drive|Dr\.?|Way|Highway|Hwy\.?|Coast Hwy)\b(?:,\s*[A-Za-z .'-]{2,40})?)"#,
            // "... is located at No.49-3, Jiwodu Village, Yangshuo, China." —
            // explicit address lead-in (common on hotel/booking mirrors).
            #"(?i)(?:is\s+located\s+at|located\s+at|address\s*[:：]?)\s+([A-Za-z0-9][A-Za-z0-9 .,'\-#／/]{6,90}?(?:China|中国|中國))"#,
            // Bare international "No.X, …, City, China" address form.
            #"((?:No\.?\s*)?\d{1,5}[\dA-Za-z\-]*,\s*[A-Za-z .'-]{2,40}(?:,\s*[A-Za-z .'-]{2,40}){0,3},\s*(?:China|中国|中國))"#
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
        if let mapLinkCandidate = westernMapLinkCandidate(evidenceText: evidenceText, sourceURL: sourceURL) {
            return [mapLinkCandidate]
        }
        if let dianpingCandidate = dianpingCandidate(from: evidenceText, sourceURL: sourceURL) {
            return [dianpingCandidate]
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
                // A bare caption-pin venue stem (e.g. "📍Ulaman, Bali, Indonesia"
                // → "Ulaman") has no address/coordinates and is only a stem, not a
                // confirmed venue. Flag it unresolved so public-search recovery
                // runs to surface the official name ("Ulaman Eco Luxury Resort")
                // — instead of short-circuiting on the thin local stem.
                if diagnosed.isCaptionPinVenueStem {
                    diagnosed.reviewState = "unresolved_place_candidate"
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
        if let dianpingCandidate = dianpingCandidate(from: evidenceText, sourceURL: sourceURL) {
            candidates.append(dianpingCandidate)
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
                normalizedSocialCandidate(candidate)
            }
            .filter { !isTransitAccessCandidate($0) }
            .filter { !looksLikeMarketingLine($0.candidateName) }
            .filter { !isProseFragmentCandidate($0.candidateName) }
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

    private func normalizedSocialCandidate(_ candidate: PendingReviewCandidate) -> PendingReviewCandidate {
        var normalized = candidate
        let sourceText = candidate.sourceText ?? candidate.evidence.joined(separator: "\n")
        if candidate.candidateName.contains("📍") || candidate.candidateName.contains("🚩") {
            normalized.candidateName = candidateNameFromCaptionLine(candidate.candidateName) ?? cleanCandidateName(candidate.candidateName)
        }
        normalized.address = cleanLocationMarker(from: candidate.address)
        if normalized.address.isEmpty ||
            normalized.address.contains("@") ||
            looksLikeCityOnlyAddress(normalized.address) ||
            (candidate.address.contains("📍") && !looksLikeAddressLine(normalized.address)) {
            normalized.address = streetAddressLine(in: sourceText) ?? normalized.address
        }
        if let markerCandidate = strongestMarkedVenueCandidate(in: sourceText),
           shouldPreferMarkedVenue(markerCandidate, over: normalized.candidateName) {
            normalized.candidateName = markerCandidate
            if let address = streetAddressLine(in: sourceText) {
                normalized.address = address
            }
            normalized.confidence = max(normalized.confidence, 0.68)
            normalized.evidence = appendUnique(
                normalized.evidence,
                ["Public metadata venue anchor: \(markerCandidate)"]
            )
        }
        return normalized
    }

    private func strongestMarkedVenueCandidate(in text: String) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }
        for line in lines {
            if line.range(of: #"(?i)\b(?:on\s+Instagram|Instagram\s+reel)\b"#, options: .regularExpression) != nil ||
                line.contains("(@") ||
                line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@") {
                continue
            }
            guard let candidate = candidateNameFromCaptionLine(line),
                  isLikelyCaptionPlaceName(candidate),
                  !looksLikeAddressLine(candidate),
                  !looksLikeMarketingLine(candidate) else { continue }
            return candidate
        }
        return nil
    }

    private func shouldPreferMarkedVenue(_ markedVenue: String, over currentName: String) -> Bool {
        if currentName.isEmpty { return true }
        if currentName.contains("📍") || currentName.contains("🚩") { return true }
        if currentName.range(of: #","#, options: .regularExpression) != nil { return true }
        if markedVenue.count > currentName.count + 4 { return true }
        return false
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

    private func isProseFragmentCandidate(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix("to ") ||
            lowered.hasPrefix("and ") ||
            lowered.hasPrefix("or ") ||
            lowered.contains(" enjoy the ") ||
            lowered.contains(" perfect ") ||
            lowered.contains(" packed with ")
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
        SocialShareTextNormalizer.embeddedURLStrings(in: text)
    }

    /// Structured Google/Apple Maps place links carry the place identity and
    /// coordinates in the URL itself. Mirror the China deep-link path: verified
    /// coordinates come from the link, but the user still confirms the match
    /// before anything becomes a Map Stamp.
    private func westernMapLinkCandidate(evidenceText: String, sourceURL: String) -> PendingReviewCandidate? {
        let mapURLStrings = ([sourceURL] + embeddedURLStrings(in: evidenceText))
            .filter { !$0.isEmpty }
        for urlString in mapURLStrings {
            if let match = westernMapLinkMatch(in: urlString) {
                let diagnostic = SocialPlaceEvidenceDiagnostic(
                    found: appendUnique(
                        [],
                        [
                            "Source URL: \(sourceURL)",
                            "Structured \(match.providerName) place link: \(match.name)",
                            "Verified coordinates: \(match.latitude), \(match.longitude)"
                        ]
                    ),
                    attempts: appendUnique(
                        analysisMethodAttempts(evidenceText: evidenceText, sourceURL: sourceURL),
                        ["Parsed structured map place link before public metadata recovery"]
                    ),
                    missingFields: [],
                    nextBestClue: "Confirm this \(match.providerName) match before saving it as a Map Stamp."
                )
                return PendingReviewCandidate(
                    candidateName: match.name,
                    address: "",
                    category: category(from: "\(match.name) \(evidenceText)"),
                    latitude: match.latitude,
                    longitude: match.longitude,
                    sourceURL: sourceURL,
                    sourceText: evidenceText.isEmpty ? nil : evidenceText,
                    evidence: diagnostic.found + diagnostic.attempts + ["Map provider: \(match.providerName)"],
                    confidence: 0.84,
                    missingInfo: ["User confirmation required"],
                    savedAt: Date(),
                    evidenceDiagnostic: diagnostic,
                    reviewState: "map_match_ready"
                )
            }
            if let queryMatch = googleMapsQueryLinkMatch(in: urlString) {
                let diagnostic = SocialPlaceEvidenceDiagnostic(
                    found: appendUnique(
                        [],
                        [
                            "Source URL: \(sourceURL)",
                            "Structured Google Maps query link: \(queryMatch.name)",
                            queryMatch.address.isEmpty ? "" : "Address clue: \(queryMatch.address)"
                        ]
                    ),
                    attempts: appendUnique(
                        analysisMethodAttempts(evidenceText: evidenceText, sourceURL: sourceURL),
                        ["Parsed Google Maps query link before public metadata recovery"]
                    ),
                    missingFields: ["Verified coordinates"],
                    nextBestClue: "Confirm this Google Maps query match before saving it as a Map Stamp."
                )
                return PendingReviewCandidate(
                    candidateName: queryMatch.name,
                    address: queryMatch.address,
                    category: category(from: "\(queryMatch.name) \(queryMatch.address) \(evidenceText)"),
                    sourceURL: sourceURL,
                    sourceText: evidenceText.isEmpty ? nil : evidenceText,
                    evidence: diagnostic.found + diagnostic.attempts + ["Map provider: Google Maps"],
                    confidence: 0.78,
                    missingInfo: ["Verified coordinates", "User confirmation required"],
                    savedAt: Date(),
                    evidenceDiagnostic: diagnostic,
                    reviewState: "map_query_ready"
                )
            }
        }
        return nil
    }

    private func isValidMapCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite
            && longitude.isFinite
            && abs(latitude) <= 90
            && abs(longitude) <= 180
            && (latitude != 0 || longitude != 0)
    }

    private func googleMapsQueryLinkMatch(in urlString: String) -> (name: String, address: String)? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return nil }
        let isGoogleMapsHost = host.matchesSocialDomain("google.com") || host.matchesSocialDomain("maps.google.com")
        guard isGoogleMapsHost else { return nil }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let rawQuery = queryItems.first(where: { $0.name == "q" })?.value else { return nil }
        let query = decodedMapPlaceName(rawQuery)
        guard !query.isEmpty else { return nil }

        let cleanedQuery = query
            .replacingOccurrences(of: #"\s*(?:美國|美国|United States|USA)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,，").union(.whitespacesAndNewlines))
        let parts = cleanedQuery
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let name = parts.first, isUsableCandidateName(name) else { return nil }
        let address = parts.dropFirst().joined(separator: ", ")
        return (name, address)
    }

    private func westernMapLinkMatch(in urlString: String) -> (providerName: String, name: String, latitude: Double, longitude: Double)? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return nil }
        let isGoogleMapsHost = host.matchesSocialDomain("google.com") || host.matchesSocialDomain("maps.google.com")
        if isGoogleMapsHost, url.path.lowercased().contains("/maps/place/") {
            guard let regex = try? NSRegularExpression(pattern: #"/maps/place/([^/@?#]+)/@(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)"#) else { return nil }
            let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
            guard let match = regex.firstMatch(in: urlString, range: range),
                  match.numberOfRanges > 3,
                  let nameRange = Range(match.range(at: 1), in: urlString),
                  let latRange = Range(match.range(at: 2), in: urlString),
                  let lngRange = Range(match.range(at: 3), in: urlString),
                  let latitude = Double(urlString[latRange]),
                  let longitude = Double(urlString[lngRange]) else { return nil }
            let name = decodedMapPlaceName(String(urlString[nameRange]))
            guard isUsableCandidateName(name), isValidMapCoordinate(latitude: latitude, longitude: longitude) else { return nil }
            return ("Google Maps", name, latitude, longitude)
        }
        if host.matchesSocialDomain("maps.apple.com") {
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = queryItems.first(where: { $0.name == "q" })?.value ?? ""
            let ll = queryItems.first(where: { $0.name == "ll" })?.value ?? ""
            let parts = ll.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            let name = decodedMapPlaceName(query)
            guard isUsableCandidateName(name), parts.count == 2, isValidMapCoordinate(latitude: parts[0], longitude: parts[1]) else { return nil }
            return ("Apple Maps", name, parts[0], parts[1])
        }
        return nil
    }

    private func decodedMapPlaceName(_ value: String) -> String {
        let plusDecoded = value.replacingOccurrences(of: "+", with: " ")
        let decoded = plusDecoded.removingPercentEncoding ?? plusDecoded
        return cleanCandidateName(decoded)
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

        // Short-link resolution gets one bounded retry: a transient network
        // blip must not silently downgrade a resolvable link to source-only.
        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                // Lossy decode keeps partially valid UTF-8 metadata readable.
                let html = String(decoding: data.prefix(300_000), as: UTF8.self)
                let title = metadataValue(in: html, keys: ["og:title", "twitter:title", "title"])
                let description = metadataValue(in: html, keys: ["og:description", "twitter:description", "description"])
                let keywords = metadataValue(in: html, keys: ["keywords"])
                let imageURL = metadataImageURL(in: html, baseURL: response.url ?? url)
                let videoURL = metadataVideoURL(in: html, baseURL: response.url ?? url)
                let jsonCaption = embeddedSocialCaption(in: html)
                return PublicMetadata(
                    resolvedURL: response.url?.absoluteString ?? url.absoluteString,
                    title: title,
                    description: description,
                    keywords: keywords,
                    imageURL: imageURL,
                    videoURL: videoURL,
                    jsonCaption: jsonCaption
                )
            } catch {
                guard attempt < maxAttempts, isTransientNetworkError(error) else { break }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        return PublicMetadata(resolvedURL: url.absoluteString, title: nil, description: nil, keywords: nil, imageURL: nil, videoURL: nil, jsonCaption: nil, fetchReturnedNothing: true)
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet, .secureConnectionFailed:
            return true
        default:
            return false
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

    private nonisolated func isSafePublicHTTPURL(_ url: URL) -> Bool {
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

    // SAFETY: every mutable delegate field is accessed while holding `lock`;
    // `session` is initialized before its task starts and URLSession is thread-safe.
    private final class SafeThumbnailDataFetcher: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private enum FetchError: Error {
            case invalidResponse
            case unsafeRedirect
            case tooLarge
        }

        private let maxBytes: Int
        private let isSafeURL: @Sendable (URL) -> Bool
        private let lock = NSLock()
        private var data = Data()
        private var response: HTTPURLResponse?
        private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
        private var didFinish = false
        private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

        init(maxBytes: Int, isSafeURL: @escaping @Sendable (URL) -> Bool) {
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
        let address = streetAddressLine(in: evidenceText) ?? firstLocationPin(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? ""
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
        let address = streetAddressLine(in: evidenceText) ?? firstLocationPin(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? ""
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
        let address = streetAddressLine(in: evidenceText) ?? firstLocationPin(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? ""
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

    private func dianpingCandidate(from evidenceText: String, sourceURL: String) -> PendingReviewCandidate? {
        guard let context = dianpingLinkContext(sourceURL: sourceURL) else { return nil }
        guard let name = dianpingBusinessName(in: evidenceText) else { return nil }

        let address = streetAddressLine(in: evidenceText) ?? firstLocationPin(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? ""
        let category = category(from: "\(name) \(evidenceText)")
        let diagnostic = SocialPlaceEvidenceDiagnostic(
            found: appendUnique(
                [
                    "Source URL: \(sourceURL)",
                    context.identifierEvidence,
                    "Dianping business clue: \(name)"
                ],
                [
                    address.isEmpty ? "" : "Address/location clue: \(address)",
                    dianpingKeywordsEvidence(in: evidenceText) ?? "",
                    dianpingTitleEvidence(in: evidenceText) ?? ""
                ]
            ),
            attempts: appendUnique(
                analysisMethodAttempts(evidenceText: evidenceText, sourceURL: sourceURL),
                [
                    "Detected Dianping source metadata",
                    "Preferred Dianping keywords/business field over generic feed title",
                    "Prepared China place-provider refinement query",
                    "Kept Dianping match in Review until provider coordinates or user confirmation"
                ]
            ),
            missingFields: appendUnique(address.isEmpty ? ["Verified address"] : [], ["Verified coordinates", "User confirmation required"]),
            nextBestClue: address.isEmpty
                ? "Confirm the exact Dianping listing or share an AMap/Baidu/Google Maps link before saving this as a Map Stamp."
                : "Confirm the provider match and coordinates before saving this Dianping clue as a Map Stamp."
        )

        return PendingReviewCandidate(
            candidateName: name,
            address: address,
            category: category,
            latitude: nil,
            longitude: nil,
            sourceURL: sourceURL,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: diagnostic.found + diagnostic.attempts + ["Dianping source stays review-only until verified"],
            confidence: address.isEmpty ? 0.58 : 0.66,
            missingInfo: diagnostic.missingFields,
            savedAt: Date(),
            evidenceDiagnostic: diagnostic,
            reviewState: "review_candidate"
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
            // A caption-pin venue stem ("📍Ulaman, Bali, Indonesia" → "Ulaman")
            // is the strongest recovery seed: search the stem + region + category
            // so the official venue name ("Ulaman Eco Luxury Resort") surfaces and
            // outranks generic hashtags (#avatar/#pandora/beautiful destinations).
            if let stem = recoverableVenueStem(from: analysis) {
                if let region {
                    queries.append("\(stem) \(region) \(keyword)")
                } else {
                    queries.append("\(stem) \(keyword)")
                }
                queries.append("\(stem) official site")
            }
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
            .replacingOccurrences(of: #"(?i)\b(?:instagram\s+reel|instagram\s+post|xiaohongshu|xhs|douyin|tiktok(?:\s+short\s+link)?|dianping)\b"#, with: " ", options: .regularExpression)
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

    /// The best place-name stem the local parser already isolated from the
    /// caption (e.g. the "Ulaman" pin stem). Used to seed recovery search so the
    /// official venue name is surfaced. Rejects generic labels / the address-only
    /// placeholder so a thin source never seeds a search with noise.
    private func recoverableVenueStem(from analysis: SocialPlaceAgentAnalysis) -> String? {
        for draft in analysis.placesFound {
            let name = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name != "Address-only place clue",
                  isUsableCandidateName(name),
                  !looksLikeMarketingLine(name) else { continue }
            return name
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

    private func dianpingLinkContext(sourceURL: String) -> DianpingLinkContext? {
        guard let url = URL(string: sourceURL),
              let host = url.host()?.lowercased(),
              host.matchesSocialDomain("dianping.com") || host.matchesSocialDomain("dpurl.cn"),
              let feedID = dianpingFeedID(in: url) else {
            return nil
        }
        return DianpingLinkContext(feedID: feedID)
    }

    private func dianpingFeedID(in url: URL) -> String? {
        let path = url.path
        if let id = firstCapture(in: path, pattern: #"/feeddetail/([A-Za-z0-9_-]{4,})"#) {
            return id
        }
        let components = url.pathComponents
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
            .filter { !$0.isEmpty }
        if url.host()?.lowercased().matchesSocialDomain("dpurl.cn") == true {
            return components.last
        }
        return components.reversed().first { value in
            value.range(of: #"^[A-Za-z0-9_-]{4,}$"#, options: .regularExpression) != nil
        }
    }

    private func dianpingBusinessName(in evidenceText: String) -> String? {
        if let keywords = dianpingKeywords(in: evidenceText) {
            let candidates = keywords
                .components(separatedBy: CharacterSet(charactersIn: ",，、|｜;；"))
                .map(cleanDianpingBusinessName)
                .filter { !$0.isEmpty }
            if let best = candidates.first(where: isLikelyDianpingBusinessName) {
                return best
            }
        }
        let titleCandidates = evidenceText
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                let cleaned = cleanHTMLText(line)
                guard cleaned.range(of: #"(?i)^(?:Title|og:title|Dianping title)\s*[:：]"#, options: .regularExpression) != nil else { return nil }
                return cleaned
                    .replacingOccurrences(of: #"(?i)^(?:Title|og:title|Dianping title)\s*[:：]\s*"#, with: "", options: .regularExpression)
            }
            .map(cleanDianpingBusinessName)
        return titleCandidates.first(where: isLikelyDianpingBusinessName)
    }

    private func dianpingKeywords(in evidenceText: String) -> String? {
        firstCapture(in: evidenceText, pattern: #"(?im)^\s*(?:Keywords|keywords|Dianping keywords)\s*[:：]\s*([^\n\r]+)"#)
            .map(cleanHTMLText)
    }

    private func dianpingKeywordsEvidence(in evidenceText: String) -> String? {
        dianpingKeywords(in: evidenceText).map { "Dianping keywords: \($0)" }
    }

    private func dianpingTitleEvidence(in evidenceText: String) -> String? {
        firstCapture(in: evidenceText, pattern: #"(?im)^\s*(?:Title|og:title|Dianping title)\s*[:：]\s*([^\n\r]+)"#)
            .map(cleanHTMLText)
            .map { "Dianping title: \($0)" }
    }

    private func cleanDianpingBusinessName(_ value: String) -> String {
        cleanCandidateName(value)
            .replacingOccurrences(of: #"(?i)\s*(?:大众点评|大眾點評|dianping).*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r,，.。:：;；|｜-–—"))
    }

    private func isLikelyDianpingBusinessName(_ value: String) -> Bool {
        guard isUsableCandidateName(value), !looksLikeMarketingLine(value), !looksLikeAddressLine(value) else {
            return false
        }
        let generic = [
            "青岛崂山", "青島嶗山", "住到了人生酒店", "人生酒店", "酒店", "民宿", "美食", "攻略", "大众点评", "大眾點評"
        ]
        if generic.contains(value) { return false }
        if value.range(of: #"不要放過|不要放过|攻略|推薦|推荐|住到了|人生|五一|20\+"#, options: .regularExpression) != nil {
            return false
        }
        return true
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

    private struct DianpingLinkContext {
        var feedID: String

        var identifierEvidence: String {
            "Dianping feed id: \(feedID)"
        }
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
           let markerIndex = components.firstIndex(where: { ["reel", "reels", "p", "tv"].contains($0.lowercased()) }),
           components.indices.contains(markerIndex + 1) {
            let marker = components[markerIndex].lowercased()
            let id = components[markerIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            guard !id.isEmpty else { return nil }
            let platformName = marker == "p" || marker == "tv" ? "instagram post" : "instagram reel"
            let pathMarker = marker == "reels" ? "reel" : marker
            return SocialPostDescriptor(platformName: platformName, id: id, siteQuery: "site:instagram.com/\(pathMarker)/\(id)")
        }
        if host.matchesSocialDomain("tiktok.com") {
            if let videoIndex = components.firstIndex(where: { $0.lowercased() == "video" }),
               components.indices.contains(videoIndex + 1) {
                let id = components[videoIndex + 1].trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                return id.isEmpty ? nil : SocialPostDescriptor(platformName: "tiktok", id: id, siteQuery: "site:tiktok.com \(id)")
            }
            // vm./vt. share short links only expose an opaque code.
            guard let id = components.reversed().first(where: { $0.count >= 4 && $0 != "/" })?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")),
                  !id.isEmpty else { return nil }
            return SocialPostDescriptor(platformName: "tiktok short link", id: id, siteQuery: "\"\(canonicalSearchURL(from: descriptorURL) ?? descriptorURL.absoluteString)\"")
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
        if host.matchesSocialDomain("dianping.com") || host.matchesSocialDomain("dpurl.cn") {
            guard let id = dianpingFeedID(in: descriptorURL) else { return nil }
            return SocialPostDescriptor(platformName: "dianping", id: id, siteQuery: "site:dianping.com \(id)")
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
        let host = url.host?.lowercased() ?? ""
        if path.contains("/reel/") || path.contains("/reels/") { return "Instagram reel" }
        if host.contains("instagram") { return "Instagram link" }
        if host.matchesSocialDomain("xiaohongshu.com") || host.matchesSocialDomain("xhslink.com") { return "Xiaohongshu link" }
        if host.matchesSocialDomain("douyin.com") || host.matchesSocialDomain("iesdouyin.com") { return "Douyin link" }
        if host.matchesSocialDomain("dianping.com") || host.matchesSocialDomain("dpurl.cn") { return "Dianping link" }
        if host.matchesSocialDomain("tiktok.com") { return "TikTok link" }
        if host == "maps.app.goo.gl" || (host.contains("google") && path.contains("/maps")) { return "Google Maps link" }
        if host.matchesSocialDomain("maps.apple.com") { return "Apple Maps link" }
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
                let cleaned = cleanLocationMarker(from: match)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ：:"))
                guard !cleaned.isEmpty else { continue }
                if looksLikeAddressLine(cleaned) {
                    return cleaned
                }
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
            let address = cleanLocationMarker(from: line)
            let priorLines = Array(lines.prefix(index))

            // Prefer structural venue anchors over the closest freeform line.
            // This mirrors the manual analysis flow: first look for an explicit
            // venue token (`Venue / menu`, quoted venue, or handle), then use the
            // address as corroborating evidence. It avoids treating review-section
            // headers, dishes, or prose near the address as place names.
            for priorLine in priorLines {
                guard let candidate = candidateNameFromCaptionLine(priorLine) else { continue }
                if isLikelyCaptionPlaceName(candidate) {
                    return (candidate, address)
                }
            }

            var previousIndex = index - 1
            while previousIndex >= 0 {
                let candidate = cleanCandidateName(lines[previousIndex])
                if isLikelyCaptionPlaceName(candidate) {
                    return (candidate, address)
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
        if let line = lines.first(where: looksLikeAddressLine) {
            return cleanLocationMarker(from: line)
        }
        if let western = lines.first(where: looksLikeWesternStreetAddress) {
            return cleanLocationMarker(from: western)
        }
        return nil
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
        if !looksLikeAddressLine(line),
           let pinnedName = firstCapture(in: line, pattern: #"[📍🚩]\s*([^@\n\r]{2,80})(?:\s+@[A-Za-z0-9._]{3,30})?"#) {
            let cleaned = cleanCandidateName(pinnedName)
            if isUsableCandidateName(cleaned),
               !looksLikeAddressLine(cleaned),
               !looksLikeOperatingHoursLine(cleaned),
               !looksLikeReviewMetricLine(cleaned),
               !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }

        if let venueMarkerName = firstCapture(in: line, pattern: #"^\s*[🏠🏡🏘️🏚️🏪🏬🏢🍽️🍴☕️📍🚩]\s*([^\n\r]{2,60})"#) {
            let cleaned = cleanMarkedCandidateName(venueMarkerName)
            if isUsableCandidateName(cleaned),
               !looksLikeAddressLine(cleaned),
               !looksLikeOperatingHoursLine(cleaned),
               !looksLikeReviewMetricLine(cleaned),
               !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }

        if let socialArrowName = firstCapture(in: line, pattern: #"^\s*[👉➡→➜📌🏻🏼🏽🏾🏿️]+\s*([^\n\r]{2,60})"#) {
            let cleaned = cleanMarkedCandidateName(socialArrowName)
            if isUsableCandidateName(cleaned),
               !looksLikeAddressLine(cleaned),
               !looksLikeOperatingHoursLine(cleaned),
               !looksLikeReviewMetricLine(cleaned),
               !looksLikeMarketingLine(cleaned),
               !isProseFragmentCandidate(cleaned),
               looksLikeStandaloneMarkedVenueName(cleaned) {
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
        if let quoted = firstCapture(in: line, pattern: #"[「《\"]\s*([^」》\"]{2,60})\s*[」》\"]"#) {
            let cleaned = cleanCandidateName(quoted)
            if isUsableCandidateName(cleaned),
               !looksLikeMarketingLine(cleaned),
               looksLikeVenueTitle(cleaned),
               looksLikeStandaloneMarkedVenueName(cleaned) {
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

    private func looksLikeWesternStreetAddress(_ value: String) -> Bool {
        value.range(
            of: #"^\s*\d{1,6}\s+[A-Za-z0-9 .'-]{2,80}\s(?:Street|St\.?|Road|Rd\.?|Avenue|Ave\.?|Boulevard|Blvd\.?|Lane|Ln\.?|Drive|Dr\.?|Way|Highway|Hwy\.?|Coast Hwy)\b"#,
            options: .regularExpression
        ) != nil
    }

    private func looksLikeCityOnlyAddress(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z .'-]{2,40},\s*(?:CA|NY|TX|FL|WA|IL|NV|AZ|OR|MA|HI|UT|CO)$"#, options: .regularExpression) != nil
    }

    private func cleanMarkedCandidateName(_ value: String) -> String {
        let truncated = value
            .replacingOccurrences(of: #"[」》\"].*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+(?:我已經|我已经|不是|而且|但|不但|with|because)\b.*$"#, with: "", options: .regularExpression)
        return cleanCandidateName(truncated)
    }

    private func looksLikeVenueTitle(_ value: String) -> Bool {
        if value.range(of: #"(?i)\b(restaurant|cafe|coffee|bar|bakery|bistro|kitchen|grill|pizzeria|sushi|ramen|hotel|resort|inn|villa|district|market|museum|gallery|park|beach|garden|dining|pottery|studio)\b"#, options: .regularExpression) != nil {
            return true
        }
        return value.range(of: #"店|館|馆|餐廳|餐厅|咖啡|茶|酒吧|烘焙|燒肉|烧肉|火鍋|火锅|壽喜燒|寿喜烧|麵|面|飯|饭|屋|坊|室|湯|汤|菜"#, options: .regularExpression) != nil
    }

    private func looksLikeStandaloneMarkedVenueName(_ value: String) -> Bool {
        guard value.count <= 40 else { return false }
        if value.range(of: #"[，,。！!？?；;]"#, options: .regularExpression) != nil {
            return false
        }
        if value.range(of: #"(?i)\b(?:best\s+for|coffee\s+quality|unique\s+coffee\s+experiences|atmosphere|aesthetic|desserts?\s+worth|bookings?)\b"#, options: .regularExpression) != nil {
            return false
        }
        if value.range(of: #"最強|最强|免費|免费|吃到飽|吃到饱|必吃|必喝|推薦|推荐|隱藏版|隐藏版|打卡|排隊|排队"#, options: .regularExpression) != nil {
            return false
        }
        return true
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

    /// Records the public-fetch receipt (og:title/description/image presence,
    /// decoded caption length, whether the fetch returned a caption) on the
    /// candidate. For a source-only degrade it also stamps the parse outcome so
    /// future failures can be triaged from the evidence alone.
    func withSocialFetchDiagnostic(_ lines: [String]) -> PendingReviewCandidate {
        guard !lines.isEmpty else { return self }
        var copy = self
        var receipt = lines
        if copy.isSourceOnly {
            receipt.append("Social fetch: parse_outcome=source_only (caption present but no venue/address resolved)")
        }
        copy.evidence = uniqueStrings(copy.evidence + receipt)
        if var diagnostic = copy.evidenceDiagnostic {
            diagnostic.attempts = uniqueStrings(diagnostic.attempts + lines)
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
