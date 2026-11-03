import CoreLocation
import CryptoKit
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
            if let index = remaining.firstIndex(where: { sameVenue(inkPlace, $0) }) {
                let place = remaining.remove(at: index)
                rows.append(row(place: place, ink: inkPlace))
                continue
            }
            let key = venueKey(inkPlace.name)
            if key.isEmpty || seenInkKeys.insert(key).inserted {
                rows.append(inkPlace)
            }
        }
        for place in remaining {
            rows.append(row(place: place, ink: nil))
        }
        return sortedByDistance(applyingDistance(rows, from: userLocation))
    }

    /// A name-only ink row does not inherit another venue's coordinates.
    /// Merge only when the ink row has coordinates `Place.matches` accepts,
    /// or the same name plus a real address.
    static func sameVenue(_ ink: SaveInkPlace, _ place: Place) -> Bool {
        if let latitude = ink.shopLatitude, let longitude = ink.shopLongitude {
            let probe = Place.from(PendingSharedPlace(
                name: ink.name,
                address: nonempty(ink.addressLine) ?? nonempty(ink.street) ?? ink.name,
                category: "food",
                latitude: latitude,
                longitude: longitude,
                dishes: [],
                savedAt: Date()
            ))
            return place.matches(probe)
        }
        guard let address = nonempty(ink.addressLine), venueKey(address) != venueKey(ink.name) else { return false }
        return venueKey(ink.name) == venueKey(place.name) && venueKey(address) == venueKey(place.address)
    }

    static func stablePlaceID(for key: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(key.utf8)))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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
            shopLongitude: mappable ? place.longitude : ink?.shopLongitude,
            aliasIDs: (place.mergedPlaceIDs ?? []).map(\.uuidString)
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
        remote: any SaveInkPlaceRemote,
        stillCurrent: @MainActor () -> Bool = { true }
    ) async -> [Place] {
        guard let userId, !userId.isEmpty, remote.isConfigured, stillCurrent() else { return local }
        let remotePlaces: [Place]
        do {
            remotePlaces = try await remote.fetchPlaces(for: userId)
        } catch {
            return local
        }
        guard stillCurrent() else { return local }
        let merged = Place.consolidated(remotePlaces + local)
        for place in local where !remotePlaces.contains(where: { $0.matches(place) }) {
            guard stillCurrent() else { return local }
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
    var walkingMinutes: @MainActor (CLLocation, CLLocationCoordinate2D) async -> Int?
    /// Owner and auth generation. A change after an await aborts writes.
    var currentSession: @MainActor () -> (owner: String?, generation: Int) = {
        Self.liveSession()
    }

    /// While auth is still restoring, the cached owner is the account. `currentUserId`
    /// is nil until restore finishes, so the two must not be compared as different owners.
    static func liveSession() -> (owner: String?, generation: Int) {
        let auth = PrivyAuthService.shared
        if auth.authState == .unknown {
            return (SavePlaceLimitHandoff.cachedActiveOwner(), auth.sessionGeneration)
        }
        return (auth.currentUserId, auth.sessionGeneration)
    }
    /// False when a resolved free account is already at the saved-place cap.
    /// Unresolved entitlement fails open so a Pro account is not parked as free.
    var canConfirmAnother: @MainActor (Int) -> Bool = { count in
        guard SaveEntitlementStore.shared.hasAuthoritativeSavedPlaceTier else { return true }
        return SavePlaceLimitGate.decide(
            tier: SaveEntitlementStore.shared.tier,
            savedPlaceCount: count
        ) != .overFreeLimit
    }

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
            walkingMinutes: { origin, destination in
                await SaveInkMapKitLookup.walkingMinutes(from: origin, to: destination)
            }
        )
    }

    private enum UploadResult {
        case uploaded
        case retryLater
        case stop
    }

    /// Uploads one stamp. A place-limit rejection stops the queue. The caller
    /// removes a stamp this queue created and binds an ownerless row to this
    /// account. A stamp the person already had stays put. Any other failure
    /// leaves the queue row for a later try.
    private func upload(
        _ place: Place,
        owner: String?,
        generation: Int,
        remoteConfigured: Bool
    ) async -> UploadResult {
        guard let owner, !owner.isEmpty, remoteConfigured else { return .uploaded }
        do {
            try await SAVEPendingImportSessionScope.$current.withValue((generation, owner)) {
                try await remote.savePlace(place, userId: owner)
            }
            return .uploaded
        } catch is SavePlaceLimitError {
            return .stop
        } catch {
            return .retryLater
        }
    }

    /// Ids this account would assign while admitting this queue row.
    /// Binding an ownerless row changes its deduplication key, so the key from
    /// before that bind counts too.
    private static func queueStampIDs(owner: String?, item: PendingSharedPlace) -> Set<UUID> {
        guard let owner, !owner.isEmpty else { return [] }
        var keys = [item.deduplicationKey]
        if item.ownerSubject == owner {
            let suffix = item.deduplicationKey.dropFirst(owner.count)
            if suffix.first == "|" {
                keys.append(String(suffix))
            }
        }
        return Set(keys.map { SaveInkPlaceCatalog.stablePlaceID(for: "\(owner)|\($0)") })
    }

    /// Drops one vault record by id. An empty name keeps `matches` from
    /// deleting a different stamp at the same venue.
    private func dropQueueStamp(_ id: UUID, owner: String?) {
        let probe = Place.from(
            PendingSharedPlace(
                name: "",
                address: "",
                category: "food",
                latitude: 0,
                longitude: 0,
                dishes: [],
                savedAt: Date()
            ),
            id: id
        )
        try? vault.removeConfirmedPlace(probe, belongingTo: owner)
    }

    private func mirrorMissing(_ places: [Place], owner: String?) {
        let existing = (try? vault.confirmedPlaces(limit: 500, belongingTo: owner)) ?? []
        for place in places where !existing.contains(where: { $0.matches(place) }) {
            try? vault.saveConfirmedPlace(place, ownerSubject: owner)
        }
    }

    func localPlaces(ink: [SaveInkPlace]) -> [SaveInkPlace] {
        let owner = currentSession().owner
        let confirmed = (try? vault.confirmedPlaces(limit: 500, belongingTo: owner)) ?? []
        return SaveInkPlaceCatalog.merge(ink: ink, confirmed: confirmed, pending: [], userLocation: nil)
    }

    func load(ink: [SaveInkPlace]) async -> SaveInkLivePlaceLoad {
        let started = currentSession()
        let owner = await userID()
        func stillHere() -> Bool {
            let now = currentSession()
            return now.generation == started.generation && now.owner == owner
        }
        guard stillHere() else {
            return SaveInkLivePlaceLoad(places: ink, userCoordinate: nil)
        }
        var confirmed = (try? vault.confirmedPlaces(limit: 500, belongingTo: owner)) ?? []
        let queued = pending.peekPendingPlaces(ownerSubject: owner)
        let remoteConfigured = owner?.isEmpty == false && remote.isConfigured
        var admitQueue = !remoteConfigured
        var remoteIDs = Set<UUID>()
        if let owner, !owner.isEmpty, remote.isConfigured {
            do {
                let remotePlaces = try await SAVEPendingImportSessionScope.$current.withValue((started.generation, owner)) {
                    try await remote.fetchPlaces(for: owner)
                }
                guard stillHere() else {
                    return SaveInkLivePlaceLoad(places: ink, userCoordinate: nil)
                }
                remoteIDs = Set(remotePlaces.map(\.id))
                confirmed = Place.consolidated(remotePlaces + confirmed)
                admitQueue = true
            } catch {
                admitQueue = false
            }
        }
        mirrorMissing(confirmed, owner: owner)
        var claimedKeys = Set<String>()
        func retain(_ item: PendingSharedPlace) {
            if item.ownerSubject == nil, let owner, !owner.isEmpty {
                pending.bindPendingPlaces(keys: [item.deduplicationKey], to: owner)
            }
        }
        if admitQueue {
            queue: for item in queued {
                guard stillHere() else { break }
                let candidate = Place.from(
                    item,
                    id: SaveInkPlaceCatalog.stablePlaceID(for: "\(owner ?? "")|\(item.deduplicationKey)")
                )
                if let existing = confirmed.first(where: { $0.matches(candidate) }) {
                    if !existing.savedIDs.isDisjoint(with: remoteIDs) {
                        claimedKeys.insert(item.deduplicationKey)
                        continue
                    }
                    switch await upload(existing, owner: owner, generation: started.generation, remoteConfigured: remote.isConfigured) {
                    case .uploaded:
                        claimedKeys.insert(item.deduplicationKey)
                        remoteIDs.formUnion(existing.savedIDs)
                    case .retryLater:
                        retain(item)
                    case .stop:
                        retain(item)
                        let minted = Self.queueStampIDs(owner: owner, item: item)
                        if !existing.savedIDs.isDisjoint(with: minted) {
                            for id in minted where existing.savedIDs.contains(id) {
                                dropQueueStamp(id, owner: owner)
                            }
                            confirmed.removeAll { place in
                                let ids = place.savedIDs
                                return !ids.isDisjoint(with: minted) && ids.subtracting(minted).isEmpty
                            }
                        }
                        break queue
                    }
                    continue
                }
                guard canConfirmAnother(Place.consolidated(confirmed).count) else { continue }
                guard (try? vault.saveConfirmedPlace(candidate, ownerSubject: owner)) != nil else { continue }
                switch await upload(candidate, owner: owner, generation: started.generation, remoteConfigured: remote.isConfigured) {
                case .uploaded:
                    claimedKeys.insert(item.deduplicationKey)
                    remoteIDs.insert(candidate.id)
                case .retryLater:
                    retain(item)
                case .stop:
                    dropQueueStamp(candidate.id, owner: owner)
                    retain(item)
                    break queue
                }
                guard stillHere() else { break }
                if let refreshed = try? vault.confirmedPlaces(limit: 500, belongingTo: owner) {
                    confirmed = Place.consolidated(confirmed + refreshed)
                }
            }
        }
        if stillHere() {
            pending.removePendingPlaces(withKeys: claimedKeys)
        }
        guard stillHere() else {
            return SaveInkLivePlaceLoad(places: ink, userCoordinate: nil)
        }
        let userLocation = await location()
        guard stillHere() else {
            return SaveInkLivePlaceLoad(places: ink, userCoordinate: nil)
        }
        let display = Place.consolidated(confirmed)
        var rows = SaveInkPlaceCatalog.merge(
            ink: ink,
            confirmed: display,
            pending: [],
            userLocation: userLocation
        )
        if let userLocation {
            var walks = 0
            for index in rows.indices where walks < 8 {
                guard stillHere() else { break }
                guard let latitude = rows[index].shopLatitude, let longitude = rows[index].shopLongitude else { continue }
                walks += 1
                let destination = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                if let minutes = await walkingMinutes(userLocation, destination) {
                    rows[index].walkMinutes = minutes
                }
            }
        }
        guard stillHere() else {
            return SaveInkLivePlaceLoad(places: ink, userCoordinate: nil)
        }
        return SaveInkLivePlaceLoad(
            places: SaveInkPlaceCatalog.sortedByDistance(rows),
            userCoordinate: userLocation?.coordinate
        )
    }
}

