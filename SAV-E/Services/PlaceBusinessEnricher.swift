import Foundation
import CoreLocation

/// Shared business-details enrichment for the canonical saved-place detail.
/// Resolves Google Places photo references / rating / price / hours for a place
/// and returns an updated `Place` with the new values merged in (existing
/// values win).
enum PlaceBusinessEnricher {
    struct Update {
        let photoURLs: [URL]
        let rating: Double?
        let priceRange: String?
        let openingHours: String?
        let resolvedGooglePlaceId: String?
        let replacedProviderMatch: Bool
    }

    /// The photo carousel should offer a real gallery, not a single shot.
    /// Places below this depth re-enrich (Google returns up to 6 here).
    static let desiredPhotoDepth = 5

    /// Whether the place is still missing details worth fetching.
    static func needsEnrichment(_ place: Place) -> Bool {
        place.businessPhotoURLStrings.count < desiredPhotoDepth ||
            place.googleRating == nil ||
            place.priceRange == nil ||
            place.openingHours == nil
    }

    /// Returns a place with freshly enriched fields merged in, or `nil` if no
    /// new details were found. Existing photos stay first unless a stale Google
    /// ID was rebound to a tighter match.
    static func enrich(
        _ place: Place,
        service: GooglePlacesServiceProtocol = GooglePlacesService.shared
    ) async -> Place? {
        guard needsEnrichment(place) else { return nil }
        guard let update = await businessDetails(for: place, service: service) else { return nil }

        var updated = place
        if !update.photoURLs.isEmpty {
            let urls = update.photoURLs.map(\.absoluteString)
            if update.replacedProviderMatch {
                // A stale or wrong Google ID rebound to this place. Put the
                // recovered photos first so Home cards do not keep another
                // business's cover.
                updated.businessPhotoUrls = (urls + (updated.businessPhotoUrls ?? []))
                    .removingDuplicatePhotoURLs()
            } else {
                updated.businessPhotoUrls = ((updated.businessPhotoUrls ?? []) + urls)
                    .removingDuplicatePhotoURLs()
            }
        }
        if let resolvedGooglePlaceId = update.resolvedGooglePlaceId {
            updated.googlePlaceId = resolvedGooglePlaceId
        }
        updated.googleRating = updated.googleRating ?? update.rating
        updated.priceRange = updated.priceRange ?? update.priceRange
        updated.openingHours = updated.openingHours ?? update.openingHours
        return updated
    }

    /// Fetches Google Places business photo URLs for an unsaved map candidate.
    /// The candidate is a lightweight value type (no `Place`), so this resolves
    /// photos by best-match search on name + coordinates. Returns `nil` if no
    /// new photos were found. Never throws — safe for fire-and-forget `.task`.
    static func candidatePhotoURLs(
        for candidate: SaveMapCandidate,
        service: GooglePlacesServiceProtocol = GooglePlacesService.shared
    ) async -> [String]? {
        let urls = await enrichedCandidate(candidate, service: service)?.businessPhotoURLs
        return urls?.isEmpty == false ? urls : nil
    }

    /// Fully enriches an unsaved map candidate — photos, rating, review count,
    /// price, hours, category, and a real address for placeholder subtitles —
    /// by best-match Google Places lookup. Existing candidate values win.
    /// Returns `nil` when no new details were found. Never throws — safe for
    /// fire-and-forget `.task`, and self-contained so any surface (drawer,
    /// full-screen detail) can enrich without depending on map selection state.
    static func enrichedCandidate(
        _ candidate: SaveMapCandidate,
        service: GooglePlacesServiceProtocol = GooglePlacesService.shared
    ) async -> SaveMapCandidate? {
        let coordinate = CLLocationCoordinate2D(latitude: candidate.latitude, longitude: candidate.longitude)
        guard let match = await bestGoogleMatch(
            name: candidate.title,
            address: candidate.subtitle,
            coordinate: coordinate,
            service: service
        ) else { return nil }

        let details = try? await service.getPlaceDetails(placeId: match.id)
        let photoReferences = details?.photoReferences?.isEmpty == false
            ? details?.photoReferences ?? []
            : [match.photoReference].compactMap { $0 }
        let photoURLs = photoReferences
            .prefix(6)
            .compactMap { service.photoURL(reference: $0, maxWidth: 900) }
            .map(\.absoluteString)
        let rating = details?.rating ?? match.rating
        let priceLevel = details?.priceLevel ?? match.priceLevel
        let openingHours = details?.openingHours?.first
        let hasDetails = !photoURLs.isEmpty ||
            rating != nil ||
            match.reviewCount != nil ||
            priceLevel != nil ||
            openingHours != nil
        guard hasDetails else { return nil }

        var updated = candidate
        if !photoURLs.isEmpty {
            updated.photoURL = updated.photoURL ?? photoURLs.first
            updated.businessPhotoURLs = photoURLs
        }
        updated.rating = updated.rating ?? rating
        updated.reviewCount = updated.reviewCount ?? match.reviewCount
        if let category = PlaceCategory.from(googleTypes: details?.types ?? match.types) {
            updated.category = category
        }
        // POI taps carry "Selected on map" instead of an address; show the
        // matched street address once Google resolves one.
        let address = (details?.formattedAddress ?? match.address)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let existingSubtitle = updated.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty, existingSubtitle.isEmpty || existingSubtitle == "Selected on map" {
            updated.subtitle = address
        }
        if let priceLevel,
           !updated.evidence.contains(where: { $0.localizedCaseInsensitiveContains("Price:") }) {
            updated.evidence.append("Price: \(String(repeating: "$", count: max(1, priceLevel)))")
        }
        if let openingHours,
           !updated.evidence.contains(where: { $0.localizedCaseInsensitiveContains("Hours:") }) {
            updated.evidence.append("Hours: \(openingHours)")
        }
        return updated
    }

