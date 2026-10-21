import AuthenticationServices
import Foundation
import UIKit

enum ClipSaveOutcome: Equatable {
    case handedOff
    case saved
    case duplicate
    case capReached
    case signInCancelled
    case failed
}

enum ClipSaveError: Equatable {
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

    static func write(_ userID: String) {
        UserDefaults(suiteName: suiteName)?.set(userID, forKey: key)
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

    private static func postPlace(_ draft: ClipPlaceDraft, token: String) async throws -> (Int, Data) {
        guard let base = SAVEProductionConfig.URLConfigValue(for: ["SAVE_API_URL", "WANDERLY_API_URL"]),
              let url = URL(string: "\(base)/places")
        else { throw ClipSaveError.failed }

        var body: [String: Any] = [
            "id": UUID().uuidString.lowercased(),
            "name": draft.name,
            "address": draft.address,
            "latitude": draft.latitude,
            "longitude": draft.longitude,
            "category": categoryRaw(draft.category),
            "status": "wantToGo",
            "source_platform": "other",
        ]
        if let rating = draft.rating { body["rating"] = rating }
        if let note = draft.note { body["note"] = note }
        if let sourceURL = draft.sourceURL { body["source_url"] = sourceURL }
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

    private static func categoryRaw(_ value: String) -> String {
        let lower = value.lowercased()
        if lower.contains("cafe") || lower.contains("coffee") || lower.contains("咖啡") { return "cafe" }
        if lower.contains("bar") || lower.contains("酒") { return "bar" }
        if lower.contains("stay") || lower.contains("hotel") || lower.contains("宿") { return "stay" }
        if lower.contains("shop") || lower.contains("購") { return "shopping" }
        if lower.contains("attraction") || lower.contains("museum") || lower.contains("景") { return "attraction" }
        return "food"
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
