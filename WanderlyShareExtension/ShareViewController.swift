import UIKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(rootView: ShareExtensionView(
            extensionContext: extensionContext
        ))
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}

// MARK: - Parsed Place Model

struct ParsedPlace {
    var name: String
    var address: String
    var category: String
    var iconName: String
    var latitude: Double?
    var longitude: Double?
    var dishes: [String]
    var priceRange: String?
}

private enum WanderlySharedStorage {
    static let appGroupSuiteName = "group.com.wanderly.app"
    static let pendingPlacesFileName = "pending-places.json"
    static let pendingReviewCandidatesFileName = "pending-review-candidates.json"
}

private enum SaveTheme {
    static let blush = Color(hex: "FFF6F8")
    static let peach = Color(hex: "FFF1D8")
    static let cream = Color(hex: "FFF8E8")
    static let mint = Color(hex: "F1FBF5")
    static let berry = Color(hex: "E8849B")
    static let cocoa = Color(hex: "6B4E57")
    static let rose = Color(hex: "9B6B78")
    static let honey = Color(hex: "F4B860")
    static let sky = Color(hex: "BEE7F8")
    static let card = Color.white.opacity(0.82)
}

private struct PendingSharedPlace: Codable {
    var name: String
    var address: String
    var category: String
    var latitude: Double
    var longitude: Double
    var dishes: [String]
    var priceRange: String?
    var sourceURL: String?
    var sourceText: String?
    var savedAt: Date
}

private struct ShareMetadata {
    var resolvedURL: String?
    var title: String?
    var description: String?
    var imageData: Data?
}

private struct PendingReviewCandidate: Codable {
    var candidateName: String
    var address: String
    var category: String
    var sourceURL: String?
    var sourceText: String?
    var evidence: [String]
    var confidence: Double
    var missingInfo: [String]
    var savedAt: Date
}

private struct ShareMemoryRecord: Codable {
    var id: UUID
    var state: String
    var sourceURL: String?
    var sourceText: String?
    var title: String
    var placeName: String?
    var address: String?
    var evidence: [String]
    var createdAt: Date
}

// MARK: - Share Extension SwiftUI View

struct ShareExtensionView: View {
    weak var extensionContext: NSExtensionContext?
    @State private var sharedURL: String = ""
    @State private var sharedText: String = ""
    @State private var sharedTitle: String = ""
    @State private var parsedPlace: ParsedPlace?
    @State private var reviewCandidate: PendingReviewCandidate?
    @State private var reviewCandidates: [PendingReviewCandidate] = []
    @State private var isParsing = true
    @State private var isSaved = false
    @State private var savedReviewCandidateCount: Int?
    @State private var parseError: String?
    @State private var selectedCategory: String = "food"

