import Foundation

// MARK: - Protocol

protocol AIParsingServiceProtocol {
    func parseURL(_ url: URL) async throws -> ParsedPlaceResult
    func parseImage(_ imageData: Data) async throws -> ParsedPlaceResult
}

// MARK: - Parsed Result

struct ParsedPlaceResult: Codable {
    var placeName: String?
    var address: String?
    var category: PlaceCategory?
    var dishes: [String]?
    var priceRange: String?
    var recommender: String?
    var latitude: Double?
    var longitude: Double?
    var confidence: Double
}

// MARK: - Errors

enum AIParsingError: LocalizedError {
    case invalidResponse
    case apiKeyMissing
    case networkError(Error)
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "AI returned something unexpected. Try again."
        case .apiKeyMissing: return "AI isn't configured yet."
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .parsingFailed(let reason): return "Parsing failed: \(reason)"
        }
    }
}

// MARK: - Gemini Implementation

final class AIParsingService: AIParsingServiceProtocol {
    static let shared = AIParsingService()

    private let apiKey: String?
    private let modelFallbacks: [String]

    init(apiKey: String? = nil, modelFallbacks: [String] = SAVEProductionConfig.defaultGeminiModelFallbacks) {
        let resolved = apiKey
            ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? SAVEProductionConfig.configValue(for: ["GEMINI_API_KEY"])
        self.apiKey = resolved
        self.modelFallbacks = modelFallbacks
    }

    // MARK: - Parse URL

    func parseURL(_ url: URL) async throws -> ParsedPlaceResult {
        guard let apiKey, !apiKey.isEmpty else {
            throw AIParsingError.apiKeyMissing
        }

        // Step 1: Fetch OpenGraph metadata from URL
        let metadata = await fetchOpenGraphMetadata(from: url)

        // Step 2: Send metadata + URL to Gemini for parsing
        let displayURL = metadata.finalURL?.absoluteString ?? url.absoluteString
        let prompt = """
        Extract place information from this shared content.

        Original URL: \(url.absoluteString)
        Final URL: \(displayURL)
        Page title: \(metadata.title ?? "unknown")
        Page description: \(metadata.description ?? "unknown")
        Site name: \(metadata.siteName ?? "unknown")

        Respond ONLY with a valid JSON object:
        {
          "placeName": "Name of the place",
          "address": "Full address",
          "category": "food" | "cafe" | "bar" | "attraction" | "stay" | "shopping",
          "dishes": ["dish1", "dish2"],
          "priceRange": "$$",
          "recommender": "@username or null",
          "latitude": 0.0,
          "longitude": 0.0,
          "confidence": 0.0 to 1.0
        }

        If you can identify the place, set confidence high (0.7+).
        If uncertain, set confidence low (<0.5) and provide your best guess.
        """

        return try await callGemini(prompt: prompt)
    }

    // MARK: - Parse Image

