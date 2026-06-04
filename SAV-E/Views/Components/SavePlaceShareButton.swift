import SwiftUI

struct SavePlaceShareContent {
    let subject: String
    let fallbackURL: URL?
    let fallbackText: String
    let payload: SharedPlaceData?
    let sourcePlaceId: UUID?

    var cacheKey: String {
        guard let payload else { return fallbackText }
        return [
            sourcePlaceId?.uuidString ?? payload.id,
            payload.name,
            payload.address,
            String(format: "%.5f", payload.lat),
            String(format: "%.5f", payload.lng),
        ].joined(separator: "|")
    }

    func message(for url: URL?) -> String {
        guard let fallbackURL, let url else { return fallbackText }
        return fallbackText.replacingOccurrences(of: fallbackURL.absoluteString, with: url.absoluteString)
    }

    static func place(_ place: Place) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: place.shareSubject,
            fallbackURL: place.saveShareURL,
            fallbackText: place.shareText,
            payload: SharedPlaceData.from(place: place),
            sourcePlaceId: place.id
        )
    }

    static func mapCandidate(_ candidate: SaveMapCandidate) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: candidate.shareSubject,
            fallbackURL: candidate.saveShareURL,
            fallbackText: candidate.shareText,
            payload: SharedPlaceData.from(candidate: candidate),
            sourcePlaceId: nil
        )
    }

    static func searchResult(_ result: SaveSearchResult) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: result.shareSubject,
            fallbackURL: result.saveShareURL,
            fallbackText: result.shareText,
            payload: SharedPlaceData.from(result: result),
            sourcePlaceId: nil
        )
    }

    static func reviewCandidate(_ candidate: PlaceReviewCandidate) -> SavePlaceShareContent {
        SavePlaceShareContent(
            subject: candidate.shareSubject,
            fallbackURL: candidate.saveShareURL,
            fallbackText: candidate.shareText,
            payload: SharedPlaceData.from(candidate: candidate),
            sourcePlaceId: nil
        )
    }
}

struct SavePlaceShareButton<Label: View>: View {
    let content: SavePlaceShareContent
    @ViewBuilder var label: () -> Label

    @State private var shareURL: URL?
    @State private var isPreparing = false

    init(content: SavePlaceShareContent, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
        _shareURL = State(initialValue: content.fallbackURL)
    }

    var body: some View {
        Group {
            if let shareURL {
                ShareLink(item: shareURL, subject: Text(content.subject), message: Text(content.message(for: shareURL))) {
                    label()
                }
            } else if content.payload != nil {
                Button {
                    Task {
                        await prepareShortLink()
                    }
                } label: {
                    label()
                        .opacity(isPreparing ? 0.56 : 1)
                }
                .disabled(isPreparing)
                .accessibilityLabel(isPreparing ? "Preparing share link" : "Create share link")
            } else {
                ShareLink(item: content.fallbackText, subject: Text(content.subject)) {
                    label()
                }
            }
        }
        .task(id: content.cacheKey) {
            await prepareShortLink()
        }
    }

    private func prepareShortLink() async {
        guard let payload = content.payload else { return }

        if let cached = await SavePlaceShareLinkCache.shared.url(for: content.cacheKey) {
            shareURL = cached
            return
        }

        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        do {
            let url = try await SupabaseService.shared.createSharedPlaceLink(
                payload: payload,
                sourcePlaceId: content.sourcePlaceId
            )
            await SavePlaceShareLinkCache.shared.set(url, for: content.cacheKey)
            shareURL = url
        } catch {
            shareURL = content.fallbackURL
        }
    }
}

private actor SavePlaceShareLinkCache {
    static let shared = SavePlaceShareLinkCache()
    private var urls: [String: URL] = [:]

    func url(for key: String) -> URL? {
        urls[key]
    }

    func set(_ url: URL, for key: String) {
        urls[key] = url
    }
}
