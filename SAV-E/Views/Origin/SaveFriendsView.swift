import SwiftUI

struct SaveFriendsView: View {
    var currentUserID: String?
    var onSaved: () async -> Void = {}
    var onParkedAtFreeLimit: (Place) throws -> PlaceReviewCandidate = { place in
        let candidate = PlaceReviewCandidate.unplacedInboxItem(
            from: place,
            ownerSubject: PrivyAuthService.shared.currentUserId
        )
        _ = try SaveLocalVaultService.shared.saveReviewCandidate(
            candidate,
            preservingParkedContext: candidate.isUnplacedInbox
        )
        SavePlaceLimitHandoff.markPaywallPending(notify: false)
        return candidate
    }
    var onRemoveParkedAtFreeLimit: (Place) throws -> Void = { place in
        try SaveLocalVaultService.shared.removeReviewCandidate(
            place.id,
            ownerSubject: PrivyAuthService.shared.currentUserId
        )
    }
    var onConnections: () -> Void = {}
    @StateObject private var store = SharedPostsStore()
    @State private var selected: SharedPlacePost?
    @State private var author: SharedPlacePost?
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SaveDisplayTitle(text: "Savvy", pointSize: 28)

                HStack {
                    SaveDisplayTitle(
                        text: language.localized(english: "Friends", traditionalChinese: "朋友"),
                        pointSize: 22
                    )
                    Spacer(minLength: 4)
                    Button(action: onConnections) {
                        Text(language.localized(english: "Invite", traditionalChinese: "邀請"))
                            .font(SaveAtlasType.strong(13))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(SaveAtlasPalette.coral, in: Capsule())
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
                    SaveTileTownCanvas(pins: friendPins, showsPins: true, clipsToPaper: true)
                        .frame(height: 88)
                        .accessibilityIdentifier("friends.mapStrip")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, AtlasMetrics.statusBarHeight + 12)
            .padding(.bottom, AtlasMetrics.height - 786 + 24)
        }
        .background(SaveAtlasPalette.canvas).foregroundStyle(SaveAtlasPalette.forest)
        .accessibilityIdentifier("friends.root")
        .refreshable { await store.refresh(.feed) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh(.feed) } } }
        .task(id: currentUserID) {
            store.parkOverLimitPlace = onParkedAtFreeLimit
            store.removeParkedOverLimitPlace = onRemoveParkedAtFreeLimit
            await store.refresh(.feed)
        }
        .sheet(item: $selected) { SharedPostDetail(initialPost: $0, store: store, onSaved: onSaved) }
        .sheet(item: $author) { SharedAuthorPassport(authorID: $0.author_id, onSaved: onSaved, parkOverLimitPlace: onParkedAtFreeLimit) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2").font(.system(size: 46, weight: .light))
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
                            SavePostageSealAvatar(name: row.authorName)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.authorName)
                                    .font(SaveAtlasType.strong(16))
                                    .foregroundStyle(SaveAtlasPalette.forest)
                                Text(lastAtText(row.lastPost))
                                    .font(SaveAtlasType.body(13))
                                    .foregroundStyle(SaveAtlasPalette.muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("friends.author.\(row.authorID)")

                    Button { selected = row.lastPost } label: {
                        SharedPostArtwork(post: row.lastPost, compact: true)
                            .frame(width: 72, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("friends.post.\(row.lastPost.id.uuidString)")
                }
                .padding(12)
                .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(SaveAtlasPalette.line.opacity(0.28), lineWidth: 1)
                }
            }
        }
    }

    private var friendPins: [SaveTileTownPin] {
        store.posts.prefix(6).map { post in
            SaveTileTownPin(id: post.id, name: post.name, isSelected: false)
        }
    }

    private func lastAtText(_ post: SharedPlacePost) -> String {
        language.localized(
            english: "Last at \(post.name)",
            traditionalChinese: "最近在 \(post.name)"
        )
    }
}
