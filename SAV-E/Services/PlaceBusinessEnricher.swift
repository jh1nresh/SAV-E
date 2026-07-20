import Foundation
import CoreLocation

/// Shared business-details enrichment used by both `PlaceDetailView` and
/// `PlaceBottomSheet` so they stay in sync. Resolves Google Places photo
/// references / rating / price / hours for a place and returns an updated
/// `Place` with the new values merged in (existing values win).
enum PlaceBusinessEnricher {
    struct Update {
        let photoURLs: [URL]
        let rating: Double?
        let priceRange: String?
        let openingHours: String?
    }

    /// Whether the place is still missing details worth fetching. Mirrors the
    /// guard used historically in `PlaceDetailView.enrichBusinessDetails`.
    static func needsEnrichment(_ place: Place) -> Bool {
        place.businessPhotoURLStrings.count < 2 ||
            place.googleRating == nil ||
            place.priceRange == nil ||
            place.openingHours == nil
    }

    /// Returns a place with freshly enriched fields merged in, or `nil` if no
    /// new details were found. Never overwrites values the place already has.
    static func enrich(
        _ place: Place,
        service: GooglePlacesServiceProtocol = GooglePlacesService.shared
    ) async -> Place? {
        guard needsEnrichment(place) else { return nil }
        guard let update = await businessDetails(for: place, service: service) else { return nil }

        var updated = place
        if !update.photoURLs.isEmpty {
            let urls = update.photoURLs.map(\.absoluteString)
            updated.sourceImageUrl = updated.sourceImageUrl ?? urls.first
            updated.businessPhotoUrls = urls
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
        return photoURLs.isEmpty ? nil : photoURLs
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

        return Update(
            photoURLs: photoURLs,
            rating: details?.rating ?? fallbackMatch?.rating,
            priceRange: priceLevel.map { String(repeating: "$", count: max(1, $0)) },
            openingHours: details?.openingHours?.first
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
            // Match against the visible name AND any alternate lookup name (e.g.
            // a customized place keeps its original business name) so every
            // surface resolves the same Google Place.
            let lookupNames = [name, alternateName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return matches.first { match in
                let matchLocation = CLLocation(latitude: match.latitude, longitude: match.longitude)
                let sameArea = targetLocation.distance(from: matchLocation) < 250
                let sameName = lookupNames.contains { lookupName in
                    match.name.localizedCaseInsensitiveContains(lookupName) ||
                        lookupName.localizedCaseInsensitiveContains(match.name)
                }
                return sameArea || sameName
            }
        } catch {
            return nil
        }
    }
}
