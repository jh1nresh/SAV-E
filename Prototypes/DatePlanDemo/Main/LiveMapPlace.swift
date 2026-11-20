#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation
import MapKit

enum LiveMapOrigin: Equatable {
    case saved, search, shared, publicPost
}

/// An ephemeral venue projection. Only `.saved` represents the account's collection.
/// Creating or sharing this value never confirms a place or records a visit.
struct LiveMapPlace: Identifiable {
    let id: String
    let place: Place
    let origin: LiveMapOrigin
    let sourceLabel: String
    var nativeMapItem: MKMapItem? = nil
    var publicSourceURL: String? = nil
    var publicSourcePlatform: SourcePlatform? = nil
    private let payload: SaveListItem

    var coordinate: CLLocationCoordinate2D { place.coordinate }
    var listPayload: SaveListItem { payload }

    /// Reuse the canonical venue identity rule; preserve the account's real ID,
    /// note and visit state instead of relabeling a native duplicate as unsaved.
    func existingSavedProjection(in places: [Place]) -> LiveMapPlace? {
        guard let owned = places.first(where: { $0.matches(place) }),
              var projection = Self.saved(owned) else { return nil }
        projection.nativeMapItem = nativeMapItem
        return projection
    }

    /// User confirmation input only. A projection does not become a saved place until
    /// the canonical MapViewModel save completes; no sender memory becomes evidence.
    var confirmationCandidate: SaveMapCandidate? {
        guard origin != .saved, place.isMapKitMappable else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: place.name),
                                 URLQueryItem(name: "ll", value: "\(place.latitude),\(place.longitude)")]
        return SaveMapCandidate(
            id: id, title: place.name, subtitle: place.address,
            latitude: place.latitude, longitude: place.longitude,
            category: payload.category,
            sourceURL: origin == .publicPost ? publicSourceURL : (origin == .search ? components.url?.absoluteString : nil),
            sourcePlatform: origin == .publicPost ? (publicSourcePlatform ?? .other) : (origin == .search ? .appleMaps : .other),
            evidence: origin == .search ? ["Apple Maps POI"] : []
        )
    }

    static func saved(_ place: Place) -> LiveMapPlace? {
        guard place.isMapKitMappable else { return nil }
        let id = "saved:\(place.id.uuidString)"
        let payload = venuePayload(
            id: id, source: .savedPlace, sourceID: place.id.uuidString,
            name: place.name, address: place.address,
            latitude: place.latitude, longitude: place.longitude, category: place.category,
            coordinateSystem: place.coordinateSystem, provider: place.locationProvider,
            googleID: place.googlePlaceId, addedAt: place.createdAt
        )
        // Preserve the actual saved value, including its status; sanitize only the payload.
        return LiveMapPlace(id: id, place: place, origin: .saved,
                            sourceLabel: "已收藏", payload: payload)
    }

    static func search(_ item: MKMapItem) -> LiveMapPlace? {
        let name = (item.name ?? item.placemark.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let coordinate = item.placemark.coordinate
        let address = item.placemark.title ?? ""
        let providerID: String?
        if #available(iOS 18.0, *) {
            providerID = item.identifier?.rawValue
        } else {
            providerID = nil
        }
        // Bit patterns avoid locale/rounding changes. Length prefixes avoid ambiguous joins.
        let fallback = "\(name.utf8.count):\(name):\(address.utf8.count):\(address):"
            + "\(coordinate.latitude.bitPattern):\(coordinate.longitude.bitPattern)"
        let id = "search:\(stableUUID(providerID ?? fallback).uuidString)"
        let payload = venuePayload(
            id: id, source: .mapCandidate, sourceID: providerID ?? id,
            name: name, address: address,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            category: PlaceCategory.from(pointOfInterestCategory: item.pointOfInterestCategory),
            coordinateSystem: .wgs84, provider: .appleMaps, googleID: nil,
            addedAt: unknownCreationDate
        )
        var place = candidatePlace(payload, markerID: id)
        place.sourcePlatform = .appleMaps
        place.providerPlaceId = providerID
        var projection = candidate(id: id, place: place, origin: .search,
                                   label: "搜尋結果候選", payload: payload)
        projection?.nativeMapItem = item
        return projection
    }

    static func shared(_ item: SaveListItem, listID: UUID) -> LiveMapPlace? {
        let id = "list:\(listID.uuidString):\(item.id.uuidString)"
        let payload = venuePayload(
            id: id, source: .mapCandidate, sourceID: item.source == .mapCandidate ? item.sourceID : id,
            name: item.title, address: item.subtitle,
            latitude: item.latitude, longitude: item.longitude, category: item.category,
            coordinateSystem: item.coordinateSystem, provider: item.locationProvider,
            googleID: item.googlePlaceId, addedAt: item.addedAt
        )
        return candidate(id: id, place: candidatePlace(payload, markerID: id),
                         origin: .shared, label: "隊伍候選", payload: payload)
    }

    static func sharedPost(_ post: SharedPlacePost) -> LiveMapPlace? {
        guard let latitude = post.latitude, let longitude = post.longitude else { return nil }
        let id = "post:\(post.id.uuidString)"
        let payload = venuePayload(
            id: id, source: .mapCandidate, sourceID: post.provider_place_id ?? id,
            name: post.name, address: post.address, latitude: latitude, longitude: longitude,
            category: PlaceCategory(rawValue: post.category),
            coordinateSystem: post.coordinate_system, provider: post.location_provider,
            googleID: post.google_place_id,
            addedAt: ISO8601DateFormatter().date(from: post.shared_at) ?? unknownCreationDate
        )
        var place = candidatePlace(payload, markerID: id)
        place.providerPlaceId = post.provider_place_id
        // The author's status, caption, stars and identity are not recipient memory.
        return candidate(id: id, place: place, origin: .shared,
                         label: "朋友已分享", payload: payload)
    }

    static func discovery(_ venue: LivePublicDiscoveryVenue) -> LiveMapPlace? {
        let value = venue.place
        let id = "public:\(venue.id)"
        let payload = venuePayload(id: id, source: .mapCandidate, sourceID: value.providerPlaceID,
            name: value.name, address: value.address, latitude: value.latitude, longitude: value.longitude,
            category: PlaceCategory(rawValue: value.category), coordinateSystem: .wgs84,
            provider: PlaceMatchProvider(rawValue: value.provider), googleID: nil, addedAt: unknownCreationDate)
        var place = candidatePlace(payload, markerID: id)
        place.providerPlaceId = value.providerPlaceID
        var pin = candidate(id: id, place: place, origin: .publicPost, label: "公開貼文 · 尚未收藏", payload: payload)
        pin?.publicSourceURL = venue.posts.first?.sourceURL
        pin?.publicSourcePlatform = venue.posts.first.flatMap { SourcePlatform(rawValue: $0.platform) }
        return pin
    }

    private static func candidate(
        id: String, place: Place, origin: LiveMapOrigin, label: String, payload: SaveListItem
    ) -> LiveMapPlace? {
        guard place.isMapKitMappable else { return nil }
        return LiveMapPlace(id: id, place: place, origin: origin, sourceLabel: label, payload: payload)
    }

    private static func candidatePlace(_ payload: SaveListItem, markerID: String) -> Place {
        var place = payload.asPlace(id: stableUUID(markerID), createdAt: payload.addedAt,
                                    includeSenderMemory: false)
        // Place requires a category; keep unknown payload categories nil rather than exporting
        // this generic display fallback as source evidence. `.wantToGo` is its candidate default,
        // never proof of a confirmed save; `origin` remains the collection-membership authority.
        place.category = payload.category ?? .attraction
        place.recommender = nil
        return place
    }

    /// Explicit allowlist: never use `from(place:)`, which includes private memory and photos.
    private static func venuePayload(
        id: String, source: SaveListItemSource, sourceID: String,
        name: String, address: String, latitude: Double, longitude: Double,
        category: PlaceCategory?, coordinateSystem: PlaceCoordinateSystem?,
        provider: PlaceMatchProvider?, googleID: String?, addedAt: Date
    ) -> SaveListItem {
        SaveListItem(
            id: stableUUID(id), source: source, sourceID: sourceID,
            title: name, subtitle: address, latitude: latitude, longitude: longitude,
            category: category, rating: nil, reviewCount: nil, sourceURL: nil,
            photoURLs: [], note: nil, addedByDisplayName: "", addedAt: addedAt,
            extraPlaceIds: nil, coordinateSystem: coordinateSystem, locationProvider: provider,
            providerMapUrl: nil, googlePlaceId: googleID
        )
    }

    private static func stableUUID(_ source: String) -> UUID {
        SaveRecipientPlaceIdentity.id(source: "live-map:\(source)", ownerSubject: nil)
    }

    // Required storage field only; a search result provides no venue creation timestamp.
    private static var unknownCreationDate: Date { Date(timeIntervalSince1970: 0) }
}
#endif
