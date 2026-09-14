import SwiftUI

struct SaveFriendsView: View {
    @ObservedObject var mapViewModel: MapViewModel
    @ObservedObject private var auth = PrivyAuthService.shared
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.scenePhase) private var scenePhase
    @State private var ratings: [FriendRestaurantRating] = []
    @State private var ownRatings: [OwnRestaurantRating] = []
    @State private var nextCursor: String?
    @State private var loading = false
    @State private var working = false
    @State private var error: String?
    @State private var friendCode = ""
    @State private var savedIDs: Set<UUID> = []
    @State private var editingPlace: Place?
    @State private var generation = UUID()
    @State private var showingMyRatings = false
    var api: SupabaseService = .shared

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()
            BrandHeader { EmptyView() }
                .placed(x: 0, y: 48, width: AtlasMetrics.width, height: 51)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(text("Friends", "朋友"))
                        .font(SaveAtlasType.display(28)).foregroundStyle(SaveAtlasPalette.forest)
                    Text(text("Restaurants your friends have eaten at and chosen to share.", "看看朋友吃過、並主動分享評分的餐廳。"))
                        .font(SaveAtlasType.body(14)).foregroundStyle(SaveAtlasPalette.muted)
                    followControls
                    Picker(text("Show", "顯示"), selection: $showingMyRatings) {
                        Text(text("From friends", "朋友分享")).tag(false)
                        Text(text("My ratings", "我的評分")).tag(true)
                    }.pickerStyle(.segmented)
                    if let error {
                        Text(error).font(SaveAtlasType.body(14)).foregroundStyle(SaveAtlasPalette.ink)
                        Button(text("Try again", "重試")) { Task { await refresh() } }.frame(minHeight: 44)
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity).accessibilityLabel(text("Loading ratings", "載入評分")) }
                    if showingMyRatings { myRatings } else { friendRatings }
                    if !mapViewModel.followedFriends.isEmpty {
                        DisclosureGroup(text("Following", "追蹤中")) {
                            ForEach(mapViewModel.followedFriends) { friend in
                                HStack {
                                    Text(friend.displayName).font(SaveAtlasType.body(15))
                                    Spacer()
                                    Button(text("Unfollow", "取消追蹤")) {
                                        Task { await perform {
                                            try await mapViewModel.unfollowFriend(friend)
                                        } }
                                    }.frame(minHeight: 44).disabled(working)
                                }
                            }
                            if mapViewModel.hasMoreFollowedFriends {
                                Button(text("More friends", "更多朋友")) { Task { await mapViewModel.loadMoreFollowedFriends() } }
                                    .frame(minHeight: 44)
                            }
                        }.font(SaveAtlasType.body(15))
                    }
                }.padding(16)
            }
            .refreshable { await refresh() }
            .placed(x: 0, y: 106, width: AtlasMetrics.width, height: 664)
        }
        .frame(width: AtlasMetrics.width, height: AtlasMetrics.height)
        .background(SaveAtlasPalette.canvas)
        .accessibilityIdentifier("friends.root")
        .task(id: auth.sessionGeneration) { await refresh() }
        .onDisappear { clearProjection() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } } else { clearProjection() }
        }
        .sheet(item: $editingPlace, onDismiss: { Task {
            await mapViewModel.loadPlaces(force: true)
            await refresh()
        } }) { place in
            RestaurantRatingEditor(place: place, existing: ownRatings.first { $0.place_id == place.id }, api: api)
        }
    }

    private var followControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(text("Friend’s invite link or code", "朋友的邀請連結或代碼"), text: $friendCode)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("friends.invite")
            Button(text("Follow friend", "追蹤朋友")) {
                Task { await perform {
                    try await mapViewModel.followReferral(friendCode)
                } }
            }.frame(minHeight: 44).disabled(working || friendCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder private var friendRatings: some View {
        if ratings.isEmpty && !loading && error == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(text("No shared ratings yet", "還沒有朋友分享評分"))
                    .font(SaveAtlasType.strong(18))
                Text(text("Follow a friend using their invite link or code. Their private ratings stay private.", "用邀請連結或代碼追蹤朋友。未分享的評分仍維持私人。"))
                    .font(SaveAtlasType.body(15))
            }.accessibilityIdentifier("friends.empty")
        }
        ForEach(ratings) { rating in
            VStack(alignment: .leading, spacing: 8) {
                Text(rating.author_name).font(SaveAtlasType.strong(14))
                Text(rating.name).font(SaveAtlasType.strong(20))
                Text(rating.address).font(SaveAtlasType.body(14)).foregroundStyle(SaveAtlasPalette.muted)
                Label(String(format: "%.1f / 5", rating.stars), systemImage: "star.fill")
                    .font(SaveAtlasType.strong(16))
                    .accessibilityLabel(text("\(rating.author_name)’s rating: \(rating.stars) out of 5", "\(rating.author_name)的評分：\(rating.stars)／5 星"))
                Text(text("Self-reported visit · Shared with followers", "本人表示已吃過・分享給追蹤者"))
                    .font(SaveAtlasType.regular(12)).foregroundStyle(SaveAtlasPalette.muted)
                Button(savedIDs.contains(rating.id) ? text("Saved to your map", "已收藏到你的地圖") : text("Save to try", "收藏・想去")) {
                    Task { await save(rating) }
                }
                .font(SaveAtlasType.strong(15)).frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(.white).background(SaveAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 12))
                .disabled(working || savedIDs.contains(rating.id))
                .accessibilityIdentifier("friends.save.\(rating.id)")
            }
            .foregroundStyle(SaveAtlasPalette.ink).padding(16).saveAtlasPaper(radius: 16, shadow: false)
        }
        if nextCursor != nil {
            Button(text("More ratings", "更多評分")) { Task { await loadMore() } }
                .frame(maxWidth: .infinity, minHeight: 44).disabled(loading || working)
        }
    }

    private var restaurants: [Place] {
        mapViewModel.places.filter {
            [.food, .cafe, .bar].contains($0.category)
                && ($0.googlePlaceId?.isEmpty == false || $0.providerPlaceId?.isEmpty == false)
                && ($0.latitude != 0 || $0.longitude != 0)
        }
    }

    @ViewBuilder private var myRatings: some View {
        Text(text("Choose a saved restaurant to rate. Sharing is optional.", "選擇已收藏的餐廳評分，由你決定是否分享。"))
            .font(SaveAtlasType.body(15))
        if restaurants.isEmpty {
            Text(text("Save a confirmed restaurant from Home or Map first.", "先從首頁或地圖收藏一間已確認的餐廳。"))
                .font(SaveAtlasType.body(15))
        }
        ForEach(restaurants) { place in
            Button { editingPlace = place } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(place.name).font(SaveAtlasType.strong(17))
                        if let own = ownRatings.first(where: { $0.place_id == place.id }) {
                            Text(String(format: "%.1f / 5 · ", own.stars) + (own.shared ? text("Shared with followers", "已分享給追蹤者") : text("Private", "私人")))
                                .font(SaveAtlasType.body(13))
                        } else {
                            Text(text("Add your rating", "新增你的評分")).font(SaveAtlasType.body(13))
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }.foregroundStyle(SaveAtlasPalette.ink).padding(16).frame(minHeight: 44)
                    .saveAtlasPaper(radius: 16, shadow: false)
            }.buttonStyle(.plain).accessibilityIdentifier("friends.rate.\(place.id)")
        }
    }

    @MainActor private func clearProjection() {
        generation = UUID()
        ratings = []; ownRatings = []; nextCursor = nil; savedIDs = []
        loading = false; error = nil
    }

    @MainActor private func refresh() async {
        clearProjection()
        let ticket = generation
        let session = auth.sessionGeneration
        loading = true
        defer { if generation == ticket { loading = false } }
        do {
            let page = try await api.fetchFriendRatings()
            let mine = try await api.fetchOwnRestaurantRatings()
            let saved = try await api.fetchSavedFriendRatingIDs()
            guard ticket == generation, session == auth.sessionGeneration, !Task.isCancelled else { return }
            ratings = page.items; nextCursor = page.nextCursor; ownRatings = mine
            savedIDs = saved
            await mapViewModel.refreshFollowedFriends(force: true)
        } catch {
            guard ticket == generation, session == auth.sessionGeneration, !Task.isCancelled else { return }
            self.error = text("Couldn’t load ratings. Check your connection and try again.", "無法載入評分，請確認連線後重試。")
        }
    }

    @MainActor private func loadMore() async {
        guard let cursor = nextCursor, !loading else { return }
        let ticket = generation
        let session = auth.sessionGeneration
        loading = true
        defer { if ticket == generation { loading = false } }
        do {
            let page = try await api.fetchFriendRatings(cursor: cursor)
            let saved = try await api.fetchSavedFriendRatingIDs()
            guard ticket == generation, session == auth.sessionGeneration, !Task.isCancelled else { return }
            // A new page replaces the old projection; previously visible rows
            // may have been withdrawn since their request.
            ratings = page.items
            savedIDs = saved
            nextCursor = page.nextCursor
        } catch {
            // A failed request must not leave potentially revoked ratings visible.
            if ticket == generation { clearProjection(); self.error = text("Couldn’t load ratings. Please refresh.", "無法載入評分，請重新整理。") }
        }
    }

    @MainActor private func perform(_ operation: () async throws -> Void) async {
        guard !working else { return }
        working = true
        let session = auth.sessionGeneration
        defer { working = false }
        do {
            try await operation()
            guard session == auth.sessionGeneration else { return }
            await refresh()
        } catch {
            guard session == auth.sessionGeneration else { return }
            clearProjection()
            self.error = text("Couldn’t finish. Check the invite or refresh and try again.", "無法完成，請確認邀請或重新整理後重試。")
        }
    }

    @MainActor private func save(_ rating: FriendRestaurantRating) async {
        guard !working else { return }
        let session = auth.sessionGeneration
        let ticket = generation
        working = true
        defer { working = false }
        do {
            let place = try await api.saveFriendRestaurant(placeID: rating.id)
            guard ticket == generation, session == auth.sessionGeneration else { return }
            mapViewModel.acceptFriendRestaurantSave(place)
            savedIDs.insert(rating.id)
        } catch {
            guard ticket == generation, session == auth.sessionGeneration else { return }
            clearProjection()
            self.error = text("Couldn’t save. The rating may no longer be shared. Please refresh.", "無法收藏，這則評分可能已停止分享，請重新整理。")
        }
    }

    private func text(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

/// Exercises the production shell against a real, isolated local backend.
/// No fixture credentials or alternate authentication ship in Release builds.
#if DEBUG
struct SaveFriendsLocalFixture: View {
    static var isEnabled: Bool {
#if targetEnvironment(simulator)
        let env = ProcessInfo.processInfo.environment
        return ProcessInfo.processInfo.arguments.contains("--uitest-local-friends")
            && ReviewDemo.isOfflineUITestMode
            && ReviewDemo.uiTestStorageIdentifier != nil
            && env["API_BASE_URL"] == "http://127.0.0.1:55440"
            && ["friends-http-A", "friends-http-B", "friends-http-C"].contains(env["SAVE_FRIENDS_FIXTURE_USER"] ?? "")
            && !(env["SAVE_FRIENDS_FIXTURE_TOKEN"] ?? "").isEmpty
#else
        false
#endif
    }

    private let api: SupabaseService
    @StateObject private var mapVM: MapViewModel

    init() {
        precondition(Self.isEnabled)
        let env = ProcessInfo.processInfo.environment
        let token = env["SAVE_FRIENDS_FIXTURE_TOKEN"]!
        let service = SupabaseService(apiBaseURL: "http://127.0.0.1:55440", accessTokenProvider: { token })
        api = service
        let userID = env["SAVE_FRIENDS_FIXTURE_USER"]!
        if PrivyAuthService.shared.currentUserId != userID {
            PrivyAuthService.shared.authState = .authenticated(userId: userID)
        }
        _mapVM = StateObject(wrappedValue: MapViewModel(
            supabaseService: service,
            pendingImportService: ReviewDemoStorage.pendingImportService,
            saveLocalVaultService: ReviewDemoStorage.localVaultService,
            correctionEventStore: ReviewDemoStorage.correctionEventStore,
            collaborativeListStore: ReviewDemoStorage.collaborativeListStore,
            referralHandoffStore: ReviewDemoStorage.referralHandoffStore,
            relatedPlaceSourcesService: service,
            usesRemotePersistence: true
        ))
    }

    var body: some View {
        ContentView(mapViewModel: mapVM, friendsAPI: api)
            .overlay(alignment: .topTrailing) {
                Text("LOCAL TEST · \(ProcessInfo.processInfo.environment["SAVE_FRIENDS_FIXTURE_USER"] ?? "")")
                    .font(.system(size: 9)).fixedSize().padding(3)
                    .background(Color.yellow, ignoresSafeAreaEdges: [])
                    .padding(.trailing, 8)
            }
    }
}
#endif

private struct RestaurantRatingEditor: View {
    let place: Place
    let existing: OwnRestaurantRating?
    let api: SupabaseService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var language
    @ObservedObject private var auth = PrivyAuthService.shared
    @State private var stars = 0.0
    @State private var eaten = false
    @State private var shared = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(place.name).font(SaveAtlasType.strong(20))
                    Picker(text("Your stars", "你的星等"), selection: $stars) {
                        Text(text("Choose a rating", "選擇評分")).tag(0.0)
                        ForEach(2...10, id: \.self) { value in
                            Text(String(format: "%.1f / 5", Double(value) / 2)).tag(Double(value) / 2)
                        }
                    }.accessibilityIdentifier("friends.editor.stars")
                    Toggle(text("I have eaten here", "我已在這裡用餐"), isOn: $eaten)
                        .accessibilityIdentifier("friends.editor.eaten")
                    Text(text("Your own experience; no verified-visit badge.", "記錄你自己的體驗，不代表經驗證的到訪。"))
                        .font(SaveAtlasType.regular(13))
                    Toggle(text("Share with followers", "分享給追蹤者"), isOn: $shared)
                        .accessibilityIdentifier("friends.editor.shared")
                    Text(text("Anyone who follows you can see your name, restaurant and stars, including future followers. Notes and photos stay private.", "所有追蹤你的人（包含日後追蹤者）都能看到你的名稱、餐廳與星等。筆記和照片維持私人。"))
                        .font(SaveAtlasType.regular(13))
                }
                Section {
                    Button(text("Save rating", "儲存評分")) { Task { await submit(withdraw: false) } }
                        .disabled(working || !eaten || stars == 0).frame(minHeight: 44)
                    if existing?.shared == true {
                        Button(text("Withdraw share", "停止分享")) { Task { await submit(withdraw: true) } }
                            .disabled(working).frame(minHeight: 44)
                    }
                    if working { ProgressView() }
                    if let error { Text(error) }
                }
            }
            .scrollContentBackground(.hidden).background(SaveAtlasPalette.canvas)
            .foregroundStyle(SaveAtlasPalette.ink).tint(SaveAtlasPalette.forest)
            .navigationTitle(text("Your restaurant rating", "你的餐廳評分"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Close", "關閉")) { dismiss() } } }
            .onAppear {
                stars = existing?.stars ?? 0
                eaten = place.status == .visited
                shared = existing?.shared ?? false
            }
            .onChange(of: auth.sessionGeneration) { _, _ in dismiss() }
            .interactiveDismissDisabled(working)
        }
    }

    @MainActor private func submit(withdraw: Bool) async {
        working = true
        defer { working = false }
        let session = auth.sessionGeneration
        do {
            if withdraw {
                try await api.withdrawRestaurantRating(placeID: place.id)
            } else {
                try await api.putRestaurantRating(placeID: place.id, stars: stars, eaten: eaten, shared: shared)
            }
            guard session == auth.sessionGeneration else { return }
            dismiss()
        } catch {
            guard session == auth.sessionGeneration else { return }
            self.error = text("Couldn’t save. Confirm this is a saved restaurant and try again.", "無法儲存，請確認這是已收藏的餐廳後重試。")
        }
    }

    private func text(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}
