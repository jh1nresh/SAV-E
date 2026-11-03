import CoreLocation
import Foundation
import MapKit

/// Reads the three place stores the ink Home can see and keeps one row per venue.
///
/// `save.ink.places.v1` has no coordinates. Legacy Map Stamps live in the local
/// vault, and the Share Extension appends `pending-places.json`. This catalog
/// dedupes those sources and attaches WGS84 coordinates when a source has them.
/// Supabase sync uses the existing `places` client. No schema migration.
enum SaveInkPlaceCatalog {
    static func venueKey(_ name: String) -> String {
        let folded = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var scalars: [Unicode.Scalar] = []
        for scalar in folded.unicodeScalars where CharacterSet.alphanumerics.contains(scalar) {
            scalars.append(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    static func minutes(fromTravelTime seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 1 }
        return max(1, Int((seconds / 60.0).rounded()))
    }

    /// One row per venue. A pending or ink row that `Place.matches` an existing
    /// stamp keeps the stamp. An ink row whose name matches exactly one stamp
    /// adopts that stamp's coordinates and keeps the ink id so visits stay attached.
    static func merge(
        ink: [SaveInkPlace],
        confirmed: [Place],
        pending: [PendingSharedPlace],
        userLocation: CLLocation?
    ) -> [SaveInkPlace] {
        var canonical = confirmed.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for item in pending {
            let candidate = Place.from(item)
            guard !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if canonical.contains(where: { $0.matches(candidate) }) { continue }
            canonical.append(candidate)
        }
        canonical = Place.consolidated(canonical)

        var remaining = canonical
        var rows: [SaveInkPlace] = []
        var seenInkKeys = Set<String>()
        for inkPlace in ink {
            let key = venueKey(inkPlace.name)
            let sameName = remaining.indices.filter { venueKey(remaining[$0].name) == key && !key.isEmpty }
            if sameName.count == 1, let index = sameName.first {
                let place = remaining.remove(at: index)
                rows.append(row(place: place, ink: inkPlace))
                seenInkKeys.insert(key)
                continue
            }
            if key.isEmpty || seenInkKeys.insert(key).inserted {
                rows.append(inkPlace)
            }
        }
        for place in remaining {
            rows.append(row(place: place, ink: nil))
        }
        return sortedByDistance(applyingDistance(rows, from: userLocation))
    }

    static func applyingDistance(_ places: [SaveInkPlace], from location: CLLocation?) -> [SaveInkPlace] {
        places.map { place in
            var copy = place
            guard let location, let latitude = place.shopLatitude, let longitude = place.shopLongitude else {
                if place.shopLatitude == nil { copy.distanceMeters = nil }
                return copy
            }
            let shop = CLLocation(latitude: latitude, longitude: longitude)
            copy.distanceMeters = location.distance(from: shop)
            return copy
        }
    }

    static func sortedByDistance(_ places: [SaveInkPlace]) -> [SaveInkPlace] {
        places.enumerated().sorted { lhs, rhs in
            switch (lhs.element.distanceMeters, rhs.element.distanceMeters) {
            case let (left?, right?) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                let nameOrder = lhs.element.name.localizedStandardCompare(rhs.element.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    static func row(place: Place, ink: SaveInkPlace?) -> SaveInkPlace {
        let name = nonempty(ink?.name) ?? nonempty(place.name) ?? ""
        let address = nonempty(place.address) ?? ""
        let street = nonempty(ink?.street) ?? address
        let visited = ink?.badge == .visited || place.status == .visited
        let badge: SaveInkPlaceBadge = visited ? .visited : .saved
        let note = clipped(place.userFacingNote)
        let blurb = nonempty(ink?.blurb) ?? note ?? (visited ? "你去過" : "存了，還沒去")
        let source = nonempty(ink?.sourceLabel)
            ?? ((place.sourceUrl?.isEmpty == false) ? "來自 分享" : "來自 已存的地點")
        let mappable = place.isMapKitMappable
        return SaveInkPlace(
            id: ink?.id ?? place.id.uuidString,
            name: name,
            stampName: nonempty(ink?.stampName) ?? name,
            street: street.isEmpty ? name : street,
            distanceMeters: nil,
            blurb: blurb,
            sourceLabel: source,
            badge: badge,
            detailNote: nonempty(ink?.detailNote) ?? note ?? blurb,
            friendUsualCount: ink?.friendUsualCount ?? 0,
            walkMinutes: ink?.walkMinutes,
            addressLine: address.isEmpty ? ink?.addressLine : address,
            videoTitle: ink?.videoTitle,
            videoSource: ink?.videoSource,
            shopLatitude: mappable ? place.latitude : ink?.shopLatitude,
            shopLongitude: mappable ? place.longitude : ink?.shopLongitude
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clipped(_ text: String?) -> String? {
        guard let trimmed = nonempty(text) else { return nil }
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80))
    }
}

/// Offline-first. A failed fetch or save leaves the local stamps in place.
/// Successful fetches union remote rows, then upload local rows the server
/// does not already have. Uses `public.places` through the existing client;
/// this does not migrate the schema.
@MainActor
enum SaveInkPlaceSync {
    static func reconcile(
        local: [Place],
        userId: String?,
        remote: any SaveInkPlaceRemote
    ) async -> [Place] {
        guard let userId, !userId.isEmpty, remote.isConfigured else { return local }
        let remotePlaces: [Place]
        do {
            remotePlaces = try await remote.fetchPlaces(for: userId)
        } catch {
            return local
        }
        let merged = Place.consolidated(remotePlaces + local)
        for place in local where !remotePlaces.contains(where: { $0.matches(place) }) {
            do {
                try await remote.savePlace(place, userId: userId)
            } catch {
                continue
            }
        }
        return merged
    }
}

protocol SaveInkPlaceRemote {
    var isConfigured: Bool { get }
    func fetchPlaces(for userId: String) async throws -> [Place]
    func savePlace(_ place: Place, userId: String) async throws
}

extension SupabaseService: SaveInkPlaceRemote {}

struct SaveInkLivePlaceLoad {
    var places: [SaveInkPlace]
    var userCoordinate: CLLocationCoordinate2D?
}

@MainActor
struct SaveInkLivePlaceLoader {
    var localPlaces: @MainActor ([SaveInkPlace]) -> [SaveInkPlace]
    var load: @MainActor ([SaveInkPlace]) async -> SaveInkLivePlaceLoad

    static let inactive = SaveInkLivePlaceLoader(
        localPlaces: { $0 },
        load: { ink in SaveInkLivePlaceLoad(places: ink, userCoordinate: nil) }
    )

    static func production() -> SaveInkLivePlaceLoader {
        let engine = SaveInkLivePlaceEngine.production()
        return SaveInkLivePlaceLoader(
            localPlaces: { engine.localPlaces(ink: $0) },
            load: { await engine.load(ink: $0) }
        )
    }
}

@MainActor
struct SaveInkLivePlaceEngine {
    var vault: SaveLocalVaultService
    var pending: PendingPlaceImportService
    var remote: any SaveInkPlaceRemote
    var userID: @MainActor () async -> String?
    var location: @MainActor () async -> CLLocation?
    var resolveCoordinate: @MainActor (String, CLLocation?) async -> CLLocationCoordinate2D?
    var walkingMinutes: @MainActor (CLLocation, CLLocationCoordinate2D) async -> Int?

    static func production() -> SaveInkLivePlaceEngine {
        SaveInkLivePlaceEngine(
            vault: .shared,
            pending: .shared,
            remote: SupabaseService.shared,
            userID: {
                if let owner = try? await PrivyAuthService.shared.resolvedActiveOwner().ownerSubject {
                    return owner
                }
                return PrivyAuthService.shared.currentUserId
            },
            location: {
                await LocationService.shared.requestCurrentLocation()
            },
            resolveCoordinate: { name, near in
                await SaveInkMapKitLookup.coordinate(forName: name, near: near)
            },
            walkingMinutes: { origin, destination in
                await SaveInkMapKitLookup.walkingMinutes(from: origin, to: destination)
            }
        )
    }

    func localPlaces(ink: [SaveInkPlace]) -> [SaveInkPlace] {
        let owner = PrivyAuthService.shared.currentUserId
        let confirmed = (try? vault.confirmedPlaces(limit: 500, belongingTo: owner)) ?? []
        let queued = pending.peekPendingPlaces(ownerSubject: owner)
        return SaveInkPlaceCatalog.merge(ink: ink, confirmed: confirmed, pending: queued, userLocation: nil)
    }

    func load(ink: [SaveInkPlace]) async -> SaveInkLivePlaceLoad {
        let owner = await userID()
        var confirmed = (try? vault.confirmedPlaces(limit: 500, belongingTo: owner)) ?? []
        let queued = pending.peekPendingPlaces(ownerSubject: owner)
        for item in queued {
            let candidate = Place.from(item)
            guard !confirmed.contains(where: { $0.matches(candidate) }) else { continue }
            guard (try? vault.saveConfirmedPlace(candidate, ownerSubject: owner)) != nil else { continue }
            if let refreshed = try? vault.confirmedPlaces(limit: 500, belongingTo: owner) {
                confirmed = refreshed
            }
        }
        let reconciled = await SaveInkPlaceSync.reconcile(local: confirmed, userId: owner, remote: remote)
        for place in reconciled where !confirmed.contains(where: { $0.matches(place) }) {
            guard (try? vault.saveConfirmedPlace(place, ownerSubject: owner)) != nil else { continue }
            confirmed.append(place)
        }
        let userLocation = await location()
        var rows = SaveInkPlaceCatalog.merge(
            ink: ink,
            confirmed: reconciled,
            pending: queued,
            userLocation: userLocation
        )
        var resolved = 0
        for index in rows.indices where rows[index].shopLatitude == nil && resolved < 5 {
            let name = rows[index].name
            guard let coordinate = await resolveCoordinate(name, userLocation) else { continue }
            rows[index].shopLatitude = coordinate.latitude
            rows[index].shopLongitude = coordinate.longitude
            resolved += 1
            let address = rows[index].addressLine ?? rows[index].street
            let stamped = Place.from(PendingSharedPlace(
                name: name,
                address: address,
                category: PlaceCategory.fromClipSnapshot(name).rawValue,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                dishes: [],
                savedAt: Date()
            ))
            if (try? vault.saveConfirmedPlace(stamped, ownerSubject: owner)) != nil {
                _ = await SaveInkPlaceSync.reconcile(local: [stamped], userId: owner, remote: remote)
            }
        }
        rows = SaveInkPlaceCatalog.applyingDistance(rows, from: userLocation)
        if let userLocation {
            var walks = 0
            for index in rows.indices where walks < 8 {
                guard let latitude = rows[index].shopLatitude, let longitude = rows[index].shopLongitude else { continue }
                walks += 1
                let destination = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                if let minutes = await walkingMinutes(userLocation, destination) {
                    rows[index].walkMinutes = minutes
                }
            }
        }
        return SaveInkLivePlaceLoad(
            places: SaveInkPlaceCatalog.sortedByDistance(rows),
            userCoordinate: userLocation?.coordinate
        )
    }
}

enum SaveInkMapKitLookup {
    static func coordinate(forName name: String, near location: CLLocation?) async -> CLLocationCoordinate2D? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 25_000,
                longitudinalMeters: 25_000
            )
        }
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return nil }
        let coordinate = item.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }
        return coordinate
    }

    static func walkingMinutes(from origin: CLLocation, to destination: CLLocationCoordinate2D) async -> Int? {
        guard let route = await walkingRoute(from: origin.coordinate, to: destination) else { return nil }
        return SaveInkPlaceCatalog.minutes(fromTravelTime: route.expectedTravelTime)
    }

    static func walkingRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async -> MKRoute? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        return try? await MKDirections(request: request).calculate().routes.first
    }
}

enum SaveInkMapCamera {
    /// Fit saved places. A focused place stays local unless the user is within 30 km,
    /// so a far fix does not zoom the detail map out to the whole trip.
    static func region(
        around coordinates: [CLLocationCoordinate2D],
        user: CLLocationCoordinate2D?,
        focused: CLLocationCoordinate2D?
    ) -> MKCoordinateRegion? {
        var points = coordinates.filter(isUsable)
        if let focused, isUsable(focused) {
            points = [focused]
            if let user, isUsable(user), distance(focused, user) < 30_000 {
                points.append(user)
            }
        } else if let user, isUsable(user) {
            points.append(user)
        }
        guard !points.isEmpty else { return nil }
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return nil }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.008),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.008)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private static func isUsable(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && coordinate.latitude.isFinite
            && coordinate.longitude.isFinite
            && (coordinate.latitude != 0 || coordinate.longitude != 0)
    }

    private static func distance(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }
}
