import Foundation
import CoreFoundation

struct GoogleMapsListPlaceCandidate: Equatable, Sendable {
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var evidence: [String]
}

/// Public list data is evidence only. Both entry points map this into their
/// existing review queue; no saved-place or account state is written here.
struct GoogleMapsListAnalysis: Sendable {
    var title: String
    var candidates: [GoogleMapsListPlaceCandidate]
    var notice: String?

    static func unavailable(_ notice: String) -> Self {
        Self(title: "Google Maps saved list", candidates: [], notice: notice)
    }
}

/// Google's public list page loads entries separately from its HTML shell.
/// This is an undocumented read-only format: fail closed if its shape changes.
/// Never forward cookies, owner profiles, contributor details, or list notes.
enum GoogleMapsPublicListLoader {
    nonisolated static let byteLimit = 4_000_000
    static let entryLimit = 500

    static func listID(in sourceURL: String) -> String? {
        guard let url = URL(string: sourceURL),
              url.scheme == "https",
              ["google.com", "www.google.com", "maps.google.com"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        let path = url.path
        let patterns = [
            #"^/maps/placelists/list/([A-Za-z0-9_-]{10,256})/?$"#,
            #"^/maps/@/data=.*!11m1!2s([A-Za-z0-9_-]{10,256})(?:!|$)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
                  let range = Range(match.range(at: 1), in: path) else { continue }
            return String(path[range])
        }
        return nil
    }

    static func requestURL(for listID: String) -> URL? {
        guard listID.range(of: #"^[A-Za-z0-9_-]{10,256}$"#, options: .regularExpression) != nil else { return nil }
        var url = URLComponents(string: "https://www.google.com/maps/preview/entitylist/getlist")!
        url.queryItems = [URLQueryItem(name: "hl", value: "zh-TW"),
                          URLQueryItem(name: "pb", value: "!1m1!1s\(listID)!2e2!3e2!4i\(entryLimit)")]
        return url.url
    }

    static func load(sourceURL: String) async -> GoogleMapsListAnalysis? {
        await load(sourceURL: sourceURL, fetch: fetchPublicData)
    }

    // Injection keeps network failures and private/malformed responses testable
    // without Google credentials, a live provider, or an AI/search fallback.
    static func load(sourceURL: String, fetch: @Sendable (URL) async throws -> Data) async -> GoogleMapsListAnalysis? {
        guard let id = listID(in: sourceURL), let url = requestURL(for: id) else { return nil }
        do {
            return parse(try await fetch(url), expectedListID: id)
        } catch {
            return .unavailable("Could not read this Google Maps list. Check that link sharing is enabled, then try again or share individual places.")
        }
    }

    static func parse(_ data: Data, expectedListID: String) -> GoogleMapsListAnalysis {
        let unreadable = GoogleMapsListAnalysis.unavailable(
            "Could not read this Google Maps list. Check that link sharing is enabled, then try again or share individual places.")
        guard data.count <= byteLimit, var text = String(data: data, encoding: .utf8) else { return unreadable }
        if text.hasPrefix(")]}'\n") { text.removeFirst(5) }
        guard let json = text.data(using: .utf8),
              let outer = (try? JSONSerialization.jsonObject(with: json)) as? [Any],
              let list = outer.first as? [Any], list.count > 12,
              let identity = list[0] as? [Any], identity.first as? String == expectedListID,
              let title = list[4] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let totalNumber = list[12] as? NSNumber,
              CFGetTypeID(totalNumber) != CFBooleanGetTypeID(),
              totalNumber.doubleValue.isFinite, totalNumber.doubleValue >= 0,
              totalNumber.doubleValue <= 1_000_000,
              totalNumber.doubleValue.rounded() == totalNumber.doubleValue else { return unreadable }
        let total = totalNumber.intValue
        let rows = list[8] as? [Any] ?? []
        guard rows.count <= entryLimit else { return unreadable }
        var candidates: [GoogleMapsListPlaceCandidate] = []
        var seen = Set<String>()
        var invalidRows = 0
        for row in rows {
            guard let entry = row as? [Any], entry.count > 2,
                  let place = entry[1] as? [Any], place.count > 6,
                  let rawName = entry[2] as? String,
                  !rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, rawName.count <= 512,
                  let address = place[4] as? String, address.count <= 2_000,
                  let coordinate = place[5] as? [Any], coordinate.count > 3,
                  let lat = coordinate[2] as? NSNumber, let lng = coordinate[3] as? NSNumber,
                  CFGetTypeID(lat) != CFBooleanGetTypeID(), CFGetTypeID(lng) != CFBooleanGetTypeID(),
                  lat.doubleValue.isFinite, lng.doubleValue.isFinite,
                  (-90...90).contains(lat.doubleValue), (-180...180).contains(lng.doubleValue) else {
                invalidRows += 1
                continue
            }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let ids = place[6] as? [String] ?? []
            let key = ids.count == 2 && ids.allSatisfy({ !$0.isEmpty })
                ? ids.joined(separator: ":") : "\(name)|\(address)|\(lat)|\(lng)"
            guard seen.insert(key).inserted else { continue }
            candidates.append(GoogleMapsListPlaceCandidate(name: name, address: address,
                latitude: lat.doubleValue, longitude: lng.doubleValue,
                evidence: ["Place identity, address and coordinates from the same Google Maps list entry"]))
        }
        let hasMore = outer.count > 1 && (outer[1] as? String)?.isEmpty == false
        // A partial list must never look like an exhaustive analysis. Preserve
        // its source instead of quietly dropping entries or the old >30 tail.
        guard total == rows.count, invalidRows == 0, !hasMore else {
            return GoogleMapsListAnalysis(title: String(title.prefix(200)), candidates: [],
                notice: "List not fully read: \(rows.count - invalidRows) of \(total) entries readable. Savvy can read up to \(entryLimit) entries per shared list. Share a smaller list or individual places, then try again.")
        }
        return GoogleMapsListAnalysis(title: String(title.prefix(200)), candidates: candidates,
            notice: candidates.isEmpty ? "This Google Maps list has no readable places yet." : nil)
    }

    private nonisolated static func fetchPublicData(from url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration, delegate: GoogleMapsListRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url == url, response.expectedContentLength <= Int64(byteLimit) else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            guard data.count < byteLimit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}

private final class GoogleMapsListRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Login, consent, and external redirects are not public list evidence.
        completionHandler(nil)
    }
}

/// Share-sheet parser for public Google Maps saved-list links.
/// Keep this path separate from Google Takeout bulk file parsing.
enum GoogleMapsListPlaceExtractor {
    static func looksLikeGoogleMapsList(sourceURL: String, title: String?, text: String?, metadataTitle: String?, metadataDescription: String?) -> Bool {
        if GoogleMapsPublicListLoader.listID(in: sourceURL) != nil { return true }
        guard let url = URL(string: sourceURL),
              ["google.com", "www.google.com", "maps.google.com", "maps.app.goo.gl"].contains(url.host?.lowercased() ?? "") else { return false }
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
        let normalizedText = normalizedEvidenceText(evidenceText)
        let linkEvidenceText = normalizedText == evidenceText ? evidenceText : [evidenceText, normalizedText].joined(separator: "\n")

        var candidates: [GoogleMapsListPlaceCandidate] = []
        candidates.append(contentsOf: candidatesFromGooglePlaceLinks(in: linkEvidenceText))
        candidates.append(contentsOf: candidatesFromGoogleMapsQueryLinks(in: linkEvidenceText))
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

    private static func normalizedEvidenceText(_ value: String) -> String {
        var decoded = value
        let replacements = [
            ("\\\\u003d", "="),
            ("\\u003d", "="),
            ("\\\\u0026", "&"),
            ("\\u0026", "&"),
            ("\\\\u002F", "/"),
            ("\\u002F", "/"),
            ("\\\\/", "/"),
            ("\\/", "/"),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">")
        ]
        for (source, target) in replacements {
            decoded = decoded.replacingOccurrences(of: source, with: target)
        }
        return decoded
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
                let coordinate = coordinateNearGoogleLink(in: nsText.substring(with: match.range))
                let address = firstAddressLine(in: htmlElementSnippet(in: nsText, around: match.range)) ?? ""
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

    private static func candidatesFromGoogleMapsQueryLinks(in text: String) -> [GoogleMapsListPlaceCandidate] {
        guard !text.isEmpty else { return [] }
        let pattern = #"(?i)(?:https?:)?(?://)?(?:www\.)?google\.com/maps\?[^"'<>\s\\]*(?:cid|query_place_id|ftid)=[^"'<>\s\\]*|/maps\?[^"'<>\s\\]*(?:cid|query_place_id|ftid)=[^"'<>\s\\]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            let snippet = htmlElementSnippet(in: nsText, around: match.range)
            guard let name = placeNameNearGoogleQueryLink(in: snippet), !name.isEmpty else {
                return nil
            }
            let coordinate = coordinateNearGoogleLink(in: nsText.substring(with: match.range))
            let address = firstAddressLine(in: snippet) ?? ""
            return GoogleMapsListPlaceCandidate(
                name: name,
                address: address,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude,
                evidence: ["Found Google Maps place URL: \(name)"]
            )
        }
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
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
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
              !["open", "website", "route", "saved", "list", "view"].contains(lower),
              lower != listLower else {
            return false
        }
        return true
    }

