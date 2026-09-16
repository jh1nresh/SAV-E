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
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.localized(english: "Friends", traditionalChinese: "朋友"))
                            .font(SaveAtlasType.display(28))
                        Text(language.localized(english: "Places shared by people you follow", traditionalChinese: "看看你追蹤的人，都把哪些地方放在心上"))
                            .font(SaveAtlasType.body(13)).foregroundStyle(SaveAtlasPalette.muted)
                    }
                    Spacer(minLength: 4)
                    Button(action: onConnections) {
                        Image(systemName: "person.badge.plus").frame(width: 44, height: 44)
                    }.accessibilityLabel(language.localized(english: "Manage following", traditionalChinese: "管理追蹤"))
                    .accessibilityIdentifier("friends.connections")
                }
                if store.isLoading && store.posts.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(50) }
                if store.error != nil { SocialLoadError() }
                if !store.isLoading && store.error == nil && store.posts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "postcard").font(.system(size: 46, weight: .light))
                        Text(language.localized(english: "Their next place could be yours", traditionalChinese: "下一個想去的地方，從朋友開始"))
                            .font(SaveAtlasType.strong(21)).multilineTextAlignment(.center)
                            .accessibilityIdentifier("friends.empty")
                        Text(language.localized(english: "Follow someone with their Savvy link. Their shared places will appear here.", traditionalChinese: "透過 Savvy 連結追蹤朋友，他們主動分享的地點就會出現在這裡。"))
                            .font(SaveAtlasType.body(14)).foregroundStyle(SaveAtlasPalette.muted).multilineTextAlignment(.center)
                        Button(language.localized(english: "Find friends", traditionalChinese: "追蹤朋友"), action: onConnections)
                            .buttonStyle(.borderedProminent).tint(SaveAtlasPalette.forest)
                    }.padding(.horizontal, 16).padding(.vertical, 60)
                }
                LazyVStack(spacing: 24) {
                    ForEach(store.posts) { post in
                        VStack(alignment: .leading, spacing: 12) {
                            Button { author = post } label: {
                                HStack {
                                    Image(systemName: "person.crop.circle").font(.system(size: 28, weight: .light))
                                    Text(post.author_name).font(SaveAtlasType.strong(15))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }.frame(minHeight: 44)
                            }.disabled(store.isDemo)
                            Button { selected = post } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    SharedPostArtwork(post: post).frame(height: 215)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay(alignment: .bottomLeading) { SharedPostStatus(status: post.status).padding(12) }
                                    HStack(alignment: .top) {
                                        Text(post.name).font(SaveAtlasType.strong(21))
                                        Spacer()
                                        Image(systemName: "arrow.up.right").font(.body)
                                    }
                                    if let caption = post.caption, !caption.isEmpty {
                                        Text(caption).font(SaveAtlasType.body(14)).lineLimit(3).foregroundStyle(SaveAtlasPalette.muted)
                                    }
                                }.contentShape(Rectangle())
                            }.accessibilityIdentifier("friends.post.\(post.id.uuidString)")
                        }
                        .buttonStyle(.plain).padding(16)
                        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 22))
                        .overlay { RoundedRectangle(cornerRadius: 22).stroke(SaveAtlasPalette.line.opacity(0.3)) }
                    }
                }
                if store.nextCursor != nil {
                    Button(language.localized(english: "Load more", traditionalChinese: "載入更多")) { Task { await store.loadMore() } }
                        .disabled(store.isLoading).frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, AtlasMetrics.statusBarHeight + 12)
            .padding(.bottom, AtlasMetrics.height - 786 + 24)
        }
        .background(SaveAtlasPalette.canvas).foregroundStyle(SaveAtlasPalette.forest)
        .accessibilityIdentifier("friends.root")
        .task(id: currentUserID) { await store.refresh(.feed) }
        .refreshable { await store.refresh(.feed) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh(.feed) } } }
        .sheet(item: $selected) { SharedPostDetail(initialPost: $0, store: store, onSaved: onSaved) }
        .sheet(item: $author) { SharedAuthorPassport(authorID: $0.author_id, onSaved: onSaved) }
    }
}
