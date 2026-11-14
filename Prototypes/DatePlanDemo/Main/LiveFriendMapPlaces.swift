#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation
import SwiftUI

/// Ephemeral attribution from an already-authorized feed. Never persist as recipient memory.
@MainActor
struct LiveFriendMapPlace: Identifiable {
    nonisolated var id: UUID { postID }
    let postID: UUID
    let pin: LiveMapPlace
    let authorName: String
    let avatarURL: URL?
    let hasVisited: Bool
    private let hasNamedAuthor: Bool

    func statusTitle(_ language: AppLanguage) -> String {
        "\(localizedAuthorName(language))・\(statusName(language))"
    }

    func localizedAuthorName(_ language: AppLanguage) -> String {
        hasNamedAuthor ? authorName : language.localized(english: "Friend", traditionalChinese: "朋友")
    }

    func statusName(_ language: AppLanguage) -> String {
        hasVisited
            ? language.localized(english: "Visited", traditionalChinese: "去過")
            : language.localized(english: "Shared", traditionalChinese: "分享")
    }

    static func projections(posts: [SharedPlacePost]) -> [LiveFriendMapPlace] {
        posts.compactMap { post in
            guard post.visible_to_followers, let pin = LiveMapPlace.sharedPost(post) else { return nil }
            let name = post.author_name.trimmingCharacters(in: .whitespacesAndNewlines)
            return LiveFriendMapPlace(postID: post.id, pin: pin,
                                      authorName: name.isEmpty ? "朋友" : name,
                                      avatarURL: safeAvatarURL(post.author_avatar_url),
                                      hasVisited: post.status == .visited, hasNamedAuthor: !name.isEmpty)
        }
    }

    /// Exact normalized name plus five-decimal coordinate cells, never fuzzy venue matching.
    /// Groups and their posts retain first-appearance order; no coordinate or author is rewritten.
    static func groupedByVenue(_ values: [LiveFriendMapPlace]) -> [[LiveFriendMapPlace]] {
        var indices: [String: Int] = [:]
        var groups: [[LiveFriendMapPlace]] = []
        let locale = Locale(identifier: "en_US_POSIX")
        for value in values {
            let name = value.pin.place.name.precomposedStringWithCanonicalMapping
                .lowercased(with: locale).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            let coordinate = value.pin.coordinate
            // Projection construction already requires finite, valid WGS84 coordinates.
            let latitude = Int64((coordinate.latitude * 100_000).rounded())
            let longitude = Int64((coordinate.longitude * 100_000).rounded())
            let key = "\(name.utf8.count):\(name)|\(latitude)|\(longitude)"
            if let index = indices[key] {
                groups[index].append(value)
            } else {
                indices[key] = groups.count
                groups.append([value])
            }
        }
        return groups
    }

    private static func safeAvatarURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return GooglePlacesPhotoSourceMarkMetrics.mapSafePhotoURL(url)
    }
}

/// Decorative badge inside the caller's annotation button; it does not own map selection.
@MainActor
struct LiveFriendPinBadge: View {
    let friend: LiveFriendMapPlace
    @Environment(\.appLanguageSettings) private var language

    init(friend: LiveFriendMapPlace) { self.friend = friend }

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if let url = friend.avatarURL {
                    CachedAsyncImage(url: url) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { avatarFallback }
                    }
                } else { avatarFallback }
            }
            .frame(width: 18, height: 18).background(DateTheme.soft).clipShape(Circle())
            .accessibilityHidden(true)
            Text(friend.localizedAuthorName(language.language))
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: 60, alignment: .leading)
            Text("・\(friend.statusName(language.language))")
                .lineLimit(1).fixedSize().layoutPriority(1)
        }
        .font(.system(.caption2, design: .rounded, weight: .semibold))
        .padding(.horizontal, 6).padding(.vertical, 4)
        .foregroundStyle(DateTheme.ink).background(DateTheme.surface, in: Capsule())
        .overlay(Capsule().stroke(DateTheme.blue.opacity(0.25)))
        .accessibilityElement(children: .ignore).accessibilityLabel(friend.statusTitle(language.language))
    }

    private var avatarFallback: some View {
        Image(systemName: "person.fill").font(.system(size: 11, weight: .medium))
            .foregroundStyle(DateTheme.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
