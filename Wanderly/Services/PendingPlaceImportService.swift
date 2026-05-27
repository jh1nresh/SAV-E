import Foundation
import MapKit

enum WanderlySharedStorage {
    static let appGroupSuiteName = "group.com.wanderly.app"
    static let pendingPlacesFileName = "pending-places.json"
    static let pendingReviewCandidatesFileName = "pending-review-candidates.json"
}

struct PendingSharedPlace: Codable {
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

struct SocialPlaceEvidenceDiagnostic: Codable, Hashable {
    var found: [String]
    var attempts: [String]
    var missingFields: [String]
    var nextBestClue: String
    var suggestedSearchQueries: [String]? = nil

    var statusLabel: String {
        if canSaveAsMapStamp { return "Map match ready" }
        if found.joined(separator: "\n").lowercased().contains("place-bearing source") { return "Place clue" }
        if lowercasedMissingFields.contains(where: { $0.contains("place name") }) { return "Source clue" }
        if lowercasedMissingFields.contains(where: { $0.contains("address") || $0.contains("coordinates") }) { return "Needs confirmation" }
        return "Review candidate"
    }

    var primaryActionLabel: String {
        if canSaveAsMapStamp { return "Confirm map match" }
        if statusLabel == "Place clue" { return "Run recovery search" }
        if statusLabel == "Source clue" { return "Add caption / screenshot / map link" }
        if lowercasedMissingFields.contains(where: { $0.contains("address") || $0.contains("coordinates") }) { return "Confirm address / coordinates" }
        return "Review evidence"
    }

    var canSaveAsMapStamp: Bool {
        let foundText = found.joined(separator: "\n").lowercased()
        return foundText.contains("google places match") &&
            foundText.contains("verified coordinates") &&
            !lowercasedMissingFields.contains(where: { $0.contains("coordinate") })
    }

    private var lowercasedMissingFields: [String] {
        missingFields.map { $0.lowercased() }
    }
}

struct PendingReviewCandidate: Codable {
    var candidateName: String
    var address: String
    var category: String
    var latitude: Double? = nil
    var longitude: Double? = nil
    var sourceURL: String?
    var sourceText: String?
    var evidence: [String]
    var confidence: Double
    var missingInfo: [String]
    var savedAt: Date
    var evidenceDiagnostic: SocialPlaceEvidenceDiagnostic? = nil
    var isSourceOnly: Bool = false
    var reviewState: String? = nil

    init(
        candidateName: String,
        address: String,
        category: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        sourceURL: String?,
        sourceText: String?,
        evidence: [String],
        confidence: Double,
        missingInfo: [String],
        savedAt: Date,
        evidenceDiagnostic: SocialPlaceEvidenceDiagnostic? = nil,
        isSourceOnly: Bool = false,
        reviewState: String? = nil
    ) {
        self.candidateName = candidateName
        self.address = address
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.sourceURL = sourceURL
        self.sourceText = sourceText
        self.evidence = evidence
        self.confidence = confidence
        self.missingInfo = missingInfo
        self.savedAt = savedAt
        self.evidenceDiagnostic = evidenceDiagnostic
        self.isSourceOnly = isSourceOnly
        self.reviewState = reviewState
    }

    private enum CodingKeys: String, CodingKey {
        case candidateName
        case address
        case category
        case latitude
        case longitude
        case sourceURL
        case sourceText
        case evidence
        case confidence
        case missingInfo
        case savedAt
        case evidenceDiagnostic
        case isSourceOnly
        case reviewState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidateName = try container.decode(String.self, forKey: .candidateName)
        address = try container.decode(String.self, forKey: .address)
        category = try container.decode(String.self, forKey: .category)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceText = try container.decodeIfPresent(String.self, forKey: .sourceText)
        evidence = try container.decode([String].self, forKey: .evidence)
        confidence = try container.decode(Double.self, forKey: .confidence)
        missingInfo = try container.decode([String].self, forKey: .missingInfo)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        evidenceDiagnostic = try container.decodeIfPresent(SocialPlaceEvidenceDiagnostic.self, forKey: .evidenceDiagnostic)
        isSourceOnly = try container.decodeIfPresent(Bool.self, forKey: .isSourceOnly) ?? false
        reviewState = try container.decodeIfPresent(String.self, forKey: .reviewState)
    }

    var hasReliableCoordinates: Bool {
        guard let latitude, let longitude else { return false }
        return latitude != 0 || longitude != 0
    }

    var isPlaceBearingSource: Bool {
        reviewState == "place_bearing_source"
    }
}

struct PlaceReviewCandidate: Identifiable, Codable, Hashable {
    var id: UUID
    var captureId: UUID?
    var name: String
    var address: String
    var city: String?
    var latitude: Double?
    var longitude: Double?
    var evidence: [String]
    var confidence: Double?
    var missingInfo: [String]
    var status: String
    var createdAt: Date