enum SaveInkMapKitLookup {
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
        guard let minLat = latitudes.min(), let maxLat = latitudes.max() else { return nil }
        let longitudes = wrappedLongitude(points.map(\.longitude))
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: longitudes.center
        )
        let span = MKCoordinateSpan(
            latitudeDelta: min(max((maxLat - minLat) * 1.6, 0.008), 180),
            longitudeDelta: min(max(longitudes.delta * 1.6, 0.008), 360)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Smallest longitude interval, including a cluster that crosses 180°.
    static func wrappedLongitude(_ longitudes: [Double]) -> (center: Double, delta: Double) {
        let normalized = longitudes.map { value -> Double in
            var longitude = value.truncatingRemainder(dividingBy: 360)
            if longitude < -180 { longitude += 360 }
            if longitude >= 180 { longitude -= 360 }
            return longitude
        }.sorted()
        guard let first = normalized.first else { return (0, 0) }
        guard normalized.count > 1 else { return (first, 0) }
        var largestGap = 0.0
        var clusterStart = first
        for index in 0..<normalized.count {
            let start = normalized[index]
            let end = index + 1 < normalized.count ? normalized[index + 1] : normalized[0] + 360
            let gap = end - start
            if gap > largestGap {
                largestGap = gap
                clusterStart = end
            }
        }
        let delta = 360 - largestGap
        var center = clusterStart + delta / 2
        while center > 180 { center -= 360 }
        while center <= -180 { center += 360 }
        return (center, delta)
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
