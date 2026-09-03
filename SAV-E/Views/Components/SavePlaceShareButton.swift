import SwiftUI

struct SavePlaceShareContent {
    let subject: String
    let fallbackURL: URL?
    let fallbackText: String
    let payload: SharedPlaceData?
    let sourcePlaceId: UUID?
    let optionalShareNote: String?

    var cacheKey: String {
        cacheKey(includingOptionalNote: false)
    }

    var stateKey: String {
        cacheKey(includingOptionalNote: true)
    }

    /// Safe item available before any network work. A short link may replace
    /// it later, but the first tap never waits for that upgrade.
    var immediateShareText: String { fallbackText }

    func cacheKey(includingOptionalNote: Bool) -> String {
        guard let payload = payload(includingOptionalNote: includingOptionalNote),
              let data = try? JSONEncoder().encode(payload)
        else { return fallbackText }
        return "\(sourcePlaceId?.uuidString ?? "unverified")|\(data.base64EncodedString())"
    }

    func payload(includingOptionalNote: Bool) -> SharedPlaceData? {
        guard let payload else { return nil }
        guard includingOptionalNote else { return payload }
        return payload.withShareNote(optionalShareNote)
    }

    func fallbackURL(includingOptionalNote: Bool) -> URL? {
        guard includingOptionalNote else { return fallbackURL }
        return payload(includingOptionalNote: true)?.toURL()
    }

    func message(for url: URL?, includingOptionalNote: Bool = false) -> String {
        guard let fallbackURL, let url else { return fallbackText }
        var message = fallbackText.replacingOccurrences(of: fallbackURL.absoluteString, with: url.absoluteString)
        if includingOptionalNote, let optionalShareNote {
            message += "\nWhy I'm sharing: \(optionalShareNote)"
        }
        return message
    }

    static func place(_ place: Place) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: place.shareSubject,
            fallbackURL: place.saveShareURL,
            fallbackText: place.shareText,
            payload: SharedPlaceData.from(place: place),
            sourcePlaceId: place.id,
            optionalShareNote: ShareRoutePayloadSanitizer.publicNote(place.note)
        )
    }

    /// Re-shares an Origin recommendation without claiming the original
    /// author's Map Stamp as the current user's source place. Community cards
    /// only carry public place facts; private notes are never attached.
    static func communityRecommendation(_ place: Place) -> SavePlaceShareContent {
        let payload = SharedPlaceData.from(place: place)
        let fallbackURL = payload.toURL()
        var fallbackLines = [
            "Savvy recommendation",
            place.name,
            place.address,
        ]
        if let fallbackURL {
            fallbackLines.append("Open in Savvy: \(fallbackURL.absoluteString)")
        }

        return SavePlaceShareContent(
            subject: "Savvy recommendation: \(place.name)",
            fallbackURL: fallbackURL,
            fallbackText: fallbackLines.joined(separator: "\n"),
            payload: payload,
            sourcePlaceId: nil,
            optionalShareNote: nil
        )
    }

    static func mapCandidate(_ candidate: SaveMapCandidate) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: candidate.shareSubject,
            fallbackURL: candidate.saveShareURL,
            fallbackText: candidate.shareText,
            payload: SharedPlaceData.from(candidate: candidate),
            sourcePlaceId: nil,
            optionalShareNote: nil
        )
    }

    static func searchResult(_ result: SaveSearchResult) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: result.shareSubject,
            fallbackURL: result.saveShareURL,
            fallbackText: result.shareText,
            payload: SharedPlaceData.from(result: result),
            sourcePlaceId: nil,
            optionalShareNote: nil
        )
    }

    static func reviewCandidate(_ candidate: PlaceReviewCandidate) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: candidate.shareSubject,
            fallbackURL: candidate.saveShareURL,
            fallbackText: candidate.shareText,
            payload: SharedPlaceData.from(candidate: candidate),
            sourcePlaceId: nil,
            optionalShareNote: nil
        )
    }
}

/// One tap always lands in the system share sheet. Private notes never travel
/// with a shared place; the short link upgrades the fallback URL in the
/// background when the backend is reachable.
struct SavePlaceShareButton<Label: View>: View {
    let content: SavePlaceShareContent
    @ViewBuilder var label: () -> Label

    @State private var shareURL: URL?
    @State private var basePreparationID: UUID?
    @State private var activeContentKey: String

    init(content: SavePlaceShareContent, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
        _shareURL = State(initialValue: content.fallbackURL)
        _activeContentKey = State(initialValue: content.stateKey)
    }

    var body: some View {
        Group {
            if let shareURL {
                ShareLink(item: shareURL, subject: Text(content.subject), message: Text(content.message(for: shareURL))) {
                    label()
                }
            } else {
                // A short link is an upgrade, never a gate. When there is no
                // embedded fallback URL, the first tap must still open the
                // system share sheet with safe plain text while preparation
                // continues in the background.
                ShareLink(item: content.immediateShareText, subject: Text(content.subject)) {
                    label()
                }
            }
        }
        .task(id: content.stateKey) {
            resetForCurrentContent(content.stateKey)
            await prepareShortLink()
        }
        .onChange(of: content.stateKey) { _, newKey in
            resetForCurrentContent(newKey)
        }
    }

    private func prepareShortLink() async {
        guard let payload = content.payload(includingOptionalNote: false) else { return }
        let cacheKey = content.cacheKey
        let contentKey = content.stateKey

        if let cached = await SavePlaceShareLinkCache.shared.url(for: cacheKey) {
            guard !Task.isCancelled, activeContentKey == contentKey else { return }
            shareURL = cached
            return
        }

        let preparationID = UUID()
        guard basePreparationID == nil else { return }
        basePreparationID = preparationID
        defer {
            if basePreparationID == preparationID { basePreparationID = nil }
        }

        do {
            let url = try await SupabaseService.shared.createSharedPlaceLink(
                payload: payload,
                sourcePlaceId: content.sourcePlaceId,
                noteConsentVersion: nil
            )
            await SavePlaceShareLinkCache.shared.set(url, for: cacheKey)
            guard !Task.isCancelled, activeContentKey == contentKey else { return }
            shareURL = url
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeContentKey == contentKey else { return }
            if let fallback = content.fallbackURL {
                shareURL = fallback
            }
        }
    }

    private func resetForCurrentContent(_ contentKey: String) {
        guard activeContentKey != contentKey else { return }
        activeContentKey = contentKey
        shareURL = content.fallbackURL
        basePreparationID = nil
    }
}

private actor SavePlaceShareLinkCache {
    private struct Entry {
        let url: URL
        let expiresAt: Date
    }

    static let shared = SavePlaceShareLinkCache()
    private var entries: [String: Entry] = [:]

    func url(for key: String) -> URL? {
        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > Date() else {
            entries[key] = nil
            return nil
        }
        return entry.url
    }

    func set(_ url: URL, for key: String) {
        entries[key] = Entry(
            url: url,
            expiresAt: Date().addingTimeInterval(24 * 60 * 60)
        )
    }
}
