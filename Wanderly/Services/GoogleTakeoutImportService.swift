import Foundation
import ZIPFoundation

enum GoogleTakeoutImportError: LocalizedError {
    case unsupportedFile
    case unreadableFile
    case emptyImport

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "Choose a .zip, .json, .geojson, or .kml export from Google Takeout."
        case .unreadableFile:
            return "SAV-E could not read this file."
        case .emptyImport:
            return "No places were found in this export."
        }
    }
}

/// Bulk importer for user-selected Google Takeout exports.
/// Do not route Google Maps saved-list share links through this service.
final class GoogleTakeoutImportService {
    static let shared = GoogleTakeoutImportService()

    func parse(fileAt url: URL) async throws -> GoogleTakeoutImportResult {
        let fileName = url.lastPathComponent
        let entries = try readableEntries(from: url)
        var drafts: [ImportedPlaceDraft] = []

        for entry in entries {
            drafts.append(contentsOf: parse(data: entry.data, fileName: entry.fileName))
        }

        let deduped = deduplicate(drafts)
        guard !deduped.isEmpty else { throw GoogleTakeoutImportError.emptyImport }
        return GoogleTakeoutImportResult(fileName: fileName, parsedAt: Date(), drafts: deduped)
    }

    private func readableEntries(from url: URL) throws -> [(fileName: String, data: Data)] {
        let ext = url.pathExtension.lowercased()

        if ext == "zip" {
            guard let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil) else {
                throw GoogleTakeoutImportError.unreadableFile
            }

            var entries: [(String, Data)] = []
            for entry in archive where entry.type == .file && isSupportedInnerFile(entry.path) {
                var data = Data()
                _ = try archive.extract(entry) { chunk in
                    data.append(chunk)
                }
                entries.append((entry.path, data))
            }
            return entries
        }

        guard isSupportedInnerFile(url.lastPathComponent) else {
            throw GoogleTakeoutImportError.unsupportedFile
        }