    var hasReliableCoordinates: Bool {
        guard let latitude, let longitude else { return false }
        return latitude != 0 || longitude != 0
    }

    var refinementQuery: String {
        [name, address, city]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " ")
    }

    var shareSubject: String {
        "SAV-E Review Candidate: \(name)"
    }

    var saveShareURL: URL? {
        guard let latitude, let longitude, latitude != 0 || longitude != 0 else { return nil }
        let data = SharedTripData(
            name: name,
            city: city ?? "",
            stops: [
                SharedTripData.SharedStop(
                    id: id.uuidString,
                    name: name,
                    address: address,
                    lat: latitude,
                    lng: longitude,
                    time: nil,
                    note: confidence.map { "Confidence: \(Int($0 * 100))%" }
                )
            ]
        )
        return data.toURL()
    }

    var shareText: String {
        var lines = [
            hasReliableCoordinates ? "SAV-E Review Candidate" : "SAV-E Source Clue",
            name
        ]

        if !address.isEmpty {
            lines.append(address)
        }
        if let city, !city.isEmpty {
            lines.append("City: \(city)")
        }
        if let confidence {
            lines.append("Confidence: \(Int(confidence * 100))%")
        }
        if !missingInfo.isEmpty {
            lines.append("Needs: \(missingInfo.joined(separator: ", "))")
        }
        if let saveShareURL {
            lines.append("Open in SAV-E: \(saveShareURL.absoluteString)")
        }
        if let mapsURL = appleMapsURL {
            lines.append("Map fallback: \(mapsURL.absoluteString)")
        }
        let sourceLines = evidence.filter { $0.localizedCaseInsensitiveContains("source") }.prefix(2)
        lines.append(contentsOf: sourceLines)

        return lines.joined(separator: "\n")
    }

    var shareMessage: String {
        [address, city]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " · ")
    }

    var appleMapsURL: URL? {
        guard let latitude, let longitude, latitude != 0 || longitude != 0 else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)")
        ]
        return components?.url
    }
}

final class PendingPlaceImportService {
    static let shared = PendingPlaceImportService()

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func consumePendingPlaces() -> [PendingSharedPlace] {
        consumePendingArray(named: WanderlySharedStorage.pendingPlacesFileName, as: PendingSharedPlace.self)
    }

    func restorePendingPlaces(_ places: [PendingSharedPlace]) {
        appendPendingArray(places, named: WanderlySharedStorage.pendingPlacesFileName)
    }

    func consumePendingReviewCandidates() -> [PendingReviewCandidate] {
        consumePendingArray(named: WanderlySharedStorage.pendingReviewCandidatesFileName, as: PendingReviewCandidate.self)
    }

    func restorePendingReviewCandidates(_ candidates: [PendingReviewCandidate]) {
        appendPendingArray(candidates, named: WanderlySharedStorage.pendingReviewCandidatesFileName)
    }

    private func consumePendingArray<Element: Decodable>(named fileName: String, as elementType: Element.Type) -> [Element] {
        guard let url = pendingFileURL(named: fileName) else { return [] }
        var result: [Element] = []
        coordinate(url: url, purpose: "consume \(fileName)") {
            guard fileManager.fileExists(atPath: url.path) else { return }
            do {
                result = try loadArray([Element].self, from: url)
                try fileManager.removeItem(at: url)
            } catch {
                print("PendingPlaceImportService: preserving unreadable \(fileName): \(error)")
                result = []
            }
        }
        return result
    }

    private func appendPendingArray<Element: Codable>(_ items: [Element], named fileName: String) {
        guard !items.isEmpty, let url = pendingFileURL(named: fileName) else { return }
        coordinate(url: url, purpose: "append \(fileName)") {
            do {
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let existing = try loadArray([Element].self, from: url)
                let data = try JSONEncoder().encode(existing + items)
                try data.write(to: url, options: [.atomic])
            } catch {
                print("PendingPlaceImportService: failed to append \(fileName): \(error)")
            }
        }
    }

    private func loadArray<Element: Decodable>(_ type: [Element].Type, from url: URL) throws -> [Element] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    private func coordinate(url: URL, purpose: String, _ work: () -> Void) {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { _ in
            work()
        }
        if let coordinationError {
            print("PendingPlaceImportService: failed to coordinate \(purpose): \(coordinationError)")
        }
    }

    private func pendingFileURL(named fileName: String) -> URL? {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WanderlySharedStorage.appGroupSuiteName) else {
            return nil
        }
        return containerURL.appendingPathComponent(fileName)
    }
}