    private let categories = ["food", "cafe", "bar", "attraction", "stay", "shopping"]

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if isParsing {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.72))
                                .frame(width: 84, height: 84)
                                .shadow(color: SaveTheme.berry.opacity(0.22), radius: 18, y: 8)
                            Text("🐾")
                                .font(.system(size: 34))
                            ProgressView()
                                .scaleEffect(0.9)
                                .tint(SaveTheme.berry)
                                .offset(y: 42)
                        }

                        Text("SAV-E is sniffing for a place...")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(SaveTheme.cocoa)
                    }
                    .frame(maxHeight: .infinity)
                } else if isSaved {
                    VStack(spacing: 16) {
                        Text("🌸")
                            .font(.system(size: 56))

                        Text(savedReviewCandidateCount == nil ? "Saved to SAV-E!" : "Tucked into Review")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "2C2C2E"))

                        Text(savedReviewCandidateCount.map { count in
                            count == 1
                                ? "Open SAV-E to finish importing this candidate into Review."
                                : "Open SAV-E to finish importing these \(count) candidates into Review."
                        } ?? "Open the app to see it on your map.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(24)
                    .background(SaveTheme.card)
                    .cornerRadius(28)
                    .shadow(color: SaveTheme.berry.opacity(0.16), radius: 20, y: 10)
                    .frame(maxHeight: .infinity)
                } else if let error = parseError {
                    VStack(spacing: 16) {
                        Text("🧸")
                            .font(.system(size: 46))
                        Text("SAV-E needs one more clue")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(Color(hex: "2C2C2E"))
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(SaveTheme.cocoa)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                        Text("Try sharing a map link, a clearer caption, or a frame with the place name 💌")
                            .font(.caption)
                            .foregroundColor(SaveTheme.rose)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(SaveTheme.card)
                    .cornerRadius(28)
                    .shadow(color: SaveTheme.berry.opacity(0.16), radius: 20, y: 10)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 20)
                } else if !reviewCandidates.isEmpty {
                    reviewCandidatesPreview(reviewCandidates)
                } else if let candidate = reviewCandidate {
                    reviewCandidatesPreview([candidate])
                } else if let place = parsedPlace {
                    placePreview(place)
                }
            }
            .background(
                LinearGradient(
                    colors: [SaveTheme.blush, SaveTheme.cream, SaveTheme.mint],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationTitle("SAV-E ✨")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        extensionContext?.cancelRequest(withError: NSError(domain: "com.wanderly", code: 0))
                    }
                }
            }
        }
        .task {
            await extractAndParse()
        }
    }

    // MARK: - Place Preview

    private func placePreview(_ place: ParsedPlace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Parsed place card
            VStack(alignment: .leading, spacing: 8) {
                Text("Ready to save Map Stamp")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Image(systemName: iconForCategory(selectedCategory))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color(hex: "C75B39"))
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name)
                            .font(.headline)
                            .foregroundColor(Color(hex: "2C2C2E"))
                        Text(place.address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let latitude = place.latitude,
                           let longitude = place.longitude {
                            Text(String(format: "%.5f, %.5f", latitude, longitude))
                                .font(.caption2)
                                .foregroundColor(SaveTheme.rose)
                        }
                    }

                    Spacer()

                    if let price = place.priceRange {
                        Text(price)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Dishes
                if !place.dishes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(place.dishes, id: \.self) { dish in
                                Text(dish)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "C75B39").opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(hex: "FFF8F0"))
            .cornerRadius(16)

            // Category selector
            Text("Category")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        Button(action: { selectedCategory = cat }) {
                            HStack(spacing: 4) {
                                Image(systemName: iconForCategory(cat))
                                    .font(.caption2)
                                Text(cat.capitalized)
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(cat == selectedCategory ? Color(hex: "C75B39") : Color(hex: "C75B39").opacity(0.1))
                            .foregroundColor(cat == selectedCategory ? .white : Color(hex: "C75B39"))
                            .cornerRadius(16)
                        }
                    }
                }
            }

            Spacer()

            // Save button
            Button(action: savePlace) {
                Text("Save Map Stamp")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "C75B39"))
                    .cornerRadius(16)
            }
        }
        .padding()
    }

    private func reviewCandidatesPreview(_ candidates: [PendingReviewCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(candidates.count == 1 ? "Tiny clue found" : "Tiny clues found")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(SaveTheme.rose)

                HStack {
                    Text("🔎")
                        .font(.system(size: 24))
                        .frame(width: 42, height: 42)
                        .background(SaveTheme.blush)
                        .cornerRadius(14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidates.count == 1 ? candidates[0].candidateName : "\(candidates.count) possible places")
                            .font(.headline)
                            .foregroundColor(Color(hex: "2C2C2E"))
                        Text(candidates.count == 1 ? (candidates[0].address.isEmpty ? "Needs address confirmation" : candidates[0].address) : "Review each candidate in SAV-E before saving.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                Text("SAV-E found a tiny place clue. Check the evidence, then hatch it into a saved memory.")
                    .font(.caption)
                    .foregroundColor(SaveTheme.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(SaveTheme.card)
            .cornerRadius(24)
            .shadow(color: SaveTheme.berry.opacity(0.13), radius: 18, y: 8)

            if candidates.count > 1 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(candidates.enumerated()), id: \.offset) { _, candidate in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(candidate.candidateName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(hex: "2C2C2E"))
                                Text(candidate.address.isEmpty ? "Needs address confirmation" : candidate.address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(SaveTheme.card)
                            .cornerRadius(14)
                        }
                    }
                }
            } else if let candidate = candidates.first, !candidate.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Evidence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(candidate.evidence.prefix(3), id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .foregroundColor(Color(hex: "2C2C2E"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer()

            Button(action: saveReviewCandidates) {
                Text(candidates.count == 1 ? "Add to Review 💌" : "Add \(candidates.count) to Review 💌")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SaveTheme.berry)
                    .cornerRadius(20)
                    .shadow(color: SaveTheme.berry.opacity(0.25), radius: 12, y: 6)
            }
        }
        .padding()
    }

    // MARK: - Extract & Parse

    private func extractAndParse() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            parseError = "No content to parse"
            isParsing = false
            return
        }

        // Extract URL or text
        for item in items {
            if let title = item.attributedTitle?.string, !title.isEmpty {
                sharedTitle = title
            }
            if let text = item.attributedContentText?.string, !text.isEmpty, sharedText.isEmpty {
                sharedText = text
            }

            guard let attachments = item.attachments else { continue }
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        sharedURL = url.absoluteString
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    if let text = try? await attachment.loadItem(forTypeIdentifier: UTType.text.identifier) as? String {
                        sharedText = text
                    }
                }
            }
        }

        let content = sharedURL.isEmpty ? sharedText : sharedURL
        guard !content.isEmpty else {
            parseError = "No URL or text found in shared content"
            isParsing = false
            return
        }

        let metadata = await shareMetadata(from: sharedURL)
        let parseContent = metadata.resolvedURL.flatMap { $0.isEmpty ? nil : $0 } ?? content

        if let mapPlace = deterministicMapPlace(from: parseContent, title: sharedTitle, text: sharedText) {
            parsedPlace = mapPlace
            selectedCategory = mapPlace.category
            isParsing = false
            return
        }

        if let sourceURL = URL(string: parseContent),
           isSocialURL(sourceURL) {
            let candidates = await socialAnalysisReviewCandidates(
                from: metadata,
                sharedTitle: sharedTitle,
                sharedText: sharedText,
                sourceURLString: parseContent
            )
            if !candidates.isEmpty {
                reviewCandidates = candidates
                selectedCategory = reviewCandidates.first?.category ?? "stay"
                isParsing = false
                return
            }
            saveSourceOnlyMemory(parseContent, reason: "No reliable social review candidate found")
            parseError = "SAV-E needs one more clue before it can review this social post. Share a map link, screenshot, or caption with a visible place name."
            isParsing = false
            return
        }

        let aiContent = [sharedTitle, sharedText, metadata.title, metadata.description, parseContent]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        // Parse with Gemini only when the shared URL does not contain usable map coordinates.
        do {
            guard hasMeaningfulPlaceContext(aiContent, sourceURLString: parseContent) else {
                throw NSError(domain: "wanderly", code: 4, userInfo: [NSLocalizedDescriptionKey: "Share a map link or a post with a visible place name so SAV-E does not guess the wrong city."])
            }
            let aiPlace = try await parseWithGemini(content: aiContent, sourceURLString: parseContent)
            if hasReliableCoordinates(aiPlace) {
                parsedPlace = aiPlace
                selectedCategory = aiPlace.category
            } else if let candidate = reviewCandidate(from: aiPlace, sourceURLString: parseContent, sourceText: aiContent) {
                reviewCandidate = candidate
                selectedCategory = candidate.category
            } else {
                throw NSError(domain: "wanderly", code: 5, userInfo: [NSLocalizedDescriptionKey: "SAV-E could not identify one exact place from this post. Share the map link or include the place name."])
            }
        } catch {
            saveSourceOnlyMemory(parseContent, reason: error.localizedDescription)
            parseError = userFacingParseError(from: error)
        }
        isParsing = false
    }

    // MARK: - Gemini Parsing

    private func parseWithGemini(content: String, sourceURLString: String) async throws -> ParsedPlace {
        guard let apiKey = geminiAPIKey(), !apiKey.isEmpty else {
            throw NSError(domain: "wanderly", code: 1, userInfo: [NSLocalizedDescriptionKey: "GEMINI_API_KEY not configured"])
        }

        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=\(apiKey)")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Extract place information from this shared content. Respond ONLY with a valid JSON object, no markdown.

        Content: \(content)

        Response schema:
        {
          "name": "Place Name",
          "address": "Full address",
          "category": "food" | "cafe" | "bar" | "attraction" | "stay" | "shopping",
          "latitude": null,
          "longitude": null,
          "dishes": ["dish1", "dish2"],
          "priceRange": "$$",
          "needsReview": false
        }

        Rules:
        - Extract the place name, address, and category only from explicit text, metadata, or map URL data
        - If it's a restaurant/food URL, extract recommended dishes
        - Use null for latitude and longitude unless exact coordinates are explicitly present in the source or map URL
        - Do not guess a city, address, or coordinates from a social URL alone
        - If the source says Beijing/北京, do not return a Shanghai/上海 place, and vice versa
        - If you can identify a likely place but exact coordinates are missing, keep the place fields and set latitude/longitude to null with needsReview true
        - If you cannot identify one exact place, set needsReview to true and use null for missing fields
        - Never use a popular default city or a plausible replacement place
        - category must be one of: food, cafe, bar, attraction, stay, shopping
        """

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.2, "maxOutputTokens": 512]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "wanderly", code: code, userInfo: [NSLocalizedDescriptionKey: "Gemini API error \(code)"])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let responseContent = candidates.first?["content"] as? [String: Any],
              let parts = responseContent["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw NSError(domain: "wanderly", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty AI response"])
        }

        // Parse JSON from response
        var jsonString = text
        if let start = text.range(of: "{"),
           let end = text.range(of: "}", options: .backwards),
           start.lowerBound < end.upperBound {
            jsonString = String(text[start.lowerBound..<end.upperBound])
        }
        guard let jsonData = jsonString.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(domain: "wanderly", code: 3, userInfo: [NSLocalizedDescriptionKey: "Couldn't parse AI response"])
        }

        let place = ParsedPlace(
            name: dict["name"] as? String ?? "Unknown Place",
            address: dict["address"] as? String ?? "",
            category: dict["category"] as? String ?? "food",
            iconName: iconForCategory(dict["category"] as? String ?? "food"),
            latitude: dict["latitude"] as? Double,
            longitude: dict["longitude"] as? Double,
            dishes: dict["dishes"] as? [String] ?? [],
            priceRange: dict["priceRange"] as? String
        )
        try validateAIPlace(place, against: content, sourceURLString: sourceURLString)
        return place
    }

    private func shareMetadata(from urlString: String) async -> ShareMetadata {
        guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
            return ShareMetadata()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let resolvedURL = response.url?.absoluteString ?? url.absoluteString
            let html = String(data: data.prefix(200_000), encoding: .utf8) ?? ""
            let imageData = await metadataImageData(in: html, baseURL: response.url ?? url)
            print("SAV-E share metadata imageData bytes=\(imageData?.count ?? 0)")
            return ShareMetadata(
                resolvedURL: resolvedURL,
                title: metadataValue(in: html, keys: ["og:title", "twitter:title", "title"]),
                description: metadataValue(in: html, keys: ["og:description", "twitter:description", "description"]),
                imageData: imageData
            )
        } catch {
            return ShareMetadata(resolvedURL: url.absoluteString, title: nil, description: nil)
        }
    }

    private func metadataImageData(in html: String, baseURL: URL) async -> Data? {
        guard let imageValue = metadataValue(in: html, keys: ["og:image", "twitter:image", "image"]),
              let imageURL = URL(string: imageValue, relativeTo: baseURL)?.absoluteURL,
              imageURL.scheme?.hasPrefix("http") == true else {
            return nil
        }

        var request = URLRequest(url: imageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard data.count <= 5_000_000,
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else {
                return nil
            }
            return data
        } catch {
            return nil
        }
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
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t\f]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s+"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
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

    private func socialReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> PendingReviewCandidate? {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        guard let handle = firstSocialHandle(in: evidenceText) else { return nil }

        let address = firstAddress(in: evidenceText) ?? locatedCity(in: evidenceText) ?? ""
        let resolved = SocialPlaceEvidenceScorer.resolvedDisplayName(fromSocialHandle: handle, evidenceText: evidenceText)
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty, isResolvedHandle: resolved.evidence != nil)
        let candidateName = resolved.name
        let category = fallbackCategory(from: evidenceText)
        var evidence = ["Instagram handle @\(handle)", "Evidence tier: \(tier.rawValue)"]
        if !sourceURLString.isEmpty {
            evidence.append("Source URL: \(sourceURLString)")
        }
        if let profileEvidence = resolved.evidence {
            evidence.append(profileEvidence)
        }
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(300)))
        }

        return PendingReviewCandidate(
            candidateName: candidateName,
            address: address,
            category: category,
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: min(0.58 + resolved.confidenceBoost, 0.85),
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func ocrFallbackReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) async -> PendingReviewCandidate? {
        guard let imageData = metadata.imageData else { return nil }
        let ocrLines = await recognizedTextLines(from: imageData)
        guard let result = SocialOCRCandidateHeuristics.candidate(from: ocrLines) else { return nil }

        let captionText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        let ocrText = ocrLines.joined(separator: "\n")
        let combinedText = [sourceURLString, captionText, ocrText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let category = fallbackCategory(from: ([result.name, captionText, ocrText].joined(separator: "\n")))
        let tier: SocialPlaceEvidenceTier = .weakCandidate
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "OCR-derived candidate: \(result.name)"
        ]
        if !ocrText.isEmpty {
            evidence.append("OCR text: \(String(ocrText.prefix(300)))")
        }
        if !result.supportingLines.isEmpty {
            evidence.append("OCR supporting lines: \(result.supportingLines.joined(separator: " | "))")
        }

        return PendingReviewCandidate(
            candidateName: result.name,
            address: "",
            category: category,
            sourceURL: sourceURLString,
            sourceText: combinedText,
            evidence: evidence,
            confidence: result.confidence,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(
                tier: tier,
                hasAddress: false,
                source: "OCR-derived candidate; verify venue identity"
            ),
            savedAt: Date()
        )
    }

    private func recognizedTextLines(from imageData: Data) async -> [String] {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return []
        }

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
    }

    private func captionNamedSocialReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> PendingReviewCandidate? {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        guard let name = bracketedPlaceName(in: evidenceText) else { return nil }
        let address = firstLocationPin(in: evidenceText) ?? streetAddressLine(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? firstAddress(in: evidenceText) ?? ""
        let category = fallbackCategory(from: "\(name) \(evidenceText)")
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "Public metadata named place: \(name)"
        ]
        if !address.isEmpty {
            evidence.append("Location clue: \(address)")
        }
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(300)))
        }

        return PendingReviewCandidate(
            candidateName: name,
            address: address,
            category: category,
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: address.isEmpty ? 0.5 : 0.62,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func captionVenueIntroReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> PendingReviewCandidate? {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        guard let name = venueIntroName(in: evidenceText) else { return nil }
        let address = firstLocationPin(in: evidenceText) ?? streetAddressLine(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? firstAddress(in: evidenceText) ?? ""
        let category = fallbackCategory(from: "\(name) \(evidenceText)")
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "Public metadata venue anchor: \(name)"
        ]
        if !address.isEmpty {
            evidence.append("Location clue: \(address)")
        }
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(300)))
        }

        return PendingReviewCandidate(
            candidateName: name,
            address: address,
            category: category,
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: address.isEmpty ? 0.56 : 0.66,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func chineseSocialTitleReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> PendingReviewCandidate? {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        guard let name = chineseVenueName(in: evidenceText) else { return nil }
        let address = firstLocationPin(in: evidenceText) ?? streetAddressLine(in: evidenceText) ?? locatedCity(in: evidenceText) ?? cityAddress(in: evidenceText) ?? firstAddress(in: evidenceText) ?? ""
        let category = fallbackCategory(from: "\(name) \(evidenceText)")
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "Public metadata named venue: \(name)"
        ]
        if !address.isEmpty {
            evidence.append("Location clue: \(address)")
        }
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(300)))
        }

        return PendingReviewCandidate(
            candidateName: name,
            address: address,
            category: category,
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: address.isEmpty ? 0.56 : 0.66,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: !address.isEmpty),
            savedAt: Date()
        )
    }

    private func captionLineSocialReviewCandidate(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> PendingReviewCandidate? {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        guard let inferred = inferredPlaceLineBeforeAddress(in: evidenceText) else { return nil }
        let category = fallbackCategory(from: "\(inferred.name) \(evidenceText)")
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: true)
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "Public metadata place line: \(inferred.name)",
            "Location clue: \(inferred.address)"
        ]
        if !evidenceText.isEmpty {
            evidence.append(String(evidenceText.prefix(300)))
        }
        return PendingReviewCandidate(
            candidateName: inferred.name,
            address: inferred.address,
            category: category,
            sourceURL: sourceURLString,
            sourceText: evidenceText.isEmpty ? nil : evidenceText,
            evidence: evidence,
            confidence: 0.6,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: true),
            savedAt: Date()
        )
    }

    private func socialAnalysisReviewCandidates(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) async -> [PendingReviewCandidate] {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        let ocrLines: [String]
        if let imageData = metadata.imageData {
            ocrLines = await recognizedTextLines(from: imageData)
        } else {
            ocrLines = []
        }

        let drafts = SocialPlaceParser().parse(
            evidence: SocialPlaceSourceEvidence(
                sourceURL: sourceURLString,
                resolvedURL: metadata.resolvedURL,
                sharedTitle: sharedTitle,
                sharedText: sharedText,
                metadataTitle: metadata.title,
                metadataDescription: metadata.description,
                ocrLines: ocrLines
            )
        )
        let candidates = drafts.map {
            pendingReviewCandidate(from: $0, sourceURLString: sourceURLString, sourceText: evidenceText, ocrLines: ocrLines)
        }

        return rankedSocialAnalysisCandidates(candidates.map(markAsSocialAnalysisCandidate))
    }

    private func pendingReviewCandidate(
        from draft: SocialPlaceCandidateDraft,
        sourceURLString: String,
        sourceText: String,
        ocrLines: [String]
    ) -> PendingReviewCandidate {
        let combinedSourceText = [sourceText, ocrLines.joined(separator: "\n")]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return PendingReviewCandidate(
            candidateName: draft.displayName,
            address: draft.locationClues.first ?? "",
            category: draft.category,
            sourceURL: sourceURLString,
            sourceText: combinedSourceText.isEmpty ? nil : combinedSourceText,
            evidence: evidenceStrings(from: draft, sourceURLString: sourceURLString),
            confidence: draft.confidence,
            missingInfo: draft.missingInfo,
            savedAt: Date()
        )
    }

    private func evidenceStrings(from draft: SocialPlaceCandidateDraft, sourceURLString: String) -> [String] {
        var values = sourceURLString.isEmpty ? [] : ["Source URL: \(sourceURLString)"]
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
        return appendUniqueEvidence([], values)
    }

    private func rankedSocialAnalysisCandidates(_ candidates: [PendingReviewCandidate]) -> [PendingReviewCandidate] {
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
        if evidence.contains("ocr-derived candidate") { score += 0.08 }
        if evidence.contains("named place") || evidence.contains("named venue") || evidence.contains("place line") || evidence.contains("venue name") { score += 0.16 }
        if evidence.contains("venue handle") { score += 0.08 }
        if evidence.contains("resolved public profile") { score += 0.12 }
        if evidence.contains("instagram handle") || evidence.contains("social handle") { score += 0.04 }
        if SocialPlaceEvidenceScorer.isRejectedTitle(candidate.candidateName) { score -= 1.0 }
        return score
    }

    private func markAsSocialAnalysisCandidate(_ candidate: PendingReviewCandidate) -> PendingReviewCandidate {
        var analyzed = candidate
        analyzed.evidence = appendUniqueEvidence(
            analyzed.evidence,
            ["Analysis pipeline: collected metadata/caption/OCR anchors, scored candidate evidence, and kept unresolved fields for review"]
        )
        return analyzed
    }

    private func appendUniqueEvidence(_ values: [String], _ newValues: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values + newValues {
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func socialReviewCandidates(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String,
        sourceURLString: String
    ) -> [PendingReviewCandidate] {
        let evidenceText = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        let lines = evidenceText
            .components(separatedBy: .newlines)
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }

        var sections: [(name: String, details: [String])] = []
        var currentName: String?
        var currentDetails: [String] = []

        for line in lines {
            if let name = numberedCandidateName(from: line) {
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

        let candidates: [PendingReviewCandidate] = sections.compactMap { section in
            let name = cleanPlaceName(section.name)
            guard isUsablePlaceName(name) else { return nil }
            let detailsText = section.details.joined(separator: "\n")
            let address = firstLocationPin(in: detailsText) ?? streetAddressLine(in: detailsText) ?? locatedCity(in: detailsText) ?? cityAddress(in: detailsText) ?? ""
            let tier = SocialPlaceEvidenceScorer.tier(hasAddress: !address.isEmpty)
            var evidence = [
                "Source URL: \(sourceURLString)",
                "Evidence tier: \(tier.rawValue)",
                "Public metadata candidate: \(name)"
            ]
            if !address.isEmpty {
                evidence.append("Location clue: \(address)")
            }
            if !detailsText.isEmpty {
                evidence.append(String(detailsText.prefix(300)))
            }

            return PendingReviewCandidate(
                candidateName: name,
                address: address,
                category: fallbackCategory(from: "\(name) \(detailsText)"),
                sourceURL: sourceURLString,
                sourceText: evidenceText.isEmpty ? nil : evidenceText,
                evidence: evidence,
                confidence: address.isEmpty ? 0.48 : 0.58,
                missingInfo: SocialPlaceEvidenceScorer.missingInfo(tier: tier, hasAddress: !address.isEmpty),
                savedAt: Date()
            )
        }

        var seenKeys = Set<String>()
        return candidates.filter { candidate in
            let key = "\(candidate.candidateName.lowercased())|\(candidate.address.lowercased())"
            guard !seenKeys.contains(key) else { return false }
            seenKeys.insert(key)
            return true
        }
    }

    private func numberedCandidateName(from line: String) -> String? {
        firstRegexCapture(in: line, pattern: #"^\s*(?:\d{1,2}[\.)]|[①②③④⑤⑥⑦⑧⑨])\s*([^\n\r]+)"#)
    }

    private func bracketedPlaceName(in content: String) -> String? {
        let patterns = [
            #"[\[【]\s*([^\]】]{2,80})\s*[\]】]"#,
            #"(?i)\b(?:at|spot|place)\s+([A-Z][A-Za-z0-9 &'._-]{2,60})\s*(?:[-–—|,]|\n)"#
        ]
        for pattern in patterns {
            if let match = firstRegexCapture(in: content, pattern: pattern) {
                let cleaned = cleanPlaceName(match)
                if isUsablePlaceName(cleaned) {
                    return cleaned
                }
            }
        }
        return nil
    }

    private func venueIntroName(in content: String) -> String? {
        let lines = content
            .components(separatedBy: .newlines)
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }

        for line in lines where looksLikeVenueIntroLine(line) {
            if let quoted = firstRegexCapture(in: line, pattern: #"[「『\"]\s*([^」』\"]{2,80})\s*[」』\"]"#) {
                let cleaned = cleanPlaceName(quoted)
                if isUsablePlaceName(cleaned), !looksLikeMarketingLine(cleaned) {
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

    private func chineseVenueName(in content: String) -> String? {
        let patterns = [
            #"(?:^|[\n\r])[-\s]*(?:[\u4e00-\u9fff]{0,4})?(?:全新開幕|新開幕|開幕)\s*([^\s新主题主題\-－—–:]{2,16})\s*(?:新主題|主题|主題)\s*[-－—–:]\s*([\u4e00-\u9fffA-Za-z0-9]{2,24})"#,
            #"([\u4e00-\u9fffA-Za-z0-9]{2,24})\s*[·・‧]\s*([\u4e00-\u9fffA-Za-z0-9]{2,24})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            guard let match = regex.firstMatch(in: content, range: range), match.numberOfRanges > 2,
                  let brandRange = Range(match.range(at: 1), in: content),
                  let themeRange = Range(match.range(at: 2), in: content) else { continue }
            let brand = cleanPlaceName(String(content[brandRange]))
            let theme = cleanPlaceName(String(content[themeRange]))
            let name = "\(brand)·\(theme)"
            if isUsablePlaceName(name), !looksLikeMarketingLine(name) {
                return name
            }
        }
        return nil
    }

    private func firstLocationPin(in content: String) -> String? {
        let patterns = [
            #"📍\s*([^\n\r\.]+)"#,
            #"\bLocation:\s*([^\n\r\.]+)"#
        ]
        for pattern in patterns {
            if let match = firstRegexCapture(in: content, pattern: pattern) {
                let cleaned = cleanHTMLText(match)
                if !cleaned.isEmpty { return cleaned }
            }
        }
        return nil
    }

    private func inferredPlaceLineBeforeAddress(in content: String) -> (name: String, address: String)? {
        let lines = content
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
                let candidate = cleanPlaceName(lines[previousIndex])
                if isLikelyCaptionPlaceName(candidate) {
                    return (candidate, line)
                }
                previousIndex -= 1
            }
        }
        return nil
    }

    private func streetAddressLine(in content: String) -> String? {
        let lines = content
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
        if let leadingName = firstRegexCapture(in: line, pattern: #"^([^/\n]{2,60})\s*/"#) {
            let cleaned = cleanPlaceName(leadingName)
            if isUsablePlaceName(cleaned),
               !looksLikeAddressLine(cleaned),
               !looksLikeOperatingHoursLine(cleaned),
               !looksLikeReviewMetricLine(cleaned),
               !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }

        let isVenueIntroLine = line.range(of: #"@|名店|插旗|開幕|新店|店名|餐廳|餐厅|restaurant"#, options: [.regularExpression, .caseInsensitive]) != nil
        if isVenueIntroLine,
           let quoted = firstRegexCapture(in: line, pattern: #"[「\"]\s*([^」\"]{2,60})\s*[」\"]"#) {
            let cleaned = cleanPlaceName(quoted)
            if isUsablePlaceName(cleaned), !looksLikeMarketingLine(cleaned) {
                return cleaned
            }
        }
        if let handle = firstRegexCapture(in: line, pattern: #"@([A-Za-z0-9._]{3,30})"#) {
            let cleaned = SocialPlaceEvidenceScorer.resolvedDisplayName(fromSocialHandle: handle).name
            if isUsablePlaceName(cleaned), !looksLikeMarketingLine(cleaned) {
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

    private func cityAddress(in content: String) -> String? {
        firstRegexCapture(in: content, pattern: #"\b([A-Z][A-Za-z .'-]{2,40},\s*(?:CA|NY|TX|FL|WA|IL|NV|AZ|OR|MA|HI|UT|CO|Bali|Indonesia|Chongqing|China))\b"#)
            .map(cleanHTMLText)
    }

    private func locatedCity(in content: String) -> String? {
        firstRegexCapture(in: content, pattern: #"(?i)\b(?:located|based)\s+in\s+([A-Z][A-Za-z .'-]{2,40})(?:[.!?,\n\r]|$)"#)
            .map(cleanHTMLText)
    }

    private func publicMetadataEvidence(from metadata: ShareMetadata, sharedTitle: String, sharedText: String) -> String {
        [sharedTitle, sharedText, metadata.title, metadata.description]
            .compactMap { $0 }
            .map(cleanHTMLText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func firstPlaceName(in content: String) -> String? {
        let patterns = [
            #"[\[【]\s*([^\]】]{2,80})\s*[\]】]"#
        ]

        for pattern in patterns {
            if let match = firstRegexCapture(in: content, pattern: pattern) {
                let cleaned = cleanPlaceName(match)
                if isUsablePlaceName(cleaned) {
                    return cleaned
                }
            }
        }
        return nil
    }

    private func firstAddress(in content: String) -> String? {
        let patterns = [
            #"\b\d{1,6}\s+[A-Za-z0-9][A-Za-z0-9 .,'#&/-]+,\s*[A-Za-z .'-]+,\s*[A-Z]{2}\s+\d{5}(?:-\d{4})?\b"#,
            #"\b\d{1,6}\s+[A-Za-z0-9][A-Za-z0-9 .,'#&/-]+,\s*[A-Za-z .'-]+,\s*(?:CA|NY|TX|FL|WA|IL|NV|AZ|OR|MA)\b"#
        ]

        for pattern in patterns {
            if let match = firstRegexMatch(in: content, pattern: pattern) {
                return cleanHTMLText(match)
            }
        }
        return nil
    }

    private func firstSocialHandle(in content: String) -> String? {
        let ignoredHandles: Set<String> = [
            "instagram", "reels", "reel", "explore", "threads", "tiktok", "xiaohongshu", "wanderly", "save"
        ]
        guard let regex = try? NSRegularExpression(pattern: #"@([A-Za-z0-9._]{3,30})"#) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, range: range)

        for match in matches {
            guard match.numberOfRanges > 1,
                  let handleRange = Range(match.range(at: 1), in: content) else { continue }
            let handle = String(content[handleRange]).lowercased()
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

    private func firstRegexCapture(in content: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: content) else {
            return nil
        }
        return String(content[captureRange])
    }

    private func firstRegexMatch(in content: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              let matchRange = Range(match.range, in: content) else {
            return nil
        }
        return String(content[matchRange])
    }

    private func cleanPlaceName(_ value: String) -> String {
        SocialPlaceEvidenceScorer.cleanCandidateName(value)
    }

    private func isUsablePlaceName(_ value: String) -> Bool {
        SocialPlaceEvidenceScorer.isUsableCandidateName(value)
    }

    private func dishHints(from content: String) -> [String] {
        let keywords = ["matcha", "hojicha", "latte", "coffee", "tea", "ramen", "noodle", "pizza", "taco", "burger", "sushi", "dessert"]
        let lowercased = content.lowercased()
        return keywords.filter { lowercased.contains($0) }.prefix(4).map { keyword in
            keyword.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
        }
    }

    private func priceRangeHint(from content: String) -> String? {
        if content.range(of: #"\$\d+"#, options: .regularExpression) != nil {
            return "$$"
        }
        return nil
    }

    private func hasMeaningfulPlaceContext(_ content: String, sourceURLString: String) -> Bool {
        guard let url = URL(string: sourceURLString),
              isSocialURL(url) else {
            return true
        }

        let withoutURLs = content
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b[a-z0-9.-]+\.(com|net|cn|link)\S*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let hasCityOrAddress = withoutURLs.range(of: #"(北京|上海|广州|深圳|成都|杭州|Tokyo|Beijing|Shanghai|Los Angeles|New York|San Francisco|\d{1,5}\s+\S+)"#, options: [.regularExpression, .caseInsensitive]) != nil
        let hasEnoughText = withoutURLs.count >= 8
        return hasCityOrAddress || hasEnoughText
    }

    private func validateAIPlace(_ place: ParsedPlace, against content: String, sourceURLString: String) throws {
        let combinedPlace = "\(place.name) \(place.address)".lowercased()
        let source = content.lowercased()
        let conflicts = [
            ("北京", "beijing", "上海", "shanghai"),
            ("上海", "shanghai", "北京", "beijing")
        ]

        for (sourceChinese, sourceEnglish, wrongChinese, wrongEnglish) in conflicts {
            let sourceMentionsCity = source.contains(sourceChinese) || source.contains(sourceEnglish)
            let placeMentionsWrongCity = combinedPlace.contains(wrongChinese) || combinedPlace.contains(wrongEnglish)
            if sourceMentionsCity && placeMentionsWrongCity {
                throw NSError(domain: "wanderly", code: 7, userInfo: [NSLocalizedDescriptionKey: "The parsed place conflicts with the city in the post. Share the exact map link to avoid saving the wrong place."])
            }
        }

        if let url = URL(string: sourceURLString), isSocialURL(url), place.name == "Unknown Place" {
            throw NSError(domain: "wanderly", code: 8, userInfo: [NSLocalizedDescriptionKey: "SAV-E could not identify one exact place from this social post."])
        }
    }

    private func hasReliableCoordinates(_ place: ParsedPlace) -> Bool {
        guard let latitude = place.latitude,
              let longitude = place.longitude else {
            return false
        }
        return isValidCoordinate(latitude: latitude, longitude: longitude)
    }

    private func reviewCandidate(from place: ParsedPlace, sourceURLString: String, sourceText: String) -> PendingReviewCandidate? {
        let name = cleanPlaceName(place.name)
        guard isUsablePlaceName(name), name != "Unknown Place" else { return nil }

        let hasAddress = !place.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let tier = SocialPlaceEvidenceScorer.tier(hasAddress: hasAddress)
        var evidence = [
            "Source URL: \(sourceURLString)",
            "Evidence tier: \(tier.rawValue)",
            "AI extracted review candidate: \(name)",
            "No reliable coordinates in source; kept out of Map Stamp"
        ]
        if hasAddress {
            evidence.append("Location clue: \(place.address)")
        }
        if !sourceText.isEmpty {
            evidence.append(String(sourceText.prefix(300)))
        }

        return PendingReviewCandidate(
            candidateName: name,
            address: place.address,
            category: place.category,
            sourceURL: sourceURLString,
            sourceText: sourceText.isEmpty ? nil : sourceText,
            evidence: evidence,
            confidence: hasAddress ? 0.62 : 0.52,
            missingInfo: SocialPlaceEvidenceScorer.missingInfo(
                tier: tier,
                hasAddress: hasAddress,
                source: "Gemini extracted a likely place but did not provide verified coordinates"
            ),
            savedAt: Date()
        )
    }

    private func isSocialURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "xhslink.com" ||
            host.hasSuffix("xiaohongshu.com") ||
            host.hasSuffix("instagram.com") ||
            host.hasSuffix("threads.net") ||
            host.hasSuffix("threads.com") ||
            host.hasSuffix("tiktok.com") ||
            host.hasSuffix("douyin.com")
    }

    private func deterministicMapPlace(from content: String, title: String, text: String) -> ParsedPlace? {
        guard let url = URL(string: content),
              isMapURL(url),
              let coordinates = mapCoordinates(from: url) else {
            return nil
        }

        let name = bestMapName(from: url, title: title, text: text)
        guard !name.isEmpty else { return nil }

        let address = mapAddress(from: url, text: text)
        let category = fallbackCategory(from: [name, address, text].joined(separator: " "))

        return ParsedPlace(
            name: name,
            address: address,
            category: category,
            iconName: iconForCategory(category),
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            dishes: [],
            priceRange: nil
        )
    }

    private func isMapURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "maps.apple.com" { return true }
        if host == "maps.app.goo.gl" || host == "goo.gl" || host == "g.co" { return true }
        if host == "maps.google.com" { return true }
        return (host == "google.com" || host.hasSuffix(".google.com")) && url.path.lowercased().hasPrefix("/maps")
    }

    private func mapCoordinates(from url: URL) -> (latitude: Double, longitude: Double)? {
        let full = [url.path, url.query ?? "", url.fragment ?? ""].joined(separator: "?")

        if let match = full.firstMatch(of: #/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/#),
           let lat = Double(match.1),
           let lng = Double(match.2),
           isValidCoordinate(latitude: lat, longitude: lng) {
            return (lat, lng)
        }

        if let match = full.firstMatch(of: #/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/#),
           let lat = Double(match.1),
           let lng = Double(match.2),
           isValidCoordinate(latitude: lat, longitude: lng) {
            return (lat, lng)
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for key in ["ll", "sll", "center"] {
            if let value = components?.queryItems?.first(where: { $0.name == key })?.value,
               let coordinate = coordinatePair(from: value) {
                return coordinate
            }
        }

        if let q = components?.queryItems?.first(where: { $0.name == "q" })?.value,
           let coordinate = coordinatePair(from: q) {
            return coordinate
        }

        return nil
    }

    private func coordinatePair(from value: String) -> (latitude: Double, longitude: Double)? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = cleaned.split(separator: ",", maxSplits: 1).map { String($0) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lng = Double(parts[1]),
              isValidCoordinate(latitude: lat, longitude: lng) else {
            return nil
        }
        return (lat, lng)
    }

    private func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180 && !(latitude == 0 && longitude == 0)
    }

    private func bestMapName(from url: URL, title: String, text: String) -> String {
        for candidate in [cleanFallbackName(title), queryName(from: url.absoluteString), cleanFallbackName(text)] {
            let cleaned = cleanFallbackName(candidate)
            if !cleaned.isEmpty,
               !cleaned.hasPrefix("http://"),
               !cleaned.hasPrefix("https://"),
               !cleaned.contains("@") {
                return cleaned
            }
        }
        return ""
    }

    private func mapAddress(from url: URL, text: String) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        for key in ["address", "daddr", "destination"] {
            if let value = components?.queryItems?.first(where: { $0.name == key })?.value,
               coordinatePair(from: value) == nil,
               !value.isEmpty {
                return value
            }
        }
        return fallbackAddress(from: text)
    }

    private func queryName(from content: String) -> String {
        guard let url = URL(string: content),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return ""
        }

        for key in ["q", "query", "search", "destination", "daddr"] {
            if let value = components.queryItems?.first(where: { $0.name == key })?.value, !value.isEmpty {
                return value
            }
        }

        let decodedPath = url.path.removingPercentEncoding ?? url.path
        for prefix in ["/maps/place/", "/maps/search/"] {
            if decodedPath.hasPrefix(prefix) {
                let value = decodedPath
                    .dropFirst(prefix.count)
                    .split(separator: "/")
                    .first
                    .map(String.init) ?? ""
                return value.replacingOccurrences(of: "+", with: " ")
            }
        }

        return decodedPath
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func cleanFallbackName(_ value: String) -> String {
        value
            .replacingOccurrences(of: " - Google Maps", with: "")
            .replacingOccurrences(of: "| Google Maps", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fallbackAddress(from text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.first(where: { line in
            line.range(of: #"\d+ .+"#, options: .regularExpression) != nil
        }) ?? ""
    }

    private func fallbackCategory(from content: String) -> String {
        let value = content.lowercased()
        let stayCategoryPattern = #"\b(inn|guest ?house|ryokan|motel)\b|酒店|飯店|饭店|旅館|旅馆|旅店|旅宿|民宿|客棧|客栈|度假村|ホテル|ゲストハウス|료칸|호텔|리조트|모텔|여관|여인숙|게스트하우스"#
        if value.contains("cafe") || value.contains("coffee") || value.contains("tea") { return "cafe" }
        if value.contains("bar") || value.contains("cocktail") { return "bar" }
        if value.contains("hotel") || value.contains("stay") || value.contains("resort") || content.range(of: stayCategoryPattern, options: [.regularExpression, .caseInsensitive]) != nil { return "stay" }
        if value.contains("shop") || value.contains("store") { return "shopping" }
        if value.contains("bakery") || value.contains("restaurant") || value.contains("food") || value.contains("dessert") || value.contains("cake") { return "food" }
        if content.range(of: #"晚餐|餐廳|餐厅|美食|咖啡|茶|酒吧|料理|餐|燒肉|烧肉|火鍋|火锅|牛舌|巴斯克|蛋糕|甜點|甜点"#, options: .regularExpression) != nil { return "food" }
        return "attraction"
    }

    private func userFacingParseError(from error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == 429 {
            return "AI is busy right now. Try again in a minute."
        }
        if nsError.code == 401 || nsError.code == 403 {
            return "AI access needs attention."
        }
        return error.localizedDescription
    }

    private func geminiAPIKey() -> String? {
        // Try environment variable first, then Secrets.plist in shared App Group
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            return key
        }
        // Try reading from main app bundle's Secrets.plist via App Group
        // For now, try the extension's own bundle
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let value = dict["GEMINI_API_KEY"],
              value != "YOUR_KEY_HERE" else { return nil }
        return value
    }

    // MARK: - Save

    private func savePlace() {
        guard let place = parsedPlace else { return }
        guard let latitude = place.latitude,
              let longitude = place.longitude,
              isValidCoordinate(latitude: latitude, longitude: longitude) else {
            if let candidate = reviewCandidate(
                from: place,
                sourceURLString: sharedURL.isEmpty ? sharedText : sharedURL,
                sourceText: sharedText
            ) {
                reviewCandidate = candidate
                parsedPlace = nil
                return
            }
            parseError = "SAV-E needs reliable coordinates before saving a Map Stamp."
            return
        }

        let pendingPlace = PendingSharedPlace(
            name: place.name,
            address: place.address,
            category: selectedCategory,
            latitude: latitude,
            longitude: longitude,
            dishes: place.dishes,
            priceRange: place.priceRange,
            sourceURL: sharedURL.isEmpty ? nil : sharedURL,
            sourceText: sharedText.isEmpty ? nil : sharedText,
            savedAt: Date()
        )

        guard let fileURL = appGroupFileURL(named: WanderlySharedStorage.pendingPlacesFileName) else {
            parseError = "Shared app storage is unavailable"
            return
        }
        guard appendPendingItems([pendingPlace], to: fileURL, as: PendingSharedPlace.self) else { return }

        savedReviewCandidateCount = nil
        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func saveReviewCandidates() {
        let candidates = reviewCandidates.isEmpty ? reviewCandidate.map { [$0] } ?? [] : reviewCandidates
        guard !candidates.isEmpty else { return }
        guard let fileURL = appGroupFileURL(named: WanderlySharedStorage.pendingReviewCandidatesFileName) else {
            parseError = "Shared app storage is unavailable"
            return
        }

        guard appendPendingItems(candidates, to: fileURL, as: PendingReviewCandidate.self) else { return }

        savedReviewCandidateCount = candidates.count
        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func saveSourceOnlyMemory(_ source: String, reason: String) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WanderlySharedStorage.appGroupSuiteName) else {
            return
        }

        let fileURL = containerURL.appendingPathComponent("save-memory-records.json")
        var records = loadMemoryRecords(from: fileURL)
        let record = ShareMemoryRecord(
            id: UUID(),
            state: "source_only",
            sourceURL: URL(string: source)?.absoluteString ?? (sharedURL.isEmpty ? nil : sharedURL),
            sourceText: sharedText.isEmpty ? reason : sharedText,
            title: sharedTitle.isEmpty ? (URL(string: source)?.host() ?? "Shared source") : sharedTitle,
            placeName: nil,
            address: nil,
            evidence: [reason].filter { !$0.isEmpty },
            createdAt: Date()
        )
        records.insert(record, at: 0)

        guard let data = try? JSONEncoder.shareMemory.encode(records) else { return }
        _ = write(data, to: fileURL)
    }

    private func loadMemoryRecords(from fileURL: URL) -> [ShareMemoryRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder.shareMemory.decode([ShareMemoryRecord].self, from: data)) ?? []
    }

    private func appGroupFileURL(named fileName: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WanderlySharedStorage.appGroupSuiteName)?
            .appendingPathComponent(fileName)
    }

    private func appendPendingItems<Element: Codable>(_ items: [Element], to fileURL: URL, as elementType: Element.Type) -> Bool {
        guard !items.isEmpty else { return true }

        var success = false
        let coordinated = coordinate(fileURL, purpose: "append pending queue") {
            do {
                let existing = try loadArray([Element].self, from: fileURL)
                let data = try JSONEncoder().encode(existing + items)
                success = write(data, to: fileURL)
            } catch {
                parseError = "Couldn't read shared app storage"
                success = false
            }
        }
        return coordinated && success
    }

    private func loadArray<Element: Decodable>(_ type: [Element].Type, from fileURL: URL) throws -> [Element] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(type, from: data)
    }

    private func coordinate(_ fileURL: URL, purpose: String, _ work: () -> Void) -> Bool {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: fileURL, options: [], error: &coordinationError) { _ in
            work()
        }
        if coordinationError != nil {
            parseError = "Couldn't coordinate shared app storage"
            return false
        }
        return true
    }

    private func write(_ data: Data, to fileURL: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            parseError = "Couldn't write shared app storage"
            return false
        }
    }

    // MARK: - Helpers

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "food": return "fork.knife"
        case "cafe": return "cup.and.saucer.fill"
        case "bar": return "wineglass.fill"
        case "attraction": return "star.fill"
        case "stay": return "bed.double.fill"
        case "shopping": return "bag.fill"
        default: return "mappin"
        }
    }
}

private extension JSONEncoder {
    static var shareMemory: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var shareMemory: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Hex Color (standalone for extension target)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
