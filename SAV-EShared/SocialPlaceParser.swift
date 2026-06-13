import Foundation

enum SocialEvidenceRole: String, Codable {
    case creatorHandle
    case venueHandle
    case venueName
    case cityClue
    case address
    case bookingLink
    case marketingText
    case sourceAccount
    case categoryClue
    case placeHighlight
}

enum SocialEvidenceSource: String, Codable {
    case numberedCaption
    case captionSentence
    case metadataTitle
    case metadataDescription
    case locationPin
    case socialHandle
    case bookingLink
    case ocr
}

struct SocialPlaceSourceEvidence {
    var sourceURL: String
    var resolvedURL: String?
    var sharedTitle: String?
    var sharedText: String?
    var metadataTitle: String?
    var metadataDescription: String?
    var ocrLines: [String]

    var combinedText: String {
        [sharedTitle, sharedText, metadataTitle, metadataDescription, ocrLines.joined(separator: "\n")]
            .compactMap { $0 }
            .map(SocialPlaceEvidenceScorer.cleanText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

struct TikTokSourceAdapterInput: Codable, Hashable {
    var sourceURL: String
    var caption: String
    var hashtags: [String]
    var coverOcr: [String]

    init(
        sourceURL: String,
        caption: String,
        hashtags: [String] = [],
        coverOcr: [String] = []
    ) {
        self.sourceURL = sourceURL
        self.caption = caption
        self.hashtags = hashtags
        self.coverOcr = coverOcr
    }
}

struct TikTokSourceAdapterResult: Codable, Hashable {
    var sourceIntent: SocialPlaceSourceIntent
    var region: String?
    var topic: String?
    var placesFound: Int
    var needsRecovery: Bool
    var resolverDecision: SocialPlaceResolverDecisionKind
    var recoveryStrategies: [SocialPlaceRecoveryStrategy]
}

struct TikTokSourceAdapter {
    private let parser: SocialPlaceParser

    init(parser: SocialPlaceParser = SocialPlaceParser()) {
        self.parser = parser
    }

    func analyze(_ input: TikTokSourceAdapterInput) -> TikTokSourceAdapterResult {
        let analysis = parser.analyze(evidence: evidence(from: input))
        return TikTokSourceAdapterResult(
            sourceIntent: analysis.sourceIntent,
            region: analysis.regionClues.first,
            topic: analysis.topic,
            placesFound: analysis.placesFound.count,
            needsRecovery: analysis.resolverDecision.kind == .pendingCandidate ||
                analysis.resolverDecision.kind == .multiPlaceList,
            resolverDecision: analysis.resolverDecision.kind,
            recoveryStrategies: analysis.recoveryStrategies
        )
    }

    func evidence(from input: TikTokSourceAdapterInput) -> SocialPlaceSourceEvidence {
        let hashtagText = input.hashtags
            .map { $0.hasPrefix("#") ? $0 : "#\($0)" }
            .joined(separator: " ")
        let sharedText = [input.caption, hashtagText]
            .map(SocialPlaceEvidenceScorer.cleanText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return SocialPlaceSourceEvidence(
            sourceURL: input.sourceURL,
            resolvedURL: nil,
            sharedTitle: nil,
            sharedText: sharedText.isEmpty ? nil : sharedText,
            metadataTitle: nil,
            metadataDescription: nil,
            ocrLines: input.coverOcr
        )
    }
}

enum SocialSharePlatform: String, Codable {
    case douyin
    case xiaohongshu
    case dianping
    case tiktok
    case instagram
    case googleMaps
    case appleMaps
    case chinaMaps
    case generic
}

struct SocialShareSourceBundle: Hashable {
    var rawShareText: String
    var embeddedURLStrings: [String]
    var primaryURLString: String?
    var platform: SocialSharePlatform
    var captionEvidence: String
    var creatorName: String?

    var primaryURL: URL? {
        primaryURLString.flatMap(URL.init(string:))
    }

    var hasResolvableURL: Bool {
        primaryURL != nil
    }
}

/// Normalizes messy real-world share pastes (mixed caption + URLs + app-open
/// boilerplate in zh/en + opaque share tokens) into a bounded source bundle.
/// The raw paste is always preserved; caption clues are never required to be a
/// bare URL, matching the china-social source adapter contract.
enum SocialShareTextNormalizer {
    static func normalize(_ rawShareText: String) -> SocialShareSourceBundle {
        let urls = embeddedURLStrings(in: rawShareText)
        let primary = primaryURLString(in: urls)
        let creatorName = creatorName(in: rawShareText)

        var working = rawShareText
        for pattern in boilerplatePatterns {
            working = working.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        working = working
            .replacingOccurrences(of: urlPattern, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: trailingShareTokenPattern, with: " ", options: .regularExpression)

        let captionLines = working
            .components(separatedBy: .newlines)
            .map(SocialPlaceEvidenceScorer.cleanText)
            .filter { !$0.isEmpty && !looksLikeShareTokenNoise($0) }

        return SocialShareSourceBundle(
            rawShareText: rawShareText,
            embeddedURLStrings: urls,
            primaryURLString: primary,
            platform: primary.map(platform(forURLString:)) ?? .generic,
            captionEvidence: captionLines.joined(separator: "\n"),
            creatorName: creatorName
        )
    }

    static func embeddedURLStrings(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;。；，)）]】」』\"'"))
        }
    }