extension Place {
    static func from(_ pendingPlace: PendingSharedPlace) -> Place {
        Place(
            id: UUID(),
            name: pendingPlace.name,
            address: pendingPlace.address,
            latitude: pendingPlace.latitude,
            longitude: pendingPlace.longitude,
            googlePlaceId: nil,
            category: PlaceCategory(rawValue: pendingPlace.category) ?? .food,
            status: .wantToGo,
            rating: nil,
            note: pendingPlace.sourceText,
            sourceUrl: pendingPlace.sourceURL,
            sourcePlatform: SourcePlatform.from(urlString: pendingPlace.sourceURL),
            sourceImageUrl: nil,
            extractedDishes: pendingPlace.dishes,
            priceRange: pendingPlace.priceRange,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: pendingPlace.savedAt
        )
    }

    static func from(_ candidate: PlaceReviewCandidate, refinedMatch: GooglePlaceMatch? = nil) -> Place {
        Place(
            id: UUID(),
            name: refinedMatch?.name ?? candidate.name,
            address: refinedMatch?.address ?? candidate.address,
            latitude: refinedMatch?.latitude ?? candidate.latitude ?? 0,
            longitude: refinedMatch?.longitude ?? candidate.longitude ?? 0,
            googlePlaceId: refinedMatch?.id,
            category: PlaceCategory.from(googleTypes: refinedMatch?.types ?? []) ??
                PlaceCategory.inferred(from: "\(candidate.name) \(candidate.address)"),
            status: .wantToGo,
            rating: nil,
            note: candidate.evidence.joined(separator: "\n"),
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: refinedMatch?.rating,
            googlePriceLevel: refinedMatch?.priceLevel,
            openingHours: nil,
            createdAt: Date()
        )
    }

    var pendingDeduplicationKey: String {
        if let normalizedSourceURL = sourceUrl?.normalizedDeduplicationURLString() {
            return normalizedSourceURL
        }
        return "\(name)|\(address)|\(createdAt.timeIntervalSince1970)"
    }

    func matches(_ pendingPlace: PendingSharedPlace) -> Bool {
        pendingDeduplicationKey == pendingPlace.deduplicationKey || (
            name == pendingPlace.name &&
            address == pendingPlace.address &&
            sourceUrl == pendingPlace.sourceURL
        )
    }

    func matches(_ other: Place) -> Bool {
        pendingDeduplicationKey == other.pendingDeduplicationKey || (
            name == other.name &&
            address == other.address &&
            sourceUrl == other.sourceUrl
        )
    }
}

extension PlaceCategory {
    static func from(pointOfInterestCategory category: MKPointOfInterestCategory?) -> PlaceCategory? {
        guard let category else { return nil }
        return fromPOIText(category.rawValue)
    }

    static func from(googleTypes types: [String]) -> PlaceCategory? {
        fromPOIText(types.joined(separator: " "))
    }

    static func poiFirst(
        pointOfInterestCategory: MKPointOfInterestCategory?,
        googleTypes: [String] = [],
        fallbackText: String
    ) -> PlaceCategory {
        if let category = from(pointOfInterestCategory: pointOfInterestCategory) {
            return category
        }
        if let category = from(googleTypes: googleTypes) {
            return category
        }
        return inferred(from: fallbackText)
    }

    static func inferred(from content: String, fallback: PlaceCategory = .food) -> PlaceCategory {
        let lowercased = content
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        if matches(lowercased, #"\b(airbnb|stay|hotel|resort|villa|motel|lodge|inn|glamping|retreat)\b|住宿|飯店|酒店|旅館|民宿"#) {
            return .stay
        }
        if matches(lowercased, #"\b(cafe|coffee|bakery|boba|milk tea|teahouse|tea house|dessert|patisserie|espresso)\b|咖啡|奶茶|珍珠|甜點|甜点|烘焙|麵包|面包"#) {
            return .cafe
        }
        if matches(lowercased, #"\b(restaurant|food|eat|dining|dinner|lunch|breakfast|brunch|sushi|ramen|noodle|pizza|taco|burger|sandwich|bbq|barbecue|steak|hot pot|sukiyaki|yakiniku|izakaya)\b|餐廳|餐厅|美食|料理|燒肉|烧肉|火鍋|火锅|壽喜燒|寿喜烧|牛舌|拉麵|拉面|壽司|寿司"#) {
            return .food
        }
        if matches(lowercased, #"\b(bar|pub|cocktail|wine|brewery|tavern|speakeasy|nightlife)\b|酒吧|調酒|调酒|啤酒|葡萄酒"#) {
            return .bar
        }
        if matches(lowercased, #"\b(shop|store|market|mall|boutique|bookstore|pharmacy|spa|salon|massage|barber|beauty|fitness|gym|yoga|wellness|clinic|bank|atm|laundry)\b|商店|市場|市场|購物|购物|按摩|美容|健身|藥局|药房|銀行|银行"#) {
            return .shopping
        }
        if matches(lowercased, #"\b(museum|park|event|gallery|festival|summit|conference|theater|theatre|cinema|movie|stadium|zoo|aquarium|beach|landmark|monument|temple|shrine|church|library|school|university|airport|station|pier|garden)\b|博物館|博物馆|公園|公园|展覽|展览|景點|景点|寺|機場|机场|車站|车站"#) {
            return .attraction
        }

        return fallback
    }