        return [(url.lastPathComponent, try Data(contentsOf: url))]
    }

    private func isSupportedInnerFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["json", "geojson", "kml"].contains(ext)
    }

    private func parse(data: Data, fileName: String) -> [ImportedPlaceDraft] {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "geojson":
            return parseGeoJSON(data: data, fileName: fileName)
        case "json":
            return parseJSON(data: data, fileName: fileName)
        case "kml":
            return parseKML(data: data, fileName: fileName)
        default:
            return []
        }
    }

    private func parseGeoJSON(data: Data, fileName: String) -> [ImportedPlaceDraft] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return parseGeoJSONObject(object, fileName: fileName, sourceFormat: "geojson")
    }

    private func parseJSON(data: Data, fileName: String) -> [ImportedPlaceDraft] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }

        if let dict = object as? [String: Any],
           let type = string(in: dict, keys: ["type"]),
           type.lowercased() == "featurecollection" {
            return parseGeoJSONObject(dict, fileName: fileName, sourceFormat: "geojson")
        }

        var objects: [[String: Any]] = []
        collectJSONObjectCandidates(object, into: &objects)
        return objects.compactMap { draft(from: $0, fileName: fileName, sourceFormat: "json") }
    }

    private func parseGeoJSONObject(_ object: Any, fileName: String, sourceFormat: String) -> [ImportedPlaceDraft] {
        guard let dict = object as? [String: Any] else { return [] }
        let features = dict["features"] as? [[String: Any]] ?? []

        return features.compactMap { feature in
            let properties = feature["properties"] as? [String: Any] ?? [:]
            let geometry = feature["geometry"] as? [String: Any]
            let coordinates = geometry?["coordinates"] as? [Any]

            let longitude = coordinates?.first.flatMap(doubleValue)
            let latitude = coordinates?.dropFirst().first.flatMap(doubleValue)

            let merged = properties.merging([
                "latitude": latitude as Any,
                "longitude": longitude as Any,
            ]) { current, _ in current }

            return draft(from: merged, fileName: fileName, sourceFormat: sourceFormat)
        }
    }

    private func parseKML(data: Data, fileName: String) -> [ImportedPlaceDraft] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }

        let placemarkPattern = #"(?is)<Placemark\b[^>]*>(.*?)</Placemark>"#
        let placemarks = regexMatches(in: xml, pattern: placemarkPattern)

        return placemarks.compactMap { placemark in
            let name = firstCapture(in: placemark, pattern: #"(?is)<name\b[^>]*>(.*?)</name>"#)
            let description = firstCapture(in: placemark, pattern: #"(?is)<description\b[^>]*>(.*?)</description>"#)
            let coordinates = firstCapture(in: placemark, pattern: #"(?is)<coordinates\b[^>]*>(.*?)</coordinates>"#)
            let parts = coordinates?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ",")
                .map(String.init)

            let longitude = parts?.first.flatMap(Double.init)
            let latitude = parts?.dropFirst().first.flatMap(Double.init)
            let title = cleanText(name ?? "").nilIfEmpty ?? "Untitled place"
            let cleanedDescription = cleanText(description ?? "")

            return makeDraft(
                name: title,
                address: cleanedDescription,
                latitude: latitude,
                longitude: longitude,
                sourceURL: googleMapsURL(from: cleanedDescription),
                sourceFile: fileName,
                sourceFormat: "kml",
                rawSnippet: cleanedDescription
            )
        }
    }

    private func collectJSONObjectCandidates(_ object: Any, into candidates: inout [[String: Any]]) {
        if let dict = object as? [String: Any] {
            if looksLikePlace(dict) {
                candidates.append(dict)
            }
            for value in dict.values {
                collectJSONObjectCandidates(value, into: &candidates)
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectJSONObjectCandidates(value, into: &candidates)
            }
        }
    }

    private func looksLikePlace(_ dict: [String: Any]) -> Bool {
        let hasName = string(in: dict, keys: ["name", "title", "Name", "Title"])?.nilIfEmpty != nil
        let hasCoordinates = coordinatePair(in: dict) != nil
        let hasAddress = string(in: dict, keys: ["address", "Address", "location", "Location"])?.nilIfEmpty != nil
        let hasMapsURL = string(in: dict, keys: ["url", "URL", "googleMapsUrl", "Google Maps URL"]).flatMap(googleMapsURL(from:)) != nil
        return hasName && (hasCoordinates || hasAddress || hasMapsURL)
    }

    private func draft(from dict: [String: Any], fileName: String, sourceFormat: String) -> ImportedPlaceDraft? {
        let name = string(in: dict, keys: ["name", "title", "Name", "Title", "place_name", "placeName"])
            ?? string(in: dict, keys: ["Location", "location"])
            ?? "Untitled place"

        let address = string(in: dict, keys: ["address", "Address", "formatted_address", "formattedAddress", "Location", "location"]) ?? ""
        let coordinates = coordinatePair(in: dict)
        let sourceURL = string(in: dict, keys: ["url", "URL", "googleMapsUrl", "Google Maps URL", "mapsUrl"])
            .flatMap(googleMapsURL(from:))
            ?? googleMapsURL(from: address)

        return makeDraft(
            name: cleanText(name),
            address: cleanText(address),
            latitude: coordinates?.latitude,
            longitude: coordinates?.longitude,
            sourceURL: sourceURL,
            sourceFile: fileName,
            sourceFormat: sourceFormat,
            rawSnippet: rawSnippet(from: dict)
        )
    }

    private func makeDraft(
        name: String,
        address: String,
        latitude: Double?,
        longitude: Double?,
        sourceURL: String?,
        sourceFile: String,
        sourceFormat: String,
        rawSnippet: String?
    ) -> ImportedPlaceDraft {
        let trimmedName = cleanText(name).nilIfEmpty ?? "Untitled place"
        let trimmedAddress = cleanText(address)
        let hasCoordinates = latitude != nil && longitude != nil
        let state: ImportedPlaceDraft.ReviewState = hasCoordinates
            ? .readyToSave
            : .needsReview("No reliable coordinates in export")

        return ImportedPlaceDraft(
            name: trimmedName,
            address: trimmedAddress,
            latitude: latitude,
            longitude: longitude,
            sourceURL: sourceURL,
            sourceFile: sourceFile,
            sourceFormat: sourceFormat,
            rawSnippet: rawSnippet,
            reviewState: state
        )
    }

    private func coordinatePair(in dict: [String: Any]) -> (latitude: Double, longitude: Double)? {
        if let latitude = value(in: dict, keys: ["latitude", "lat", "Latitude"]),
           let longitude = value(in: dict, keys: ["longitude", "lng", "lon", "Longitude"]) {
            return (latitude, longitude)
        }

        if let location = dict["location"] as? [String: Any],
           let latitude = value(in: location, keys: ["latitude", "lat"]),
           let longitude = value(in: location, keys: ["longitude", "lng", "lon"]) {
            return (latitude, longitude)
        }

        if let geometry = dict["geometry"] as? [String: Any],
           let location = geometry["location"] as? [String: Any],
           let latitude = value(in: location, keys: ["lat", "latitude"]),
           let longitude = value(in: location, keys: ["lng", "longitude"]) {
            return (latitude, longitude)
        }

        return nil
    }

    private func value(in dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dict[key].flatMap(doubleValue) {
                return value
            }
        }
        return nil
    }

    private func string(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
            if let value = dict[key] {
                let text = String(describing: value)
                if !text.isEmpty, text != "<null>" {
                    return text
                }
            }
        }
        return nil
    }

    private func doubleValue(_ value: Any) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private func rawSnippet(from dict: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return String(text.prefix(800))
    }

    private func googleMapsURL(from value: String) -> String? {
        guard let match = value.range(of: #"https?://[^\s<>"']+"#, options: .regularExpression) else {
            return nil
        }
        let url = String(value[match])
        guard let host = URL(string: url)?.host?.lowercased(),
              host.contains("google") || host.contains("goo.gl") else {
            return nil
        }
        return url
    }

    private func cleanText(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func regexMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[valueRange])
        }
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        regexMatches(in: text, pattern: pattern).first
    }

    private func deduplicate(_ drafts: [ImportedPlaceDraft]) -> [ImportedPlaceDraft] {
        var seen: Set<String> = []
        var result: [ImportedPlaceDraft] = []
        for draft in drafts where !draft.name.isEmpty {
            let key = draft.deduplicationKey
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(draft)
        }
        return result
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
