import UIKit
import SwiftUI
import UniformTypeIdentifiers
import CoreLocation

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
    var latitude: Double
    var longitude: Double
    var dishes: [String]
    var priceRange: String?
}

private enum WanderlySharedStorage {
    static let appGroupSuiteName = "group.com.wanderly.app"
    static let pendingPlacesKey = "pendingPlaces"
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
}

// MARK: - Share Extension SwiftUI View

struct ShareExtensionView: View {
    weak var extensionContext: NSExtensionContext?
    @State private var sharedURL: String = ""
    @State private var sharedText: String = ""
    @State private var sharedTitle: String = ""
    @State private var parsedPlace: ParsedPlace?
    @State private var isParsing = true
    @State private var isSaved = false
    @State private var parseError: String?
    @State private var selectedCategory: String = "food"

    private let categories = ["food", "cafe", "bar", "attraction", "stay", "shopping"]

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if isParsing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(Color(hex: "C75B39"))

                        Text("AI is parsing the shared content...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if isSaved {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(Color(hex: "A8B5A0"))

                        Text("Saved to SAV-E!")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "2C2C2E"))

                        Text("Open the app to see it on your map.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if let error = parseError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(Color(hex: "C75B39"))
                        Text("Couldn't parse this content")
                            .font(.headline)
                            .foregroundColor(Color(hex: "2C2C2E"))
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                    .padding()
                } else if let place = parsedPlace {
                    placePreview(place)
                }
            }
            .background(Color(hex: "FFF8F0"))
            .navigationTitle("Save Place")
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
                Text("Detected Place")
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
                Text("Save to Map")
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
           isSocialURL(sourceURL),
           let metadataPlace = await deterministicSocialMetadataPlace(
            from: metadata,
            sharedTitle: sharedTitle,
            sharedText: sharedText
           ) {
            parsedPlace = metadataPlace
            selectedCategory = metadataPlace.category
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
            parsedPlace = try await parseWithGemini(content: aiContent, sourceURLString: parseContent)
            selectedCategory = parsedPlace?.category ?? "food"
        } catch {
            let isSocialSource = URL(string: parseContent).map(isSocialURL) ?? false
            if !isSocialSource,
               let fallback = fallbackPlace(from: parseContent, title: sharedTitle, text: sharedText),
               isValidCoordinate(latitude: fallback.latitude, longitude: fallback.longitude) {
                parsedPlace = fallback
                selectedCategory = fallback.category
            } else {
                parseError = userFacingParseError(from: error)
            }
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
          "latitude": 0.0,
          "longitude": 0.0,
          "dishes": ["dish1", "dish2"],
          "priceRange": "$$",
          "needsReview": false
        }

        Rules:
        - Extract the place name, address, and category only from explicit text, metadata, or map URL data
        - If it's a restaurant/food URL, extract recommended dishes
        - Do not guess a city, address, or coordinates from a social URL alone
        - If the source says Beijing/北京, do not return a Shanghai/上海 place, and vice versa
        - If you cannot identify one exact place, set needsReview to true and use latitude 0.0, longitude 0.0
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

        if dict["needsReview"] as? Bool == true {
            throw NSError(domain: "wanderly", code: 5, userInfo: [NSLocalizedDescriptionKey: "SAV-E could not identify one exact place from this post. Share the map link or include the place name."])
        }

        let place = ParsedPlace(
            name: dict["name"] as? String ?? "Unknown Place",
            address: dict["address"] as? String ?? "",
            category: dict["category"] as? String ?? "food",
            iconName: iconForCategory(dict["category"] as? String ?? "food"),
            latitude: dict["latitude"] as? Double ?? 0,
            longitude: dict["longitude"] as? Double ?? 0,
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
            return ShareMetadata(
                resolvedURL: resolvedURL,
                title: metadataValue(in: html, keys: ["og:title", "twitter:title", "title"]),
                description: metadataValue(in: html, keys: ["og:description", "twitter:description", "description"])
            )
        } catch {
            return ShareMetadata(resolvedURL: url.absoluteString, title: nil, description: nil)
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
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#034;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deterministicSocialMetadataPlace(
        from metadata: ShareMetadata,
        sharedTitle: String,
        sharedText: String
    ) async -> ParsedPlace? {
        let evidence = publicMetadataEvidence(from: metadata, sharedTitle: sharedTitle, sharedText: sharedText)
        guard let address = firstAddress(in: evidence),
              let name = firstPlaceName(in: evidence) else {
            return nil
        }

        guard let coordinates = await geocodeAddress(address) else {
            return nil
        }

        let category = fallbackCategory(from: evidence)
        return ParsedPlace(
            name: name,
            address: address,
            category: category,
            iconName: iconForCategory(category),
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            dishes: dishHints(from: evidence),
            priceRange: priceRangeHint(from: evidence)
        )
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

    private func geocodeAddress(_ address: String) async -> (latitude: Double, longitude: Double)? {
        await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(address) { placemarks, _ in
                guard let coordinate = placemarks?.first?.location?.coordinate,
                      self.isValidCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (coordinate.latitude, coordinate.longitude))
            }
        }
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
        cleanHTMLText(value)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]【】\"'“”.,:;! "))
            .split(separator: "\n")
            .first
            .map(String.init) ?? ""
    }

    private func isUsablePlaceName(_ value: String) -> Bool {
        let lowered = value.lowercased()
        guard value.count >= 2,
              value.count <= 80,
              !lowered.contains("instagram"),
              !lowered.contains("reel"),
              !lowered.contains("comment"),
              !lowered.contains("like") else {
            return false
        }
        return true
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
        guard isValidCoordinate(latitude: place.latitude, longitude: place.longitude) else {
            throw NSError(domain: "wanderly", code: 6, userInfo: [NSLocalizedDescriptionKey: "SAV-E could not find reliable coordinates for this post. Share the map link to save it accurately."])
        }

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

    private func fallbackPlace(from content: String, title: String, text: String) -> ParsedPlace? {
        let candidateName = bestFallbackName(content: content, title: title, text: text)
        guard let name = candidateName, !name.isEmpty else { return nil }

        let category = fallbackCategory(from: [name, content, text].joined(separator: " "))
        let coordinates = fallbackCoordinates(from: [name, content, text].joined(separator: " "))

        return ParsedPlace(
            name: name,
            address: fallbackAddress(from: text),
            category: category,
            iconName: iconForCategory(category),
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            dishes: [],
            priceRange: nil
        )
    }

    private func bestFallbackName(content: String, title: String, text: String) -> String? {
        for candidate in [title, queryName(from: content), text] {
            let cleaned = cleanFallbackName(candidate)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        return nil
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
        if value.contains("cafe") || value.contains("coffee") { return "cafe" }
        if value.contains("bar") || value.contains("cocktail") { return "bar" }
        if value.contains("hotel") || value.contains("stay") { return "stay" }
        if value.contains("shop") || value.contains("store") { return "shopping" }
        if value.contains("bakery") || value.contains("restaurant") || value.contains("food") { return "food" }
        return "attraction"
    }

    private func fallbackCoordinates(from content: String) -> (latitude: Double, longitude: Double) {
        let value = content.lowercased()
        if value.contains("san francisco") {
            return (37.7749, -122.4194)
        }
        return (0, 0)
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

        let pendingPlace = PendingSharedPlace(
            name: place.name,
            address: place.address,
            category: selectedCategory,
            latitude: place.latitude,
            longitude: place.longitude,
            dishes: place.dishes,
            priceRange: place.priceRange,
            sourceURL: sharedURL.isEmpty ? nil : sharedURL,
            sourceText: sharedText.isEmpty ? nil : sharedText,
            savedAt: Date()
        )

        guard let defaults = UserDefaults(suiteName: WanderlySharedStorage.appGroupSuiteName) else {
            parseError = "Shared app storage is unavailable"
            return
        }
        var pending = loadPendingPlaces(from: defaults)
        pending.append(pendingPlace)
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: WanderlySharedStorage.pendingPlacesKey)
        } else {
            parseError = "Couldn't save this place"
            return
        }

        isSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func loadPendingPlaces(from defaults: UserDefaults) -> [PendingSharedPlace] {
        guard let data = defaults.data(forKey: WanderlySharedStorage.pendingPlacesKey) else {
            return []
        }
        return (try? JSONDecoder().decode([PendingSharedPlace].self, from: data)) ?? []
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
