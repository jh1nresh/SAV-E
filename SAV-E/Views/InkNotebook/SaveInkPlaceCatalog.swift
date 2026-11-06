import CoreLocation
import CryptoKit
import Foundation
import MapKit
import os

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
            aliasIDs: (place.mergedPlaceIDs ?? []).map(\.uuidString),
            blurbIsUserContent: nonempty(ink?.blurb) != nil ? (ink?.blurbIsUserContent ?? false) : note != nil,
            detailNoteIsUserContent: nonempty(ink?.detailNote) != nil ? (ink?.detailNoteIsUserContent ?? false) : note != nil,
            mapReference: place.hasValidCoordinate ? SaveInkMapReference(
                latitude: place.latitude, longitude: place.longitude,
                coordinateSystem: place.resolvedCoordinateSystem,
                provider: place.locationProvider, providerPlaceID: place.providerPlaceId
            ) : ink?.mapReference
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
    func updatePlace(_ place: Place, userId: String) async throws
}

extension SupabaseService: SaveInkPlaceRemote {
    func updatePlace(_ place: Place, userId: String) async throws {
        try await updatePlace(place)
    }
}

struct SaveInkLivePlaceLoad {
    var places: [SaveInkPlace]
    var userCoordinate: CLLocationCoordinate2D?
    /// False while the server place count is still unknown. A failed fetch
    /// stays false so a new save cannot slip in under a partial local list.
    var countIsAuthoritative: Bool = false
}

@MainActor
struct SaveInkLivePlaceLoader {
    var localPlaces: @MainActor ([SaveInkPlace]) -> [SaveInkPlace]
    var load: @MainActor ([SaveInkPlace]) async -> SaveInkLivePlaceLoad