    func parseImage(_ imageData: Data) async throws -> ParsedPlaceResult {
        guard let apiKey, !apiKey.isEmpty else {
            throw AIParsingError.apiKeyMissing
        }

        let base64 = imageData.base64EncodedString()

        let prompt = """
        Look at this image and extract place/restaurant information.
        Respond ONLY with a valid JSON object:
        {
          "placeName": "Name",
          "address": "Address if visible",
          "category": "food" | "cafe" | "bar" | "attraction" | "stay" | "shopping",
          "dishes": ["any visible dishes"],
          "priceRange": "$$ or null",
          "confidence": 0.0 to 1.0
        }
        """

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]]
                ]
            ]],
            "generationConfig": ["temperature": 0.2, "maxOutputTokens": 512]
        ]

        return try await callGemini(body: body)
    }

    // MARK: - Private

    private func callGemini(prompt: String) async throws -> ParsedPlaceResult {
        guard apiKey != nil else { throw AIParsingError.apiKeyMissing }

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2, "maxOutputTokens": 512]
        ]

        return try await callGemini(body: body)
    }

    private func callGemini(body: [String: Any]) async throws -> ParsedPlaceResult {
        guard let apiKey else { throw AIParsingError.apiKeyMissing }
        let requestBody = try JSONSerialization.data(withJSONObject: body)
        var lastStatusCode = 0

        for model in modelFallbacks {
            let endpoint = SAVEProductionConfig.geminiGenerateContentURL(apiKey: apiKey, model: model)
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = requestBody

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { continue }
            lastStatusCode = http.statusCode
            if http.statusCode == 200 {
                return try parseGeminiResponse(data)
            }
            if http.statusCode != 404 && http.statusCode != 429 {
                break
            }
        }

        throw AIParsingError.parsingFailed(Self.userFacingGeminiError(statusCode: lastStatusCode))
    }

    private static func userFacingGeminiError(statusCode: Int) -> String {
        if statusCode == 429 {
            return "AI is busy right now. Try again in a minute."
        }
        if statusCode == 401 || statusCode == 403 {
            return "AI access needs attention."
        }
        return "AI request failed. Try again in a moment."
    }

    private func parseGeminiResponse(_ data: Data) throws -> ParsedPlaceResult {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw AIParsingError.invalidResponse
        }

        // Extract JSON
        var jsonString = text
        if let start = text.range(of: "{"),
           let end = text.range(of: "}", options: .backwards),
           start.lowerBound < end.upperBound {
            jsonString = String(text[start.lowerBound..<end.upperBound])
        }
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw AIParsingError.invalidResponse
        }

        let categoryStr = dict["category"] as? String ?? "food"

        return ParsedPlaceResult(
            placeName: dict["placeName"] as? String,
            address: dict["address"] as? String,
            category: PlaceCategory(rawValue: categoryStr),
            dishes: dict["dishes"] as? [String],
            priceRange: dict["priceRange"] as? String,
            recommender: dict["recommender"] as? String,
            latitude: dict["latitude"] as? Double,
            longitude: dict["longitude"] as? Double,
            confidence: dict["confidence"] as? Double ?? 0.5
        )
    }

    // MARK: - OpenGraph Metadata

    private struct OGMetadata {
        var title: String?
        var description: String?
        var siteName: String?
        var finalURL: URL?
    }

    private func fetchOpenGraphMetadata(from url: URL) async -> OGMetadata {
        var metadata = OGMetadata()
        metadata.finalURL = url

        do {
            // Configuration for realistic browser simulation
            let config = URLSessionConfiguration.default
            // We use a custom delegate to track redirects if needed, 
            // but for simplicity here we'll use the default redirect behavior 
            // and focus on high-quality headers.
            let session = URLSession(configuration: config)
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            
            // Set robust headers to bypass basic bot detection
            let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("none", forHTTPHeaderField: "X-Requested-With")
            
            // If it's a known short link, set a realistic referer
            if url.host?.contains("xhslink") == true {
                request.setValue("https://www.xiaohongshu.com/", forHTTPHeaderField: "Referer")
            }

            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                metadata.finalURL = httpResponse.url
            }
            
            guard let html = String(data: data, encoding: .utf8) else { return metadata }

            // Extract metadata
            metadata.title = extractMeta(from: html, property: "og:title")
                ?? extractTag(from: html, tag: "title")
            metadata.description = extractMeta(from: html, property: "og:description")
                ?? extractMeta(from: html, name: "description")
            metadata.siteName = extractMeta(from: html, property: "og:site_name")
            
            // If title is just "小红书" or "Xiaohongshu", it's likely we hit a wall, 
            // but we still pass the HTML snippet to Gemini to see if it can find clues.
        } catch {
            print("Metadata fetch error: \(error.localizedDescription)")
        }

        return metadata
    }

    private func extractMeta(from html: String, property: String) -> String? {
        let pattern = #"<meta[^>]*property="\#(property)"[^>]*content="([^"]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    private func extractMeta(from html: String, name: String) -> String? {
        let pattern = #"<meta[^>]*name="\#(name)"[^>]*content="([^"]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    private func extractTag(from html: String, tag: String) -> String? {
        let pattern = "<\(tag)>([^<]*)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }
}
