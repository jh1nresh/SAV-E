import Foundation

struct GoogleMapsListPlaceCandidate: Equatable {
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var evidence: [String]
}

/// Share-sheet parser for public Google Maps saved-list links.
/// Keep this path separate from Google Takeout bulk file parsing.
enum GoogleMapsListPlaceExtractor {
    static func looksLikeGoogleMapsList(sourceURL: String, title: String?, text: String?, metadataTitle: String?, metadataDescription: String?) -> Bool {
        let combined = [sourceURL, title, text, metadataTitle, metadataDescription]
            .compactMap { $0 }
            .joined(separator: "\n")
            .lowercased()

        guard combined.contains("google.com") || combined.contains("maps.app.goo.gl") || combined.contains("maps.google") else {
            return false
        }

        return combined.contains("/maps/placelists") ||
            combined.contains("/maps/list") ||
            combined.contains("/maps/@") && combined.contains("saved") ||
            combined.contains("google maps") && (combined.contains(" · ") || combined.contains("places") || combined.contains("saved"))
    }

    static func extractCandidates(sourceURL: String, title: String?, text: String?, metadataTitle: String?, metadataDescription: String?, htmlText: String?) -> [GoogleMapsListPlaceCandidate] {
        let evidenceText = [text, metadataTitle, metadataDescription, htmlText]
            .compactMap { $0 }
            .joined(separator: "\n")

        var candidates: [GoogleMapsListPlaceCandidate] = []
        candidates.append(contentsOf: candidatesFromGooglePlaceLinks(in: evidenceText))
        candidates.append(contentsOf: candidatesFromPlainPlaceLines(in: [text, metadataDescription].compactMap { $0 }.joined(separator: "\n")))

        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let cleaned = cleanPlaceName(candidate.name)
            guard isUsablePlaceName(cleaned, listTitle: title ?? metadataTitle ?? "") else { return nil }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return GoogleMapsListPlaceCandidate(
                name: cleaned,
                address: candidate.address,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                evidence: candidate.evidence
            )
        }
    }

    private static func candidatesFromGooglePlaceLinks(in text: String) -> [GoogleMapsListPlaceCandidate] {
        guard !text.isEmpty else { return [] }
        let patterns = [
            #"(?i)(?:https?:\\/\\/)?(?:www\.)?google\.com/maps/place/([^\"'<>?#]+)"#,
            #"(?i)(?:https?:\\/\\/)?(?:www\.)?google\.com/maps/search/([^\"'<>?#]+)"#,
            #"(?i)/maps/place/([^\"'<>?#]+)"#,
            #"(?i)/maps/search/([^\"'<>?#]+)"#
        ]

        var results: [GoogleMapsListPlaceCandidate] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for match in matches where match.numberOfRanges > 1 {
                let raw = nsText.substring(with: match.range(at: 1))
                let name = decodeGooglePathComponent(raw)
                guard !name.isEmpty else { continue }
                let nearby = nearbyText(in: nsText, around: match.range, radius: 280)
                let coordinate = coordinateNearGoogleLink(in: nearby)
                let address = firstAddressLine(in: nearby) ?? ""
                results.append(GoogleMapsListPlaceCandidate(
                    name: name,
                    address: address,
                    latitude: coordinate?.latitude,
                    longitude: coordinate?.longitude,
                    evidence: ["Found Google Maps place link: \(name)"]
                ))
            }
        }
        return results
    }

    private static func candidatesFromPlainPlaceLines(in text: String) -> [GoogleMapsListPlaceCandidate] {
        let lines = text
            .components(separatedBy: .newlines)
            .map { cleanPlaceName($0) }
            .filter { !$0.isEmpty }

        var results: [GoogleMapsListPlaceCandidate] = []
        for (index, line) in lines.enumerated() {
            guard isUsablePlaceName(line, listTitle: "") else { continue }
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            let address = SocialPlaceEvidenceScorer.looksLikeAddressLine(next) ? next : ""
            if !address.isEmpty || line.range(of: #"(?i)(restaurant|cafe|coffee|bakery|bar|bistro|taco|sushi|ramen|pizza|茶|咖啡|餐廳|餐厅|美食)"#, options: .regularExpression) != nil {
                results.append(GoogleMapsListPlaceCandidate(
                    name: line,
                    address: address,
                    latitude: nil,
                    longitude: nil,
                    evidence: ["Found place-like line in shared Google Maps list: \(line)"]
                ))
            }
        }
        return results
    }

    private static func decodeGooglePathComponent(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\\u0026.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"/@.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[&?].*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding ?? value
    }

    private static func cleanPlaceName(_ value: String) -> String {
        SocialPlaceEvidenceScorer.cleanCandidateName(value)
            .replacingOccurrences(of: " - Google Maps", with: "")
            .replacingOccurrences(of: "| Google Maps", with: "")
            .replacingOccurrences(of: "Google Maps", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " [](){}<>|•·,;\"'"))
    }

    private static func isUsablePlaceName(_ name: String, listTitle: String) -> Bool {
        let lower = name.lowercased()
        let listLower = listTitle.lowercased()
        guard SocialPlaceEvidenceScorer.isUsableCandidateName(name),
              name.count >= 2,
              name.count <= 90,
              !lower.hasPrefix("http"),
              !lower.contains("google"),
              !lower.contains("maps"),
              !lower.contains("directions"),
              !lower.contains("share"),
              !lower.contains("reviews"),
              !lower.contains("photos"),
              !lower.contains("save to"),
              lower != listLower else {
            return false
        }
        return true
    }

    private static func nearbyText(in text: NSString, around range: NSRange, radius: Int) -> String {
        let start = max(0, range.location - radius)
        let end = min(text.length, range.location + range.length + radius)
        return text.substring(with: NSRange(location: start, length: end - start))
    }

    private static func coordinateNearGoogleLink(in text: String) -> (latitude: Double, longitude: Double)? {
        let patterns = [
            #"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)"#,
            #"@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsText = text as NSString
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)), match.numberOfRanges > 2,
                  let latitude = Double(nsText.substring(with: match.range(at: 1))),
                  let longitude = Double(nsText.substring(with: match.range(at: 2))),
                  latitude >= -90, latitude <= 90, longitude >= -180, longitude <= 180, !(latitude == 0 && longitude == 0) else {
                continue
            }
            return (latitude, longitude)
        }
        return nil
    }

    private static func firstAddressLine(in text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { SocialPlaceEvidenceScorer.cleanText($0) }
            .first(where: { SocialPlaceEvidenceScorer.looksLikeAddressLine($0) })
    }
}
