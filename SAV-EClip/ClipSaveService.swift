import Foundation
import UIKit

enum ClipSaveOutcome: Equatable {
    case handedOff
    case pending(Int)
    case failed
}

struct ClipPlaceDraft: Equatable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var category: String
    var rating: Double?
    var note: String?
    var sourceURL: String?
    var placeId: String?
    var friendShareCode: String?
    var coordinateSystem: String? = nil
    var locationProvider: String? = nil
    var providerMapURL: String? = nil
    var googlePlaceId: String? = nil

        var listSaveItem: ClipListSaveItem {
            ClipListSaveItem(
                name: name,
                address: address,
                latitude: latitude,
                longitude: longitude,
                category: category,
                rating: rating,
                note: note,
                sourceURL: sourceURL,
                placeId: placeId,
                coordinateSystem: coordinateSystem,
                locationProvider: locationProvider,
                providerMapURL: providerMapURL,
                googlePlaceId: googlePlaceId
            )
        }

        var hasValidCoordinate: Bool {
        latitude.isFinite && longitude.isFinite
            && (abs(latitude) > 0.0001 || abs(longitude) > 0.0001)
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }

    func mapsURL() -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        if hasValidCoordinate {
            components?.queryItems = [
                URLQueryItem(name: "q", value: name),
                URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            ]
            return components?.url
        }
        let query = [name, address].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " ")
        guard !query.isEmpty else { return nil }
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    static func from(place: SharedPlaceData, shareCode: String?) -> ClipPlaceDraft {
        ClipPlaceDraft(
            name: place.name,
            address: place.address,
            latitude: place.lat,
            longitude: place.lng,
            category: place.category,
            rating: place.rating,
            note: place.note,
            sourceURL: place.safeSourceURL?.absoluteString,
            placeId: place.id.isEmpty ? nil : place.id,
            friendShareCode: shareCode,
            coordinateSystem: place.coordinateSystem,
            locationProvider: place.locationProvider,
            providerMapURL: place.providerMapUrl
        )
    }

    static func from(item: SharedListItem) -> ClipPlaceDraft {
        ClipPlaceDraft(
            name: item.title,
            address: item.subtitle,
            latitude: item.latitude,
            longitude: item.longitude,
            category: item.category ?? "Place",
            rating: item.rating,
            note: item.note,
            sourceURL: item.sourceURL,
            placeId: item.sourceID.isEmpty ? item.id.uuidString : item.sourceID,
            friendShareCode: nil,
            coordinateSystem: item.coordinateSystem,
            locationProvider: item.locationProvider,
            providerMapURL: item.providerMapUrl,
            googlePlaceId: item.googlePlaceId
        )
    }
}

enum ClipFullApp {
    static var queryURL: URL? { URL(string: "savvy://") }

    static var isInstalled: Bool {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-clip-no-full-app") { return false }
#endif
        guard let queryURL else { return false }
        return UIApplication.shared.canOpenURL(queryURL)
    }
}

@MainActor
enum ClipSaveService {
    @discardableResult
    static func persist(_ draft: ClipPlaceDraft, url: URL, sender: String?) -> Bool {
        let snapshot = PendingConfirmedPlace(
            placeId: draft.placeId ?? "",
            name: draft.name,
            address: draft.address,
            latitude: draft.latitude,
            longitude: draft.longitude,
            category: draft.category,
            sourceURL: draft.sourceURL,
            extraPlaceIds: nil,
            coordinateSystem: draft.coordinateSystem,
            locationProvider: draft.locationProvider,
            providerMapUrl: draft.providerMapURL,
            googlePlaceId: draft.googlePlaceId
        )
        return PendingShareStore.write(
            PendingSharePayload(
                kind: .place,
                shareCode: draft.friendShareCode,
                placeId: draft.placeId,
                listId: nil,
                sender: sender,
                url: url.absoluteString,
                confirmedPlaces: [snapshot]
            )
        )
    }

    static func persistList(
        listId: String?,
        shareCode: String?,
        url: URL,
        sender: String?,
        drafts: [ClipPlaceDraft]
    ) -> Bool {
        let unique = ClipListSavePlanner.uniqueItems(from: drafts.map(\.listSaveItem))
        let places = unique.map {
            PendingConfirmedPlace(
                placeId: $0.placeId ?? "",
                name: $0.name,
                address: $0.address,
                latitude: $0.latitude,
                longitude: $0.longitude,
                category: $0.category,
                sourceURL: $0.sourceURL,
                extraPlaceIds: $0.extraPlaceIds.isEmpty ? nil : $0.extraPlaceIds,
                coordinateSystem: $0.coordinateSystem,
                locationProvider: $0.locationProvider,
                providerMapUrl: $0.providerMapURL,
                googlePlaceId: $0.googlePlaceId
            )
        }
        return PendingShareStore.write(
            PendingSharePayload(
                kind: .list,
                shareCode: shareCode,
                placeId: nil,
                listId: listId,
                sender: sender,
                url: url.absoluteString,
                confirmedPlaces: places
            )
        )
    }

    /// A Clip tap records intent, never a saved place or an authenticated owner.
    static func save(
        draft: ClipPlaceDraft,
        handoffURL: URL,
        sender: String?,
        isInstalled: Bool = ClipFullApp.isInstalled,
        openURL: @MainActor @escaping (URL, @escaping (Bool) -> Void) -> Void = openInstalledApp
    ) async -> ClipSaveOutcome {
        guard !Task.isCancelled else { return .failed }
        let written = persist(draft, url: handoffURL, sender: sender)
        guard written else { return .failed }
        guard isInstalled else { return .pending(1) }
        return await handoff(handoffURL, count: 1, openURL: openURL)
    }

    static func saveList(
        drafts: [ClipPlaceDraft],
        listId: String?,
        shareCode: String?,
        handoffURL: URL,
        sender: String?,
        isInstalled: Bool = ClipFullApp.isInstalled,
        openURL: @MainActor @escaping (URL, @escaping (Bool) -> Void) -> Void = openInstalledApp
    ) async -> ClipSaveOutcome {
        guard !Task.isCancelled else { return .failed }
        let unique = ClipListSavePlanner.uniqueItems(from: drafts.map(\.listSaveItem))
        guard !unique.isEmpty else { return .failed }
        let handoffURL = ClipListSavePlanner.compactHandoffURL(
            incoming: handoffURL, shareCode: shareCode, listId: listId
        )
        let written = persistList(
            listId: listId, shareCode: shareCode, url: handoffURL,
            sender: sender, drafts: drafts
        )
        guard written else { return .failed }
        guard isInstalled else { return .pending(unique.count) }
        return await handoff(handoffURL, count: unique.count, openURL: openURL)
    }

    private static func handoff(
        _ url: URL, count: Int,
        openURL: @MainActor @escaping (URL, @escaping (Bool) -> Void) -> Void
    ) async -> ClipSaveOutcome {
        await withCheckedContinuation { continuation in
            openURL(url) { opened in
                // A failed open leaves the durable journal available for retry.
                continuation.resume(returning: opened ? .handedOff : .pending(count))
            }
        }
    }

    private static func openInstalledApp(_ url: URL, completion: @escaping (Bool) -> Void) {
        UIApplication.shared.open(url, options: [.universalLinksOnly: true], completionHandler: completion)
    }
}
