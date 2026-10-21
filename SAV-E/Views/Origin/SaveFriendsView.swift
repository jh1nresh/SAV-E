import SwiftUI

/// Doodle v1 Friends: people-first last-at list. HoP keeps the map strip off this tab.
/// Visual reference is Codex packet spec §7.4 Friends column, not DESIGN v2 friends.png.
struct SaveFriendsView: View {
    var currentUserID: String?
    var onSaved: () async -> Void = {}
    var onConnections: () -> Void = {}
    @StateObject private var store = SharedPostsStore()
    @State private var selected: SharedPlacePost?
    @State private var author: SharedPlacePost?
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, SaveLayout.screenMargin)
                .padding(.top, AtlasMetrics.statusBarHeight + SaveSpace.xs)
                .frame(minHeight: SaveLayout.minTap)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if store.isLoading && store.posts.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, SaveSpace.xl)
                            .accessibilityIdentifier("friends.loading")
                    }
                    if store.error != nil { SocialLoadError().padding(.top, SaveSpace.md) }
                    if !store.isLoading && store.error == nil && store.posts.isEmpty {
                        emptyState
                    }
                    peopleList
                    if store.nextCursor != nil {
                        Button(language.localized(english: "Load more", traditionalChinese: "載入更多")) {
                            Task { await store.loadMore() }
                        }
                        .disabled(store.isLoading)
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .frame(maxWidth: .infinity, minHeight: SaveLayout.minTap)
                        .padding(.top, SaveSpace.md)
                    }
                }
                .padding(.horizontal, SaveLayout.screenMargin)
                .padding(.bottom, SaveTileTownProductLock.rootTabScrollClearance)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SaveDottedBackground())
        .foregroundStyle(SaveAtlasPalette.ink)
        .accessibilityIdentifier("friends.root")
        .task(id: currentUserID) { await store.refresh(.feed) }
        .refreshable { await store.refresh(.feed) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh(.feed) } } }
        .sheet(item: $selected) { SharedPostDetail(initialPost: $0, store: store, onSaved: onSaved) }
        .sheet(item: $author) { SharedAuthorPassport(authorID: $0.author_id, onSaved: onSaved) }
    }

    private var header: some View {
        HStack(spacing: SaveSpace.xs) {
            SaveDisplayTitle(
                text: language.localized(english: "Friends", traditionalChinese: "朋友"),
                pointSize: 34,
                relativeTo: .largeTitle
            )
            .accessibilityIdentifier("friends.title")

            Spacer(minLength: SaveSpace.xs)

            Button(action: onConnections) {
                Text(language.localized(english: "Invite", traditionalChinese: "邀請"))
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .padding(.horizontal, SaveSpace.md)
                    .padding(.vertical, 6)
                    .frame(minHeight: SaveLayout.chipHeight)
                    .overlay {
                        Capsule()
                            .stroke(SaveAtlasPalette.ink, lineWidth: 1)
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(minWidth: SaveLayout.minTap, minHeight: SaveLayout.minTap)
            .accessibilityLabel(language.localized(english: "Invite", traditionalChinese: "邀請"))
            .accessibilityHint(language.localized(
                english: "Opens following and invite links",
                traditionalChinese: "打開追蹤與邀請連結"
            ))
            .accessibilityIdentifier("friends.connections")
        }
        .frame(minHeight: SaveLayout.minTap)
    }

    private var emptyState: some View {
        VStack(spacing: SaveSpace.md) {
            SaveDoodleFriendsMark(size: 64)
                .padding(.top, SaveSpace.xxl)
                .accessibilityHidden(true)

            Text(language.localized(
                english: "Their next place could be yours",
                traditionalChinese: "下一個想去的地方，從朋友開始"
            ))
            .font(SaveDisplayType.display(24, relativeTo: .title2))
            .foregroundStyle(SaveAtlasPalette.forest)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("friends.empty")

            Text(language.localized(
                english: "Follow someone with their Savvy link. Their shared places will appear here.",
                traditionalChinese: "透過 Savvy 連結追蹤朋友，他們主動分享的地點就會出現在這裡。"
            ))
            .font(SaveAtlasType.body(13))
            .foregroundStyle(SaveAtlasPalette.muted)
            .multilineTextAlignment(.center)

            Button(action: onConnections) {
                Text(language.localized(english: "Find friends", traditionalChinese: "追蹤朋友"))
                    .font(SaveAtlasType.strong(17))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .frame(maxWidth: .infinity, minHeight: SaveLayout.buttonHeight)
                    .background(
                        SaveAtlasPalette.paper,
                        in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
                            .stroke(SaveAtlasPalette.coral, lineWidth: SaveAtlasPalette.strokeWidth)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("friends.findFriends")
        }
        .padding(.bottom, SaveSpace.xxl)
        .frame(maxWidth: .infinity)
    }

    private var peopleList: some View {
        let rows = SaveFriendLastAt.rows(from: store.posts)
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                friendRow(row)
                if index < rows.count - 1 {
                    SaveDoodleDashedDivider()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends.list")
    }

    private func friendRow(_ row: SaveFriendLastAt.Row) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Button { author = row.lastPost } label: {
                HStack(alignment: .center, spacing: 0) {
                    SaveDoodleFriendAvatar(name: row.authorName, imageURL: row.lastPost.author_avatar_url)
                        .padding(.trailing, SaveLayout.stickerToText)

                    VStack(alignment: .leading, spacing: SaveLayout.titleToMeta) {
                        Text(row.authorName)
                            .font(SaveAtlasType.strong(17))
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .lineLimit(1)
                        Text(
                            SaveFriendLastAt.lastAtText(
                                row.lastPost,
                                language: language.language,
                                now: SaveFriendLastAt.clock
                            )
                        )
                            .font(SaveAtlasType.body(13))
                            .foregroundStyle(SaveAtlasPalette.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("friends.author.\(row.authorID)")

            Button { selected = row.lastPost } label: {
                SaveDoodleFriendSticker(name: row.lastPost.name, category: row.lastPost.category)
                    .frame(width: 32, height: 32)
                    .frame(width: SaveLayout.minTap, height: SaveLayout.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.localized(
                english: "Open \(row.lastPost.name)",
                traditionalChinese: "打開\(row.lastPost.name)"
            ))
            .accessibilityIdentifier("friends.post.\(row.lastPost.id.uuidString)")
        }
        .padding(.vertical, SaveLayout.rowVerticalPadding)
        .frame(minHeight: SaveLayout.rowMinHeight, alignment: .leading)
    }
}

/// Hand-drawn initial (or photo) in a 48pt ink ring. Replaces the postage-seal avatar.
struct SaveDoodleFriendAvatar: View {
    let name: String
    var imageURL: String? = nil
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(SaveAtlasPalette.paper)
            if let imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initial
                    }
                }
                .clipShape(Circle())
            } else {
                initial
            }
            Circle()
                .stroke(SaveAtlasPalette.forest, lineWidth: 1.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .accessibilityLabel(name)
    }

    private var initial: some View {
        Text(SaveDoodleFriendAvatar.initial(from: name))
            .font(SaveDisplayType.display(24, relativeTo: .title2))
            .foregroundStyle(SaveAtlasPalette.forest)
    }

    static func initial(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}

/// Slightly imperfect ring so the avatar reads as ink, not a system chrome circle.
nonisolated struct SaveDoodleInkRing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.insetBy(dx: 2.2, dy: 2.2)
        path.addEllipse(in: CGRect(
            x: inset.minX + 0.8,
            y: inset.minY - 0.6,
            width: inset.width - 1.0,
            height: inset.height + 0.9
        ))
        return path
    }
}

/// 32pt official outline sticker. Packet §7.4 wants line-art, not a filled box.
struct SaveDoodleFriendSticker: View {
    let name: String
    let category: String

    var body: some View {
        SaveDoodleSticker(
            category: PlaceCategory(rawValue: category) ?? .attraction,
            placeName: name,
            visited: false,
            pointSize: 32,
            boxSize: SaveLayout.minTap
        )
    }

    static func kind(name: String, category: String) -> SaveDoodleOfficialSticker {
        SaveDoodleOfficialSticker.named(
            for: PlaceCategory(rawValue: category) ?? .attraction,
            placeName: name
        )
    }

    static func symbolName(for category: PlaceCategory?) -> String {
        switch category {
        case .food: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .bar: return "wineglass"
        case .attraction: return "leaf"
        case .stay: return "bed.double"
        case .shopping: return "bag"
        case nil: return "mappin"
        }
    }
}

/// One decorative doodle for the empty Friends page (spec §8).
struct SaveDoodleFriendsMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            SaveDoodleInkRing()
                .stroke(SaveDoodle.pencil, lineWidth: 1.5)
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(x: -size * 0.16)
            SaveDoodleInkRing()
                .stroke(SaveDoodle.pencil, lineWidth: 1.5)
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(x: size * 0.16)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Latest explicit post per author. Lives with Friends (was TileTown-adjacent).
enum SaveFriendLastAt {
    struct Row: Identifiable, Equatable {
        var id: String { authorID }
        let authorID: String
        let authorName: String
        let lastPost: SharedPlacePost
    }

    static var clock: Date {
        if ProcessInfo.processInfo.arguments.contains("--uitest-friends-town") {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: "2026-10-20T10:00:00Z") ?? Date()
        }
        return Date()
    }

    static func rows(from posts: [SharedPlacePost]) -> [Row] {
        var latest: [String: SharedPlacePost] = [:]
        for post in posts {
            if let existing = latest[post.author_id] {
                if post.shared_at > existing.shared_at {
                    latest[post.author_id] = post
                }
            } else {
                latest[post.author_id] = post
            }
        }
        return latest.values
            .sorted { lhs, rhs in
                if lhs.shared_at != rhs.shared_at { return lhs.shared_at > rhs.shared_at }
                return lhs.author_name.localizedCaseInsensitiveCompare(rhs.author_name) == .orderedAscending
            }
            .map { post in
                Row(authorID: post.author_id, authorName: post.author_name, lastPost: post)
            }
    }

    static func lastAtText(_ post: SharedPlacePost, language: AppLanguage, now: Date = Date()) -> String {
        let age = relativeAge(from: post.shared_at, now: now, language: language)
        switch language {
        case .traditionalChinese:
            return "最近在 \(post.name) · \(age)"
        case .english:
            return "last at \(post.name) · \(age)"
        }
    }

    static func relativeAge(from sharedAt: String, now: Date = Date(), language: AppLanguage = .english) -> String {
        guard let date = date(from: sharedAt) else {
            return language == .traditionalChinese ? "剛剛" : "now"
        }
        let seconds = max(0, now.timeIntervalSince(date))
        let chinese = language == .traditionalChinese
        if seconds < 3600 {
            return chinese ? "剛剛" : "now"
        }
        let hours = Int(seconds / 3600)
        if hours < 24 {
            return chinese ? "\(hours)小時" : "\(hours)h"
        }
        let days = Int(seconds / 86_400)
        if days < 7 {
            return chinese ? "\(days)天" : "\(days)d"
        }
        let weeks = days / 7
        if weeks < 5 {
            return chinese ? "\(weeks)週" : "\(weeks)w"
        }
        let months = max(1, days / 30)
        return chinese ? "\(months)個月" : "\(months)mo"
    }

    static func date(from sharedAt: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: sharedAt) ?? ISO8601DateFormatter().date(from: sharedAt)
    }
}

#if DEBUG
#Preview("Friends") {
    SaveFriendsView()
}

#Preview("Friends dark") {
    SaveFriendsView()
        .preferredColorScheme(.dark)
}
#endif
