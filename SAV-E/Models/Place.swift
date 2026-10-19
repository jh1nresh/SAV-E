import Foundation
import CoreLocation

// MARK: - Place

struct Place: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var googlePlaceId: String?
    var category: PlaceCategory
    var status: PlaceStatus
    var rating: Double?
    var note: String?
    var sourceUrl: String?
    var sourcePlatform: SourcePlatform
    var coordinateSystem: PlaceCoordinateSystem? = nil
    var locationProvider: PlaceMatchProvider? = nil
    var providerPlaceId: String? = nil
    var providerMapUrl: String? = nil
    var sourceImageUrl: String?
    var businessPhotoUrls: [String]? = nil
    var extractedDishes: [String]?
    var priceRange: String?
    var recommender: String?
    var googleRating: Double?
    var googlePriceLevel: Int?
    var openingHours: String?
    var createdAt: Date
    var visibility: PlaceVisibility? = nil
    var socialSignal: PlaceSocialSignal? = nil
    var placeHighlights: [String]? = nil
    var recommendedItems: [RecommendedItem]? = nil
    var vibeTags: [String]? = nil
    var accessNotes: [String]? = nil
    var sourceHandle: String? = nil
    var mergedPlaceIDs: [UUID]? = nil
    /// Extra source lines that must survive a remote reload without being
    /// written into the user-facing `note` shown as "Your saved memory".
    var additionalSourceEvidence: [String]? = nil

    var savedIDs: Set<UUID> { Set([id] + (mergedPlaceIDs ?? [])) }

    func mergingSources(from other: Place) -> Place {
        var merged = self
        let aliases = Array(savedIDs.union(other.savedIDs).subtracting([id])).sorted { $0.uuidString < $1.uuidString }
        merged.mergedPlaceIDs = aliases.isEmpty ? nil : aliases
        // A fresh copy of the same record owns its edits, including cleared notes.
        merged.createdAt = min(createdAt, other.createdAt)
        let primaryURL = sourceUrl ?? other.sourceUrl
        // Same-id remote+local reloads must still union evidence and structured
        // memory. Different-id merges can also lift the other stamp's note
        // lines into additional evidence; same-id keeps `self.note`.
        let extraEvidence = id == other.id
            ? other.savedAdditionalSourceEvidence
            : other.incomingEvidence(excludingNote: note)
        merged.additionalSourceEvidence = (savedAdditionalSourceEvidence + extraEvidence)
            .filter { line in
                guard let primaryURL, !primaryURL.isEmpty else { return true }
                return line != "Source URL: \(primaryURL)"
            }
            .removingDuplicates()
            .nilIfEmpty
        merged.sourceUrl = sourceUrl ?? other.sourceUrl
        if sourceUrl == nil { merged.sourcePlatform = other.sourcePlatform }
        merged.recommender = recommender ?? other.recommender
        merged.googlePlaceId = googlePlaceId ?? other.googlePlaceId
        merged.sourceImageUrl = sourceImageUrl ?? other.sourceImageUrl
        merged.businessPhotoUrls = (businessPhotoURLStrings + other.businessPhotoURLStrings).removingDuplicates()
        merged.placeHighlights = (savedPlaceHighlights + other.savedPlaceHighlights).removingDuplicates()
        merged.vibeTags = (savedVibeTags + other.savedVibeTags).removingDuplicates()
        merged.accessNotes = (savedAccessNotes + other.savedAccessNotes).removingDuplicates()
        merged.recommendedItems = Self.mergingRecommendedItems(savedRecommendedItems, with: other.savedRecommendedItems)
        merged.extractedDishes = merged.savedRecommendedItems.map(\.name).nilIfEmpty
        merged.rating = rating ?? other.rating
        merged.googleRating = googleRating ?? other.googleRating
        merged.priceRange = priceRange ?? other.priceRange
        merged.openingHours = openingHours ?? other.openingHours
        return merged
    }

    /// Attach a Review clue to an already-saved stamp. Evidence, extra URLs,
    /// and structured fields go through `mergingSources` so nothing is dropped
    /// before the clue is deleted. Stamp order (`createdAt`) stays put.
    /// A stamp that already has a displayable handle keeps it; a different
    /// clue handle is stored as durable `Creator handle:` evidence instead of
    /// replacing the stamp's attribution. The stamp's user-facing `note` is
    /// left unchanged.
    func attachingReviewClue(_ clue: PlaceReviewCandidate) -> Place {
        var incoming = Place.from(clue)
        let clueHandle = SaveSourceHandle.displayable(incoming.sourceHandle)
            ?? SaveSourceHandle.displayable(incoming.recommender)
            ?? SaveSourceHandle.displayable(clue.sourceHandle)
        incoming.sourceHandle = clueHandle
        incoming.recommender = clueHandle
        var merged = mergingSources(from: incoming)
        merged.createdAt = createdAt
        let stampHandle = SaveSourceHandle.displayable(sourceHandle)
            ?? SaveSourceHandle.displayable(recommender)
        if let stampHandle {
            merged.sourceHandle = SaveSourceHandle.displayable(sourceHandle)
            merged.recommender = SaveSourceHandle.displayable(recommender) ?? stampHandle
            if let clueHandle, clueHandle.caseInsensitiveCompare(stampHandle) != .orderedSame {
                merged = merged.appendingAdditionalEvidence("Creator handle: @\(clueHandle)")
            }
        } else {
            merged.sourceHandle = clueHandle
            merged.recommender = clueHandle
        }
        return merged
    }

    func hasStructuredDetails(unlike previous: Place?) -> Bool {
        savedPlaceHighlights != (previous?.savedPlaceHighlights ?? [])
            || savedVibeTags != (previous?.savedVibeTags ?? [])
            || savedAccessNotes != (previous?.savedAccessNotes ?? [])
            || savedRecommendedItems != (previous?.savedRecommendedItems ?? [])
    }

    func hasAdditionalEvidence(unlike previous: Place?) -> Bool {
        savedAdditionalSourceEvidence != (previous?.savedAdditionalSourceEvidence ?? [])
    }

    private static func mergingRecommendedItems(_ primary: [RecommendedItem], with other: [RecommendedItem]) -> [RecommendedItem] {
        var items = primary
        for item in other {
            if let index = items.firstIndex(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
                if items[index].price == nil { items[index].price = item.price }
            } else {
                items.append(item)
            }
        }
        return items
    }

    /// Wire value for `places.note`. That column is plain user memory
    /// (`placeClaims` analysisSummary and save-rn `mapPlace` read it as text).
    /// Extra clue evidence, highlights, vibe, access, and priced recommended
    /// items live in `places.memory_meta`, not in `note`.
    func wireNoteForPersistence() -> String? {
        userFacingNote
    }

    func memoryMetaForPersistence() -> PlaceMemoryMeta? {
        let additional = savedAdditionalSourceEvidence.filter { !Self.isGeneratedEvidenceLine($0) }
        let meta = PlaceMemoryMeta(
            v: 1,
            evidence: additional.nilIfEmpty,
            highlights: savedPlaceHighlights.nilIfEmpty,
            recommended: savedRecommendedItems.nilIfEmpty,
            vibe: savedVibeTags.nilIfEmpty,
            access: savedAccessNotes.nilIfEmpty
        )
        return meta.isEmpty ? nil : meta
    }

    /// User-authored memory only. Leftover `SavvyMemory/1` envelopes written
    /// by earlier builds are decoded so JSON never surfaces as the note.
    var userFacingNote: String? {
        Self.decodedWireNote(note).note
    }

    var durableStructuredEvidence: [String] {
        savedPlaceHighlights.map { "Highlight: \($0)" }
            + savedRecommendedItems.map { "Highlight: Recommended item: \($0.displayText)" }
            + savedVibeTags.map { "Vibe: \($0)" }
            + savedAccessNotes.map { "Access: \($0)" }
    }

    /// Stable venue identity with every original ID retained for old trip stops.
    static func consolidated(_ places: [Place]) -> [Place] {
        var result: [Place] = []
        for place in places.sorted(by: {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }) {
            if let index = result.firstIndex(where: { $0.matches(place) }) {
                result[index] = result[index].mergingSources(from: place)
            } else {
                result.append(place)
            }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    var savedRecommendedItems: [RecommendedItem] {
        if let recommendedItems, !recommendedItems.isEmpty { return recommendedItems }
        return (extractedDishes ?? []).map { RecommendedItem(name: $0, price: nil) }
    }

    var savedPlaceHighlights: [String] { placeHighlights ?? [] }
    var savedVibeTags: [String] { vibeTags ?? [] }
    var savedAccessNotes: [String] { accessNotes ?? [] }
    var savedSourceHandle: String? { sourceHandle ?? recommender }
    var savedAdditionalSourceEvidence: [String] { additionalSourceEvidence ?? [] }

    var noteLines: [String] {
        (note ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func incomingEvidence(excludingNote excludedNote: String?) -> [String] {
        var lines = savedAdditionalSourceEvidence
        lines.append(contentsOf: noteLines)
        if let sourceUrl, !sourceUrl.isEmpty {
            lines.append("Source URL: \(sourceUrl)")
        }
        let excluded = excludedNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        return lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty, line != excluded else { return false }
                return !Self.isGeneratedEvidenceLine(line) && !Self.isStructuredEvidenceLine(line)
            }
            .removingDuplicates()
    }

    func appendingAdditionalEvidence(_ line: String) -> Place {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        var extra = savedAdditionalSourceEvidence
        if extra.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return self
        }
        extra.append(trimmed)
        var copy = self
        copy.additionalSourceEvidence = extra.nilIfEmpty
        return copy
    }

    static func classifiedSourceLines(_ lines: [String]) -> (note: String?, additional: [String]) {
        var noteLines: [String] = []
        var additional: [String] = []
        for raw in lines.flatMap({ $0.components(separatedBy: .newlines) }) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if isGeneratedEvidenceLine(line) || isStructuredEvidenceLine(line) { continue }
            if isURLEvidenceLine(line) || isDurableReceiptLine(line) {
                additional.append(line)
                continue
            }
            if let evidence = labeledEvidenceValue(line) {
                additional.append(evidence)
                continue
            }
            noteLines.append(line)
        }
        return (
            noteLines.isEmpty ? nil : noteLines.joined(separator: "\n"),
            additional.removingDuplicates()
        )
    }

    static func decodedWireNote(_ raw: String?) -> (
        note: String?,
        additional: [String],
        highlights: SocialPlaceStructuredHighlights
    ) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return (nil, [], .empty)
        }
        if let envelope = decodeMemoryNoteEnvelope(trimmed) {
            let note = envelope.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                (note?.isEmpty == false) ? note : nil,
                envelope.evidence ?? [],
                SocialPlaceStructuredHighlights(
                    placeHighlights: envelope.highlights ?? [],
                    recommendedItems: envelope.recommended ?? [],
                    vibeTags: envelope.vibe ?? [],
                    accessNotes: envelope.access ?? []
                )
            )
        }
        // Never reclassify a multi-line user note. Older labeled-wire
        // dumps stay visible as the user's memory rather than stripping
        // lines that begin with Highlight:/Vibe:/Evidence:/Access:.
        return (trimmed, [], .empty)
    }

    static func isGeneratedEvidenceLine(_ line: String) -> Bool {
        generatedEvidencePrefixes.contains { prefix in
            line.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
        }
    }

    static func isStructuredEvidenceLine(_ line: String) -> Bool {
        structuredEvidencePrefixes.contains { prefix in
            line.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
        }
    }

    static func isDurableReceiptLine(_ line: String) -> Bool {
        receiptEvidencePrefixes.contains { prefix in
            line.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
        }
    }

    static func isURLEvidenceLine(_ line: String) -> Bool {
        line.lowercased().hasPrefix("source url:") || line.hasPrefix("http://") || line.hasPrefix("https://")
    }

    private static func labeledEvidenceValue(_ line: String) -> String? {
        guard let range = line.range(of: "Evidence:", options: [.anchored, .caseInsensitive]) else { return nil }
        let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func decodeMemoryNoteEnvelope(_ raw: String) -> MemoryNoteEnvelope? {
        guard raw.hasPrefix(memoryNoteEnvelopeMarker) else { return nil }
        let json = raw.dropFirst(memoryNoteEnvelopeMarker.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(MemoryNoteEnvelope.self, from: data),
              envelope.v == memoryNoteEnvelopeVersion else {
            return nil
        }
        return envelope
    }

    private static let memoryNoteEnvelopeMarker = "SavvyMemory/1"
    private static let memoryNoteEnvelopeVersion = 1

    /// Diagnostics that must never become saved memory or additional evidence.
    private static let generatedEvidencePrefixes = [
        "Recommender:",
        "Verified coordinates",
        "Analysis method:",
        "Analysis pipeline:",
        "Evidence tier:",
        "Location clue:",
        "Google Places",
        "Venue name:",
        "Category clue:",
        "Confidence:",
        "Debug:",
        "Diagnostic:",
    ]

    /// Evidence Receipt lines (DESIGN.md) kept in `additionalSourceEvidence`.
    private static let receiptEvidencePrefixes = [
        "Creator handle:",
        "Source handle:",
        "Address clue:",
    ]

    private static let structuredEvidencePrefixes = [
        "Highlight:",
        "Vibe:",
        "Access:",
    ]

    private struct MemoryNoteEnvelope: Codable {
        var v: Int
        var note: String?
        var evidence: [String]?
        var highlights: [String]?
        var recommended: [RecommendedItem]?
        var vibe: [String]?
        var access: [String]?
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var resolvedCoordinateSystem: PlaceCoordinateSystem {
        coordinateSystem ?? .wgs84
    }

    var hasValidCoordinate: Bool {
        latitude.isFinite && longitude.isFinite &&
            (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
            (latitude != 0 || longitude != 0)
    }

    var isMapKitMappable: Bool {
        hasValidCoordinate && resolvedCoordinateSystem == .wgs84
    }

    var providerMapDestinationURL: URL? {
        guard let rawValue = providerMapUrl,
              let url = URL(string: rawValue),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "uri.amap.com" else {
            return nil
        }
        return url
    }

    var sourceEvidence: [String] {
        var evidence: [String] = []
        if let sourceUrl = sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceUrl.isEmpty {
            evidence.append("Source URL: \(sourceUrl)")
        }
        if let recommender = recommender?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommender.isEmpty {
            evidence.append("Recommender: \(recommender)")
        }
        evidence += savedAdditionalSourceEvidence
        evidence += noteLines
        return evidence.removingDuplicates()
    }

    var primarySourceURL: URL? {
        if let sourceUrl = normalizedSourceURL(from: sourceUrl) {
            return sourceUrl
        }
        return sourceEvidence
            .flatMap(Self.urls)
            .first
    }

    var publicShareSourceURL: URL? {
        ShareRoutePayloadSanitizer.publicURL(from: primarySourceURL?.absoluteString)
    }

    var shareSubject: String {
        "Savvy Map Stamp: \(name)"
    }

    var saveShareURL: URL? {
        SharedPlaceData.from(place: self).toURL()
    }

    var shareText: String {
        var lines = [
            "Savvy Map Stamp",
            name,
            address,
            "Category: \(category.displayName)",
            "Status: \(status.memoryCardLabel)"
        ]

        if let rating = googleRating ?? rating {
            lines.append("Rating: \(String(format: "%.1f", rating))")
        }
        if let priceRange, !priceRange.isEmpty {
            lines.append("Price: \(priceRange)")
        }
        if let recommender, !recommender.isEmpty {
            lines.append("Recommended by: \(recommender)")
        }
        if let sourceURL = publicShareSourceURL {
            lines.append("Source: \(sourceURL.absoluteString)")
        }
        if let saveShareURL {
            lines.append("Open in Savvy: \(saveShareURL.absoluteString)")
        }
        return lines.joined(separator: "\n")
    }

    var shareMessage: String {
        var parts = [address, category.displayName]
        if let rating = googleRating ?? rating {
            parts.append(String(format: "%.1f stars", rating))
        }
        return parts.joined(separator: " · ")
    }

    var shareAreaLabel: String {
        let parts = address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 2 { return parts[parts.count - 2] }
        return parts.first ?? ""
    }

    var appleMapsURL: URL? {
        guard isMapKitMappable else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)")
        ]
        return components?.url
    }

    func matchesMapFeature(title: String, coordinate: CLLocationCoordinate2D) -> Bool {
        guard isMapKitMappable else { return false }
        let distance = CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        guard distance < 120 else { return false }

        let featureName = title.normalizedMapMatchText
        let placeName = name.normalizedMapMatchText
        let sameName = !featureName.isEmpty &&
            (featureName == placeName ||
             featureName.contains(placeName) ||
             placeName.contains(featureName))

        return sameName || distance < 20
    }

    var businessPhotoURLStrings: [String] {
        var values = businessPhotoUrls ?? []
        if let sourceImageUrl {
            values.append(sourceImageUrl)
        }
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .removingDuplicates()
    }

    var businessLookupName: String {
        name
            .replacingOccurrences(of: #"[（(].*?[）)]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedSourceURL(from rawValue: String?) -> URL? {
        guard let raw = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }

        if let url = URL(string: raw), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(raw)")
    }

    private static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector
            .matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .filter { url in
                guard let scheme = url.scheme?.lowercased() else { return false }
                return scheme == "http" || scheme == "https"
            }
    }
}