    static let inactive = SaveInkLivePlaceLoader(
        localPlaces: { $0 },
        load: { ink in
            SaveInkLivePlaceLoad(places: ink, userCoordinate: nil, countIsAuthoritative: true)
        }
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
    /// Pro storage is unlimited. A short read would hide stamps past the cutoff
    /// whenever the server list cannot be fetched.
    private static let vaultReadLimit = 100_000

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

    /// Writes new evidence onto a stamp the server already has. The queue row
    /// is claimed only after this succeeds.
    private func updateRemote(
        _ place: Place,
        owner: String?,
        generation: Int,
        remoteConfigured: Bool
    ) async -> UploadResult {
        guard let owner, !owner.isEmpty, remoteConfigured else { return .uploaded }
        do {
            try await SAVEPendingImportSessionScope.$current.withValue((generation, owner)) {
                try await remote.updatePlace(place, userId: owner)
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
    @discardableResult
    private func dropQueueStamp(_ id: UUID, owner: String?) -> Bool {
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
        do {
            try vault.removeConfirmedPlace(probe, belongingTo: owner)
            vault.forgetCapRejectedStamp(id, owner: owner)
            return true
        } catch {
            _ = vault.rememberCapRejectedStamp(id, owner: owner)
            return false
        }
    }

    private func mirrorMissing(_ places: [Place], owner: String?) {
        let existing = (try? vault.confirmedPlaces(limit: Self.vaultReadLimit, belongingTo: owner)) ?? []
        for place in places {
            if let match = existing.first(where: { $0.matches(place) }) {
                guard Self.vaultIsStale(match, comparedWith: place) else { continue }
            }
            try? vault.saveConfirmedPlace(place, ownerSubject: owner)
        }
    }

    /// Ink rows that are not the same venue as a confirmed stamp are extra
    /// places on the list, so they count toward the free cap.
    private static func visibleStampCount(confirmed: [Place], ink: [SaveInkPlace]) -> Int {
        let stamps = Place.consolidated(confirmed)
        let extra = ink.filter { row in !stamps.contains { SaveInkPlaceCatalog.sameVenue(row, $0) } }
        return stamps.count + extra.count
    }

    /// Compares the fields `SaveMemoryRecord` writes back. Visibility, price
    /// range, and opening hours are not in that record, so they cannot round-trip.
    private static func vaultIsStale(_ stored: Place, comparedWith merged: Place) -> Bool {
        stored.savedIDs != merged.savedIDs
            || stored.name != merged.name
            || stored.address != merged.address
            || stored.latitude != merged.latitude
            || stored.longitude != merged.longitude
            || stored.category != merged.category
            || stored.status != merged.status
            || stored.note != merged.note
            || stored.createdAt != merged.createdAt
            || (stored.rating ?? stored.googleRating) != (merged.rating ?? merged.googleRating)
            || stored.googlePlaceId != merged.googlePlaceId
            || stored.sourceUrl != merged.sourceUrl
            || stored.coordinateSystem != merged.coordinateSystem
            || stored.locationProvider != merged.locationProvider
            || stored.providerPlaceId != merged.providerPlaceId
            || stored.providerMapUrl != merged.providerMapUrl
            || stored.sourceHandle != merged.sourceHandle
            || stored.savedPlaceHighlights != merged.savedPlaceHighlights
            || stored.savedRecommendedItems != merged.savedRecommendedItems
            || stored.savedVibeTags != merged.savedVibeTags
            || stored.savedAccessNotes != merged.savedAccessNotes
            || stored.additionalSourceEvidence != merged.additionalSourceEvidence
            || GooglePlacesPhotoURL.persistableString(stored.sourceImageUrl)
                != GooglePlacesPhotoURL.persistableString(merged.sourceImageUrl)
            || PlaceBusinessPhotoPersistence.importedRemoteURLs(stored.businessPhotoUrls)
                != PlaceBusinessPhotoPersistence.importedRemoteURLs(merged.businessPhotoUrls)
    }

    func localPlaces(ink: [SaveInkPlace]) -> [SaveInkPlace] {
        let owner = currentSession().owner
        guard let hidden = vault.capRejectedStampIDs(owner: owner) else { return ink }
        let confirmed = ((try? vault.confirmedPlaces(limit: Self.vaultReadLimit, belongingTo: owner)) ?? [])
            .filter { $0.savedIDs.isDisjoint(with: hidden) }
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
        var confirmed = (try? vault.confirmedPlaces(limit: Self.vaultReadLimit, belongingTo: owner)) ?? []
        guard let hidden = vault.capRejectedStampIDs(owner: owner) else {
            return SaveInkLivePlaceLoad(places: ink, userCoordinate: nil, countIsAuthoritative: false)
        }
        if !hidden.isEmpty {
            for id in hidden {
                _ = dropQueueStamp(id, owner: owner)
            }
            let stillHidden = vault.capRejectedStampIDs(owner: owner) ?? hidden
            confirmed.removeAll { !$0.savedIDs.isDisjoint(with: stillHidden) }
        }
        let queued = pending.peekPendingPlaces(ownerSubject: owner)
        let signedIn = owner?.isEmpty == false
        var admitQueue = signedIn && !remote.isConfigured
        var countIsAuthoritative = !signedIn || !remote.isConfigured
        var remoteIDs = Set<UUID>()
        if let owner, !owner.isEmpty, remote.isConfigured {
            do {
                let fetched = try await SAVEPendingImportSessionScope.$current.withValue((started.generation, owner)) {
                    try await remote.fetchPlaces(for: owner)
                }
                guard stillHere() else {
                    return SaveInkLivePlaceLoad(places: ink, userCoordinate: nil)
                }
                let remotePlaces = fetched.map { place in
                    var authoritative = place
                    let aliases = confirmed.filter { $0.matches(place) }
                        .reduce(into: place.savedIDs) { $0.formUnion($1.savedIDs) }
                        .subtracting([place.id])
                    authoritative.mergedPlaceIDs = aliases.isEmpty ? nil : aliases.sorted { $0.uuidString < $1.uuidString }
                    return authoritative
                }
                remoteIDs = Set(remotePlaces.map(\.id))
                let localOnly = confirmed.filter { place in
                    !remotePlaces.contains { $0.matches(place) }
                }
                let retryable = localOnly.filter { place in
                    queued.contains { place.matches(Place.from($0)) }
                }
                for place in localOnly where !retryable.contains(where: { $0.savedIDs.contains(place.id) }) {
                    dropQueueStamp(place.id, owner: owner)
                }
                confirmed = Place.consolidated(remotePlaces + retryable)
                admitQueue = true
                countIsAuthoritative = true
            } catch {
                guard stillHere() else {
                    return SaveInkLivePlaceLoad(places: ink, userCoordinate: nil)
                }
                admitQueue = false
                countIsAuthoritative = false
            }
        }
        guard stillHere() else {
            return SaveInkLivePlaceLoad(places: ink, userCoordinate: nil)
        }
        mirrorMissing(confirmed, owner: owner)
        var claimedItems: [PendingSharedPlace] = []
        func retain(_ item: PendingSharedPlace) -> Bool {
            guard item.ownerSubject == nil, let owner, !owner.isEmpty else { return true }
            return pending.bindPendingPlaces(keys: [item.deduplicationKey], to: owner)
        }
        func unboundKey(_ item: PendingSharedPlace) -> String {
            var unbound = item
            unbound.ownerSubject = nil
            return unbound.deduplicationKey
        }
        func holdUnbound(_ item: PendingSharedPlace) {
            guard let owner, !owner.isEmpty else { return }
            if retain(item) {
                vault.releaseUnboundShare(key: item.deduplicationKey)
                return
            }
            _ = vault.claimUnboundShare(key: item.deduplicationKey, owner: owner)
        }
        if admitQueue, vault.unboundShareLedgerIsReadable() {
            queue: for item in queued {
                guard stillHere() else { break }
                let holdKey = unboundKey(item)
                if let owner, !owner.isEmpty, let heldBy = vault.unboundShareOwner(for: holdKey) {
                    if heldBy != owner {
                        if item.ownerSubject == nil { continue }
                    } else if retain(item) {
                        guard vault.releaseUnboundShare(key: holdKey) else { break queue }
                    }
                }
                // Secure every snapshot before an upload can suspend this pass.
                // Keep the original item/key for IDs; cleanup below uses a bound
                // snapshot only after a durable bind succeeds.
                if item.ownerSubject == nil, let owner, !owner.isEmpty,
                   !retain(item),
                   !vault.claimUnboundShare(key: holdKey, owner: owner) {
                    break queue
                }
                let candidate = Place.from(
                    item,
                    id: SaveInkPlaceCatalog.stablePlaceID(for: "\(owner ?? "")|\(item.deduplicationKey)")
                )
                if let existing = confirmed.first(where: { $0.matches(candidate) }) {
                    let merged = existing.mergingSources(from: candidate)
                    if Self.vaultIsStale(existing, comparedWith: merged) {
                        guard (try? vault.saveConfirmedPlace(merged, ownerSubject: owner)) != nil else { continue }
                    }
                    if let index = confirmed.firstIndex(where: { !$0.savedIDs.isDisjoint(with: existing.savedIDs) }) {
                        confirmed[index] = merged
                    }
                    if !merged.savedIDs.isDisjoint(with: remoteIDs) {
                        let remoteID = merged.savedIDs.first { remoteIDs.contains($0) } ?? merged.id
                        let payload = merged.id == remoteID ? merged : merged.rekeyed(to: remoteID)
                        switch await updateRemote(payload, owner: owner, generation: started.generation, remoteConfigured: remote.isConfigured) {
                        case .uploaded:
                            claimedItems.append(item)
                            remoteIDs.formUnion(payload.savedIDs)
                        case .retryLater:
                            if !retain(item) {
                                holdUnbound(item)
                                break queue
                            }
                        case .stop:
                            if !retain(item) {
                                holdUnbound(item)
                                break queue
                            }
                            break queue
                        }
                        continue
                    }
                    switch await upload(merged, owner: owner, generation: started.generation, remoteConfigured: remote.isConfigured) {
                    case .uploaded:
                        claimedItems.append(item)
                        remoteIDs.formUnion(merged.savedIDs)
                    case .retryLater:
                        if !retain(item) {
                            holdUnbound(item)
                            break queue
                        }
                    case .stop:
                        if !retain(item) {
                            holdUnbound(item)
                            break queue
                        }
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
                guard canConfirmAnother(Self.visibleStampCount(confirmed: confirmed, ink: ink)) else {
                    if retain(item) {
                        vault.releaseUnboundShare(key: item.deduplicationKey)
                        continue
                    }
                    if let owner, !owner.isEmpty {
                        _ = vault.claimUnboundShare(key: item.deduplicationKey, owner: owner)
                    }
                    break queue
                }
                guard (try? vault.saveConfirmedPlace(candidate, ownerSubject: owner)) != nil else { continue }
                switch await upload(candidate, owner: owner, generation: started.generation, remoteConfigured: remote.isConfigured) {
                case .uploaded:
                    claimedItems.append(item)
                    remoteIDs.insert(candidate.id)
                case .retryLater:
                    if !retain(item) {
                        dropQueueStamp(candidate.id, owner: owner)
                        holdUnbound(item)
                        break queue
                    }
                case .stop:
                    dropQueueStamp(candidate.id, owner: owner)
                    if retain(item) {
                        vault.releaseUnboundShare(key: item.deduplicationKey)
                    } else if let owner, !owner.isEmpty {
                        _ = vault.claimUnboundShare(key: item.deduplicationKey, owner: owner)
                    }
                    break queue
                }
                guard stillHere() else { break }
                if let refreshed = try? vault.confirmedPlaces(limit: Self.vaultReadLimit, belongingTo: owner) {
                    guard let suppressed = vault.capRejectedStampIDs(owner: owner) else {
                        confirmed = []
                        countIsAuthoritative = false
                        break queue
                    }
                    confirmed = Place.consolidated(confirmed + refreshed)
                        .filter { $0.savedIDs.isDisjoint(with: suppressed) }
                }
            }
        }
        if stillHere() {
            for item in claimedItems {
                var processed = item
                if item.ownerSubject == nil, let owner, !owner.isEmpty {
                    // Keep a retry row until both ownership and hold cleanup are
                    // durable. A successful upload alone cannot release either.
                    guard retain(item) else {
                        _ = vault.claimUnboundShare(key: item.deduplicationKey, owner: owner)
                        continue
                    }
                    processed.ownerSubject = owner
                }
                let holdKey = unboundKey(item)
                if let owner, vault.unboundShareOwner(for: holdKey) == owner {
                    guard vault.releaseUnboundShare(key: holdKey) else { continue }
                }
                _ = pending.removeProcessedPendingPlaces([processed])
            }
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
            userCoordinate: userLocation?.coordinate,
            countIsAuthoritative: countIsAuthoritative
        )
    }
}

/// Transient, typed map provenance. The arrival engine keeps its independent
/// WGS84-only shop position, even when a provider map can display this reference.
struct SaveInkMapReference: Equatable {
    var latitude: Double
    var longitude: Double
    var coordinateSystem: PlaceCoordinateSystem
    var provider: PlaceMatchProvider?
    var providerPlaceID: String?

    var hasValidCoordinate: Bool {
        latitude.isFinite && longitude.isFinite &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
        (latitude != 0 || longitude != 0)
    }
}

enum SaveInkMapDisplay: Equatable {
    case loading
    case apple
    case amap(URL)
    case unavailable
}

enum SaveInkMapPolicy {
    static func reference(for place: SaveInkPlace) -> SaveInkMapReference? {
        if let reference = place.mapReference {
            return reference.hasValidCoordinate ? reference : nil
        }
        guard let latitude = place.shopLatitude, let longitude = place.shopLongitude else { return nil }
        let reference = SaveInkMapReference(latitude: latitude, longitude: longitude,
                                            coordinateSystem: .wgs84, provider: nil, providerPlaceID: nil)
        return reference.hasValidCoordinate ? reference : nil
    }

    /// The viewed destination controls the map, never the user's GPS or locale.
    static func target(in places: [SaveInkPlace], focusedID: String?) -> SaveInkPlace? {
        if let focusedID { return places.first { $0.id == focusedID } }
        return places.first
    }

    static func token(for place: SaveInkPlace?) -> String {
        guard let place else { return "empty" }
        let reference = reference(for: place)
        return [place.id, place.name, place.addressLine ?? place.street,
                reference.map { "\($0.latitude),\($0.longitude)|\($0.coordinateSystem.rawValue)|\($0.provider?.rawValue ?? "")|\($0.providerPlaceID ?? "")" } ?? "unlocated"].joined(separator: "|")
    }

    static func display(for place: SaveInkPlace, countryCode: String?) -> SaveInkMapDisplay {
        guard let reference = reference(for: place), let code = normalizedCountry(countryCode) else { return .unavailable }
        if code == "CN" {
            return amapEmbedURL(for: place).map(SaveInkMapDisplay.amap) ?? .unavailable
        }
        // HK, MO and TW are distinct ISO regions. GCJ-02 / BD-09 never become
        // Apple coordinates just because the country lookup returned outside CN.
        return reference.coordinateSystem == .wgs84 ? .apple : .unavailable
    }

    static func normalizedCountry(_ raw: String?) -> String? {
        guard let code = raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              Locale.isoRegionCodes.contains(code) else { return nil }
        return code
    }

    /// Apple can report aggregate CN metadata for Taiwan, Hong Kong and Macao.
    /// Resolve the destination's exact administrative labels, never the viewer's
    /// region/time zone. Unknown CN subdivisions stay unavailable rather than
    /// silently selecting a mainland provider. Labels use CLDR subdivision names
    /// plus the SAR locality labels returned by Apple's en_US geocoder.
    static func routingRegionCode(
        isoCountryCode: String?, administrativeArea: String?, locality: String?, subLocality: String?
    ) -> String? {
        guard let code = normalizedCountry(isoCountryCode) else { return nil }
        guard code == "CN" else { return code }
        let area = administrativeLabel(administrativeArea)
        let city = administrativeLabel(locality)
        let district = administrativeLabel(subLocality)
        let taiwan = ["Taiwan", "Taiwan Province", "台湾", "台湾省", "台灣", "台灣省", "臺灣", "臺灣省"]
        let hongKong = ["Hong Kong", "Hong Kong SAR", "Hong Kong SAR China", "香港", "香港特别行政区", "香港特別行政區"]
        let macao = ["Macao", "Macau", "Macao SAR", "Macau SAR", "Macao SAR China", "澳門", "澳门", "澳门特别行政区", "澳門特別行政區"]
        if containsLabel(area, in: taiwan) { return "TW" }
        if containsLabel(area, in: hongKong) { return "HK" }
        if containsLabel(area, in: macao) { return "MO" }
        if area.isEmpty {
            // Apple's public HQ address result can omit Beijing's admin field.
            // Only the four exact municipality names are sufficient on their own.
            if containsLabel(city, in: ["Beijing", "Shanghai", "Tianjin", "Chongqing", "北京市", "上海市", "天津市", "重庆市", "重慶市"]) { return "CN" }
            if containsLabel(city, in: ["Hong Kong SAR", "Hong Kong SAR China", "香港特别行政区", "香港特別行政區"]) { return "HK" }
            if containsLabel(city, in: ["Macao SAR", "Macau SAR", "Macao SAR China", "澳门特别行政区", "澳門特別行政區"]) { return "MO" }
            return nil
        }
        // Apple's public Kinmen/Matsu results can say Fujian/Quanzhou/Jinmen
        // and Fujian/Fuzhou/Lianjiang. Those labels are ambiguous across the
        // strait: do not turn them into either mainland or Taiwan user truth.
        if containsLabel(area, in: ["Fujian", "Fujian Province", "福建", "福建省"]),
           [city, district].contains(where: { containsLabel($0, in: [
               "Jinmen", "Kinmen", "Jinmen County", "Kinmen County", "金门", "金門", "金门县", "金門縣",
               "Lianjiang", "Lienchiang", "Lianjiang County", "Lienchiang County", "连江", "連江", "连江县", "連江縣"
           ]) }) { return nil }
        let mainland = [
            "Anhui", "Beijing", "Chongqing", "Fujian", "Guangdong", "Gansu", "Guangxi", "Guizhou",
            "Henan", "Hubei", "Hebei", "Hainan", "Heilongjiang", "Hunan", "Jilin", "Jiangsu", "Jiangxi",
            "Liaoning", "Inner Mongolia", "Ningxia", "Qinghai", "Sichuan", "Shandong", "Shanghai",
            "Shaanxi", "Shanxi", "Tianjin", "Xinjiang", "Tibet", "Yunnan", "Zhejiang"
        ]
        let chinese = [
            "安徽省", "北京市", "重庆市", "重慶市", "福建省", "广东省", "廣東省", "甘肃省", "甘肅省",
            "广西壮族自治区", "廣西壯族自治區", "贵州省", "貴州省", "河南省", "湖北省", "河北省", "海南省",
            "黑龙江省", "黑龍江省", "湖南省", "吉林省", "江苏省", "江蘇省", "江西省", "辽宁省", "遼寧省",
            "内蒙古自治区", "內蒙古自治區", "宁夏回族自治区", "寧夏回族自治區", "青海省", "四川省",
            "山东省", "山東省", "上海市", "陕西省", "陝西省", "山西省", "天津市", "新疆维吾尔自治区",
            "新疆維吾爾自治區", "西藏自治区", "西藏自治區", "云南省", "雲南省", "浙江省"
        ]
        let provinces = mainland.filter { ![
            "Beijing", "Chongqing", "Shanghai", "Tianjin", "Guangxi", "Inner Mongolia", "Ningxia", "Xinjiang", "Tibet"
        ].contains($0) }
        let aliases = mainland + provinces.map { "\($0) Province" } + chinese
        return containsLabel(area, in: aliases) ? "CN" : nil
    }

    private static func administrativeLabel(_ value: String?) -> String {
        (value ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                               locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func containsLabel(_ label: String, in aliases: [String]) -> Bool {
        !label.isEmpty && aliases.contains { administrativeLabel($0) == label }
    }

    static func amapEmbedURL(for place: SaveInkPlace) -> URL? {
        guard let reference = reference(for: place), supportsAmap(reference) else { return nil }
        guard reference.coordinateSystem == .gcj02 else {
            // The marker endpoint converts WGS84 before the compact map loads.
            return amapMarkerURL(for: place, opensApp: false)
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.amap.com"
        components.path = "/ssr/embed/place"
        // POI details may open provider login even with a valid coordinate.
        // Embed the saved point; retain the original POI ID only for external handoff.
        var items = [URLQueryItem(name: "lng", value: String(reference.longitude)),
                     URLQueryItem(name: "lat", value: String(reference.latitude))]
        items += [URLQueryItem(name: "name", value: place.name),
                  URLQueryItem(name: "platform", value: "pc"),
                  URLQueryItem(name: "zoom", value: "16"),
                  URLQueryItem(name: "src", value: "savvy")]
        components.queryItems = items
        return components.url
    }

    static func amapMarkerURL(for place: SaveInkPlace, opensApp: Bool) -> URL? {
        guard let reference = reference(for: place), supportsAmap(reference) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "uri.amap.com"
        components.path = "/marker"
        var items: [URLQueryItem]
        // The external handoff can select the POI directly. Embedded WGS84
        // needs the coordinate-aware redirect before the compact map can load.
        if let id = amapID(reference), opensApp || reference.coordinateSystem == .gcj02 {
            items = [URLQueryItem(name: "poiid", value: id)]
        } else {
            items = [URLQueryItem(name: "position", value: "\(reference.longitude),\(reference.latitude)"),
                     URLQueryItem(name: "coordinate", value: reference.coordinateSystem == .wgs84 ? "wgs84" : "gaode")]
        }
        components.queryItems = items + [URLQueryItem(name: "name", value: place.name),
                                        URLQueryItem(name: "src", value: "savvy"),
                                        URLQueryItem(name: "callnative", value: opensApp ? "1" : "0")]
        return components.url
    }

    /// The documented WGS84 marker URI currently redirects to a mobile card.
    /// Adapt only the observed official redirect into the documented GCJ embed;
    /// a changed response shape fails closed, never stores converted coordinates.
    static func amapWGS84Reference(in url: URL) -> SaveInkMapReference? {
        guard safeHTTPS(url, host: "uri.amap.com"), url.path == "/marker", url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              Set(items.map(\.name)).count == items.count,
              Set(items.map(\.name)).isSubset(of: ["position", "coordinate", "callnative", "name", "src"]),
              items.first(where: { $0.name == "coordinate" })?.value == "wgs84",
              items.first(where: { $0.name == "callnative" })?.value == "0",
              let position = items.first(where: { $0.name == "position" })?.value else { return nil }
        return coordinatePair(position, system: .wgs84)
    }

    static func amapEmbedFromWGS84Redirect(_ redirect: URL, original: URL) -> URL? {
        guard let input = amapWGS84Reference(in: original), safeHTTPS(redirect, host: "m.amap.com"),
              redirect.query == nil, redirect.fragment == nil,
              let components = URLComponents(url: redirect, resolvingAgainstBaseURL: false) else { return nil }
        let prefix = "/share/index/lnglat="
        let path = components.percentEncodedPath
        guard path.hasPrefix(prefix) else { return nil }
        let fields = String(path.dropFirst(prefix.count)).split(separator: "&", omittingEmptySubsequences: false)
        guard let first = fields.first, let point = coordinatePair(String(first), system: .gcj02),
              countryMatchIsNearby(input, latitude: point.latitude, longitude: point.longitude) else { return nil }
        // Provider response fields are never copied into the embed. Validate the
        // known response shape and keep the original destination name instead.
        let tail = fields.dropFirst().joined(separator: "&")
        guard let response = URLComponents(string: "https://m.amap.com/?" + tail)?.queryItems,
              Set(response.map(\.name)).count == response.count,
              Set(response.map(\.name)).isSubset(of: ["name", "src", "callnative", "innersrc"]),
              response.allSatisfy({ $0.value != nil }),
              response.first(where: { $0.name == "src" })?.value == "savvy",
              response.first(where: { $0.name == "callnative" })?.value == "0" else { return nil }
        let name = URLComponents(url: original, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "name" }?.value ?? ""
        var embed = URLComponents()
        embed.scheme = "https"
        embed.host = "www.amap.com"
        embed.path = "/ssr/embed/place"
        embed.queryItems = [URLQueryItem(name: "lng", value: String(point.longitude)),
                            URLQueryItem(name: "lat", value: String(point.latitude)),
                            URLQueryItem(name: "name", value: name), URLQueryItem(name: "platform", value: "pc"),
                            URLQueryItem(name: "zoom", value: "16"), URLQueryItem(name: "src", value: "savvy")]
        return embed.url
    }

    static func isAmapEmbed(_ url: URL?) -> Bool {
        guard let url else { return false }
        return safeHTTPS(url, host: "www.amap.com") && url.path == "/ssr/embed/place"
    }

    private static func safeHTTPS(_ url: URL, host: String) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == host &&
        url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    private static func coordinatePair(_ raw: String, system: PlaceCoordinateSystem) -> SaveInkMapReference? {
        let values = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard values.count == 2, let longitude = Double(values[0]), let latitude = Double(values[1]) else { return nil }
        let point = SaveInkMapReference(latitude: latitude, longitude: longitude,
                                       coordinateSystem: system, provider: system == .gcj02 ? .amap : nil, providerPlaceID: nil)
        return point.hasValidCoordinate ? point : nil
    }

    /// Only initial requests and HTTPS redirects inside the official map hosts
    /// may load. In-map links/new windows do not navigate the containing app.
    static func permitsWebNavigation(_ url: URL?, userInitiated: Bool) -> Bool {
        guard !userInitiated, let url, url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }
        return ["www.amap.com", "m.amap.com", "uri.amap.com"].contains(host)
    }

    private static func supportsAmap(_ reference: SaveInkMapReference) -> Bool {
        reference.coordinateSystem == .wgs84 ||
        (reference.coordinateSystem == .gcj02 && reference.provider == .amap)
    }

    private static func amapID(_ reference: SaveInkMapReference) -> String? {
        guard reference.provider == .amap,
              let id = reference.providerPlaceID?.trimmingCharacters(in: .whitespacesAndNewlines),
              id.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else { return nil }
        return id
    }

    /// The destination's region is display-only. Provider coordinates are
    /// used only for nearby-result validation, never as a MapKit search region.
    @MainActor
    static func destinationCountryCode(for place: SaveInkPlace) async -> String? {
        await destinationCountryCode(for: place, request: SaveInkMapCountryRequest())
    }

    @MainActor
    static func destinationCountryCode(for place: SaveInkPlace, request: SaveInkMapCountryRequest) async -> String? {
        guard !Task.isCancelled, let reference = reference(for: place) else { return nil }
        let address = (place.addressLine ?? place.street).trimmingCharacters(in: .whitespacesAndNewlines)
        if reference.coordinateSystem != .wgs84, address.isEmpty || address == place.name { return nil }
        guard let matches = await request.matches(reference: reference, address: address), !Task.isCancelled else { return nil }
        if request.usedAddressSearch {
            return searchCountryCode(reference: reference, matches: matches)
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        if reference.coordinateSystem != .wgs84 {
            guard let location = match.location,
                  countryMatchIsNearby(reference, latitude: location.coordinate.latitude,
                                       longitude: location.coordinate.longitude) else { return nil }
        }
        return routingRegionCode(isoCountryCode: match.isoCountryCode, administrativeArea: match.administrativeArea,
                                 locality: match.locality, subLocality: match.subLocality)
    }

    /// Nearby address-search results may establish a common region. They do
    /// not choose a replacement POI or change the user's stored coordinates.
    static func searchCountryCode(reference: SaveInkMapReference, matches: [CLPlacemark]) -> String? {
        let nearby = matches.filter { match in
            guard let coordinate = match.location?.coordinate else { return false }
            return countryMatchIsNearby(reference, latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        let codes = nearby.map {
            routingRegionCode(isoCountryCode: $0.isoCountryCode, administrativeArea: $0.administrativeArea,
                              locality: $0.locality, subLocality: $0.subLocality)
        }
        guard let first = codes.first, let code = first, codes.allSatisfy({ $0 == code }) else { return nil }
        return code
    }

    static func countryMatchIsNearby(_ reference: SaveInkMapReference, latitude: Double, longitude: Double) -> Bool {
        guard reference.hasValidCoordinate, latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        let radians = Double.pi / 180
        let dy = (latitude - reference.latitude) * radians
        let dx = (longitude - reference.longitude) * radians
        let a = pow(sin(dy / 2), 2) + cos(reference.latitude * radians) * cos(latitude * radians) * pow(sin(dx / 2), 2)
        let distance = 6_371_000 * 2 * atan2(sqrt(max(0, a)), sqrt(max(0, 1 - a)))
        return distance <= 2_000
    }
}

@MainActor
final class SaveInkMapCountryRequest {
    typealias Completion = @MainActor ([CLPlacemark]?) -> Void
    typealias Start = @MainActor (SaveInkMapReference, String, @escaping Completion) -> Void

    private let geocoder = CLGeocoder()
    private let cancellation = OSAllocatedUnfairLock(initialState: false)
    private let timeout: Duration
    private let start: Start?
    private let stop: (@MainActor () -> Void)?
    private let search: Start?
    /// Optional observation for public live fixtures; no addresses or coordinates are logged.
    private let observe: (@MainActor (String, [CLPlacemark]?, Error?) -> Void)?
    private var addressSearch: MKLocalSearch?
    private(set) var usedAddressSearch = false
    private var continuation: CheckedContinuation<[CLPlacemark]?, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var finished = false

    init(timeout: Duration = .seconds(12), start: Start? = nil, stop: (@MainActor () -> Void)? = nil,
         search: Start? = nil, observe: (@MainActor (String, [CLPlacemark]?, Error?) -> Void)? = nil) {
        self.timeout = timeout
        self.start = start
        self.stop = stop
        self.search = search
        self.observe = observe
    }

    /// CLGeocoder cancellation does not guarantee its async wrapper will resume.
    /// Own the continuation: deadline/cancellation finish exactly once, before
    /// asking the underlying service to stop. Late Apple callbacks are harmless.
    func matches(reference: SaveInkMapReference, address: String) async -> [CLPlacemark]? {
        guard !Task.isCancelled, !finished, continuation == nil else { return nil }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, !finished else { continuation.resume(returning: nil); return }
                self.continuation = continuation
                let timeout = timeout
                deadlineTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.cancel()
                }
                if let start {
                    start(reference, address) { [weak self] result in self?.finish(result) }
                } else {
                    let completion: @Sendable ([CLPlacemark]?, Error?) -> Void = { [weak self] result, error in
                        Task { @MainActor [weak self] in
                            self?.completeGeocoding(result, error: error, reference: reference, address: address)
                        }
                    }
                    if reference.coordinateSystem == .wgs84 {
                        geocoder.reverseGeocodeLocation(
                            CLLocation(latitude: reference.latitude, longitude: reference.longitude),
                            preferredLocale: Locale(identifier: "en_US"), completionHandler: completion)
                    } else {
                        geocoder.geocodeAddressString(address, in: nil, preferredLocale: Locale(identifier: "en_US"),
                                                      completionHandler: completion)
                    }
                }
            }
        } onCancel: { [cancellation] in
            // A queued geocoder callback may run before the MainActor cleanup.
            cancellation.withLock { $0 = true }
            Task { @MainActor in self.cancel() }
        }
    }

    func completeGeocoding(_ result: [CLPlacemark]?, error: Error?, reference: SaveInkMapReference, address: String) {
        guard !finished, !usedAddressSearch, continuation != nil, !cancellation.withLock({ $0 }) else { return }
        observe?("geocoder", result, error)
        let failure = error as NSError?
        guard reference.coordinateSystem == .gcj02, reference.provider == .amap, !address.isEmpty,
              failure?.domain == kCLErrorDomain, failure?.code == CLError.geocodeFoundNoResult.rawValue,
              result?.isEmpty != false else {
            finish(error == nil ? result : nil)
            return
        }
        usedAddressSearch = true
        if let search {
            search(reference, address) { [weak self] matches in self?.finish(matches) }
            return
        }
        let query = MKLocalSearch.Request()
        query.naturalLanguageQuery = address
        query.resultTypes = .address
        let operation = MKLocalSearch(request: query)
        addressSearch = operation
        operation.start { [weak self] response, error in
            Task { @MainActor [weak self] in
                self?.observe?("addressSearch", response?.mapItems.map(\.placemark), error)
                self?.finish(error == nil ? response?.mapItems.map(\.placemark) : nil)
            }
        }
    }

    private func finish(_ result: [CLPlacemark]?) {
        guard !finished else { return }
        finished = true
        deadlineTask?.cancel()
        deadlineTask = nil
        let pending = continuation
        continuation = nil
        pending?.resume(returning: cancellation.withLock({ $0 }) ? nil : result)
    }

    func cancel() {
        cancellation.withLock { $0 = true }
        guard !finished else { return }
        observe?("cancelOrDeadline", nil, nil)
        finish(nil)
        if let stop { stop() } else { geocoder.cancelGeocode() }
        addressSearch?.cancel()
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
            if let nearest = points.map({ distance($0, user) }).min() {
                if nearest < 30_000 {
                    points.append(user)
                }
            } else {
                points.append(user)
            }
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