    static func inferredMapCategory(
        title: String,
        subtitle: String,
        pointOfInterestCategory: String?,
        fallback: PlaceCategory
    ) -> PlaceCategory {
        let poi = pointOfInterestCategory?
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased() ?? ""

        if let category = fromPOIText(poi) { return category }

        return inferred(
            from: "\(title) \(subtitle) \(pointOfInterestCategory ?? "")",
            fallback: fallback
        )
    }

    private static func fromPOIText(_ value: String) -> PlaceCategory? {
        let normalized = value
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        if matches(normalized, #"cafe|coffee|bakery|tea|dessert|patisserie"#) {
            return .cafe
        }
        if matches(normalized, #"restaurant|meal|food|foodtruck"#) {
            return .food
        }
        if matches(normalized, #"bar|nightlife|brewery|winery|liquor|pub"#) {
            return .bar
        }
        if matches(normalized, #"lodging|hotel|motel|resort|campground"#) {
            return .stay
        }
        if matches(normalized, #"store|shop|mall|market|pharmacy|supermarket|spa|fitness|beauty|salon|massage|gym|bank|atm|laundry"#) {
            return .shopping
        }
        if matches(normalized, #"museum|park|tourist|attraction|gallery|zoo|aquarium|theater|theatre|cinema|movie|stadium|airport|school|university|library|hospital|doctor|dentist|parking|station|transit|charger|evcharger|gas|post|courthouse|government|cityhall|police|fire|religious|church|worship|nationalpark|amusementpark|fairground|conventioncenter|musicvenue|publictransport|landmark|beach"#) {
            return .attraction
        }

        return nil
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

extension PendingSharedPlace {
    var deduplicationKey: String {
        if let normalizedSourceURL = sourceURL?.normalizedDeduplicationURLString() {
            return normalizedSourceURL
        }
        return "\(name)|\(address)|\(savedAt.timeIntervalSince1970)"
    }
}

extension SourcePlatform {
    static func from(urlString: String?) -> SourcePlatform {
        guard let url = urlString.flatMap(URL.init(string:)),
              let host = url.host()?.lowercased() else {
            return .other
        }
        if host.matchesDomain("instagram.com") { return .instagram }
        if host.matchesDomain("threads.net") || host.matchesDomain("threads.com") { return .threads }
        if host.matchesDomain("xiaohongshu.com") || host.matchesDomain("xhslink.com") { return .xiaohongshu }
        if host.isGoogleMapsHost(path: url.path, queryItems: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems) {
            return .googleMaps
        }
        return .other
    }
}

private extension String {
    func normalizedDeduplicationURLString() -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if components.path == "/" {
            components.path = ""
        }

        components.queryItems = components.queryItems?
            .filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && name != "fbclid"
            }
            .sorted { lhs, rhs in
                let lhsName = lhs.name.lowercased()
                let rhsName = rhs.name.lowercased()
                if lhsName != rhsName {
                    return lhsName < rhsName
                }
                return (lhs.value ?? "") < (rhs.value ?? "")
            }

        if components.queryItems?.isEmpty == true {
            components.queryItems = nil
        }

        return components.string
    }

    func matchesDomain(_ domain: String) -> Bool {
        self == domain || hasSuffix(".\(domain)")
    }

    func isGoogleMapsHost(path: String, queryItems: [URLQueryItem]?) -> Bool {
        if self == "maps.google.com" {
            return true
        }

        let lowercasedPath = path.lowercased()
        if matchesDomain("google.com"), lowercasedPath.hasPrefix("/maps") {
            return true
        }

        if matchesDomain("maps.app.goo.gl") {
            return true
        }

        guard self == "goo.gl" || self == "g.co" else {
            return false
        }

        return lowercasedPath.contains("maps") || (queryItems ?? []).contains { item in
            let name = item.name.lowercased()
            return name == "q" || name == "ll"
        }
    }
}