private extension Array {
    var nilIfEmpty: [Element]? { isEmpty ? nil : self }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}

private extension String {
    var normalizedMapMatchText: String {
        folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Enums

enum PlaceCategory: String, Codable, CaseIterable, Hashable {
    case food, cafe, bar, attraction, stay, shopping

    var displayName: String {
        switch self {
        case .food: return "Food"
        case .cafe: return "Cafe"
        case .bar: return "Bar"
        case .attraction: return "Attraction"
        case .stay: return "Stay"
        case .shopping: return "Shopping"
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .food:
            return language.localized(english: "Food", traditionalChinese: "美食")
        case .cafe:
            return language.localized(english: "Cafe", traditionalChinese: "咖啡")
        case .bar:
            return language.localized(english: "Bar", traditionalChinese: "酒吧")
        case .attraction:
            return language.localized(english: "Attraction", traditionalChinese: "景點")
        case .stay:
            return language.localized(english: "Stay", traditionalChinese: "住宿")
        case .shopping:
            return language.localized(english: "Shopping", traditionalChinese: "購物")
        }
    }

    var iconName: String {
        switch self {
        case .food: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .bar: return "wineglass.fill"
        case .attraction: return "star.fill"
        case .stay: return "bed.double.fill"
        case .shopping: return "bag.fill"
        }
    }
}

enum PlaceStatus: String, Codable, Hashable {
    case wantToGo, visited

    var displayName: String {
        switch self {
        case .wantToGo: return "Want to Go"
        case .visited: return "Visited"
        }
    }

    var memoryCardLabel: String {
        switch self {
        case .wantToGo: return "Map Stamp"
        case .visited: return "Visited"
        }
    }

    func memoryCardLabel(language: AppLanguage) -> String {
        switch self {
        case .wantToGo:
            return language.localized(english: "Map Stamp", traditionalChinese: "地圖章")
        case .visited:
            return language.localized(english: "Visited", traditionalChinese: "去過")
        }
    }

    /// Map Stamp substate shown on the Memory Card. Not a `SaveMemoryBadge` case.
    func visitIntentLabel(language: AppLanguage) -> String {
        switch self {
        case .wantToGo:
            return language.localized(english: "Want to try", traditionalChinese: "想找時間去")
        case .visited:
            return language.localized(english: "Visited", traditionalChinese: "去過")
        }
    }

    func visitIntentAccessibilityIdentifier() -> String {
        switch self {
        case .wantToGo:
            return "drawer.saved.wantToGo"
        case .visited:
            return "drawer.saved.visited"
        }
    }
}

enum SourcePlatform: String, Codable, CaseIterable, Hashable {
    case instagram, threads, xiaohongshu, douyin, dianping, meituan, googleMaps, amap, baidu, other
    case appleMaps = "apple_maps"
    case taobaoInstantCommerce = "taobao_instant_commerce"

    var displayName: String {
        switch self {
        case .instagram: return "Instagram"
        case .threads: return "Threads"
        case .xiaohongshu: return "Xiaohongshu"
        case .douyin: return "Douyin"
        case .dianping: return "Dianping"
        case .meituan: return "Meituan"
        case .taobaoInstantCommerce: return "Taobao Instant Commerce"
        case .googleMaps: return "Google Maps"
        case .appleMaps: return "Apple Maps"
        case .amap: return "Amap"
        case .baidu: return "Baidu Maps"
        case .other: return "Other"
        }
    }
}

// MARK: - Mock Data

extension Place {
    static let mock = Place(
        id: UUID(),
        name: "Tartine Bakery",
        address: "600 Guerrero St, San Francisco, CA",
        latitude: 37.7614,
        longitude: -122.4241,
        googlePlaceId: "ChIJAQAAMal-j4ARm6sMODkLP28",
        category: .cafe,
        status: .wantToGo,
        rating: 4.5,
        note: "Must try the morning bun!",
        sourceUrl: "https://instagram.com/p/example",
        sourcePlatform: .instagram,
        sourceImageUrl: nil,
        extractedDishes: ["Morning Bun", "Country Bread"],
        priceRange: "$$",
        recommender: "@foodie_friend",
        googleRating: 4.6,
        googlePriceLevel: 2,
        openingHours: "Mon-Sun 8:00 AM - 5:00 PM",
        createdAt: Date(),
        visibility: .privateMemory,
        socialSignal: nil
    )

    static let mockList: [Place] = [
        .mock,
        Place(
            id: UUID(),
            name: "Ramen Nagi",
            address: "541 Valencia St, San Francisco, CA",
            latitude: 37.7642,
            longitude: -122.4214,
            category: .food,
            status: .visited,
            rating: 4.8,
            note: "Black King ramen is incredible",
            sourcePlatform: .threads,
            extractedDishes: ["Black King Ramen"],
            priceRange: "$$",
            googleRating: 4.5,
            createdAt: Date().addingTimeInterval(-86400),
            visibility: .privateMemory,
            socialSignal: nil
        ),
        Place(
            id: UUID(),
            name: "The Interval",
            address: "2 Marina Blvd, San Francisco, CA",
            latitude: 37.8064,
            longitude: -122.4090,
            category: .bar,
            status: .wantToGo,
            sourcePlatform: .other,
            priceRange: "$$$",
            googleRating: 4.3,
            createdAt: Date().addingTimeInterval(-172800),
            visibility: .privateMemory,
            socialSignal: nil
        ),
    ]

    static func socialSignalSeeds(near _: [Place]) -> [Place] {
        // Real social signals must come from follows/referrals/trending data, not demo seeds.
        []
    }
}

struct PlaceMemoryMeta: Codable, Equatable, Hashable {
    var v: Int = 1
    var evidence: [String]?
    var highlights: [String]?
    var recommended: [RecommendedItem]?
    var vibe: [String]?
    var access: [String]?

    var isEmpty: Bool {
        (evidence ?? []).isEmpty
            && (highlights ?? []).isEmpty
            && (recommended ?? []).isEmpty
            && (vibe ?? []).isEmpty
            && (access ?? []).isEmpty
    }

    func jsonObject() throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}

extension Array where Element == Place {
    var indexedBySavedID: [UUID: Place] {
        Dictionary(flatMap { place in place.savedIDs.map { ($0, place) } }, uniquingKeysWith: { first, _ in first })
    }

    var indexedBySavedIDString: [String: Place] {
        Dictionary(indexedBySavedID.map { ($0.key.uuidString, $0.value) }, uniquingKeysWith: { first, _ in first })
    }
}