    private static func placeNameNearGoogleQueryLink(in snippet: String) -> String? {
        let patterns = [
            #"(?is)aria-label\s*=\s*["']([^"']+)["']"#,
            #"(?is)title\s*=\s*["']([^"']+)["']"#,
            #"(?is)>\s*([^<>]{2,90})\s*</a>"#
        ]
        let nsSnippet = snippet as NSString
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            guard let match = regex.firstMatch(in: snippet, range: NSRange(location: 0, length: nsSnippet.length)),
                  match.numberOfRanges > 1 else {
                continue
            }
            let name = cleanPlaceName(nsSnippet.substring(with: match.range(at: 1)))
            if isUsablePlaceName(name, listTitle: "") {
                return name
            }
        }
        return nil
    }

    private static func htmlElementSnippet(in text: NSString, around range: NSRange) -> String {
        let beforeStart = max(0, range.location - 400)
        let beforeLength = range.location - beforeStart
        let before = text.substring(with: NSRange(location: beforeStart, length: beforeLength)) as NSString
        let openRange = before.range(of: "<a", options: [.backwards, .caseInsensitive])
        let snippetStart = openRange.location == NSNotFound ? max(0, range.location - 180) : beforeStart + openRange.location

        let afterStart = range.location + range.length
        let afterEnd = min(text.length, afterStart + 400)
        let afterLength = max(0, afterEnd - afterStart)
        let after = text.substring(with: NSRange(location: afterStart, length: afterLength)) as NSString
        let closeRange = after.range(of: "</a>", options: .caseInsensitive)
        let snippetEnd = closeRange.location == NSNotFound ? min(text.length, range.location + range.length + 180) : afterStart + closeRange.location + closeRange.length

        return text.substring(with: NSRange(location: snippetStart, length: max(0, snippetEnd - snippetStart)))
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
