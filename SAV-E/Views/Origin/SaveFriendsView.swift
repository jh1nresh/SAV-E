import SwiftUI

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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SavePixelDisplayText(text: "Savvy", pointSize: 34)

                HStack {
                    Text(language.localized(english: "Friends", traditionalChinese: "朋友"))
                        .font(SaveAtlasType.strong(22))
                        .foregroundStyle(SaveAtlasPalette.forest)
                    Spacer(minLength: 4)
                    Button(action: onConnections) {
                        Text(language.localized(english: "Invite", traditionalChinese: "邀請"))
                            .font(SaveAtlasType.strong(13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(SaveAtlasPalette.coral, in: SaveKraftTicketShape())
                    }
                    .accessibilityLabel(language.localized(english: "Manage following", traditionalChinese: "管理追蹤"))
                    .accessibilityIdentifier("friends.connections")
                }

                if store.isLoading && store.posts.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(50) }
                if store.error != nil { SocialLoadError() }
                if !store.isLoading && store.error == nil && store.posts.isEmpty {
                    emptyState
                }
                peopleList
                if store.nextCursor != nil {
                    Button(language.localized(english: "Load more", traditionalChinese: "載入更多")) { Task { await store.loadMore() } }
                        .disabled(store.isLoading).frame(maxWidth: .infinity, minHeight: 44)
                }
                if !store.posts.isEmpty {
                    sharedPlacesSummary
                        .accessibilityIdentifier("friends.mapStrip")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, AtlasMetrics.statusBarHeight + 12)
            .padding(.bottom, SaveTileTownProductLock.rootTabScrollClearance)
        }
        .background(SaveAtlasPalette.canvas).foregroundStyle(SaveAtlasPalette.forest)
        .accessibilityIdentifier("friends.root")
        .task(id: currentUserID) { await store.refresh(.feed) }
        .refreshable { await store.refresh(.feed) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh(.feed) } } }
        .sheet(item: $selected) { SharedPostDetail(initialPost: $0, store: store, onSaved: onSaved) }
        .sheet(item: $author) { SharedAuthorPassport(authorID: $0.author_id, onSaved: onSaved) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2").font(.system(size: 46, weight: .light)).savePixelated()
            Text(language.localized(english: "Their next place could be yours", traditionalChinese: "下一個想去的地方，從朋友開始"))
                .font(SaveAtlasType.strong(21)).multilineTextAlignment(.center)
                .accessibilityIdentifier("friends.empty")
            Text(language.localized(english: "Follow someone with their Savvy link. Their shared places will appear here.", traditionalChinese: "透過 Savvy 連結追蹤朋友，他們主動分享的地點就會出現在這裡。"))
                .font(SaveAtlasType.body(14)).foregroundStyle(SaveAtlasPalette.muted).multilineTextAlignment(.center)
            Button(action: onConnections) {
                Text(language.localized(english: "Find friends", traditionalChinese: "追蹤朋友"))
                    .foregroundStyle(SaveAtlasPalette.paper)
            }
            .buttonStyle(.borderedProminent).tint(SaveAtlasPalette.forest)
            .accessibilityIdentifier("friends.findFriends")
        }.padding(.horizontal, 16).padding(.vertical, 60)
    }

    private var peopleList: some View {
        LazyVStack(spacing: 14) {
            ForEach(SaveFriendLastAt.rows(from: store.posts)) { row in
                HStack(spacing: 12) {
                    Button { author = row.lastPost } label: {
                        HStack(spacing: 12) {
                            SavePostageSealAvatar(
                                name: row.authorName,
                                authorID: row.authorID,
                                photoURL: row.lastPost.author_avatar_url.flatMap(URL.init(string:)),
                                size: 64
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.authorName)
                                    .font(SaveAtlasType.strong(16))
                                    .foregroundStyle(SaveAtlasPalette.forest)
                                Text(lastAtText(row.lastPost))
                                    .font(SaveAtlasType.body(13))
                                    .foregroundStyle(SaveAtlasPalette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("friends.author.\(row.authorID)")

                    Button { selected = row.lastPost } label: {
                        Group {
                            if (row.lastPost.photo_count ?? 0) > 0 {
                                SharedPostArtwork(post: row.lastPost, compact: true)
                            } else {
                                SaveKraftStampPixelArt(scene: .from(name: row.lastPost.name, category: row.lastPost.category, detail: row.lastPost.caption ?? ""))
                            }
                        }
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(language.localized(
                        english: "Open shared place, \(row.lastPost.name)",
                        traditionalChinese: "開啟分享地點，\(row.lastPost.name)"
                    ))
                    .accessibilityIdentifier("friends.post.\(row.lastPost.id.uuidString)")
                }
                .padding(12)
                .background(SaveAtlasPalette.paper, in: SaveKraftTicketShape())
                .overlay {
                    SaveKraftTicketShape()
                        .stroke(SaveAtlasPalette.line.opacity(0.65), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// Shared posts have no coordinates. A paper summary avoids implying
    /// either a geographic position or a friend's current location.
    private var sharedPlacesSummary: some View {
        Label(
            language.localized(
                english: "Places explicitly shared by friends",
                traditionalChinese: "朋友主動分享的地點"
            ),
            systemImage: "person.2"
        )
        .font(SaveAtlasType.body(13))
        .foregroundStyle(SaveAtlasPalette.muted)
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.horizontal, 16)
        .background(SaveAtlasPalette.paper, in: SaveKraftTicketShape())
    }

    private func lastAtText(_ post: SharedPlacePost) -> String {
        post.status == .wantToGo
            ? language.localized(english: "Wants to go · \(post.name)", traditionalChinese: "想去・\(post.name)")
            : language.localized(english: "Shared · \(post.name)", traditionalChinese: "分享了・\(post.name)")
    }
}
