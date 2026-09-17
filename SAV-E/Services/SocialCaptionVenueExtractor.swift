import Foundation

/// One venue the LLM believes a social caption is primarily about.
///
/// This is intentionally minimal: the deterministic parser already owns
/// marker-driven extraction (📍 pins, address lines, @handles). The LLM only
/// supplies a *name* (plus loose area/category hints) for the prose-only long
/// tail the deterministic parser deliberately rejects to avoid false positives.
/// Coordinates are never produced here — an extracted venue is only ever a
/// Review Candidate stem, never a Map Stamp.
struct ExtractedVenue: Equatable {
    /// The venue's proper name, as it literally appears in the caption.
    var name: String
    /// City / neighborhood / country hint, if the caption named one.
    var area: String?
    /// Loose category hint: cafe/food/bar/hotel/attraction/shopping/stay.
    var category: String?
    /// LLM self-reported confidence, 0...1.
    var confidence: Double
}

/// Extracts the primary venue name from a social caption when the deterministic
/// marker-driven parser found nothing. Injectable so tests can supply a fake
/// (no network); production uses the Gemini-backed implementation below.
protocol SocialCaptionVenueExtractor {
    func extractVenue(caption: String, sourceURL: String) async -> ExtractedVenue?
}

/// Live extractor backed by the shared backend Gemini proxy (the same transport
/// `GeminiSaveLLMClient` uses). Works for real Privy users *and* the App Review
/// demo guest, because the transport falls back to the `x-save-guest-token`
/// header when no Privy JWT is available.
///
/// Honest runtime note: in production this depends on the live proxy returning a
/// well-formed extraction. It is bounded (single attempt + the transport's own
/// transient retry, a hard timeout, capped output) and fails safe to `nil` on
/// any error — a flaky/empty LLM response degrades to the deterministic
/// source-only receipt, it never throws into the recovery flow.
final class GeminiCaptionVenueExtractor: SocialCaptionVenueExtractor {
    private let geminiTransport: SAVEGeminiTransport

    init(
        apiKey: String? = nil,
        modelFallbacks: [String] = SAVEProductionConfig.defaultGeminiModelFallbacks,
        session: URLSession = .shared
    ) {
        self.geminiTransport = SAVEGeminiTransport(
            modelFallbacks: modelFallbacks,
            session: session,
            accessTokenProvider: { try await PrivyAuthService.shared.accessToken() },
            // App Review demo: caption extraction reaches the LLM proxy via an
            // anonymous guest token when there's no real Privy JWT.
            guestTokenProvider: { ReviewDemoGuestTokenHolder.shared.current },
            directAPIKey: apiKey ?? SAVEProductionConfig.clientGeminiAPIKeyIfAllowed(),
            // Tighter than the drawer answer transport: caption extraction is a
            // best-effort fallback on the latency-sensitive paste path.
            requestTimeout: 12,
            maxAttemptsPerModel: 1
        )
    }

    /// Returns the live extractor only when a usable LLM path is configured
    /// (backend proxy URL or a direct API key). Otherwise `nil`, so the service
    /// keeps its deterministic-only behavior without any failed network calls.
    static func liveFromConfig() -> GeminiCaptionVenueExtractor? {
        let hasBackend = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]) != nil
        let apiKey = SAVEProductionConfig.clientGeminiAPIKeyIfAllowed()
        guard hasBackend || apiKey != nil else { return nil }
        return GeminiCaptionVenueExtractor(apiKey: apiKey)
    }

    func extractVenue(caption: String, sourceURL: String) async -> ExtractedVenue? {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let boundedCaption = SocialCaptionVenueExtractionPolicy.boundedCaption(trimmed)

        let prompt = SocialCaptionVenueExtractionPolicy.prompt(caption: boundedCaption)
        do {
            let text = try await generateText(prompt: prompt, temperature: 0, maxOutputTokens: 256)
            return Self.parseExtraction(from: text)
        } catch {
            // Fail safe: any transport/parse error degrades to the deterministic
            // source-only path. The LLM is a bonus, never a dependency.
            return nil
        }
    }

    static func extractionPrompt(caption: String) -> String {
        SocialCaptionVenueExtractionPolicy.prompt(caption: caption)
    }

    /// Parses the strict-JSON extraction. A missing/null/empty name means "no
    /// venue" → nil. Tolerant of the LLM wrapping JSON in prose by scanning for
    /// the outermost object.
    static func parseExtraction(from text: String) -> ExtractedVenue? {
        guard let extraction = SocialCaptionVenueExtractionPolicy.parseExtraction(from: text) else { return nil }
        return ExtractedVenue(
            name: extraction.name,
            area: extraction.area,
            category: extraction.category,
            confidence: extraction.confidence
        )
    }

    private func generateText(prompt: String, temperature: Double, maxOutputTokens: Int) async throws -> String {
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": temperature, "maxOutputTokens": maxOutputTokens]
        ]
        let json = try await geminiTransport.generateContent(body: body)
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw SAVEGeminiTransportError.emptyResponse
        }
        return text
    }
}

// The production social path uses one server-owned prompt and map verifier.
// The legacy extractor above remains only for non-social compatibility helpers.
struct SocialSemanticField: Codable, Equatable {
    var value: String
    var quote: String
    var source: String
}

struct SocialSemanticMapPlace: Codable, Equatable {
    var id: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
}

struct SocialSemanticVenue: Codable, Equatable {
    var name: SocialSemanticField
    var branch: SocialSemanticField?
    var address: SocialSemanticField?
    var transport: SocialSemanticField?
    var mapStatus: String
    var matches: [SocialSemanticMapPlace]
}

struct SocialSemanticResult: Codable, Equatable {
    var status: String
    var venues: [SocialSemanticVenue]
    var reason: String?

    static let pending = SocialSemanticResult(status: "analysis_pending", venues: [], reason: nil)

    func supplemented(by next: SocialSemanticResult) -> SocialSemanticResult {
        if next.status == "cancelled" || status != "ready" { return next }
        guard next.status == "ready" else { return self }
        func normalized(_ value: String) -> String {
            value.precomposedStringWithCompatibilityMapping.lowercased().replacingOccurrences(of: "臺", with: "台").filter { !$0.isWhitespace }
        }
        let rank = ["matched": 3, "ambiguous": 2, "unverified": 1, "conflict": 1]
        let retains = venues.allSatisfy { old in next.venues.contains { updated in
            let fields: [(SocialSemanticField?, SocialSemanticField?)] = [(old.name, updated.name), (old.branch, updated.branch), (old.address, updated.address), (old.transport, updated.transport)]
            return fields.allSatisfy { before, after in before == nil || (after != nil && normalized(before!.value) == normalized(after!.value)) }
                && (rank[updated.mapStatus] ?? 0) >= (rank[old.mapStatus] ?? 0)
                && (old.matches.isEmpty || !updated.matches.isEmpty)
        } }
        return retains ? next : self
    }
}

protocol SocialSemanticAnalyzing {
    func analyze(caption: String, ocrText: String?) async -> SocialSemanticResult
}

struct BackendSocialSemanticAnalyzer: SocialSemanticAnalyzing {
    func analyze(caption: String, ocrText: String?) async -> SocialSemanticResult {
        do {
            return try await SupabaseService.shared.analyzeSocialCaption(caption: caption, ocrText: ocrText)
        } catch is CancellationError {
            return SocialSemanticResult(status: "cancelled", venues: [], reason: nil)
        } catch {
            await SAVEAnalysisScope.current?.markProviderFailure()
            return .pending
        }
    }
}