    private static func businessDetails(
        for place: Place,
        service: GooglePlacesServiceProtocol
    ) async -> Update? {
        var details: GooglePlaceDetails?
        var fallbackMatch: GooglePlaceMatch?
        if let googlePlaceId = place.googlePlaceId {
            details = try? await service.getPlaceDetails(placeId: googlePlaceId)

            // Saved provider IDs can become stale or point to a record without
            // photos. Recover by matching the current name, address, and
            // coordinates instead of leaving the sheet permanently empty.
            if details?.photoReferences?.isEmpty != false {
                fallbackMatch = await bestGoogleMatch(
                    name: place.name,
                    alternateName: place.businessLookupName,
                    address: place.address,
                    coordinate: place.coordinate,
                    service: service
                )
                if let fallbackMatch,
                   let recoveredDetails = try? await service.getPlaceDetails(placeId: fallbackMatch.id) {
                    details = recoveredDetails
                }
            }
        } else {
            guard let match = await bestGoogleMatch(
                name: place.name,
                alternateName: place.businessLookupName,
                address: place.address,
                coordinate: place.coordinate,
                service: service
            ) else { return nil }
            details = try? await service.getPlaceDetails(placeId: match.id)
            fallbackMatch = match
        }

        let photoReferences = details?.photoReferences?.isEmpty == false
            ? details?.photoReferences ?? []
            : [fallbackMatch?.photoReference].compactMap { $0 }
        let photoURLs = photoReferences
            .prefix(6)
            .compactMap { service.photoURL(reference: $0, maxWidth: 900) }
        let priceLevel = details?.priceLevel ?? fallbackMatch?.priceLevel
        let hasDetails = !photoURLs.isEmpty ||
            details?.rating != nil ||
            fallbackMatch?.rating != nil ||
            priceLevel != nil ||
            details?.openingHours?.isEmpty == false
        guard hasDetails else { return nil }

        let resolvedGooglePlaceId = details.flatMap { value -> String? in
            let trimmed = value.placeId.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } ?? fallbackMatch?.id
        let replacedProviderMatch = place.googlePlaceId != nil
            && resolvedGooglePlaceId != place.googlePlaceId

        return Update(
            photoURLs: photoURLs,
            rating: details?.rating ?? fallbackMatch?.rating,
            priceRange: priceLevel.map { String(repeating: "$", count: max(1, $0)) },
            openingHours: details?.openingHours?.first,
            resolvedGooglePlaceId: resolvedGooglePlaceId,
            replacedProviderMatch: replacedProviderMatch
        )
    }

    private static func bestGoogleMatch(
        name: String,
        alternateName: String? = nil,
        address: String,
        coordinate: CLLocationCoordinate2D,
        service: GooglePlacesServiceProtocol
    ) async -> GooglePlaceMatch? {
        do {
            let matches = try await service.searchPlace(
                query: "\(name) \(address)",
                near: coordinate
            )
            return matches
                .compactMap { match -> (match: GooglePlaceMatch, score: Double)? in
                    guard let score = PlaceBusinessMatchPolicy.score(
                        name: name,
                        alternateName: alternateName,
                        coordinate: coordinate,
                        match: match
                    ) else { return nil }
                    return (match, score)
                }
                .min { $0.score < $1.score }?
                .match
        } catch {
            return nil
        }
    }
}

/// Tight Home/detail photo matching. A same-name hit 2 km away, or a nameless
/// shop 35 m away, can bind another place's cover to a Map Stamp card.
enum PlaceBusinessMatchPolicy {
    static let namedMatchMaxDistanceMeters: CLLocationDistance = 250
    static let minimumSharedNameLength = 4

    static func score(
        name: String,
        alternateName: String? = nil,
        coordinate: CLLocationCoordinate2D,
        match: GooglePlaceMatch
    ) -> Double? {
        let lookupNames = [name, alternateName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let candidate = CLLocation(latitude: match.latitude, longitude: match.longitude)
        let distance = target.distance(from: candidate)
        guard namesAlign(lookupNames, matchName: match.name) else { return nil }
        guard distance < namedMatchMaxDistanceMeters else { return nil }
        return distance
    }

    static func namesAlign(_ lookupNames: [String], matchName: String) -> Bool {
        lookupNames.contains { distinctiveOverlap($0, matchName) }
    }

    private static func distinctiveOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalize(lhs)
        let right = normalize(rhs)
        if left.isEmpty || right.isEmpty { return false }
        if left == right { return true }
        let shorter = left.count <= right.count ? left : right
        let longer = left.count <= right.count ? right : left
        guard shorter.count >= minimumSharedNameLength else { return false }
        return longer.contains(shorter)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Array where Element == String {
    func removingDuplicatePhotoURLs() -> [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}
