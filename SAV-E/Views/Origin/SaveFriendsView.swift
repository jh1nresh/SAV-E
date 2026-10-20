import SwiftUI

/// Doodle v1 Friends: people-first activity list. HoP keeps the map strip off this tab.
/// Parity target is DESIGN 2026-10-20 `friends-light.png` (402×874, no shared-map).
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
                .frame(minHeight: 44)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if store.isLoading && store.posts.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, SaveSpace.xl)
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
                Text(language.localized(english: "＋ Invite", traditionalChinese: "＋ 邀請"))
                    .font(SaveAtlasType.strong(15))
                    .foregroundStyle(SaveAtlasPalette.coral)
                    .padding(.horizontal, SaveSpace.md)
                    .frame(height: SaveLayout.chipHeight)
                    .overlay {
                        Capsule()
                            .stroke(SaveAtlasPalette.coral, lineWidth: 1)
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .frame(minWidth: SaveLayout.minTap, minHeight: SaveLayout.minTap)
            .accessibilityLabel(language.localized(english: "Manage following", traditionalChinese: "管理追蹤"))
            .accessibilityIdentifier("friends.connections")
        }
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
        return VStack(alignment: .leading, spacing: 0) {
            if !rows.isEmpty {
                Text(language.localized(english: "最近動態 Recent", traditionalChinese: "最近動態 Recent"))
                    .font(SaveDisplayType.display(20, relativeTo: .title3))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .padding(.top, SaveSpace.sm)
                    .padding(.bottom, SaveSpace.xs)
            }
            ForEach(rows) { row in
                friendRow(row)
                SaveDoodleDashedDivider()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends.list")
    }

    private func friendRow(_ row: SaveFriendLastAt.Row) -> some View {
        HStack(alignment: .center, spacing: SaveLayout.stickerToText) {
            Button { author = row.lastPost } label: {
                SaveDoodleFriendAvatar(name: row.authorName, imageURL: row.lastPost.author_avatar_url)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("friends.author.\(row.authorID)")

            Button { selected = row.lastPost } label: {
                VStack(alignment: .leading, spacing: SaveLayout.titleToMeta) {
                    Text(row.authorName)
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .lineLimit(1)
                    Text(
                        SaveFriendLastAt.lastAtText(
                            row.lastPost,
                            postCount: row.postCount,
                            language: language.language,
                            now: SaveFriendLastAt.clock
                        )
                    )
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("friends.post.\(row.lastPost.id.uuidString)")
        }
        .frame(minHeight: SaveLayout.rowMinHeight, alignment: .leading)
    }
}

/// 48pt kraft-light fill with a hairline. Initials are SF rounded, not Caveat.
struct SaveDoodleFriendAvatar: View {
    let name: String
    var imageURL: String? = nil
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(SaveAtlasPalette.kraftLight)
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
                .stroke(SaveAtlasPalette.line, lineWidth: 1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .accessibilityLabel(name)
    }

    private var initial: some View {
        Text(SaveDoodleFriendAvatar.initial(from: name))
            .font(SaveAtlasType.strong(17))
            .foregroundStyle(SaveAtlasPalette.forest)
    }

    static func initial(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let latin = trimmed.first(where: { $0.isLetter && $0.isASCII }) {
            return String(latin).uppercased()
        }
        if let last = trimmed.last(where: { !$0.isWhitespace }) {
            return String(last)
        }
        return "?"
    }
}

/// Slightly imperfect ring so the empty-state mark reads as ink.
nonisolated struct SaveDoodleInkRing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.insetBy(dx: 1.5, dy: 1.5)
        path.addEllipse(in: CGRect(
            x: inset.minX + 0.6,
            y: inset.minY - 0.4,
            width: inset.width - 0.8,
            height: inset.height + 0.6
        ))
        return path
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
        let postCount: Int
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
        var counts: [String: Int] = [:]
        for post in posts {
            counts[post.author_id, default: 0] += 1
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
                Row(
                    authorID: post.author_id,
                    authorName: post.author_name,
                    lastPost: post,
                    postCount: counts[post.author_id] ?? 1
                )
            }
    }

    static func lastAtText(
        _ post: SharedPlacePost,
        postCount: Int = 1,
        language: AppLanguage,
        now: Date = Date()
    ) -> String {
        let age = relativeAge(from: post.shared_at, now: now, language: language)
        if postCount > 1 {
            let city = post.address
            switch language {
            case .traditionalChinese:
                return "在\(city)有 \(postCount) 個地點 · \(age)"
            case .english:
                return "\(postCount) places in \(city) · \(age)"
            }
        }
        switch (post.status, language) {
        case (.visited, .traditionalChinese):
            return "去過 \(post.name) · \(age)"
        case (.visited, .english):
            return "visited \(post.name) · \(age)"
        case (_, .traditionalChinese):
            return "收藏了 \(post.name) · \(age)"
        case (_, .english):
            return "saved \(post.name) · \(age)"
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
        if days < 2 {
            return chinese ? "昨天" : "yesterday"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: chinese ? "zh_Hant" : "en_US_POSIX")
        formatter.dateFormat = chinese ? "M月d日" : "MMM d"
        return formatter.string(from: date)
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
