import AuthenticationServices
import Foundation
import UIKit

enum ClipSaveOutcome: Equatable {
    case handedOff
    case saved
    case duplicate
    case capReached
    case listSaved(ClipListSaveCounts)
    case listFailed(ClipListSaveCounts?)
    case signInCancelled
    case failed
}

enum ClipSaveError: Error, Equatable, Sendable {
    case cancelled
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
                placeId: placeId
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
            friendShareCode: shareCode
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
            friendShareCode: nil
        )
    }
}

enum ClipFullApp {
    static var queryURL: URL? { URL(string: "savvy://") }

    static var isInstalled: Bool {
        guard let queryURL else { return false }
        return UIApplication.shared.canOpenURL(queryURL)
    }
}

enum ClipAppleAccountStore {
    static let suiteName = PendingShareStore.suiteName
    static let key = "clipAppleUserID"

    static func defaults(_ store: UserDefaults? = nil) -> UserDefaults? {
        store ?? UserDefaults(suiteName: suiteName)
    }

    static func read(from store: UserDefaults? = nil) -> String? {
        guard let value = defaults(store)?.string(forKey: key)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func write(_ userID: String, to store: UserDefaults? = nil) {
        let trimmed = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults(store)?.set(trimmed, forKey: key)
    }

    static func clear(_ store: UserDefaults? = nil) {
        defaults(store)?.removeObject(forKey: key)
    }
}

enum ClipSaveAPI {
    static func parseOutcome(status: Int, data: Data) -> ClipSaveOutcome {
        if status == 403, let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let code = body["code"] as? String
            let error = body["error"] as? String
            if code == "over_free_limit" || error == "saved_place_limit" {
                return .capReached
            }
        }
        if (200...299).contains(status) {
            if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let outcome = body["outcome"] as? String,
               outcome == "already_saved" {
                return .duplicate
            }
            return .saved
        }
        if status == 409 {
            return .duplicate
        }
        return .failed
    }

    static func parseListOutcome(status: Int, data: Data) -> ClipSaveOutcome {
        switch ClipListSavePlanner.parseOutcome(status: status, data: data) {
        case .success(let counts):
            return .listSaved(counts)
        case .failure:
            return .listFailed(nil)
        }
    }
}

@MainActor
enum ClipSaveService {
    static func persist(_ draft: ClipPlaceDraft, url: URL, sender: String?) {
        PendingShareStore.write(
            PendingSharePayload(
                kind: .place,
                shareCode: draft.friendShareCode,
                placeId: draft.placeId,
                listId: nil,
                sender: sender,
                url: url.absoluteString
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
                sourceURL: $0.sourceURL
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
                confirmedPlaceIds: unique.compactMap { id in
                    id.placeId?.trimmingCharacters(in: .whitespacesAndNewlines)
                }.filter { !$0.isEmpty },
                confirmedPlaces: places
            )
        )
    }

    static func save(
        draft: ClipPlaceDraft,
        handoffURL: URL,
        sender: String?,
        openURL: @escaping (URL, @escaping (Bool) -> Void) -> Void = { url, completion in
            UIApplication.shared.open(url, options: [:], completionHandler: completion)
        },
        signIn: @escaping () async throws -> String = { try await ClipAppleAuth.signIn() },
        postPlace: @escaping (ClipPlaceDraft, String) async throws -> (Int, Data) = postPlace
    ) async -> ClipSaveOutcome {
        persist(draft, url: handoffURL, sender: sender)
        if ClipFullApp.isInstalled {
            return await withCheckedContinuation { continuation in
                openURL(handoffURL) { opened in
                    continuation.resume(returning: opened ? .handedOff : .failed)
                }
            }
        }
        do {
            let token = try await signIn()
            let (status, data) = try await postPlace(draft, token)
            return ClipSaveAPI.parseOutcome(status: status, data: data)
        } catch let error as ClipSaveError {
            return error == .cancelled ? .signInCancelled : .failed
        } catch {
            return .failed
        }
    }

    static func saveList(
        drafts: [ClipPlaceDraft],
        listId: String?,
        shareCode: String?,
        handoffURL: URL,
        sender: String?,
        openURL: @escaping (URL, @escaping (Bool) -> Void) -> Void = { url, completion in
            UIApplication.shared.open(url, options: [:], completionHandler: completion)
        },
        signIn: @escaping () async throws -> String = { try await ClipAppleAuth.signIn() },
        postPlaces: @escaping ([ClipListSaveItem], String) async throws -> (Int, Data) = postPlaces
    ) async -> ClipSaveOutcome {
        let handoff = ClipListSavePlanner.compactHandoffURL(
            incoming: handoffURL,
            shareCode: shareCode,
            listId: listId
        )
        let written = persistList(
            listId: listId,
            shareCode: shareCode,
            url: handoff,
            sender: sender,
            drafts: drafts
        )
        guard written else { return .failed }
        if ClipFullApp.isInstalled {
            return await withCheckedContinuation { continuation in
                openURL(handoff) { opened in
                    let handedOff = ClipListSavePlanner.handoffAfterPersist(written: written, opened: opened)
                    continuation.resume(returning: handedOff ? .handedOff : .failed)
                }
            }
        }
        do {
            let token = try await signIn()
            let unique = ClipListSavePlanner.itemsToSave(
                confirmed: drafts.map(\.listSaveItem),
                liveList: []
            )
            let (status, data) = try await postPlaces(unique, token)
            return ClipSaveAPI.parseListOutcome(status: status, data: data)
        } catch let error as ClipSaveError {
            return error == .cancelled ? .signInCancelled : .listFailed(nil)
        } catch {
            return .listFailed(nil)
        }
    }

    private static func postPlace(_ draft: ClipPlaceDraft, token: String) async throws -> (Int, Data) {
        guard let base = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
              let url = URL(string: "\(base)/places")
        else { throw ClipSaveError.failed }

        var body = ClipListSavePlanner.placeBody(from: draft.listSaveItem)
        if let code = draft.friendShareCode { body["friend_share_code"] = code }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClipSaveError.failed }
        return (http.statusCode, data)
    }

    private static func postPlaces(_ items: [ClipListSaveItem], token: String) async throws -> (Int, Data) {
        guard let base = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
              let url = URL(string: "\(base)/places")
        else { throw ClipSaveError.failed }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ClipListSavePlanner.requestBody(items: items))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClipSaveError.failed }
        return (http.statusCode, data)
    }
}

@MainActor
final class ClipAppleAuth: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, Error>?

    static func signIn() async throws -> String {
        let auth = ClipAppleAuth()
        retained = auth
        defer { retained = nil }
        return try await auth.run()
    }

    private static var retained: ClipAppleAuth?

    private func run() async throws -> String {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8),
              !token.isEmpty
        else {
            continuation?.resume(throwing: ClipSaveError.failed)
            continuation = nil
            return
        }
        ClipAppleAccountStore.write(credential.user)
        continuation?.resume(returning: token)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        continuation?.resume(throwing: cancelled ? ClipSaveError.cancelled : ClipSaveError.failed)
        continuation = nil
    }
}
