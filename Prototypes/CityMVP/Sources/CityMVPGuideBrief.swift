#if SAVVY_CITY_MVP
import Foundation

/// Read-only snapshot of one confirmed vault Place. No candidate conversion or writes.
nonisolated struct CityMVPGuideBrief: Sendable {
    let id: UUID
    let name: String
    let address: String
    let category: String
    let savedAt: Date
    let visited: Bool
    let sourceURL: URL?
    let sourceStatements: [String]
    let privateNote: String?
    let canShowOnMap: Bool

    @MainActor init(place: Place) {
        id = place.id; name = place.name; address = place.address
        category = place.category.rawValue; savedAt = place.createdAt
        visited = place.status == .visited
        sourceURL = Self.safeSourceURL(place.sourceUrl)
        sourceStatements = (place.durableStructuredEvidence + place.savedAdditionalSourceEvidence)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        privateNote = place.userFacingNote.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        canShowOnMap = place.isMapKitMappable
    }

    var hasAddress: Bool { !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Conservative display hint only; a detected number does not verify a taxi destination.
    var hasStreetNumber: Bool {
        address.range(of: #"[0-9０-９]+(?:[-之][0-9０-９]+)?\s*[號号]|(?:路|街|道|巷|弄)\s*[0-9０-９]+(?:[-之][0-9０-９]+)?\s*$|^\s*[0-9]+[A-Za-z]?\s+[A-Za-z]"#,
                      options: .regularExpression) != nil
    }
    var driverCardText: String? { hasStreetNumber ? "师傅，请带我去：\n\(address)\n\(name)" : nil }

    static func safeSourceURL(_ raw: String?) -> URL? {
        guard let raw, !raw.contains(where: { $0.isWhitespace || $0.isNewline }),
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: raw), parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              let url = parts.url else { return nil }
        let credentials: Set<String> = ["token", "access_token", "refresh_token", "api_key", "apikey", "password", "authorization"]
        let fragmentQuery = parts.fragment.flatMap { URLComponents(string: "?" + $0)?.queryItems } ?? []
        guard !((parts.queryItems ?? []) + fragmentQuery).contains(where: { credentials.contains($0.name.lowercased()) }) else { return nil }
        return url
    }
}

/// Immutable venue-only allowlist. Private notes, source statements, coordinates,
/// photos, ratings and visit history have no fields in this export contract.
nonisolated struct CityMVPGuideExport: Codable, Sendable {
    struct Venue: Codable, Sendable {
        let id: String
        let name: String
        let address: String
        let category: String
        let state: String
        let savedAt: String
        let sourceURL: String?
    }
    let format: String
    let version: Int
    let exportedAt: String
    let places: [Venue]
    static let maximumBytes = 128 * 1_024

    static func encode(_ brief: CityMVPGuideBrief, exportedAt: Date = Date()) -> Data? {
        guard brief.savedAt.timeIntervalSince1970.isFinite, exportedAt.timeIntervalSince1970.isFinite,
              !brief.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              brief.name.utf8.count <= 2048, brief.address.utf8.count <= 4096,
              (brief.sourceURL?.absoluteString.utf8.count ?? 0) <= 4096,
              ![brief.name, brief.address].contains(where: { value in
                  value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t" }
              }),
              brief.name.utf8.count + brief.address.utf8.count + (brief.sourceURL?.absoluteString.utf8.count ?? 0) < maximumBytes else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload = Self(format: "savvy-guide", version: 1, exportedAt: formatter.string(from: exportedAt), places: [
            Venue(id: brief.id.uuidString, name: brief.name, address: brief.address, category: brief.category,
                  state: "confirmed", savedAt: formatter.string(from: brief.savedAt), sourceURL: brief.sourceURL?.absoluteString)
        ])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload), data.count <= maximumBytes else { return nil }
        return data
    }
}
#endif