    static func platform(forURLString urlString: String) -> SocialSharePlatform {
        let lowered = urlString.lowercased()
        if lowered.hasPrefix("iosamap://") || lowered.hasPrefix("amapuri://") || lowered.hasPrefix("baidumap://") {
            return .chinaMaps
        }
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return .generic }
        let path = url.path.lowercased()
        if isHost(host, domain: "douyin.com") || isHost(host, domain: "iesdouyin.com") { return .douyin }
        if isHost(host, domain: "xiaohongshu.com") || isHost(host, domain: "xhslink.com") { return .xiaohongshu }
        if isHost(host, domain: "dianping.com") || isHost(host, domain: "dpurl.cn") { return .dianping }
        if isHost(host, domain: "tiktok.com") { return .tiktok }
        if isHost(host, domain: "instagram.com") { return .instagram }
        if isHost(host, domain: "amap.com") || isHost(host, domain: "map.baidu.com") { return .chinaMaps }
        if host == "maps.app.goo.gl" || (isHost(host, domain: "goo.gl") && path.contains("maps")) { return .googleMaps }
        if isHost(host, domain: "google.com") && path.contains("/maps") { return .googleMaps }
        if isHost(host, domain: "maps.apple.com") { return .appleMaps }
        return .generic
    }

    // MARK: - Private

    private static let urlPattern = #"https?://[^\s<>\"'，。；）)\]】」』]+|(?:iosamap|amapuri|baidumap)://[^\s<>\"]+"#

    // Trailing copy-code soup appended by mainland share sheets, e.g.
    // "05/20 JIi:/ f@o.Qk :9pm" glued to the end of a caption line.
    private static let trailingShareTokenPattern =
        #"\s+\d{1,2}/\d{1,2}(?:\s+[A-Za-z0-9@:/.,!?%$#\-_]{1,16}){0,8}\s*$"#

    private static let boilerplatePatterns = [
        // Douyin share lead-in: "9.41 复制打开抖音，看看【…的作品】…"
        #"\d{1,2}\.\d{2}\s+(?=(?:[A-Za-z0-9]{2,10}[:/]{1,3}\s+)?复制打开)"#,
        #"[A-Za-z0-9]{2,10}[:/]{1,3}\s+(?=复制打开)"#,
        #"复制打开(?:抖音|快手)(?:极速版|極速版)?[，,]?\s*(?:看看)?"#,
        #"【[^【】\n]{1,40}的(?:图文作品|圖文作品|作品|视频|視頻|影片|直播)】"#,
        #"长按复制此条消息[^\n]*"#,
        #"長按複製此條訊息[^\n]*"#,
        // Xiaohongshu share lead-in: "73 【标题】 😆 token 😆 link 复制本条信息…"
        #"^\s*\d{1,3}\s+(?=【)"#,
        #"[😆😝🤗🥳😊]\s*[A-Za-z0-9]{6,24}\s*[😆😝🤗🥳😊]"#,
        #"复制本条信息[^\n]*"#,
        #"複製本條訊息[^\n]*"#,
        #"打开【?小红书】?\s*App查看精彩内容[！!]?"#,
        #"打開【?小紅書】?\s*App查看精彩內容[！!]?"#,
        #"(?:\d+\s+)?发现了?一篇[^\n]{0,20}笔记[^\n]{0,20}(?:快来看吧)?[！!]?"#,
        #"复制这段内容[^\n]*"#,
        // English app share boilerplate.
        #"(?i)check out [^\n]{0,60}(?:'s)? (?:video|post) on tiktok[.!]?"#
    ]

    private static func primaryURLString(in urls: [String]) -> String? {
        urls.enumerated().min { lhs, rhs in
            let lhsRank = platformPriority(platform(forURLString: lhs.element))
            let rhsRank = platformPriority(platform(forURLString: rhs.element))
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.offset < rhs.offset
        }?.element
    }

    private static func platformPriority(_ platform: SocialSharePlatform) -> Int {
        switch platform {
        case .chinaMaps, .googleMaps, .appleMaps:
            return 0
        case .dianping:
            return 1
        case .douyin:
            return 2
        case .xiaohongshu:
            return 3
        case .tiktok:
            return 4
        case .instagram:
            return 5
        case .generic:
            return 6
        }
    }

    private static func creatorName(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"【([^【】\n]{1,40})的(?:图文作品|圖文作品|作品|视频|視頻|影片|直播)】"#
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        let cleaned = SocialPlaceEvidenceScorer.cleanText(String(text[captureRange]))
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func looksLikeShareTokenNoise(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 48,
              trimmed.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) == nil,
              trimmed.range(of: #"[@:/]"#, options: .regularExpression) != nil,
              trimmed.range(of: #"^@[A-Za-z0-9._]{3,30}$"#, options: .regularExpression) == nil else {
            return false
        }
        if trimmed.range(of: #"^\d{1,2}/\d{1,2}\b"#, options: .regularExpression) != nil { return true }
        let tokens = trimmed.split(separator: " ")
        let opaque = tokens.allSatisfy { token in
            token.count <= 12 &&
                token.range(of: #"^[A-Za-z0-9@:/.,!?%$#\-_]+$"#, options: .regularExpression) != nil
        }
        let hasRealWord = trimmed.range(of: #"(?i)\b[a-z]{5,}\b"#, options: .regularExpression) != nil
        return opaque && !hasRealWord
    }

    private static func isHost(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }
}

struct SocialEvidenceAtom {
    var source: SocialEvidenceSource
    var role: SocialEvidenceRole
    var value: String
    var line: String
    var confidence: Double

    var chip: String {
        switch role {
        case .creatorHandle:
            return "Creator handle: @\(value)"
        case .venueHandle:
            return "Venue handle: @\(value)"
        case .venueName:
            return "Venue name: \(value)"
        case .cityClue:
            return "Location clue: \(value)"
        case .address:
            return "Address clue: \(value)"
        case .bookingLink:
            return "Booking link: \(value)"
        case .marketingText:
            return "Marketing text ignored"
        case .sourceAccount:
            if value.hasPrefix("http://") || value.hasPrefix("https://") {
                return "Source URL: \(value)"
            }
            return "Source account: @\(value)"
        case .categoryClue:
            return "Category clue: \(value)"
        case .placeHighlight:
            return "Highlight: \(value)"
        }
    }
}

struct SocialPlaceCandidateDraft {
    var canonicalName: String
    var displayName: String
    var category: String
    var handles: [String]
    var creatorHandles: [String]
    var venueHandles: [String]
    var locationClues: [String]
    var bookingLinks: [String]
    var evidence: [SocialEvidenceAtom]
    var confidence: Double
    var missingInfo: [String]

    var hasAddress: Bool {
        !locationClues.isEmpty
    }

    var evidenceChips: [String] {
        Array(NSOrderedSet(array: evidence.map(\.chip))) as? [String] ?? evidence.map(\.chip)
    }
}

struct SocialPlaceSourceActor {
    var handle: String
    var role: SocialEvidenceRole
    var why: String
}

struct SocialPlaceDiscardedCandidate {
    var value: String
    var reason: String
}

enum SocialPlaceSourceType: String, Codable {
    case singleVenuePost
    case multiPlaceList
    case creatorOnly
    case sourceOnly
    case unknown
    case singlePlaceRecommendation
    case creatorSourceOnly
    case ocrHeavySource
    case mapShare
    case bookingOrReservation
    case activityOrExperienceVenue
    case vagueLifestyleCaption
    case ambiguous
}

enum SocialPlaceRecoveryStrategy: String, Codable, Hashable {
    case directParse
    case publicSearchRecovery
    case handleResolver
    case listMode
    case ocrExtraction
    case mapLinkResolution
    case bookingLinkResolution
    case askForMoreEvidence
    case sourceOnlyReceipt
}

struct SocialPlaceSourceUnderstanding {
    var sourceType: SocialPlaceSourceType
    var recoveryStrategies: [SocialPlaceRecoveryStrategy]
    var evidenceTier: SocialPlaceEvidenceTier
    var reasons: [String]
    var missingInfo: [String]
}

enum SocialPlaceSourceIntent: String, Codable {
    case nonPlace
    case creatorOnly
    case restaurantRecommendation
    case cafeRecommendation
    case travelRecommendation
    case stayRecommendation
    case multiPlaceList
    case singleVenuePost
    case unknownPlaceBearing
}

enum SocialPlaceResolverDecisionKind: String, Codable {
    case verifiedCandidate
    case pendingCandidate
    case multiPlaceList
    case sourceOnly
    case reject
}

struct SocialPlaceResolverDecision: Codable, Hashable {
    var kind: SocialPlaceResolverDecisionKind
    var confidence: Double
    var reasons: [String]
    var requiredEvidence: [String]
    var nextAction: String

    var allowsDirectSave: Bool {
        kind == .verifiedCandidate
    }

    var shouldRunPublicSearch: Bool {
        switch kind {
        case .pendingCandidate, .multiPlaceList:
            return requiredEvidence.contains("Public corroboration") ||
                requiredEvidence.contains("Map/place match") ||
                nextAction.lowercased().contains("search")
        case .verifiedCandidate, .sourceOnly, .reject:
            return false
        }
    }

    var reviewState: String {
        switch kind {
        case .verifiedCandidate:
            return "map_match_ready"
        case .pendingCandidate:
            return "pending_candidate"
        case .multiPlaceList:
            return "multi_place_list"
        case .sourceOnly:
            return "source_only"
        case .reject:
            return "rejected_non_place"
        }
    }
}

struct SocialPlaceRecoveryHint: Codable, Hashable {
    var label: String
    var queryFragment: String
}

struct SocialPlaceSourceGroup {
    var label: String
    var venueHandles: [String]
    var evidenceLine: String
}

struct SocialPlaceAgentAnalysis {
    var sourceType: SocialPlaceSourceType
    var sourceSummary: String
    var topic: String?
    var regionClues: [String]
    var groups: [SocialPlaceSourceGroup]
    var placesFound: [SocialPlaceCandidateDraft]
    var sourceActors: [SocialPlaceSourceActor]
    var discardedCandidates: [SocialPlaceDiscardedCandidate]
    var sourceIntent: SocialPlaceSourceIntent
    var isPlaceBearing: Bool
    var placeBearingReason: String?
    var recoveryHints: [SocialPlaceRecoveryHint]
    var understanding: SocialPlaceSourceUnderstanding
    var resolverDecision: SocialPlaceResolverDecision
    var confidence: Double
    var nextBestAction: String
}

extension SocialPlaceAgentAnalysis {
    var recoveryStrategies: [SocialPlaceRecoveryStrategy] {
        understanding.recoveryStrategies
    }

    var primaryRecoveryStrategy: SocialPlaceRecoveryStrategy {
        understanding.recoveryStrategies.first ?? .sourceOnlyReceipt
    }
}

extension SocialPlaceResolverDecision {
    static func resolve(
        sourceType: SocialPlaceSourceType,
        sourceIntent: SocialPlaceSourceIntent,
        placesFound: [SocialPlaceCandidateDraft],
        groups: [SocialPlaceSourceGroup],
        understanding: SocialPlaceSourceUnderstanding,
        isPlaceBearing: Bool
    ) -> SocialPlaceResolverDecision {
        let hasCandidates = !placesFound.isEmpty
        let hasAddress = placesFound.contains { !$0.locationClues.isEmpty }
        let hasVerifiedMapMatch = placesFound.contains { draft in
            draft.evidenceChips.contains { $0.localizedCaseInsensitiveContains("coordinates") }
        }
        let strategies = understanding.recoveryStrategies
        let reasons = understanding.reasons

        if sourceType == .mapShare {
            return SocialPlaceResolverDecision(
                kind: hasVerifiedMapMatch ? .verifiedCandidate : .pendingCandidate,
                confidence: hasVerifiedMapMatch ? 0.9 : 0.68,
                reasons: reasons + ["structured map source should be resolved before saving"],
                requiredEvidence: hasVerifiedMapMatch ? ["User confirmation"] : ["Structured map resolution", "Coordinates"],
                nextAction: hasVerifiedMapMatch
                    ? "Ask the user to confirm the map match."
                    : "Resolve the map link into a candidate before saving."
            )
        }

        if sourceType == .bookingOrReservation {
            return SocialPlaceResolverDecision(
                kind: .pendingCandidate,
                confidence: hasAddress ? 0.66 : 0.52,
                reasons: reasons + ["booking source can name a venue but still needs map verification"],
                requiredEvidence: ["Map/place match", "Coordinates", "User confirmation"],
                nextAction: "Extract the venue from the booking source, then refine against Places before saving."
            )
        }

        if sourceIntent == .nonPlace && !hasCandidates && !isPlaceBearing {
            return SocialPlaceResolverDecision(
                kind: sourceType == .sourceOnly ? .sourceOnly : .reject,
                confidence: 0,
                reasons: reasons + ["no place-bearing intent or candidate evidence"],
                requiredEvidence: ["Venue name", "Address or map link"],
                nextAction: sourceType == .sourceOnly
                    ? "Keep the source receipt and ask for a caption, screenshot, or map link."
                    : "Do not create a place candidate until the user adds clearer place evidence."
            )
        }

        if sourceType == .multiPlaceList || !groups.isEmpty || sourceIntent == .multiPlaceList {
            return SocialPlaceResolverDecision(
                kind: .multiPlaceList,
                confidence: min(max(understanding.evidenceTier == .sourceOnly ? 0.42 : 0.62, 0.42), 0.72),
                reasons: reasons + ["source contains multiple venue/list groups"],
                requiredEvidence: ["User selects candidates", "Map/place match", "Public corroboration"],
                nextAction: "Show multiple review candidates; let the user add one or all before map confirmation."
            )
        }

        if hasCandidates {
            return SocialPlaceResolverDecision(
                kind: hasAddress && hasVerifiedMapMatch ? .verifiedCandidate : .pendingCandidate,
                confidence: hasAddress ? 0.66 : 0.5,
                reasons: reasons + ["candidate exists but is not a saved place until coordinates are verified"],
                requiredEvidence: hasAddress
                    ? ["Coordinates", "User confirmation"]
                    : ["Address", "Coordinates", "User confirmation"],
                nextAction: "Create a review candidate and require Places/map confirmation before saving."
            )
        }

        if isPlaceBearing || strategies.contains(.publicSearchRecovery) {
            return SocialPlaceResolverDecision(
                kind: .pendingCandidate,
                confidence: 0.35,
                reasons: reasons + ["place-bearing source lacks a verified venue name"],
                requiredEvidence: ["Public corroboration", "Venue name", "Map/place match"],
                nextAction: "Run source recovery search; keep the result in Review unless a map match is confirmed."
            )
        }

        if sourceType == .creatorSourceOnly || sourceType == .creatorOnly || sourceType == .sourceOnly {
            return SocialPlaceResolverDecision(
                kind: .sourceOnly,
                confidence: 0,
                reasons: reasons + ["source has no safe venue evidence"],
                requiredEvidence: ["Venue name", "Address or map link"],
                nextAction: "Keep a source receipt and ask for a better clue."
            )
        }

        return SocialPlaceResolverDecision(
            kind: .reject,
            confidence: 0,
            reasons: reasons + ["ambiguous or vague text should not become a place"],
            requiredEvidence: ["Venue name", "Address or map link"],
            nextAction: "Ask for a screenshot, caption, or map link before creating a candidate."
        )
    }
}

struct SocialSourceClassifier {
    func classify(
        evidence: SocialPlaceSourceEvidence,
        legacySourceType: SocialPlaceSourceType,
        sourceIntent: SocialPlaceSourceIntent,
        placesFound: [SocialPlaceCandidateDraft],
        groups: [SocialPlaceSourceGroup],
        creatorHandles: Set<String>,
        regionClues: [String]
    ) -> SocialPlaceSourceUnderstanding {
        let text = evidence.combinedText
        let hasVenueHandles = placesFound.contains { !$0.venueHandles.isEmpty } ||
            groups.contains { !$0.venueHandles.isEmpty }
        let hasBookingClues = isBookingSource(evidence.sourceURL) ||
            isBookingText(text) ||
            placesFound.contains { !$0.bookingLinks.isEmpty }
        let hasMapClues = isMapShare(evidence.sourceURL) || isMapShare(evidence.resolvedURL) || isMapText(text)
        let hasOCRClues = !evidence.ocrLines.isEmpty
        let hasDirectCandidates = !placesFound.isEmpty
        let isPlaceBearing = isPlaceBearingIntent(sourceIntent)

        let type: SocialPlaceSourceType
        if hasMapClues {
            type = .mapShare
        } else if hasBookingClues {
            type = .bookingOrReservation
        } else if legacySourceType == .multiPlaceList || !groups.isEmpty || sourceIntent == .multiPlaceList {
            type = .multiPlaceList
        } else if looksLikeActivityOrExperience(text: text, placesFound: placesFound) {
            type = .activityOrExperienceVenue
        } else if hasOCRClues && !hasDirectCandidates {
            type = .ocrHeavySource
        } else if hasDirectCandidates || isSinglePlaceIntent(sourceIntent) {
            type = .singlePlaceRecommendation
        } else if legacySourceType == .creatorOnly || (!creatorHandles.isEmpty && !hasVenueHandles) {
            type = .creatorSourceOnly
        } else if isVagueLifestyleCaption(text) {
            type = .vagueLifestyleCaption
        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            type = .sourceOnly
        } else if isPlaceBearing {
            type = .singlePlaceRecommendation
        } else {
            type = .ambiguous
        }

        let strategies = recoveryStrategies(
            sourceType: type,
            sourceIntent: sourceIntent,
            hasDirectCandidates: hasDirectCandidates,
            hasVenueHandles: hasVenueHandles,
            hasOCRClues: hasOCRClues
        )

        return SocialPlaceSourceUnderstanding(
            sourceType: type,
            recoveryStrategies: strategies,
            evidenceTier: evidenceTier(
                sourceType: type,
                hasDirectCandidates: hasDirectCandidates,
                hasVerifiedAddressClue: placesFound.contains { !$0.locationClues.isEmpty }
            ),
            reasons: reasons(
                sourceType: type,
                sourceIntent: sourceIntent,
                hasDirectCandidates: hasDirectCandidates,
                hasVenueHandles: hasVenueHandles,
                hasOCRClues: hasOCRClues,
                regionClues: regionClues
            ),
            missingInfo: missingInfo(sourceType: type, strategies: strategies)
        )
    }

    private func recoveryStrategies(
        sourceType: SocialPlaceSourceType,
        sourceIntent: SocialPlaceSourceIntent,
        hasDirectCandidates: Bool,
        hasVenueHandles: Bool,
        hasOCRClues: Bool
    ) -> [SocialPlaceRecoveryStrategy] {
        var strategies: [SocialPlaceRecoveryStrategy] = []

        switch sourceType {
        case .mapShare:
            strategies.append(.mapLinkResolution)
        case .bookingOrReservation:
            strategies.append(.bookingLinkResolution)
        case .multiPlaceList:
            strategies.append(.listMode)
        case .ocrHeavySource:
            strategies.append(.ocrExtraction)
        case .creatorSourceOnly, .sourceOnly:
            strategies.append(.sourceOnlyReceipt)
        case .vagueLifestyleCaption, .ambiguous, .unknown:
            strategies.append(.askForMoreEvidence)
        case .singlePlaceRecommendation, .activityOrExperienceVenue, .singleVenuePost:
            break
        case .creatorOnly:
            strategies.append(.sourceOnlyReceipt)
        }

        if hasDirectCandidates {
            strategies.append(.directParse)
        }
        if hasVenueHandles {
            strategies.append(.handleResolver)
        }
        if shouldRunPublicSearch(sourceType: sourceType, sourceIntent: sourceIntent, hasDirectCandidates: hasDirectCandidates) {
            strategies.append(.publicSearchRecovery)
        }
        if hasOCRClues, !strategies.contains(.ocrExtraction) {
            strategies.append(.ocrExtraction)
        }
        if strategies.isEmpty {
            strategies.append(.askForMoreEvidence)
        }

        return uniqueStrategies(strategies)
    }

    private func shouldRunPublicSearch(
        sourceType: SocialPlaceSourceType,
        sourceIntent: SocialPlaceSourceIntent,
        hasDirectCandidates: Bool
    ) -> Bool {
        switch sourceType {
        case .singlePlaceRecommendation, .multiPlaceList, .activityOrExperienceVenue, .ocrHeavySource, .bookingOrReservation:
            return true
        case .mapShare:
            return false
        case .vagueLifestyleCaption, .ambiguous, .unknown:
            return isPlaceBearingIntent(sourceIntent)
        case .singleVenuePost:
            return !hasDirectCandidates || isPlaceBearingIntent(sourceIntent)
        case .sourceOnly, .creatorOnly, .creatorSourceOnly:
            return false
        }
    }

    private func evidenceTier(
        sourceType: SocialPlaceSourceType,
        hasDirectCandidates: Bool,
        hasVerifiedAddressClue: Bool
    ) -> SocialPlaceEvidenceTier {
        if sourceType == .mapShare || hasVerifiedAddressClue { return .likely }
        if hasDirectCandidates { return .weakCandidate }
        switch sourceType {
        case .sourceOnly, .creatorOnly, .creatorSourceOnly, .vagueLifestyleCaption, .ambiguous, .unknown:
            return .sourceOnly
        case .singleVenuePost, .singlePlaceRecommendation, .multiPlaceList, .ocrHeavySource, .bookingOrReservation, .activityOrExperienceVenue, .mapShare:
            return .weakCandidate
        }
    }

    private func reasons(
        sourceType: SocialPlaceSourceType,
        sourceIntent: SocialPlaceSourceIntent,
        hasDirectCandidates: Bool,
        hasVenueHandles: Bool,
        hasOCRClues: Bool,
        regionClues: [String]
    ) -> [String] {
        var values = ["classified as \(sourceType.rawValue)", "intent \(sourceIntent.rawValue)"]
        if hasDirectCandidates { values.append("direct venue clue present") }
        if hasVenueHandles { values.append("venue handle clue present") }
        if hasOCRClues { values.append("OCR evidence present") }
        if let region = regionClues.first { values.append("region clue: \(region)") }
        return values
    }

    private func missingInfo(sourceType: SocialPlaceSourceType, strategies: [SocialPlaceRecoveryStrategy]) -> [String] {
        var values: [String] = []
        if strategies.contains(.publicSearchRecovery) {
            values.append("Public corroboration")
        }
        if strategies.contains(.handleResolver) {
            values.append("Handle ownership check")
        }
        if strategies.contains(.mapLinkResolution) || strategies.contains(.bookingLinkResolution) {
            values.append("Structured place resolution")
        }
        if strategies.contains(.askForMoreEvidence) {
            values.append("More evidence from user")
        }
        switch sourceType {
        case .singlePlaceRecommendation, .multiPlaceList, .ocrHeavySource, .bookingOrReservation, .activityOrExperienceVenue:
            values.append("Verified map/place match")
        case .creatorSourceOnly, .sourceOnly, .vagueLifestyleCaption, .ambiguous, .unknown, .creatorOnly:
            values.append("Usable venue name")
        case .mapShare, .singleVenuePost:
            break
        }
        return Array(Set(values)).sorted()
    }

    private func isSinglePlaceIntent(_ intent: SocialPlaceSourceIntent) -> Bool {
        switch intent {
        case .restaurantRecommendation, .cafeRecommendation, .travelRecommendation, .stayRecommendation, .singleVenuePost, .unknownPlaceBearing:
            return true
        case .nonPlace, .creatorOnly, .multiPlaceList:
            return false
        }
    }

    private func isPlaceBearingIntent(_ intent: SocialPlaceSourceIntent) -> Bool {
        switch intent {
        case .nonPlace, .creatorOnly:
            return false
        case .restaurantRecommendation, .cafeRecommendation, .travelRecommendation, .stayRecommendation, .multiPlaceList, .singleVenuePost, .unknownPlaceBearing:
            return true
        }
    }

    private func isMapShare(_ rawURL: String?) -> Bool {
        guard let rawURL, let url = URL(string: rawURL) else { return false }
        let host = url.host?.lowercased() ?? ""
        return host.contains("google.com") && url.path.lowercased().contains("/maps") ||
            host == "maps.app.goo.gl" ||
            host.contains("maps.apple.com") ||
            host.contains("goo.gl")
    }

    private func isMapText(_ text: String) -> Bool {
        text.range(of: #"(?i)(google maps|apple maps|maps\.app\.goo\.gl|maps\.apple\.com|/maps/place)"#, options: .regularExpression) != nil
    }

    private func isBookingSource(_ rawURL: String?) -> Bool {
        guard let rawURL, let url = URL(string: rawURL) else { return false }
        let host = url.host?.lowercased() ?? ""
        return host.contains("opentable") ||
            host.contains("resy") ||
            host.contains("tock") ||
            host.contains("sevenrooms") ||
            host.contains("booking.com") ||
            host.contains("airbnb")
    }

    private func isBookingText(_ text: String) -> Bool {
        text.range(of: #"(?i)\b(?:book|booking|reservation|reserve|resy|opentable|tock|sevenrooms)\b"#, options: .regularExpression) != nil
    }

    private func looksLikeActivityOrExperience(text: String, placesFound: [SocialPlaceCandidateDraft]) -> Bool {
        if placesFound.contains(where: { $0.category == "attraction" && !$0.bookingLinks.isEmpty }) {
            return true
        }
        return text.range(of: #"(?i)\b(?:pottery|ceramics?|workshops?|classes?|lessons?|experience|activity|tour)\b"#, options: .regularExpression) != nil
    }

    private func isVagueLifestyleCaption(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.range(of: #"\b(?:vibe|aesthetic|weekend|slow down|hidden gem|perfect day|save this)\b"#, options: .regularExpression) != nil
    }

    private func uniqueStrategies(_ values: [SocialPlaceRecoveryStrategy]) -> [SocialPlaceRecoveryStrategy] {
        var seen = Set<SocialPlaceRecoveryStrategy>()
        var result: [SocialPlaceRecoveryStrategy] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

struct SocialPlaceParser {
    func parse(evidence: SocialPlaceSourceEvidence) -> [SocialPlaceCandidateDraft] {
        analyze(evidence: evidence).placesFound
    }

    /// Promotes inline caption markers (👉 name pointer, 📍/🗺️ location pin,
    /// 🍽️ hours, 🚇/🚇 transit, · separator) to line breaks so the per-line
    /// marker parsers fire on single-line og:description captions. A marker that
    /// already starts a line is left untouched; only mid-line occurrences get a
    /// preceding newline inserted.
    static func lineBreakInlineCaptionMarkers(in text: String) -> String {
        guard !text.isEmpty else { return text }
        // Rewrite is applied per physical line so multi-line captions (where
        // 👉/📍/🍽️/🚇 already lead their own line) are untouched. A line is only
        // exploded when it is a long single-line og:description blob carrying
        // multiple markers inline — the shape Instagram returns. A short venue
        // line like "<阿夢> 📍中正紀念堂" (one inline area marker) stays intact so
        // its inline area clue is not detached from the venue.
        return text
            .components(separatedBy: "\n")
            .map(explodeInlineMarkersIfBlob)
            .joined(separator: "\n")
    }

    private static func explodeInlineMarkersIfBlob(_ line: String) -> String {
        guard line.count >= 60 else { return line }
        let markerPattern = #"(👉|📍|🗺️?|🍽️?|🚇|🚉|🚩|📌)"#
        guard let countRegex = try? NSRegularExpression(pattern: markerPattern) else { return line }
        let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard countRegex.numberOfMatches(in: line, range: fullRange) >= 2 else { return line }
        let inlinePattern = #"(?<=[^\n\r])\s*"# + markerPattern
        guard let regex = try? NSRegularExpression(pattern: inlinePattern) else { return line }
        return regex.stringByReplacingMatches(in: line, range: fullRange, withTemplate: "\n$1")
    }

    func analyze(evidence: SocialPlaceSourceEvidence) -> SocialPlaceAgentAnalysis {
        // Single-line og:description captions (Instagram returns the whole
        // caption as one og:title/og:description line, no newlines) embed venue
        // markers inline: "…👉🏻Venue 📍Address…". The per-line marker logic
        // below only fires when 👉/📍/🍽️/🚇 anchor the start of a line, so we
        // first promote inline markers to line breaks. Multi-line captions are
        // unaffected (markers already lead their own line).
        let text = SocialPlaceParser.lineBreakInlineCaptionMarkers(in: evidence.combinedText)
        let lines = text
            .components(separatedBy: .newlines)
            .map(SocialPlaceEvidenceScorer.cleanText)
            .filter { !$0.isEmpty }

        let handleContexts = handleContexts(in: lines, fullText: text)
        let creatorHandles = Set(handleContexts.filter { $0.role == .creatorHandle }.map(\.handle))
        let sourceActors = handleContexts
            .filter { $0.role == .creatorHandle || $0.role == .sourceAccount }
            .map { SocialPlaceSourceActor(handle: $0.handle, role: $0.role, why: $0.reason) }
        let sourceGroups = sourceGroups(from: lines)
        let topic = sourceTopic(from: text)
        let regionClues = regionClues(from: text)
        let discarded = creatorHandles.map {
            SocialPlaceDiscardedCandidate(
                value: SocialPlaceEvidenceScorer.displayName(fromSocialHandle: $0),
                reason: "creator handle, not a venue"
            )
        }

        let isDouyinAggregateList = looksLikeDouyinAggregateFoodList(text: text, sourceURL: evidence.sourceURL)
        var candidates: [SocialPlaceCandidateDraft] = []
        candidates.append(contentsOf: douyinFoodListCandidates(from: text, sourceURL: evidence.sourceURL))
        if !isDouyinAggregateList || !candidates.isEmpty {
            candidates.append(contentsOf: numberedCandidates(from: lines, sourceURL: evidence.sourceURL, fullText: text, handleContexts: handleContexts))
            candidates.append(contentsOf: bracketedCandidates(from: text, sourceURL: evidence.sourceURL))
            candidates.append(contentsOf: englishStayCandidates(from: lines, sourceURL: evidence.sourceURL, fullText: text))
            candidates.append(contentsOf: inferredAddressCandidates(from: lines, sourceURL: evidence.sourceURL, fullText: text))
            candidates.append(contentsOf: addressOnlyCandidates(from: lines, sourceURL: evidence.sourceURL, fullText: text))
            candidates.append(contentsOf: chineseVenueCandidates(from: text, sourceURL: evidence.sourceURL))
            candidates.append(contentsOf: instagramMetadataTitleCandidates(from: lines, sourceURL: evidence.sourceURL, fullText: text))
            candidates.append(contentsOf: handleOnlyCandidates(from: handleContexts, sourceURL: evidence.sourceURL, fullText: text, creatorHandles: creatorHandles))
        }
        candidates.append(contentsOf: ocrCandidates(from: evidence.ocrLines, sourceURL: evidence.sourceURL, fullText: text))

        let sourceType = sourceType(
            text: text,
            sourceURL: evidence.sourceURL,
            groups: sourceGroups,
            candidates: candidates,
            creatorHandles: creatorHandles
        )
        let merged = attachSourceGroupEvidence(
            groups: sourceGroups,
            to: mergeCandidates(candidates)
        )
            .filter { !SocialPlaceEvidenceScorer.isRejectedTitle($0.displayName) }
        let rankedMerged = prioritizeParsedCandidates(merged)
        let intent = sourceIntent(
            text: text,
            sourceType: sourceType,
            topic: topic,
            regionClues: regionClues,
            groups: sourceGroups,
            placesFound: rankedMerged,
            creatorHandles: creatorHandles
        )
        let isPlaceBearing = isPlaceBearingIntent(intent)
        let understanding = SocialSourceClassifier().classify(
            evidence: evidence,
            legacySourceType: sourceType,
            sourceIntent: intent,
            placesFound: rankedMerged,
            groups: sourceGroups,
            creatorHandles: creatorHandles,
            regionClues: regionClues
        )
        let resolverDecision = SocialPlaceResolverDecision.resolve(
            sourceType: understanding.sourceType,
            sourceIntent: intent,
            placesFound: rankedMerged,
            groups: sourceGroups,
            understanding: understanding,
            isPlaceBearing: isPlaceBearing
        )

        // A list-shaped source (e.g. OCR cover "推薦４間冰店") stays a
        // multi-place list needing evidence instead of a bare source receipt.
        let analysisSourceType: SocialPlaceSourceType = sourceType == .sourceOnly && merged.isEmpty
            ? (understanding.sourceType == .multiPlaceList ? .multiPlaceList : .sourceOnly)
            : (sourceType == .ambiguous || sourceType == .unknown ? understanding.sourceType : sourceType)

        return SocialPlaceAgentAnalysis(
            sourceType: analysisSourceType,
            sourceSummary: sourceSummary(for: text, ocrLineCount: evidence.ocrLines.count, sourceType: analysisSourceType, topic: topic),
            topic: topic,
            regionClues: regionClues,
            groups: sourceGroups,
            placesFound: rankedMerged,
            sourceActors: uniqueActors(sourceActors),
            discardedCandidates: uniqueDiscarded(discarded),
            sourceIntent: intent,
            isPlaceBearing: isPlaceBearing,
            placeBearingReason: isPlaceBearing ? placeBearingReason(intent: intent, topic: topic, regionClues: regionClues) : nil,
            recoveryHints: recoveryHints(intent: intent, topic: topic, regionClues: regionClues, text: text),
            understanding: understanding,
            resolverDecision: resolverDecision,
            confidence: sourceConfidence(sourceType: analysisSourceType, groups: sourceGroups, candidates: rankedMerged),
            nextBestAction: rankedMerged.isEmpty
                ? isPlaceBearing
                    ? "Run source recovery search or add the exact place name/map link before saving as a Map Stamp."
                    : "Add one more clue: place name, screenshot, caption, or map link."
                : analysisSourceType == .multiPlaceList
                    ? "Review or enrich selected venue clues before saving Map Stamps."
                : "Open Review to confirm exact address and coordinates."
        )
    }

    static func canonicalPlaceName(_ value: String) -> String {
        SocialPlaceEvidenceScorer.cleanCandidateName(value)
            .replacingOccurrences(of: #"^\s*(?:\d{1,2}[\.)]|[①②③④⑤⑥⑦⑧⑨])\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(@[A-Za-z0-9._]{3,30}\)\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(the)\s+(?=(?:spectacular|sonoma|jw|marriott|ulaman|four|known|new)\b)"#, with: "$1 ", options: .regularExpression)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Candidate builders

    private func douyinFoodListCandidates(from text: String, sourceURL: String) -> [SocialPlaceCandidateDraft] {
        let segments = douyinListSegments(from: text, sourceURL: sourceURL)
        guard segments.count >= 2 else { return [] }
        let regions = regionClues(from: text)
        let primaryRegion = normalizedPrimaryRegion(from: regions)

        return segments.compactMap { segment in
            guard let name = douyinVenueName(from: segment.body) else { return nil }
            let category = category(from: "\(name)\n\(segment.body)\n\(text)")
            var atoms = [
                SocialEvidenceAtom(source: .numberedCaption, role: .venueName, value: name, line: segment.line, confidence: 0.7)
            ]
            if let primaryRegion {
                atoms.append(SocialEvidenceAtom(source: .captionSentence, role: .cityClue, value: primaryRegion, line: text, confidence: 0.5))
            }
            if segment.body.range(of: #"(?i)\bThai\s+Town\b"#, options: .regularExpression) != nil {
                atoms.append(SocialEvidenceAtom(source: .captionSentence, role: .cityClue, value: "Thai Town", line: segment.line, confidence: 0.58))
            }

            return draft(
                name: name,
                category: category,
                sourceURL: sourceURL,
                fullText: text,
                atoms: atoms,
                confidence: category == "food" ? 0.6 : 0.54,
                tier: .weakCandidate,
                extraMissingInfo: ["Douyin food-list candidate; confirm exact map listing"]
            )
        }
    }

    private func numberedCandidates(
        from lines: [String],
        sourceURL: String,
        fullText: String,
        handleContexts: [HandleContext]
    ) -> [SocialPlaceCandidateDraft] {
        var sections: [(line: String, details: [String])] = []
        var currentLine: String?
        var currentDetails: [String] = []

        for line in lines {
            if numberedName(from: line) != nil {
                if let currentLine {
                    sections.append((currentLine, currentDetails))
                }
                currentLine = line
                currentDetails = []
            } else if currentLine != nil {
                currentDetails.append(line)
            }
        }
        if let currentLine {
            sections.append((currentLine, currentDetails))
        }

        return sections.compactMap { section in
            guard let rawName = numberedName(from: section.line) else { return nil }
            let extracted = extractNameAndHandles(from: rawName)
            let name = SocialPlaceEvidenceScorer.cleanCandidateName(extracted.name)
            guard SocialPlaceEvidenceScorer.isUsableCandidateName(name) else { return nil }

            let detailsText = section.details.joined(separator: "\n")
            let location = firstLocationClue(in: detailsText)
            let bookingLinks = bookingLinks(in: detailsText)
            let category = category(from: "\(name)\n\(detailsText)")
            let tier = SocialPlaceEvidenceScorer.tier(hasAddress: location != nil)
            var atoms = [
                SocialEvidenceAtom(source: .numberedCaption, role: .venueName, value: name, line: section.line, confidence: 0.72)
            ]
            atoms.append(contentsOf: extracted.handles.map {
                SocialEvidenceAtom(source: .socialHandle, role: .venueHandle, value: $0, line: section.line, confidence: 0.64)
            })
            if let location {
                atoms.append(SocialEvidenceAtom(source: .locationPin, role: .cityClue, value: location, line: detailsText, confidence: 0.62))
            }
            atoms.append(contentsOf: bookingLinks.map {
                SocialEvidenceAtom(source: .bookingLink, role: .bookingLink, value: $0, line: detailsText, confidence: 0.58)
            })

            return draft(
                name: name,
                category: category,
                sourceURL: sourceURL,
                fullText: fullText,
                handles: extracted.handles,
                venueHandles: extracted.handles,
                locationClues: location.map { [$0] } ?? [],
                bookingLinks: bookingLinks,
                atoms: atoms,
                confidence: location == nil ? 0.56 : 0.66,
                tier: tier
            )
        }
    }

    private func bracketedCandidates(from text: String, sourceURL: String) -> [SocialPlaceCandidateDraft] {
        let patterns = [
            #"<\s*([A-Za-z0-9\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af][A-Za-z0-9 &'._\-\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]{1,80})\s*>"#,
            #"[《]\s*([^》\n\r]{2,80})\s*[》]"#,
            #"[\[【]\s*([^\]】]{2,80})\s*[\]】]"#,
            #"(?i)\b(?:at|spot|place)\s+([A-Z][A-Za-z0-9 &'._-]{2,60})\s*(?:[-–—|,]|\n)"#,
            #"(?i)\b(?:new\s+)?(?:brunch\s+)?(?:spot|place|restaurant|cafe)\s*:\s*([A-Z][A-Za-z0-9 &'._-]{2,60})\s*(?:[-–—|,]|\n|$)"#
        ]
        return patterns.compactMap { pattern in
            guard let name = firstCapture(in: text, pattern: pattern) else { return nil }
            let cleaned = SocialPlaceEvidenceScorer.cleanCandidateName(name)
            guard SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(cleaned) else { return nil }
            let location = firstLocationClue(in: text)
            let tier = SocialPlaceEvidenceScorer.tier(hasAddress: location != nil)
            return draft(
                name: cleaned,
                category: category(from: "\(cleaned)\n\(text)"),
                sourceURL: sourceURL,
                fullText: text,
                locationClues: location.map { [$0] } ?? [],
                atoms: [
                    SocialEvidenceAtom(source: .captionSentence, role: .venueName, value: cleaned, line: text, confidence: 0.6)
                ],
                confidence: location == nil ? 0.52 : 0.64,
                tier: tier
            )
        }
    }

    private func englishStayCandidates(from lines: [String], sourceURL: String, fullText: String) -> [SocialPlaceCandidateDraft] {
        lines.compactMap { line in
            if let match = englishThisIsStayMatch(in: line) {
                let name = SocialPlaceEvidenceScorer.cleanCandidateName(match.name)
                guard SocialPlaceEvidenceScorer.isUsableCandidateName(name), looksLikeStayVenue(name) else { return nil }
                let location = SocialPlaceEvidenceScorer.cleanText(match.area)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，"))
                return draft(
                    name: name,
                    category: "stay",
                    sourceURL: sourceURL,
                    fullText: fullText,
                    locationClues: location.isEmpty ? [] : [location],
                    atoms: [
                        SocialEvidenceAtom(source: .captionSentence, role: .venueName, value: name, line: line, confidence: 0.68),
                        SocialEvidenceAtom(source: .captionSentence, role: .cityClue, value: location, line: line, confidence: 0.56)
                    ],
                    confidence: 0.64,
                    tier: .weakCandidate
                )
            }

            if let name = firstCapture(in: line, pattern: #"(?i)\b(?:staying at|welcome to|check out)\s+([A-Z][A-Za-z0-9 &'._-]{2,80})(?:[.!?,\n\r]|$)"#) {
                let cleaned = SocialPlaceEvidenceScorer.cleanCandidateName(name)
                guard SocialPlaceEvidenceScorer.isUsableCandidateName(cleaned), looksLikeStayVenue(cleaned) else { return nil }
                let location = firstLocationClue(in: fullText)
                return draft(
                    name: cleaned,
                    category: "stay",
                    sourceURL: sourceURL,
                    fullText: fullText,
                    locationClues: location.map { [$0] } ?? [],
                    atoms: [
                        SocialEvidenceAtom(source: .captionSentence, role: .venueName, value: cleaned, line: line, confidence: 0.64)
                    ],
                    confidence: 0.58,
                    tier: SocialPlaceEvidenceScorer.tier(hasAddress: location != nil)
                )
            }
            return nil
        }
    }

    private func inferredAddressCandidates(from lines: [String], sourceURL: String, fullText: String) -> [SocialPlaceCandidateDraft] {
        guard lines.count >= 2 else { return [] }
        var result: [SocialPlaceCandidateDraft] = []
        for (index, line) in lines.enumerated() where SocialPlaceEvidenceScorer.looksLikeAddressLine(line) &&
            !SocialPlaceEvidenceScorer.looksLikeMarketingLine(line) &&
            !SocialPlaceEvidenceScorer.looksLikeMenuOrPriceLine(line) {
            let address = firstLocationClue(in: line) ?? cleanLocationMarker(from: line)
            guard strictAddressLike(address)
                    || firstStreetAddress(in: address) != nil
                    || looksLikeInternationalAddressLine(address) else { continue }
            let priorLines = Array(lines.prefix(index))
            let candidateLines = priorLines.reversed() + priorLines
            for priorLine in candidateLines {
                guard let name = candidateNameFromCaptionLine(priorLine) ?? standaloneVenueNameBeforeAddress(priorLine) else { continue }
                let bookingLinks = bookingLinks(in: fullText)
                var atoms = [
                    SocialEvidenceAtom(source: .captionSentence, role: .venueName, value: name, line: priorLine, confidence: 0.62),
                    SocialEvidenceAtom(source: .captionSentence, role: .address, value: address, line: line, confidence: 0.68)
                ]
                atoms.append(contentsOf: bookingLinks.map {
                    SocialEvidenceAtom(source: .bookingLink, role: .bookingLink, value: $0, line: fullText, confidence: 0.56)
                })
                result.append(
                    draft(
                        name: name,
                        category: category(from: "\(name)\n\(fullText)"),
                        sourceURL: sourceURL,
                        fullText: fullText,
                        locationClues: [address],
                        bookingLinks: bookingLinks,
                        atoms: atoms,
                        confidence: 0.68,
                        tier: .likely
                    )
                )
                break
            }
        }
        return result
    }

    private func standaloneVenueNameBeforeAddress(_ line: String) -> String? {
        let cleaned = SocialPlaceEvidenceScorer.cleanCandidateName(line)
        guard SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(cleaned),
              !SocialPlaceEvidenceScorer.looksLikeMenuOrPriceLine(cleaned),
              !SocialPlaceEvidenceScorer.looksLikeMarketingLine(cleaned),
              looksLikeStandaloneNameNearAddress(cleaned) else {
            return nil
        }
        return cleaned
    }

    private func looksLikeStandaloneNameNearAddress(_ value: String) -> Bool {
        guard value.count >= 2,
              value.count <= 40,
              value.range(of: #"[@#<>📍📌🚩🗺，,。！!？?；;：:]"#, options: .regularExpression) == nil,
              value.range(of: #"最強|最强|免費|免费|吃到飽|吃到饱|超浮誇|超浮夸|必吃|必喝|必訪|必访|推薦|推荐|隱身|隐藏|隱藏|份量|服務|服务|重頭戲|重头戏|銷魂|销魂|超好吃|打卡|排隊|排队"#, options: .regularExpression) == nil else {
            return false
        }
        if value.range(of: #"^[A-Za-z][A-Za-z0-9 &'._-]{1,50}(?:\s+[A-Za-z][A-Za-z0-9 &'._-]{1,50}){0,4}$"#, options: .regularExpression) != nil {
            return true
        }
        return value.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil &&
            value.range(of: #"(?:店|館|馆|亭|坊|堂|屋|家|本家|食堂|餐廳|餐厅|咖啡|茶館|茶馆|麵|面|鍋|锅|燒肉|烧肉|壽司|寿司|甜點|甜点|酒吧|Bar|Cafe|Kitchen|Bistro)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func addressOnlyCandidates(from lines: [String], sourceURL: String, fullText: String) -> [SocialPlaceCandidateDraft] {
        lines.compactMap { line in
            guard SocialPlaceEvidenceScorer.looksLikeAddressLine(line),
                  !SocialPlaceEvidenceScorer.looksLikeMarketingLine(line),
                  !SocialPlaceEvidenceScorer.looksLikeMenuOrPriceLine(line) else { return nil }
            let address = firstLocationClue(in: line) ?? cleanLocationMarker(from: line)
            guard !address.isEmpty else { return nil }
            return draft(
                name: "Address-only place clue",
                category: category(from: "\(address)\n\(fullText)"),
                sourceURL: sourceURL,
                fullText: fullText,
                locationClues: [address],
                atoms: [
                    SocialEvidenceAtom(source: .captionSentence, role: .address, value: address, line: line, confidence: 0.7)
                ],
                confidence: 0.5,
                tier: .weakCandidate,
                extraMissingInfo: ["Address-only clue; enrich with Google Places before saving"]
            )
        }
    }

    private func chineseVenueCandidates(from text: String, sourceURL: String) -> [SocialPlaceCandidateDraft] {
        var names: [String] = []
        if let quoted = quotedVenueName(in: text) {
            names.append(quoted)
        }
        for line in text.components(separatedBy: .newlines) {
            if let launchHeadline = launchHeadlineVenueName(in: line) {
                names.append(launchHeadline)
            }
        }
        if let composed = composedChineseVenueName(in: text) {
            names.append(composed)
        }

        let location = firstLocationClue(in: text)
        return names.compactMap { name in
            guard SocialPlaceEvidenceScorer.isUsableCandidateName(name) else { return nil }
            return draft(
                name: name,
                category: category(from: "\(name)\n\(text)"),
                sourceURL: sourceURL,
                fullText: text,
                locationClues: location.map { [$0] } ?? [],
                atoms: [
                    SocialEvidenceAtom(source: .captionSentence, role: .venueName, value: name, line: text, confidence: 0.66)
                ],
                confidence: location == nil ? 0.58 : 0.68,
                tier: SocialPlaceEvidenceScorer.tier(hasAddress: location != nil)
            )
        }
    }

    private func instagramMetadataTitleCandidates(from lines: [String], sourceURL: String, fullText: String) -> [SocialPlaceCandidateDraft] {
        lines.compactMap { line in
            guard let name = firstCapture(in: line, pattern: #"(?i)^(.{2,80})\s+on\s+Instagram\s*:"#) else {
                return nil
            }
            let cleaned = SocialPlaceEvidenceScorer.cleanCandidateName(name)
            guard SocialPlaceEvidenceScorer.isUsableCandidateName(cleaned),
                  looksLikeVenueTitle(cleaned),
                  !looksLikeInstagramCreatorTitle(cleaned) else {
                return nil
            }
            let location = firstLocationClue(in: fullText)
            return draft(
                name: cleaned,
                category: category(from: "\(cleaned)\n\(fullText)"),
                sourceURL: sourceURL,
                fullText: fullText,
                locationClues: location.map { [$0] } ?? [],
                atoms: [
                    SocialEvidenceAtom(source: .metadataTitle, role: .venueName, value: cleaned, line: line, confidence: 0.62)
                ],
                confidence: location == nil ? 0.54 : 0.66,
                tier: SocialPlaceEvidenceScorer.tier(hasAddress: location != nil),
                extraMissingInfo: ["Instagram metadata title; verify exact venue and address"]
            )
        }
    }

    private func handleOnlyCandidates(
        from contexts: [HandleContext],
        sourceURL: String,
        fullText: String,
        creatorHandles: Set<String>
    ) -> [SocialPlaceCandidateDraft] {
        contexts.compactMap { context in
            guard (context.role == .venueHandle || sourceAccountCanBecomeCandidate(context, sourceURL: sourceURL)),
                  !creatorHandles.contains(context.handle) else { return nil }
            let resolved = context.role == .venueHandle && looksLikeSocialPlaceList(fullText)
                ? (
                    name: SocialPlaceEvidenceScorer.displayName(fromSocialHandle: context.handle),
                    evidence: Optional<String>.none,
                    confidenceBoost: 0.0
                )
                : SocialPlaceEvidenceScorer.resolvedDisplayName(fromSocialHandle: context.handle, evidenceText: fullText)
            guard context.role == .venueHandle || resolved.evidence != nil else { return nil }
            let name = resolved.name
            guard SocialPlaceEvidenceScorer.isUsableCandidateName(name) else { return nil }
            let location = firstLocationClue(in: fullText)
            let tier = SocialPlaceEvidenceScorer.tier(hasAddress: location != nil, isResolvedHandle: resolved.evidence != nil)
            var atoms = [
                SocialEvidenceAtom(source: .socialHandle, role: .venueHandle, value: context.handle, line: context.line, confidence: 0.56)
            ]
            if let profileEvidence = resolved.evidence {
                atoms.append(SocialEvidenceAtom(source: .socialHandle, role: .venueName, value: name, line: profileEvidence, confidence: 0.62))
            }
            if let location {
                atoms.append(SocialEvidenceAtom(source: .captionSentence, role: .cityClue, value: location, line: fullText, confidence: 0.48))
            }
            return draft(
                name: name,
                category: category(from: "\(context.line)\n\(fullText)"),
                sourceURL: sourceURL,
                fullText: fullText,
                handles: [context.handle],
                venueHandles: [context.handle],
                locationClues: location.map { [$0] } ?? [],
                atoms: atoms,
                confidence: min(0.52 + resolved.confidenceBoost, 0.72),
                tier: tier
            )
        }
    }

    private func sourceAccountCanBecomeCandidate(_ context: HandleContext, sourceURL: String) -> Bool {
        let host = URL(string: sourceURL)?.host?.lowercased()
        let isInstagramHost = host == "instagram.com" || (host?.hasSuffix(".instagram.com") == true)
        guard context.role == .sourceAccount,
              let url = URL(string: sourceURL),
              isInstagramHost else {
            return false
        }
        let components = url.pathComponents
            .filter { $0 != "/" }
            .map { $0.lowercased() }
        return components.count == 1 && components.first == context.handle.lowercased()
    }

    private func ocrCandidates(from ocrLines: [String], sourceURL: String, fullText: String) -> [SocialPlaceCandidateDraft] {
        guard let result = SocialOCRCandidateHeuristics.candidate(from: ocrLines) else { return [] }
        let ocrText = ocrLines.joined(separator: "\n")
        return [
            draft(
                name: result.name,
                category: category(from: "\(result.name)\n\(fullText)\n\(ocrText)"),
                sourceURL: sourceURL,
                fullText: fullText,
                atoms: [
                    SocialEvidenceAtom(source: .ocr, role: .venueName, value: result.name, line: ocrText, confidence: result.confidence)
                ],
                confidence: result.confidence,
                tier: .weakCandidate,
                extraMissingInfo: ["OCR-derived candidate; verify venue identity"]
            )
        ]
    }

    // MARK: - Draft assembly

    private func strictAddressLike(_ value: String) -> Bool {
        value.rangeOfCharacter(from: .decimalDigits) != nil &&
            value.range(of: #"[縣市區路街巷弄號]"#, options: .regularExpression) != nil
    }

    /// International (non-CJK, non-US-street) address line: a 5-digit postal code
    /// after a capitalized locality, or a recognizable SEA street/district token
    /// ("Alley", "Soi", "Khlong", "Watthana", "Bangkok", "Thanon"). Lets
    /// Thai-script + Latin pin addresses like
    /// "295 …, Ekkamai 15 Alley, …, Bangkok 10110泰國" pair with a venue.
    private func looksLikeInternationalAddressLine(_ value: String) -> Bool {
        value.range(of: #"\b[A-Z][A-Za-z .'-]{2,40}\s+\d{5}\b"#, options: .regularExpression) != nil ||
            value.range(of: #"(?i)\b(?:Alley|Soi|Khlong|Watthana|Bangkok|Thanon)\b"#, options: .regularExpression) != nil
    }

    private func orderedLocationClues(_ values: [String]) -> [String] {
        uniqueStrings(values).sorted { lhs, rhs in
            let lhsStrict = strictAddressLike(lhs)
            let rhsStrict = strictAddressLike(rhs)
            if lhsStrict != rhsStrict { return lhsStrict && !rhsStrict }
            return false
        }
    }

    private func highlightAtoms(from fullText: String, excluding name: String) -> [SocialEvidenceAtom] {
        let lines = fullText
            .components(separatedBy: .newlines)
            .map(SocialPlaceEvidenceScorer.cleanText)
            .filter { !$0.isEmpty }

        let itemPattern = #"^[*•\-]?\s*([^$＄\n]{2,24})\s*[$＄]\s*\d+"#
        let featureKeywords = [
            "深夜", "咖啡廳", "小餐館", "份量", "大推", "好吃", "舒適", "暖色", "開放式廚房",
            "推薦", "必點", "招牌", "步行", "捷運", "環境", "氛圍", "甜點", "海鮮"
        ]

        var atoms: [SocialEvidenceAtom] = []
        for line in lines {
            if line.contains(name) || line.hasPrefix("#") || SocialPlaceEvidenceScorer.looksLikeAddressLine(line) {
                continue
            }

            if let match = line.range(of: itemPattern, options: .regularExpression) {
                let matched = String(line[match])
                    .replacingOccurrences(of: #"^[*•\-]\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !matched.isEmpty {
                    atoms.append(SocialEvidenceAtom(source: .captionSentence, role: .placeHighlight, value: "Recommended item: \(matched)", line: line, confidence: 0.52))
                }
                continue
            }

            let hasFeature = featureKeywords.contains { line.localizedCaseInsensitiveContains($0) }
            if hasFeature, line.count <= 90, !SocialPlaceEvidenceScorer.looksLikeMenuOrPriceLine(line) {
                atoms.append(SocialEvidenceAtom(source: .captionSentence, role: .placeHighlight, value: line, line: line, confidence: 0.42))
            }
        }
        return Array(appendUniqueAtoms(atoms).prefix(8))
    }

    private func draft(
        name: String,
        category: String,
        sourceURL: String,
        fullText: String,
        handles: [String] = [],
        creatorHandles: [String] = [],
        venueHandles: [String] = [],
        locationClues: [String] = [],
        bookingLinks: [String] = [],
        atoms: [SocialEvidenceAtom],
        confidence: Double,
        tier: SocialPlaceEvidenceTier,
        extraMissingInfo: [String] = []
    ) -> SocialPlaceCandidateDraft {
        let displayName = cleanDisplayName(name)
        let hasAddress = !locationClues.isEmpty
        let sourceAtom = SocialEvidenceAtom(source: .metadataDescription, role: .sourceAccount, value: sourceURL, line: sourceURL, confidence: 0.2)
        let tierAtom = SocialEvidenceAtom(source: .metadataDescription, role: .categoryClue, value: "Evidence tier: \(tier.rawValue)", line: fullText, confidence: 0.2)
        let highlightAtoms = highlightAtoms(from: fullText, excluding: displayName)
        let allAtoms = appendUniqueAtoms(atoms + highlightAtoms + [sourceAtom, tierAtom])
        let missing = SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: hasAddress) + extraMissingInfo

        return SocialPlaceCandidateDraft(
            canonicalName: Self.canonicalPlaceName(displayName),
            displayName: displayName,
            category: category,
            handles: uniqueStrings(handles),
            creatorHandles: uniqueStrings(creatorHandles),
            venueHandles: uniqueStrings(venueHandles),
            locationClues: orderedLocationClues(locationClues),
            bookingLinks: uniqueStrings(bookingLinks),
            evidence: allAtoms,
            confidence: confidence,
            missingInfo: uniqueStrings(missing).sorted()
        )
    }

    private func mergeCandidates(_ candidates: [SocialPlaceCandidateDraft]) -> [SocialPlaceCandidateDraft] {
        var orderedKeys: [String] = []
        var merged: [String: SocialPlaceCandidateDraft] = [:]

        for candidate in candidates where !candidate.canonicalName.isEmpty {
            let key = candidate.canonicalName

            if var existing = merged[key] {
                existing.handles = uniqueStrings(existing.handles + candidate.handles)
                existing.creatorHandles = uniqueStrings(existing.creatorHandles + candidate.creatorHandles)
                existing.venueHandles = uniqueStrings(existing.venueHandles + candidate.venueHandles)
                existing.locationClues = orderedLocationClues(existing.locationClues + candidate.locationClues)
                existing.bookingLinks = uniqueStrings(existing.bookingLinks + candidate.bookingLinks)
                existing.evidence = appendUniqueAtoms(existing.evidence + candidate.evidence)
                existing.confidence = max(existing.confidence, candidate.confidence)
                existing.missingInfo = uniqueStrings(existing.missingInfo + candidate.missingInfo).sorted()
                merged[key] = existing
            } else if let richerKey = orderedKeys.first(where: { existingKey in
                existingKey.count > key.count &&
                    existingKey.contains(key) &&
                    merged[existingKey]?.locationClues.isEmpty == false
            }), var existing = merged[richerKey] {
                existing.handles = uniqueStrings(existing.handles + candidate.handles)
                existing.creatorHandles = uniqueStrings(existing.creatorHandles + candidate.creatorHandles)
                existing.venueHandles = uniqueStrings(existing.venueHandles + candidate.venueHandles)
                existing.bookingLinks = uniqueStrings(existing.bookingLinks + candidate.bookingLinks)
                existing.evidence = appendUniqueAtoms(existing.evidence + candidate.evidence)
                existing.confidence = max(existing.confidence, candidate.confidence)
                existing.missingInfo = uniqueStrings(existing.missingInfo + candidate.missingInfo).sorted()
                merged[richerKey] = existing
            } else {
                orderedKeys.append(key)
                merged[key] = candidate
            }
        }
        return orderedKeys.compactMap { merged[$0] }
    }

    private func prioritizeParsedCandidates(_ candidates: [SocialPlaceCandidateDraft]) -> [SocialPlaceCandidateDraft] {
        let namedCandidates = candidates.filter { $0.displayName != "Address-only place clue" }
        let addressOnlyCandidates = candidates.filter { $0.displayName == "Address-only place clue" }
        if namedCandidates.count == 1, addressOnlyCandidates.count == 1, var named = namedCandidates.first, let addressOnly = addressOnlyCandidates.first {
            let addressClues = addressOnly.locationClues.filter(strictAddressLike)
            if !addressClues.isEmpty {
                named.locationClues = orderedLocationClues(addressClues + named.locationClues)
                named.evidence = appendUniqueAtoms(named.evidence + addressOnly.evidence)
                named.confidence = max(named.confidence, 0.68)
                named.missingInfo = uniqueStrings(named.missingInfo + addressOnly.missingInfo)
                    .filter { $0 != "Address-only clue; enrich with Google Places before saving" }
                    .sorted()
                return [named]
            }
        }
        return namedCandidates + addressOnlyCandidates
    }

    // MARK: - Handles

    private struct HandleContext {
        var handle: String
        var line: String
        var role: SocialEvidenceRole
        var reason: String
    }

    private func handleContexts(in lines: [String], fullText: String) -> [HandleContext] {
        lines.flatMap { line in
            handles(in: line).map { handle in
                let role = classify(handle: handle, line: line, fullText: fullText)
                return HandleContext(handle: handle, line: line, role: role.role, reason: role.reason)
            }
        }
    }

    private func classify(handle: String, line: String, fullText: String) -> (role: SocialEvidenceRole, reason: String) {
        let lowered = line.lowercased()
        let escaped = NSRegularExpression.escapedPattern(for: handle)
        let followPattern = #"(?i)\b(?:please\s+)?follow\s+@"# + escaped + #"\b"#
        if looksLikeInstagramOwnerLine(line) {
            return (.sourceAccount, "Handle appears in Instagram profile/source metadata; keep as provenance unless the shared URL is that profile.")
        }
        if line.range(of: followPattern, options: .regularExpression) != nil ||
            lowered.range(of: #"\b(?:creator|travel tips|hidden gems|guide|by|via)\b"#, options: .regularExpression) != nil && !looksVenueContext(line) {
            return (.creatorHandle, "Appears near creator/follow language; not near a venue line.")
        }
        if numberedName(from: line) != nil ||
            line.range(of: #"(?i)\b(?:staying at|located at|located in|known for|offers?|experience|encounters?|sanctuary|tours?|wildlife|animal|book|reserve|hotel|resort|restaurant|cafe|airbnb|villa|treehouse)\b"#, options: .regularExpression) != nil {
            return (.venueHandle, "Appears inside a venue/stay/place line.")
        }
        if looksLikeSocialPlaceList(fullText), handles(in: line).count > 0 {
            return (.venueHandle, "Appears in a social place-list caption; keep as venue handle evidence pending enrichment.")
        }
        return (.sourceAccount, "Handle kept as provenance; not enough evidence to make it a place.")
    }

    private func looksLikeInstagramOwnerLine(_ line: String) -> Bool {
        line.range(of: #"(?i)\b(?:on\s+Instagram|Instagram\s+reel|Instagram\s+photos\s+and\s+videos)\b"#, options: .regularExpression) != nil ||
            line.range(of: #"\([^\n\r]{0,80}@[A-Za-z0-9._]{3,30}\)[^\n\r]{0,80}(?:Instagram|reel)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func looksLikeSocialPlaceList(_ text: String) -> Bool {
        text.range(
            of: #"(?i)\b(?:coffee\s+shops?|restaurants?|cafes?|bars?|bakeries|dessert\s+shops?|places?|spots?)\b[^\n\r]{0,80}\b(?:county|city|la|los angeles|oc|orange county|tokyo|taipei|seoul|paris|london|new york|returning to|favorite|favourite|best)\b"#,
            options: .regularExpression
        ) != nil ||
        text.range(
            of: #"(?i)\b(?:best for|worth it|atmosphere|aesthetic|coffee quality|unique coffee experiences|go to first)\b"#,
            options: .regularExpression
        ) != nil
    }

    private func handles(in text: String) -> [String] {
        let ignored: Set<String> = ["instagram", "reels", "reel", "explore", "threads", "tiktok", "xiaohongshu", "save", "media"]
        guard let regex = try? NSRegularExpression(pattern: #"@([A-Za-z0-9._]{3,30})"#) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let handleRange = Range(match.range(at: 1), in: text) else { return nil }
            let handle = String(text[handleRange]).lowercased()
            guard !ignored.contains(handle),
                  !handle.contains("instagram"),
                  handle.range(of: #"\d{5,}"#, options: .regularExpression) == nil else {
                return nil
            }
            return handle
        }
    }

    // MARK: - Extraction helpers

    private func numberedName(from line: String) -> String? {
        firstCapture(in: line, pattern: #"^\s*(?:\d{1,2}[\.)]|[①②③④⑤⑥⑦⑧⑨])\s*([^\n\r]+)"#)
    }

    private func douyinListSegments(from text: String, sourceURL: String) -> [(line: String, body: String)] {
        guard looksLikeDouyinFoodList(text: text, sourceURL: sourceURL),
              let regex = try? NSRegularExpression(
                pattern: #"(?i)\bP\d{1,2}(?:\s*[-–—]\s*P?\d{1,2})?\s+(.+?)(?=\s+\bP\d{1,2}(?:\s*[-–—]\s*P?\d{1,2})?\s+|#[^\s#]+|$)"#,
                options: [.dotMatchesLineSeparators]
              ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let fullRange = Range(match.range(at: 0), in: text),
                  let bodyRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            let line = SocialPlaceEvidenceScorer.cleanText(String(text[fullRange]))
            let body = SocialPlaceEvidenceScorer.cleanText(String(text[bodyRange]))
            guard !body.isEmpty else { return nil }
            return (line, body)
        }
    }

    private func looksLikeDouyinFoodList(text: String, sourceURL: String) -> Bool {
        let loweredURL = sourceURL.lowercased()
        let hasDouyinSource = loweredURL.contains("douyin.com") || loweredURL.contains("iesdouyin.com") || text.contains("抖音")
        let pRangeCount = matches(in: text, pattern: #"(?i)\bP\d{1,2}(?:\s*[-–—]\s*P?\d{1,2})?\s+"#).count
        let textHasDouyinURL = text.range(of: #"(?i)https?://(?:www\.)?(?:v\.)?(?:ies)?douyin\.com/\S*"#, options: .regularExpression) != nil
        return pRangeCount >= 2 && (hasDouyinSource || textHasDouyinURL)
    }

    private func looksLikeDouyinAggregateFoodList(text: String, sourceURL: String) -> Bool {
        let loweredURL = sourceURL.lowercased()
        let hasDouyinSource = loweredURL.contains("douyin.com") ||
            loweredURL.contains("iesdouyin.com") ||
            text.contains("抖音") ||
            text.range(of: #"(?i)https?://(?:www\.)?(?:v\.)?(?:ies)?douyin\.com/\S*"#, options: .regularExpression) != nil
        guard hasDouyinSource else { return false }
        return text.range(
            of: #"(?:从|從)?\s*(?:\d{1,2}|[０-９]{1,2}|[一二三四五六七八九十]{1,3})\s*\+?\s*(?:間|家|個)?\s*(?:冰店|冰品|剉冰|刨冰|甜點|甜品|咖啡|咖啡廳|餐廳|餐厅|小吃|美食|店)"#,
            options: .regularExpression
        ) != nil
    }

    private func douyinVenueName(from body: String) -> String? {
        var value = body
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(?:泰国菜|泰國菜|马来西亚菜|馬來西亞菜)[，,、\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:可颂很好吃|巧克力.*|推荐.*|推薦.*|已经.*|已經.*|在\s+Thai\s+town.*)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.,，。:：;；!！"))

        if let latinLead = firstCapture(in: value, pattern: #"^([A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ0-9 &'._-]{1,60})(?=\s+[\u4e00-\u9fff]|$)"#) {
            value = latinLead
        }
        if let mixedKopitiam = firstCapture(in: body, pattern: #"(?i)\b(Ipoh\s+Kopitiam\s+怡保茶餐[厅廳])\b"#) {
            value = mixedKopitiam
        }

        value = normalizeDouyinVenueName(value)
        guard SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(value) else { return nil }
        return value
    }

    private func normalizeDouyinVenueName(_ value: String) -> String {
        let cleaned = cleanDisplayName(value)
        let canonical = Self.canonicalPlaceName(cleaned)
        switch canonical {
        case "brothers and cousins taco", "brothers and cousins tacos":
            return "Brothers and Cousins Tacos"
        default:
            return cleaned
        }
    }

    private func extractNameAndHandles(from value: String) -> (name: String, handles: [String]) {
        let handles = handles(in: value)
        let name = value
            .replacingOccurrences(of: #"\s*\(@[A-Za-z0-9._]{3,30}\)\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"@[A-Za-z0-9._]{3,30}"#, with: " ", options: .regularExpression)
        return (name, handles)
    }

    private func cleanDisplayName(_ value: String) -> String {
        SocialPlaceEvidenceScorer.cleanCandidateName(value)
            .replacingOccurrences(of: #"^\s*(?:\d{1,2}[\.)]|[①②③④⑤⑥⑦⑧⑨])\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(@[A-Za-z0-9._]{3,30}\)\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+@[A-Za-z0-9._]{3,30}\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!。！"))
    }

    private func firstLocationClue(in text: String) -> String? {
        if let streetAddress = firstStreetAddress(in: text) {
            return streetAddress
                .replacingOccurrences(of: #"(?i)\s+(?:if\s+you|to\s+check|for\s+more).*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，"))
        }

        let explicitLocationPatterns = [
            #"[📍👣📮]\s*(?:地點|地点|地址|Location|Address)?\s*[:：]?\s*([^\n\r\.]+)"#,
            #"(?:^|\b)(?:Location|Address|地點|地点|地址)\s*[:：]\s*([^\n\r\.]+)"#,
            #"(?i)\b(?:located|based)\s+in\s+([A-Z][A-Za-z .'-]{2,40})(?:[.!?,\n\r]|$)"#,
            #"\b([A-Z][A-Za-z .'-]{2,40},\s*(?:CA|NY|TX|FL|WA|IL|NV|AZ|OR|MA|HI|UT|CO|Bali|Indonesia|Chongqing|China|California))\b"#
        ]
        for pattern in explicitLocationPatterns {
            guard let value = firstCapture(in: text, pattern: pattern) else { continue }
            let cleaned = SocialPlaceEvidenceScorer.cleanText(value)
                // Strip a dangling caption separator / closing quote left when an
                // inline 📍 address is the caption's last clause (e.g.
                // "…Bangkok 10110泰國 -\"").
                .replacingOccurrences(of: #"\s*[-–—]\s*["“”']?\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，:：\"“”'"))
            if !cleaned.isEmpty { return cleaned }
        }

        let addressLine = text
            .components(separatedBy: .newlines)
            .map(SocialPlaceEvidenceScorer.cleanText)
            .first { line in
                SocialPlaceEvidenceScorer.looksLikeAddressLine(line) &&
                    !SocialPlaceEvidenceScorer.looksLikeMarketingLine(line) &&
                    !SocialPlaceEvidenceScorer.looksLikeMenuOrPriceLine(line)
            }
        if let addressLine { return cleanLocationMarker(from: addressLine) }

        return nil
    }

    private func cleanLocationMarker(from value: String) -> String {
        let cleaned = SocialPlaceEvidenceScorer.cleanText(value)
            .replacingOccurrences(of: #"^[📍🗺👣🚩📮]\s*(?:地點|地点|地址|Location|Address)?\s*[:：]?\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*(?:located\s+at|located|address|location|地點|地点|地址)\s*[:：]?\s*[📍🗺📮]?\s*"#, with: "", options: .regularExpression)
        if let streetAddress = firstStreetAddress(in: cleaned) {
            return streetAddress
                .replacingOccurrences(of: #"(?i)\s+(?:if\s+you|to\s+check|for\s+more).*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，"))
        }
        // Strip trailing caption sentence artifacts (a dangling caption
        // separator / closing quote left when an inline 📍 address is the last
        // clause, e.g. "…Bangkok 10110泰國 -\"").
        return cleaned
            .replacingOccurrences(of: #"\s*[-–—]\s*["“”']?\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r。!！?？,，\"“”'"))
    }

    private func englishThisIsStayMatch(in line: String) -> (name: String, area: String)? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\bThis is(?: the)?\s+(.{2,80}?)\s+(?:in|near)\s+(?:the\s+)?([A-Z][A-Za-z .'-]{2,80})(?:[.!?\n\r]|$)"#
        ) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges > 2,
              let nameRange = Range(match.range(at: 1), in: line),
              let areaRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return (String(line[nameRange]), String(line[areaRange]))
    }

    private func looksLikeStayVenue(_ value: String) -> Bool {
        value.range(of: #"(?i)\b(hotel|resort|marriott|hyatt|hilton|villa|cabin|treehouse|spa|lodge|inn|airbnb|glamping|retreat|spyglass|ulaman)\b"#, options: .regularExpression) != nil
    }

    private func looksLikeVenueTitle(_ value: String) -> Bool {
        value.range(of: #"(?i)\b(restaurant|cafe|coffee|bar|bakery|bistro|kitchen|grill|pizzeria|taqueria|sushi|ramen|hotel|resort|inn|villa|district|market|mall|museum|gallery|park|beach|garden|paseo|dining|pottery|ceramics?|studio|workshops?|classes?|lessons?|experience|atelier)\b"#, options: .regularExpression) != nil
    }

    private func looksLikeInstagramCreatorTitle(_ value: String) -> Bool {
        let cityCount = ["台北", "臺北", "新北", "台中", "臺中", "台南", "臺南", "高雄", "全台", "Taipei", "Taichung", "Tainan", "Kaohsiung"]
            .filter { value.localizedCaseInsensitiveContains($0) }
            .count
        return cityCount >= 2 ||
            value.range(of: #"(?i)(食記|美食|foodie|food blogger|travel guide|全台)"#, options: .regularExpression) != nil
    }

    private func looksVenueContext(_ line: String) -> Bool {
        line.range(of: #"(?i)\b(staying at|located at|located in|known for|book|reserve|hotel|resort|restaurant|cafe|airbnb|villa|treehouse|spot|place)\b"#, options: .regularExpression) != nil
    }

    private func bookingLinks(in text: String) -> [String] {
        let patterns: [(pattern: String, captureIndex: Int)] = [
            (#"\b((?:https?://)?(?:www\.)?(?:airbnb|booking|resy|opentable|inline|tablecheck)\.[^\s]+)"#, 1),
            (#"(?i)\b(?:for\s+bookings?|bookings?|book|reserve|reservations?|appointments?)\b[\s\S]{0,80}?\b((?:https?://)?(?:www\.)?[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?:/[^\s]*)?)"#, 1)
        ]

        let links = patterns.flatMap { spec -> [String] in
            guard let regex = try? NSRegularExpression(pattern: spec.pattern, options: [.caseInsensitive]) else { return [] }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                guard match.numberOfRanges > spec.captureIndex,
                      let range = Range(match.range(at: spec.captureIndex), in: text) else { return nil }
                return String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，\"'”’"))
            }
        }
        return uniqueStrings(links)
    }

    private func firstStreetAddress(in text: String) -> String? {
        firstCapture(
            in: text,
            pattern: #"\b(\d{1,6}\s+Via\s+[A-Za-z0-9 .'-]{2,80}(?:,\s*[A-Za-z .'-]{2,40})?(?:,\s*(?:CA|NY|TX|FL|WA|IL|NV|AZ|OR|MA|HI|UT|CO))?(?:\s+\d{5}(?:-\d{4})?)?|\d{1,6}\s+[A-Za-z0-9 .'-]{2,80}\b(?:Street|St\.?|Road|Rd\.?|Avenue|Ave\.?|Boulevard|Blvd\.?|Lane|Ln\.?|Drive|Dr\.?|Way|Highway|Hwy\.?|Coast Hwy|Place|Pl\.?|Court|Ct\.?|Old Street)(?:\s*\([^\n\r)]{2,40}\))?(?:,?\s*[A-Za-z0-9 .'-]{2,60}){0,2}(?:,?\s*(?:CA|NY|TX|FL|WA|IL|NV|AZ|OR|MA|HI|UT|CO))?(?:\s+\d{5}(?:-\d{4})?)?)\b"#
        )
    }

    private func candidateNameFromCaptionLine(_ line: String) -> String? {
        if !SocialPlaceEvidenceScorer.looksLikeAddressLine(line),
           let pinnedName = firstCapture(in: line, pattern: #"📍\s*([^@\n\r]{2,80})(?:\s+@[A-Za-z0-9._]{3,30})?"#) {
            let cleaned = cleanDisplayName(pinnedName)
            if (line.contains("@") || looksLikeVenueTitle(cleaned)),
               SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(cleaned) {
                return cleaned
            }
        }

        if !SocialPlaceEvidenceScorer.looksLikeAddressLine(line),
           let arrowName = firstCapture(in: line, pattern: #"^\s*[👉➡→➜📌🏻🏼🏽🏾🏿️]+\s*([^\n\r]{2,80})"#) {
            let cleaned = cleanDisplayName(arrowName)
            if SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(cleaned),
               !SocialPlaceEvidenceScorer.looksLikeOperatingHoursLine(cleaned),
               !SocialPlaceEvidenceScorer.looksLikeMenuOrPriceLine(cleaned),
               looksLikeStandaloneMarkedVenueName(cleaned) {
                return cleaned
            }
        }

        if let quotedHeadlineVenue = headlineQuotedVenueName(in: line) {
            return quotedHeadlineVenue
        }

        if let launchHeadlineName = launchHeadlineVenueName(in: line) {
            return launchHeadlineName
        }

        if let leadingName = firstCapture(in: line, pattern: #"^([^/\n]{2,60})\s*/"#) {
            let cleaned = SocialPlaceEvidenceScorer.cleanCandidateName(leadingName)
            if SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(cleaned) {
                return cleaned
            }
        }

        if let numbered = numberedName(from: line) {
            let extracted = extractNameAndHandles(from: numbered)
            let cleaned = cleanDisplayName(extracted.name)
            if SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(cleaned) {
                return cleaned
            }
        }

        if line.range(of: #"主打|形式|course|コース|menu|price|餐點|價位"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let markedName = venueNameFromMarkedCaptionLine(trimmedLine) {
            return markedName
        }
        if let cjkSeparated = cjkSeparatedVenueName(in: line) {
            return cjkSeparated
        }
        if let quoted = quotedVenueName(in: line) {
            return quoted
        }
        return nil
    }

    private func venueNameFromMarkedCaptionLine(_ trimmedLine: String) -> String? {
        guard !trimmedLine.isEmpty,
              !SocialPlaceEvidenceScorer.looksLikeTransitAccessLine(trimmedLine),
              !SocialPlaceEvidenceScorer.looksLikeOperatingHoursLine(trimmedLine),
              !SocialPlaceEvidenceScorer.looksLikeReviewMetricLine(trimmedLine),
              !SocialPlaceEvidenceScorer.looksLikeMenuOrPriceLine(trimmedLine) else { return nil }
        let firstScalar = trimmedLine.unicodeScalars.first?.value
        if firstScalar == 0x1F687 || firstScalar == 0x1F68C || firstScalar == 0x1F68E ||
            trimmedLine.range(of: #"公告|捷運|地鐵|地铁|metro|subway|station|出口"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }
        let startsWithKnownMarker = firstScalar == 0x1F449 ||
            firstScalar == 0x27A1 ||
            firstScalar == 0x2192 ||
            firstScalar == 0x279C ||
            firstScalar == 0x1F4CC ||
            firstScalar == 0x1F4CD ||
            firstScalar == 0x1F6A9 ||
            firstScalar == 0x1F3E0 ||
            firstScalar == 0x1F3E1 ||
            trimmedLine.hasPrefix("店名")
        let startsWithGenericSymbolMarker = firstScalar.map { $0 >= 0x2000 } ?? false
        guard startsWithKnownMarker || startsWithGenericSymbolMarker else { return nil }

        let markerStripped = trimmedLine
            .replacingOccurrences(
                of: #"^\s*(?:[^A-Za-z0-9\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af@#]+\s*)*(?:店名|店家|餐廳|餐厅|venue|restaurant)?\s*[:：\-–—]?\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"^[^A-Za-z\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]+"#,
                with: "",
                options: .regularExpression
            )
        guard markerStripped != trimmedLine else { return nil }

        let cleaned = cleanDisplayName(markerStripped)
        guard SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(cleaned),
              looksLikeStandaloneMarkedVenueName(cleaned) else { return nil }
        return cleaned
    }

    private func looksLikeStandaloneMarkedVenueName(_ value: String) -> Bool {
        guard value.count <= 32 else { return false }
        if value.range(of: #"[，,。！!？?；;]"#, options: .regularExpression) != nil {
            return false
        }
        if value.range(of: #"最強|最强|免費|免费|吃到飽|吃到饱|超浮誇|超浮夸|必吃|必喝|必訪|必访|推薦|推荐|隱藏版|隐藏版|打卡|排隊|排队"#, options: .regularExpression) != nil {
            return false
        }
        if value.range(of: #"(?i)\b(?:must\s+try|hidden\s+gem|save\s+this|best\s+of|things\s+to)\b"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private func launchHeadlineVenueName(in line: String) -> String? {
        guard line.range(of: #"開幕|插旗|登台|正式|即將|即将|新店"#, options: .regularExpression) != nil else {
            return nil
        }
        let patterns = [
            #"([A-Z][A-Za-z0-9 &'._-]{2,60})\s+\d{1,2}/\d{1,2}"#,
            #"(?:法式吐司|咖啡|餐廳|餐厅|麵包|面包|甜點|甜点|品牌)\s+([A-Z][A-Za-z0-9 &'._-]{2,60})(?:\s|$)"#,
            #"([A-Z][A-Za-z0-9 &'._-]{2,60})\s*(?:即將|即将|正式|開幕|插旗|登台)"#
        ]
        for pattern in patterns {
            guard let raw = firstCapture(in: line, pattern: pattern) else { continue }
            let cleaned = SocialPlaceEvidenceScorer.cleanCandidateName(raw)
                .replacingOccurrences(of: #"\s+\d{1,2}$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，"))
            guard SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(cleaned),
                  !SocialPlaceEvidenceScorer.looksLikeMarketingLine(cleaned) else { continue }
            return cleaned
        }
        return nil
    }

    private func cjkSeparatedVenueName(in line: String) -> String? {
        guard line.range(of: #"[·・‧]"#, options: .regularExpression) != nil,
              line.range(of: #"[\u4e00-\u9fff]"#, options: .regularExpression) != nil else {
            return nil
        }
        let cleaned = SocialPlaceEvidenceScorer.cleanCandidateName(line)
        guard SocialPlaceEvidenceScorer.isLikelyCaptionPlaceName(cleaned),
              !SocialPlaceEvidenceScorer.looksLikeGenericProductOrCityLine(cleaned),
              !SocialPlaceEvidenceScorer.looksLikeMarketingLine(cleaned) else {
            return nil
        }
        return cleaned
    }

    private func quotedVenueName(in text: String) -> String? {
        let venueIntroPattern = #"名店|正式插旗|插旗|開幕|新店|店名|from\s+tokyo|來自東京|頂級燒肉"#
        for line in text.components(separatedBy: .newlines)
            where line.range(of: venueIntroPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            if let quoted = firstCapture(in: line, pattern: #"[「『《\"]\s*([^」』》\"]{2,80})\s*[」』》\"]"#) {
                let cleaned = SocialPlaceEvidenceScorer.cleanCandidateName(quoted)
                if SocialPlaceEvidenceScorer.isUsableCandidateName(cleaned) {
                    return cleaned
                }
            }
        }

        for line in text.components(separatedBy: .newlines)
            where !SocialPlaceEvidenceScorer.looksLikeMarketingLine(line) {
            if let headline = headlineQuotedVenueName(in: line) { return headline }
        }
        return nil
    }

    private func headlineQuotedVenueName(in line: String) -> String? {
        guard line.range(of: #"必吃|必喝|必訪|必去|餐廳|餐厅|美食|韓其林|米其林|弘大|新村|明洞|西門|士林|東區|東区|台北|臺北"#, options: .regularExpression) != nil else {
            return nil
        }
        let patterns = [
            "[「『《]\\s*([^」』》\\n\\r]{2,40})\\s*[」』》]",
            "[「『《]\\s*([^」』》\\n\\r]{2,40}(?:店|館|馆|餐廳|餐厅|咖啡|茶|酒吧|烘焙|燒肉|烧肉|火鍋|火锅|壽喜燒|寿喜烧|麵|面|飯|饭|屋|坊|室|湯|汤))",
            "[\\\"]\\s*([^\\\"\\n\\r]{2,40})\\s*[\\\"]"
        ]
        for pattern in patterns {
            guard let quoted = firstCapture(in: line, pattern: pattern) else { continue }
            let cleaned = SocialPlaceEvidenceScorer.cleanCandidateName(quoted)
            if SocialPlaceEvidenceScorer.isUsableCandidateName(cleaned),
               !SocialPlaceEvidenceScorer.looksLikeCaptionHeadlineTitle(cleaned),
               !SocialPlaceEvidenceScorer.looksLikeMarketingLine(cleaned),
               !SocialPlaceEvidenceScorer.looksLikeGenericProductOrCityLine(cleaned) {
                return cleaned
            }
        }
        return nil
    }

    private func composedChineseVenueName(in text: String) -> String? {
        let patterns = [
            #"(?:^|[\n\r])[-\s]*(?:[\u4e00-\u9fff]{0,4})?(?:全新開幕|新開幕|開幕)\s*([^\s新主题主題\-－—–:]{2,16})\s*(?:新主題|主题|主題)\s*[-－—–:]\s*([\u4e00-\u9fffA-Za-z0-9]{2,24})"#,
            #"([\u4e00-\u9fffA-Za-z0-9]{2,24})\s*[·・‧]\s*([\u4e00-\u9fffA-Za-z0-9]{2,24})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) where match.numberOfRanges > 2 {
                guard let brandRange = Range(match.range(at: 1), in: text),
                      let themeRange = Range(match.range(at: 2), in: text) else { continue }
                let brand = SocialPlaceEvidenceScorer.cleanCandidateName(String(text[brandRange]))
                let theme = SocialPlaceEvidenceScorer.cleanCandidateName(String(text[themeRange]))
                let name = "\(brand)·\(theme)"
                if SocialPlaceEvidenceScorer.isUsableCandidateName(name),
                   !SocialPlaceEvidenceScorer.looksLikeGenericProductOrCityLine(name),
                   !SocialPlaceEvidenceScorer.looksLikeMarketingLine(name) {
                    return name
                }
            }
        }
        return nil
    }

    private func category(from text: String) -> String {
        let lowered = text.lowercased()
        if lowered.range(of: #"airbnb|stay|hotel|resort|villa|home|cabin|treehouse|marriott|hyatt|hilton|lodge|inn|glamping|retreat"#, options: .regularExpression) != nil {
            return "stay"
        }
        if lowered.range(of: #"\b(pottery|ceramics?|studio|workshops?|classes?|lessons?|experiences?|atelier|wildlife|animal\s+encounters?|sanctuary|tours?|zoo|aquarium|safari)\b"#, options: .regularExpression) != nil {
            return "attraction"
        }
        if lowered.range(of: #"\b(restaurant|food|eat|cafe|coffee|tea|bar|hot pot|sukiyaki|yakiniku)\b"#, options: .regularExpression) != nil {
            return "food"
        }
        if text.range(of: #"晚餐|餐廳|餐厅|美食|咖啡|茶|酒吧|料理|餐|燒肉|烧肉|火鍋|火锅|牛舌|壽喜燒"#, options: .regularExpression) != nil {
            return "food"
        }
        return "attraction"
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private func matches(in text: String, pattern: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range)
    }

    private func candidateScore(_ candidate: SocialPlaceCandidateDraft) -> Double {
        var score = candidate.confidence
        if !candidate.locationClues.isEmpty { score += 0.14 }
        if !candidate.venueHandles.isEmpty { score += 0.08 }
        if !candidate.bookingLinks.isEmpty { score += 0.06 }
        if candidate.category == "stay" || candidate.category == "food" { score += 0.03 }
        return score
    }

    private func sourceSummary(
        for text: String,
        ocrLineCount: Int,
        sourceType: SocialPlaceSourceType,
        topic: String?
    ) -> String {
        if sourceType == .multiPlaceList {
            if let topic, !topic.isEmpty {
                return "multi-place list: \(topic)"
            }
            return "multi-place social list"
        }
        var parts: [String] = []
        if text.lowercased().contains("instagram") || text.contains("@") {
            parts.append("social caption")
        }
        if text.components(separatedBy: .newlines).contains(where: { numberedName(from: $0) != nil }) {
            parts.append("numbered list")
        }
        if ocrLineCount > 0 {
            parts.append("OCR text")
        }
        return parts.isEmpty ? "public link evidence" : parts.joined(separator: " with ")
    }

    private func sourceType(
        text: String,
        sourceURL: String,
        groups: [SocialPlaceSourceGroup],
        candidates: [SocialPlaceCandidateDraft],
        creatorHandles: Set<String>
    ) -> SocialPlaceSourceType {
        if groups.count >= 2 {
            return .multiPlaceList
        }
        if looksLikeSocialPlaceList(text), candidates.filter({ !$0.venueHandles.isEmpty }).count >= 2 {
            return .multiPlaceList
        }
        if looksLikeDouyinFoodList(text: text, sourceURL: sourceURL), candidates.count >= 2 {
            return .multiPlaceList
        }
        if looksLikeDouyinAggregateFoodList(text: text, sourceURL: sourceURL), candidates.isEmpty {
            return .multiPlaceList
        }
        if candidates.count == 1 {
            return .singleVenuePost
        }
        if candidates.isEmpty, !creatorHandles.isEmpty {
            return .creatorOnly
        }
        if candidates.isEmpty {
            return .sourceOnly
        }
        return .unknown
    }

    private func sourceGroups(from lines: [String]) -> [SocialPlaceSourceGroup] {
        var groups: [SocialPlaceSourceGroup] = []
        for (index, line) in lines.enumerated() {
            let venueHandles = handles(in: line)
            guard !venueHandles.isEmpty else { continue }
            guard let label = nearbyListGroupLabel(after: index, in: lines) ?? nearbyListGroupLabel(before: index, in: lines) else {
                continue
            }
            groups.append(
                SocialPlaceSourceGroup(
                    label: label,
                    venueHandles: uniqueStrings(venueHandles),
                    evidenceLine: line
                )
            )
        }
        return uniqueGroups(groups)
    }

    private func nearbyListGroupLabel(after index: Int, in lines: [String]) -> String? {
        let nextIndex = index + 1
        guard lines.indices.contains(nextIndex), handles(in: lines[nextIndex]).isEmpty else { return nil }
        return listGroupLabel(from: lines[nextIndex])
    }

    private func nearbyListGroupLabel(before index: Int, in lines: [String]) -> String? {
        let previousIndex = index - 1
        guard lines.indices.contains(previousIndex), handles(in: lines[previousIndex]).isEmpty else { return nil }
        return listGroupLabel(from: lines[previousIndex])
    }

    private func listGroupLabel(from line: String) -> String? {
        let cleaned = SocialPlaceEvidenceScorer.cleanText(line)
            .replacingOccurrences(of: #"^[→\-–—•\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？"))
        guard cleaned.count >= 3,
              cleaned.count <= 80,
              cleaned.range(of: #"(?i)\b(?:best for|worth it|atmosphere|aesthetic|coffee quality|unique|desserts?|experiences?|favorite|favourite)\b"#, options: .regularExpression) != nil,
              handles(in: cleaned).isEmpty else {
            return nil
        }
        return cleaned.lowercased()
    }

    private func sourceIntent(
        text: String,
        sourceType: SocialPlaceSourceType,
        topic: String?,
        regionClues: [String],
        groups: [SocialPlaceSourceGroup],
        placesFound: [SocialPlaceCandidateDraft],
        creatorHandles: Set<String>
    ) -> SocialPlaceSourceIntent {
        if sourceType == .multiPlaceList || !groups.isEmpty {
            return .multiPlaceList
        }
        if sourceType == .singleVenuePost || !placesFound.isEmpty {
            return .singleVenuePost
        }
        let trimmed = SocialPlaceEvidenceScorer.cleanText(text)
        guard !trimmed.isEmpty else { return .nonPlace }

        let searchable = normalizedSearchText(trimmed)
        let topicText = normalizedSearchText(topic ?? "")
        if isPlaceListRecommendation(searchable) || isPlaceListRecommendation(topicText) {
            return .multiPlaceList
        }
        if isRestaurantRecommendation(searchable) || isRestaurantRecommendation(topicText) {
            return .restaurantRecommendation
        }
        if isCafeRecommendation(searchable) || isCafeRecommendation(topicText) {
            return .cafeRecommendation
        }
        if isStayRecommendation(searchable) || isStayRecommendation(topicText) {
            return .stayRecommendation
        }
        if isTravelRecommendation(searchable) || isTravelRecommendation(topicText) {
            return .travelRecommendation
        }
        if sourceType == .creatorOnly || !creatorHandles.isEmpty {
            return .creatorOnly
        }
        if !regionClues.isEmpty, hasPlaceCategorySignal(searchable) {
            return .unknownPlaceBearing
        }
        return .nonPlace
    }

    private func isPlaceBearingIntent(_ intent: SocialPlaceSourceIntent) -> Bool {
        switch intent {
        case .nonPlace, .creatorOnly:
            return false
        case .restaurantRecommendation, .cafeRecommendation, .travelRecommendation, .stayRecommendation, .multiPlaceList, .singleVenuePost, .unknownPlaceBearing:
            return true
        }
    }

    private func placeBearingReason(intent: SocialPlaceSourceIntent, topic: String?, regionClues: [String]) -> String {
        let topicSuffix = topic.map { " about \($0)" } ?? ""
        let regionSuffix = normalizedPrimaryRegion(from: regionClues).map { " near \($0)" } ?? ""
        switch intent {
        case .restaurantRecommendation:
            return "restaurant recommendation source\(topicSuffix)\(regionSuffix)"
        case .cafeRecommendation:
            return "cafe or coffee recommendation source\(topicSuffix)\(regionSuffix)"
        case .stayRecommendation:
            return "stay or resort recommendation source\(topicSuffix)\(regionSuffix)"
        case .travelRecommendation:
            return "travel place recommendation source\(topicSuffix)\(regionSuffix)"
        case .multiPlaceList:
            return "multi-place list source\(topicSuffix)\(regionSuffix)"
        case .singleVenuePost:
            return "single venue source\(topicSuffix)\(regionSuffix)"
        case .unknownPlaceBearing:
            return "place-bearing source\(topicSuffix)\(regionSuffix)"
        case .nonPlace, .creatorOnly:
            return "not place-bearing"
        }
    }

    private func recoveryHints(
        intent: SocialPlaceSourceIntent,
        topic: String?,
        regionClues: [String],
        text: String
    ) -> [SocialPlaceRecoveryHint] {
        guard isPlaceBearingIntent(intent) else { return [] }
        var hints: [SocialPlaceRecoveryHint] = []
        if let topic, !topic.isEmpty {
            hints.append(SocialPlaceRecoveryHint(label: "topic", queryFragment: topic))
        }
        if let region = normalizedPrimaryRegion(from: regionClues) {
            hints.append(SocialPlaceRecoveryHint(label: "region", queryFragment: region))
        }
        if let phrase = meaningfulPlaceBearingPhrase(from: text) {
            hints.append(SocialPlaceRecoveryHint(label: "caption phrase", queryFragment: phrase))
        }
        let keyword = sourceIntentSearchKeyword(intent)
        if !keyword.isEmpty {
            hints.append(SocialPlaceRecoveryHint(label: "category", queryFragment: keyword))
        }
        var seen = Set<String>()
        return hints.filter { hint in
            let key = "\(hint.label)|\(hint.queryFragment.lowercased())"
            guard !seen.contains(key), !hint.queryFragment.isEmpty else { return false }
            seen.insert(key)
            return true
        }
    }

    private func normalizedSearchText(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[#_]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isPlaceListRecommendation(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let countPattern = #"(?:\d{1,2}|[０-９]{1,2}|[一二三四五六七八九十]{1,3})\s*\+?"#
        let patterns = [
            #"\b(?:best|top|favorite|favourite|must[- ]?try|recommended?)\s+\d{1,2}\s+(?:restaurants?|cafes?|coffee shops?|dessert shops?|ice shops?|places to eat|food spots?)\b"#,
            #"(?:推薦|精選|必吃|必去|收藏)\s*"# + countPattern + #"\s*(?:間|家|個)?\s*(?:冰店|冰品|剉冰|刨冰|甜點|甜品|咖啡|咖啡廳|餐廳|餐厅|小吃|美食|店)"#,
            countPattern + #"\s*(?:間|家|個)?\s*(?:冰店|冰品|剉冰|刨冰|甜點|甜品|咖啡|咖啡廳|餐廳|餐厅|小吃|美食|店)"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private func isRestaurantRecommendation(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let patterns = [
            #"\b(?:favorite|favourite|best|top|must try|must-try|iconic|hidden gem|hidden gems)[^.\n]{0,80}\b(?:restaurants?|food spots?|dinner spots?|brunch spots?|places to eat)\b"#,
            #"\b(?:where to eat|wheretoeat|places to eat|food spots?|dinner spots?|brunch spots?)\b"#,
            #"\b(?:restaurants?|food spots?|places to eat)\s+in\s+(?:la|los angeles|oc|orange county|tokyo|taipei|seoul|paris|london|new york|[a-z][a-z .'-]{2,60})\b"#,
            #"(?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園|東京|大阪|首爾|서울)?[^\n\r]{0,20}(?:推薦|必吃|想衝去吃|吃什麼)[^\n\r]{0,40}(?:刨冰|剉冰|冰品|冰店|芒果冰|粉粿冰|八寶冰|布丁冰|小吃|美食|餐廳|餐厅)"#,
            #"(?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)的(?!(?:那間店|那家店|這間店|这间店|這家店|这家店|那個地方|那个地方))[^\n\r，,。！!？?]{2,24}[\s\S]{0,80}(?:鴨|鸭|烤鴨|烤鸭|餐廳|餐厅|美食|小吃|聚餐|吃|訂位|订位)"#,
            #"(?:士林|西門|大安|信義|萬華|中山|松山|內湖|板橋|新莊|蘆洲|台北|臺北)[📍\s·・:：-]{0,4}[^\n\r]{0,50}(?:壽喜燒|寿喜烧|漢堡排|日本料理|日式料理|餐廳|餐厅|美食)"#,
            #"(?:刨冰|剉冰|冰品|冰店|芒果冰|粉粿冰|八寶冰|布丁冰|小吃|美食)[^\n\r]{0,30}(?:推薦|必吃|店)"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private func isCafeRecommendation(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let patterns = [
            #"\b(?:favorite|favourite|best|top|must try|must-try|hidden gem|hidden gems)[^.\n]{0,80}\b(?:cafes?|coffee shops?)\b"#,
            #"\b(?:cafes?|coffee shops?)\s+in\s+(?:la|los angeles|oc|orange county|tokyo|taipei|seoul|paris|london|new york|[a-z][a-z .'-]{2,60})\b"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private func isStayRecommendation(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let patterns = [
            #"\b(?:hotels?|resorts?|stays?|villas?|airbnbs?|where to stay)\s+in\s+(?:la|los angeles|oc|orange county|bali|tokyo|taipei|seoul|paris|london|new york|[a-z][a-z .'-]{2,60})\b"#,
            #"\b(?:best|favorite|favourite|hidden gem|iconic)[^.\n]{0,80}\b(?:hotels?|resorts?|stays?|villas?|airbnbs?)\b"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private func isTravelRecommendation(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let patterns = [
            #"\b(?:hidden gems?|things to do|places to visit|travel spots?|must visit|must-visit)\s+(?:in|near)\s+(?:la|los angeles|oc|orange county|bali|tokyo|taipei|seoul|paris|london|new york|[a-z][a-z .'-]{2,60})\b"#,
            #"\b(?:best|favorite|favourite|top)[^.\n]{0,80}\b(?:things to do|places to visit|travel spots?)\b"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private func hasPlaceCategorySignal(_ text: String) -> Bool {
        text.range(
            of: #"\b(?:restaurants?|cafes?|coffee shops?|bars?|bakeries|dessert shops?|hotels?|resorts?|places to eat|things to do|hidden gems?|wildlife|animal\s+encounters?|sanctuar(?:y|ies)|tours?|experiences?)\b|(?:冰店|冰品|剉冰|刨冰|甜點|甜品|咖啡廳|餐廳|餐厅|小吃|美食|店|壽喜燒|寿喜烧|漢堡排|日本料理|日式料理)"#,
            options: .regularExpression
        ) != nil
    }

    private func sourceIntentSearchKeyword(_ intent: SocialPlaceSourceIntent) -> String {
        switch intent {
        case .restaurantRecommendation:
            return "restaurant"
        case .cafeRecommendation:
            return "cafe coffee shop"
        case .stayRecommendation:
            return "hotel resort stay"
        case .travelRecommendation, .unknownPlaceBearing, .multiPlaceList:
            return "place"
        case .singleVenuePost:
            return "venue"
        case .nonPlace, .creatorOnly:
            return ""
        }
    }

    private func normalizedPrimaryRegion(from regionClues: [String]) -> String? {
        guard let clue = regionClues.first else { return nil }
        let lowered = clue.lowercased()
        if lowered == "losangeles" || lowered == "la" || lowered == "lacoffee" { return "LA" }
        if lowered == "orangecounty" || lowered == "oc" || lowered == "ocfood" { return "Orange County" }
        if lowered == "sandiego" { return "San Diego" }
        if lowered == "newyork" { return "New York" }
        if clue == "臺南" { return "台南" }
        if clue == "臺北" { return "台北" }
        if clue == "臺中" { return "台中" }
        return clue
    }

    private func meaningfulPlaceBearingPhrase(from text: String) -> String? {
        let patterns = [
            #"(?i)\b((?:favorite|favourite|best|top|must-try|must try|iconic|hidden gems?|where to eat)[^.\n\r]{0,90})"#,
            #"(?i)\b((?:restaurants?|cafes?|coffee shops?|hotels?|resorts?|things to do|places to visit)\s+in\s+(?:LA|Los Angeles|OC|Orange County|Tokyo|Taipei|Seoul|Paris|London|New York|[A-Z][A-Za-z .'-]{2,60}))\b"#,
            #"((?:士林|西門|大安|信義|萬華|中山|松山|內湖|板橋|新莊|蘆洲)[^\n\r]{0,60}(?:壽喜燒|寿喜烧|漢堡排|日本料理|日式料理|餐廳|餐厅|美食))"#,
            #"((?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)的(?!(?:那間店|那家店|這間店|这间店|這家店|这家店|那個地方|那个地方))[^\n\r，,。！!？?@#]{2,24})"#,
            #"((?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園|東京|大阪|首爾|서울)[^\n\r]{0,30}(?:推薦|必吃|吃什麼|冰店|冰品|剉冰|刨冰|小吃|美食|餐廳|餐厅))"#,
            #"((?:推薦|精選|必吃|必去|收藏)\s*(?:\d{1,2}|[０-９]{1,2}|[一二三四五六七八九十]{1,3})\s*(?:間|家|個)?\s*(?:冰店|冰品|剉冰|刨冰|甜點|甜品|咖啡|咖啡廳|餐廳|餐厅|小吃|美食|店))"#
        ]
        for pattern in patterns {
            guard let phrase = firstCapture(in: text, pattern: pattern) else { continue }
            let cleaned = SocialPlaceEvidenceScorer.cleanText(phrase)
                .replacingOccurrences(of: #"[📍👣🗺]+"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r.。!！?？,，\"'“”"))
            if cleaned.count >= 8, cleaned.count <= 120 {
                return cleaned
            }
        }
        return nil
    }

    private func sourceTopic(from text: String) -> String? {
        let patterns = [
            #"(?i)\b(LA\s*(?:must[-\s]*eat\s*)?(?:food|restaurants?|eats?)\s*list)\b"#,
            #"(?:🇺🇸)?\s*(LA必吃美食)"#,
            #"(洛杉[矶磯]美食)"#,
            #"(?i)\b(?:the\s+)?(coffee shops?\s+in\s+Los Angeles County)\b"#,
            #"((?:推薦|精選|必吃|必去|收藏)\s*(?:\d{1,2}|[０-９]{1,2}|[一二三四五六七八九十]{1,3})\s*(?:間|家|個)?\s*(?:冰店|冰品|剉冰|刨冰|甜點|甜品|咖啡|咖啡廳|餐廳|餐厅|小吃|美食|店))"#,
            #"((?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)的(?!(?:那間店|那家店|這間店|这间店|這家店|这家店|那個地方|那个地方))[^\n\r，,。！!？?@#]{2,24})"#,
            #"((?:台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)[^\n\r]{0,20}(?:冰店|冰品|剉冰|刨冰|小吃|美食|餐廳|餐厅|甜點|甜品|咖啡廳))"#,
            #"(?i)\b(?:favorite|favourite|best|top|must-try|must try|hidden gems?)?[^\n\r]{0,30}\b((?:coffee shops?|restaurants?|cafes?|bars?|bakeries|dessert shops?)\s+in\s+(?:LA|OC|[A-Z][A-Za-z .'-]{2,60}))\b"#,
            #"(?i)\b((?:LA|Los Angeles|Orange County|OC|Tokyo|Taipei|Seoul|Paris|London|New York)\s+(?:coffee shops?|restaurants?|cafes?|bars?|bakeries|dessert shops?))\b"#
        ]
        for pattern in patterns {
            guard let topic = firstCapture(in: text, pattern: pattern) else { continue }
            let cleaned = SocialPlaceEvidenceScorer.cleanText(topic)
                .replacingOccurrences(of: #"(?i)^the\s+"#, with: "", options: .regularExpression)
            if cleaned.contains("/") { continue }
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    private func regionClues(from text: String) -> [String] {
        var clues: [String] = []
        let patterns = [
            #"(?i)(?:^|[^A-Za-z])(LA)(?:[^A-Za-z]|$)"#,
            #"(?i)\bLos Angeles County\b"#,
            #"(?i)\bLos Angeles\b"#,
            #"(?i)\bSan Diego\b"#,
            #"(?i)\bBonsall\b"#,
            #"(?i)\bThai\s+Town\b"#,
            #"洛杉[矶磯]"#,
            #"(?i)\bOrange County\b"#,
            #"(?i)\bOC\b"#,
            #"(?i)#(losangeles|lacoffee|orangecounty|ocfood|tokyo|taipei|seoul|paris|london|newyork)\b"#,
            #"(北京|上海|廣州|广州|深圳|杭州|南京|成都|重慶|重庆|武漢|武汉|西安|青島|青岛|廈門|厦门|長沙|长沙)(?=[^\n\r]{0,20}(?:攻略|推薦|推荐|必吃|美食|餐廳|餐厅|小吃|咖啡|甜點|甜品|店))"#,
            #"(士林|西門|大安|信義|萬華|中山|松山|內湖|板橋|新莊|蘆洲)(?=[📍\s·・:：-]{0,4}[^\n\r]{0,40}(?:壽喜燒|寿喜烧|漢堡排|日本料理|日式料理|餐廳|餐厅|美食|咖啡|甜點|甜品|小吃))"#,
            #"(台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)(?=的(?!(?:那間店|那家店|這間店|这间店|這家店|这家店|那個地方|那个地方))[^\n\r，,。！!？?@#]{2,24})"#,
            #"(台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)(?=[^\n\r]{0,12}(?:冰店|冰品|剉冰|刨冰|小吃|美食|餐廳|餐厅|甜點|甜品|咖啡廳|推薦|必吃|吃什麼))"#,
            #"#(台南|臺南|台北|臺北|台中|臺中|高雄|新北|桃園)(?:小吃|美食|冰品|冰店|甜點|甜品)?"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                let captureRange = match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound
                    ? match.range(at: 1)
                    : match.range
                guard let matchRange = Range(captureRange, in: text) else { continue }
                let raw = String(text[matchRange]).replacingOccurrences(of: "#", with: "")
                clues.append(SocialPlaceEvidenceScorer.cleanText(raw))
            }
        }
        return uniqueStrings(clues)
    }

    private func attachSourceGroupEvidence(
        groups: [SocialPlaceSourceGroup],
        to candidates: [SocialPlaceCandidateDraft]
    ) -> [SocialPlaceCandidateDraft] {
        guard !groups.isEmpty else { return candidates }
        return candidates.map { candidate in
            var candidate = candidate
            let matchedGroups = groups.filter { group in
                !Set(group.venueHandles).isDisjoint(with: Set(candidate.venueHandles))
            }
            guard !matchedGroups.isEmpty else { return candidate }
            let atoms = matchedGroups.map { group in
                SocialEvidenceAtom(
                    source: .captionSentence,
                    role: .categoryClue,
                    value: "Source group: \(group.label)",
                    line: group.evidenceLine,
                    confidence: 0.42
                )
            }
            candidate.evidence = appendUniqueAtoms(candidate.evidence + atoms)
            candidate.missingInfo = uniqueStrings(candidate.missingInfo + ["Grouped list clue; enrich before saving"])
                .sorted()
            return candidate
        }
    }

    private func sourceConfidence(
        sourceType: SocialPlaceSourceType,
        groups: [SocialPlaceSourceGroup],
        candidates: [SocialPlaceCandidateDraft]
    ) -> Double {
        switch sourceType {
        case .multiPlaceList:
            return min(0.5 + Double(groups.count) * 0.05 + Double(candidates.count) * 0.01, 0.78)
        case .singleVenuePost, .singlePlaceRecommendation, .activityOrExperienceVenue, .bookingOrReservation, .mapShare:
            return candidates.first?.confidence ?? 0.5
        case .creatorOnly, .creatorSourceOnly:
            return 0.32
        case .sourceOnly:
            return 0.24
        case .ocrHeavySource:
            return 0.38
        case .vagueLifestyleCaption:
            return 0.28
        case .ambiguous, .unknown:
            return 0.4
        }
    }

    private func uniqueGroups(_ groups: [SocialPlaceSourceGroup]) -> [SocialPlaceSourceGroup] {
        var seen = Set<String>()
        var result: [SocialPlaceSourceGroup] = []
        for group in groups {
            let key = "\(group.label)|\(group.venueHandles.joined(separator: ","))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(group)
        }
        return result
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    private func appendUniqueAtoms(_ atoms: [SocialEvidenceAtom]) -> [SocialEvidenceAtom] {
        var seen = Set<String>()
        var result: [SocialEvidenceAtom] = []
        for atom in atoms {
            let key = "\(atom.role.rawValue)|\(atom.value.lowercased())|\(atom.line.lowercased())"
            guard !seen.contains(key), !atom.value.isEmpty else { continue }
            seen.insert(key)
            result.append(atom)
        }
        return result
    }

    private func uniqueActors(_ actors: [SocialPlaceSourceActor]) -> [SocialPlaceSourceActor] {
        var seen = Set<String>()
        return actors.filter { actor in
            let key = "\(actor.role.rawValue)|\(actor.handle)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func uniqueDiscarded(_ discarded: [SocialPlaceDiscardedCandidate]) -> [SocialPlaceDiscardedCandidate] {
        var seen = Set<String>()
        return discarded.filter { item in
            let key = "\(item.value.lowercased())|\(item.reason)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
