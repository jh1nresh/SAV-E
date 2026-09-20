import SwiftUI
import PhotosUI
import ImageIO

struct SharedPostArtwork: View {
    let post: SharedPlacePost
    var compact = false
    var body: some View {
        ZStack {
            (post.status == .visited ? SaveAtlasPalette.mint : SaveAtlasPalette.kraft).opacity(0.65)
            VStack(spacing: compact ? 8 : 18) {
                Image(systemName: post.icon)
                    .font(.system(size: compact ? 26 : 48, weight: .light))
                if !compact {
                    Text(post.address).font(SaveAtlasType.body(13)).lineLimit(2)
                }
            }
            .foregroundStyle(SaveAtlasPalette.forest)
            .padding(12)
            if let count = post.photo_count, count > 0 {
                if compact || count == 1 {
                    SharedPostPhoto(post: post, index: 0)
                } else {
                    TabView {
                        ForEach(0..<min(count, SharedPostDraft.maxPhotos), id: \.self) { index in
                            SharedPostPhoto(post: post, index: index)
                        }
                    }
                    .tabViewStyle(.page)
                }
            }
        }
        .clipped()
    }
}


/// Authenticated, memory-only media. Revalidate after returning to the app;
/// never pass follower photos to the app's public/disk image cache.
private struct SharedPostPhoto: View {
    let post: SharedPlacePost
    let index: Int
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SaveAtlasPalette.paper
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                        .accessibilityLabel(language.localized(english: "Photo \(index + 1)", traditionalChinese: "照片 \(index + 1)"))
                } else if failed {
                    Button { retry += 1 } label: {
                        Label(language.localized(english: "Retry photo", traditionalChinese: "重試載入照片"), systemImage: "arrow.clockwise")
                            .font(SaveAtlasType.body(12)).frame(minHeight: 44)
                    }
                } else { ProgressView() }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .task(id: "\(post.id)-\(post.photo_version ?? "")-\(index)-\(retry)-\(scenePhase)") {
            image = nil; failed = false
            guard scenePhase == .active else { return }
            do {
                let data = try await SupabaseService.shared.fetchSharedPostPhoto(id: post.id, index: index)
                try Task.checkCancellation()
                guard let decoded = UIImage(data: data) else { throw SupabaseError.invalidResponse("Invalid photo") }
                image = decoded
            } catch is CancellationError { }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}

/// Downsample before decoding; encode pixels only, without source EXIF/GPS.
enum SharedPostPhotoEncoder {
    nonisolated static func jpeg(from data: Data) throws -> Data {
        guard data.count <= 50 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200
              ] as CFDictionary) else { throw PhotoError.unreadable }
        for quality in [0.8, 0.6, 0.4, 0.25] {
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result as CFMutableData, "public.jpeg" as CFString, 1, nil) else { throw PhotoError.unreadable }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), result.length <= 262_144 { return result as Data }
        }
        throw PhotoError.tooLarge
    }
    enum PhotoError: Error { case unreadable, tooLarge }
}

struct SharedPostStatus: View {
    let status: PlaceStatus
    @Environment(\.appLanguageSettings) private var language
    var body: some View {
        Label(status == .visited ? language.localized(english: "Visited", traditionalChinese: "去過") : language.localized(english: "Want to go", traditionalChinese: "想去"),
              systemImage: status == .visited ? "checkmark.seal" : "bookmark")
            .font(SaveAtlasType.strong(11))
            .foregroundStyle(SaveAtlasPalette.forest)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(SaveAtlasPalette.paper.opacity(0.95), in: Capsule())
    }
}

struct SharedPostsGrid: View {
    @ObservedObject var store: SharedPostsStore
    let onSelect: (SharedPlacePost) -> Void
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        VStack(spacing: 16) {
            Picker(language.localized(english: "Posts", traditionalChinese: "分享貼文"), selection: $store.filter) {
                ForEach(SharedPostFilter.allCases) { filter in Text(filter.title(language.language)).tag(filter) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("posts.filter")

            if store.isLoading && store.posts.isEmpty { ProgressView().padding() }
            if store.error != nil {
                SocialLoadError()
            } else if !store.isLoading && store.posts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3").font(.system(size: 30, weight: .light))
                    Text(language.localized(english: "No shared posts yet", traditionalChinese: "還沒有分享貼文"))
                        .font(SaveAtlasType.strong(16))
                    Text(language.localized(english: "Your saved places stay private until you choose to share.", traditionalChinese: "收藏先留給自己，想分享時再發佈。"))
                        .font(SaveAtlasType.body(13)).multilineTextAlignment(.center)
                }
                .foregroundStyle(SaveAtlasPalette.muted)
                .padding(.vertical, 28)
                .accessibilityIdentifier("posts.empty")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5, alignment: .top), count: textSize.isAccessibilitySize ? 2 : 3), spacing: 14) {
                ForEach(store.posts) { post in
                    Button { onSelect(post) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            SharedPostArtwork(post: post, compact: true)
                                .aspectRatio(0.82, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                .overlay(alignment: .bottomLeading) { SharedPostStatus(status: post.status).padding(5) }
                            Text(post.name)
                                .font(SaveAtlasType.strong(12)).foregroundStyle(SaveAtlasPalette.ink)
                                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            if !post.visible_to_followers {
                                Text(language.localized(english: "Sharing paused", traditionalChinese: "分享已暫停"))
                                    .font(SaveAtlasType.body(10)).foregroundStyle(SaveAtlasPalette.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("posts.item.\(post.id.uuidString)")
                }
            }
            if store.nextCursor != nil {
                Button(language.localized(english: "Load more", traditionalChinese: "載入更多")) {
                    Task { await store.loadMore() }
                }.disabled(store.isLoading).frame(minHeight: 44)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.posts")
    }
}

struct SocialLoadError: View {
    @Environment(\.appLanguageSettings) private var language
    var body: some View {
        Label(language.localized(english: "Couldn’t load sharing. Pull down to try again.", traditionalChinese: "暫時無法載入分享，下拉可重試。"), systemImage: "wifi.exclamationmark")
            .font(SaveAtlasType.body(13)).foregroundStyle(SaveAtlasPalette.muted)
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("posts.error")
    }
}

struct SharedPostDetail: View {
    let initialPost: SharedPlacePost
    @ObservedObject var store: SharedPostsStore
    var isOwner = false
    var onSaved: () async -> Void = {}
    @State private var post: SharedPlacePost?
    @State private var error: String?
    @State private var busy = false
    @State private var saved = false
    @State private var showEdit = false
    @State private var showWithdraw = false
    @State private var showAuthor = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let post {
                        Button { showAuthor = true } label: {
                            Label(post.author_name, systemImage: "person.crop.circle")
                                .font(SaveAtlasType.strong(16))
                        }.disabled(isOwner || store.isDemo)
                        SharedPostArtwork(post: post).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 20))
                        SharedPostStatus(status: post.status)
                        Text(post.name).font(SaveAtlasType.display(26))
                        Text(post.address).font(SaveAtlasType.body(14)).foregroundStyle(SaveAtlasPalette.muted)
                        if let stars = post.stars {
                            Label(String(format: "%.1f", stars), systemImage: "star.fill").font(SaveAtlasType.strong(16))
                        }
                        if let caption = post.caption, !caption.isEmpty {
                            Text(caption).font(SaveAtlasType.body(16)).textSelection(.enabled)
                        }
                        Text(post.visible_to_followers
                            ? language.localized(english: "Visible to people who follow the author", traditionalChinese: "追蹤作者的人可見")
                            : language.localized(english: "Sharing paused — only you can view this post", traditionalChinese: "分享已暫停，目前只有你能查看"))
                            .font(SaveAtlasType.body(12)).foregroundStyle(SaveAtlasPalette.muted)
                            .accessibilityIdentifier("posts.audience")
                        if isOwner {
                            Button(language.localized(english: "Edit post", traditionalChinese: "編輯貼文")) { showEdit = true }
                                .buttonStyle(.borderedProminent).tint(SaveAtlasPalette.forest)
                                .disabled(store.isDemo || busy).accessibilityIdentifier("posts.edit")
                            Button(language.localized(english: "Withdraw post", traditionalChinese: "撤回分享"), role: .destructive) { showWithdraw = true }
                                .disabled(store.isDemo || busy).accessibilityIdentifier("posts.withdraw")
                        } else {
                            Button {
                                busy = true
                                Task {
                                    do { try await store.save(id: post.id); saved = true; await onSaved() }
                                    catch { self.error = language.localized(english: "Couldn’t save this post. It may no longer be shared.", traditionalChinese: "無法收藏，這篇分享可能已撤回。") }
                                    busy = false
                                }
                            } label: {
                                Label(saved ? language.localized(english: "Saved to your places", traditionalChinese: "已加入你的收藏") : language.localized(english: "Save to my places", traditionalChinese: "加入我的收藏"), systemImage: saved ? "checkmark" : "bookmark")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent).tint(SaveAtlasPalette.forest)
                            .disabled(busy || saved || store.isDemo).accessibilityIdentifier("posts.save")
                        }
                        if store.isDemo {
                            Text(language.localized(english: "Sample preview — sharing requires your own account.", traditionalChinese: "範例預覽；使用自己的帳號即可分享。"))
                                .font(SaveAtlasType.body(12))
                        }
                    } else if error == nil { ProgressView().frame(maxWidth: .infinity).padding(60) }
                    if let error { Text(error).font(SaveAtlasType.body(14)).foregroundStyle(SaveAtlasPalette.muted) }
                }.padding(20)
            }
            .background(SaveAtlasPalette.canvas)
            .foregroundStyle(SaveAtlasPalette.ink)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.localized(english: "Done", traditionalChinese: "完成")) { dismiss() } }
            }
            .task { await revalidate() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await revalidate() } } }
            .sheet(isPresented: $showEdit) {
                if let post {
                    SharedPostComposer(id: post.id, name: post.name, status: post.status, existing: post, store: store) { dismiss() }
                }
            }
            .sheet(isPresented: $showAuthor) {
                SharedAuthorPassport(authorID: initialPost.author_id, onSaved: onSaved)
            }
            .confirmationDialog(language.localized(english: "Withdraw this post?", traditionalChinese: "撤回這篇分享？"), isPresented: $showWithdraw, titleVisibility: .visible) {
                Button(language.localized(english: "Withdraw post", traditionalChinese: "撤回分享"), role: .destructive) {
                    busy = true
                    Task {
                        do { try await store.withdraw(id: initialPost.id); dismiss() }
                        catch { self.error = language.localized(english: "Couldn’t withdraw. Please try again.", traditionalChinese: "撤回失敗，請重試。") }
                        busy = false
                    }
                }
            } message: {
                Text(language.localized(english: "Your saved place stays. Separately shared public links keep their own visibility.", traditionalChinese: "你的收藏會保留；另外發佈的公開連結仍依原本設定顯示。"))
            }
        }
        .accessibilityIdentifier("posts.detail")
    }

    private func revalidate() async {
        post = nil; error = nil
        do { post = try await store.detail(initialPost) }
        catch { self.error = language.localized(english: "This post is unavailable or no longer shared with you.", traditionalChinese: "這篇貼文目前無法查看，或已停止向你分享。") }
    }
}

struct SharedPostComposer: View {
    let id: UUID
    let name: String
    let status: PlaceStatus
    var existing: SharedPlacePost?
    @ObservedObject var store: SharedPostsStore
    let onPublished: () -> Void
    @State private var draft = SharedPostDraft(status: .wantToGo, stars: nil, caption: "")
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var loadingPhotos = false
    @State private var preparedAccount: String?
    @State private var photoError: String?
    @State private var isReady = false
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(name).font(SaveAtlasType.strong(21))
                    Picker(language.localized(english: "Share as", traditionalChinese: "分享狀態"), selection: $draft.status) {
                        Text(language.localized(english: "Want to go", traditionalChinese: "想去")).tag(PlaceStatus.wantToGo)
                        Text(language.localized(english: "Visited", traditionalChinese: "去過")).tag(PlaceStatus.visited)
                    }.pickerStyle(.segmented)
                    .onChange(of: draft.status) { _, value in if value == .wantToGo { draft.stars = nil } }
                } footer: {
                    Text(language.localized(english: "This post doesn’t change the status of your private saved place.", traditionalChinese: "貼文狀態不會更改私人收藏中的紀錄。"))
                }
                photoSection
                Section(language.localized(english: "Caption · optional", traditionalChinese: "想說的話 · 選填")) {
                    TextEditor(text: $draft.caption).frame(minHeight: 100).accessibilityIdentifier("posts.caption")
                    Text("\(draft.caption.unicodeScalars.count) / 500").font(.caption).foregroundStyle(draft.isValid ? SaveAtlasPalette.muted : .red)
                }
                if draft.status == .visited {
                    Section(language.localized(english: "Rating · optional", traditionalChinese: "評分 · 選填")) {
                        Picker(language.localized(english: "Rating", traditionalChinese: "評分"), selection: $draft.stars) {
                            Text(language.localized(english: "No rating", traditionalChinese: "不評分")).tag(nil as Double?)
                            ForEach(ratingOptions, id: \.self) { value in
                                Text(String(format: "%.1f ★", value)).tag(Optional(value))
                            }
                        }
                    }
                }
                Section {
                    Label(language.localized(english: "Visible to people who follow you", traditionalChinese: "追蹤你的人可見"), systemImage: "person.2")
                    Text(language.localized(english: "Private notes, imported reviews and source links stay private.", traditionalChinese: "私人筆記、匯入評價與來源連結不會附在貼文中。"))
                        .font(.footnote).foregroundStyle(SaveAtlasPalette.muted)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .disabled(busy || loadingPhotos || !isReady)
            .scrollContentBackground(.hidden).background(SaveAtlasPalette.canvas)
            .navigationTitle(language.localized(english: "Share a place", traditionalChinese: "分享地點"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(language.localized(english: "Cancel", traditionalChinese: "取消")) { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.localized(english: "Publish", traditionalChinese: "發佈")) {
                        busy = true; error = nil
                        Task {
                            do {
                                guard preparedAccount == PrivyAuthService.shared.currentUserId else { throw CancellationError() }
                                try await store.publish(id: id, draft: draft); dismiss(); onPublished()
                            }
                            catch { self.error = language.localized(english: "Couldn’t publish. Your draft is still here; please try again.", traditionalChinese: "發佈失敗，草稿仍在，請重試。") }
                            busy = false
                        }
                    }.disabled(!isReady || !draft.isValid || busy || loadingPhotos || !selectedPhotos.isEmpty || store.isDemo).accessibilityIdentifier("posts.publish")
                }
            }
            .overlay { if !isReady && error == nil { ProgressView() } }
            .task { await prepare() }
            .task(id: selectedPhotos) { await loadSelectedPhotos() }
            .interactiveDismissDisabled(busy)
        }
    }

    private var photoSection: some View {
        Section {
            if !(draft.photos ?? []).isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array((draft.photos ?? []).enumerated()), id: \.offset) { index, data in
                            VStack(spacing: 4) {
                                if let image = UIImage(data: data) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(width: 100, height: 100).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .accessibilityLabel(language.localized(english: "Selected photo \(index + 1)", traditionalChinese: "已選照片 \(index + 1)"))
                                }
                                Button(role: .destructive) { draft.photos?.remove(at: index) } label: {
                                    Text(language.localized(english: "Remove", traditionalChinese: "移除"))
                                        .font(SaveAtlasType.body(13)).frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(language.localized(english: "Remove photo \(index + 1)", traditionalChinese: "移除照片 \(index + 1)"))
                                .accessibilityIdentifier("posts.photo.remove.\(index)")
                            }
                        }
                    }
                }
            }
            if (draft.photos?.count ?? 0) < SharedPostDraft.maxPhotos {
                PhotosPicker(selection: $selectedPhotos,
                             maxSelectionCount: SharedPostDraft.maxPhotos - (draft.photos?.count ?? 0),
                             matching: .images) {
                    Label(language.localized(english: "Add photos", traditionalChinese: "新增照片"), systemImage: "photo.badge.plus")
                        .foregroundStyle(SaveAtlasPalette.forest).frame(minHeight: 44)
                }
                .accessibilityIdentifier("posts.photos.add")
            }
            if loadingPhotos { ProgressView(language.localized(english: "Preparing photos…", traditionalChinese: "正在準備照片…")) }
            if let photoError { Text(photoError).font(SaveAtlasType.body(13)).foregroundStyle(.red) }
        } header: {
            Text(language.localized(english: "Photos · up to 3", traditionalChinese: "照片 · 最多 3 張"))
        } footer: {
            Text(language.localized(english: "Only the photos you choose here are shared when you publish.", traditionalChinese: "只有在這裡選取的照片，會在發佈後分享給追蹤你的人。"))
        }
    }

    private func loadSelectedPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        loadingPhotos = true; photoError = nil
        defer { loadingPhotos = false; selectedPhotos = [] }
        do {
            var additions: [Data] = []
            for item in selectedPhotos {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw SharedPostPhotoEncoder.PhotoError.unreadable }
                let jpeg = try await Task.detached(priority: .userInitiated) { try SharedPostPhotoEncoder.jpeg(from: data) }.value
                try Task.checkCancellation()
                additions.append(jpeg)
            }
            draft.photos = Array(((draft.photos ?? []) + additions).prefix(SharedPostDraft.maxPhotos))
        } catch is CancellationError { }
        catch {
            photoError = language.localized(english: "Couldn’t prepare these photos. Try choosing them again or use a smaller image.", traditionalChinese: "無法準備這些照片，請重新選取或改用較小的圖片。")
        }
    }

    private var ratingOptions: [Double] {
        // Older explicit shares may carry half-stars or another valid fraction.
        // Always include the current value so opening the editor cannot lose it.
        Array(Set((2...10).map { Double($0) / 2 } + (draft.stars.map { [$0] } ?? []))).sorted()
    }

    private func prepare() async {
        guard !isReady else { return }
        preparedAccount = PrivyAuthService.shared.currentUserId
        draft = SharedPostDraft(status: status, stars: nil, caption: "", photos: [])
        if let existing {
            do { try await restore(existing) }
            catch {
                self.error = language.localized(english: "Couldn’t load the existing photos. Close and try again.", traditionalChinese: "無法載入原有照片，請關閉後重試。")
                return
            }
        } else if !store.isDemo {
            // A place may already have a post outside the first loaded page.
            // Load that explicit content before editing; never overwrite it blind.
            do {
                let post = try await SupabaseService.shared.fetchSharedPost(id: id)
                guard !Task.isCancelled else { return }
                try await restore(post)
            } catch SupabaseError.apiError(404, _) {
                // No active post is a valid new-share state.
            } catch {
                self.error = language.localized(english: "Couldn’t check existing sharing. Close and try again.", traditionalChinese: "無法確認原有分享，請關閉後重試。")
                return
            }
        }
        guard !Task.isCancelled, preparedAccount == PrivyAuthService.shared.currentUserId else { return }
        isReady = true
    }

    private func restore(_ post: SharedPlacePost) async throws {
        var photos: [Data] = []
        for index in 0..<min(max(post.photo_count ?? 0, 0), SharedPostDraft.maxPhotos) {
            photos.append(try await SupabaseService.shared.fetchSharedPostPhoto(id: post.id, index: index))
        }
        try Task.checkCancellation()
        draft = SharedPostDraft(status: post.status, stars: post.stars, caption: post.caption ?? "", photos: photos)
    }
}

struct SharedPlacePicker: View {
    let places: [Place]
    @ObservedObject var store: SharedPostsStore
    @State private var query = ""
    @State private var selected: Place?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var language
    var body: some View {
        NavigationStack {
            List {
                if places.isEmpty {
                    Text(language.localized(english: "Save and confirm a place first, then share it here.", traditionalChinese: "先收藏並確認一個地點，就能在這裡分享。"))
                }
                ForEach(places.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { place in
                    Button { selected = place } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name).foregroundStyle(SaveAtlasPalette.ink)
                            Text(place.address).font(.caption).foregroundStyle(SaveAtlasPalette.muted)
                        }.padding(.vertical, 5)
                    }
                }
            }
            .searchable(text: $query, prompt: language.localized(english: "Find a saved place", traditionalChinese: "搜尋收藏地點"))
            .scrollContentBackground(.hidden).background(SaveAtlasPalette.canvas)
            .navigationTitle(language.localized(english: "Choose a place", traditionalChinese: "選一個地點"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(language.localized(english: "Cancel", traditionalChinese: "取消")) { dismiss() } } }
            .sheet(item: $selected) { place in
                SharedPostComposer(id: place.id, name: place.name, status: place.status, store: store) { dismiss() }
            }
        }
    }
}

struct SharedAuthorPassport: View {
    let authorID: String
    var onSaved: () async -> Void = {}
    @StateObject private var store = SharedPostsStore()
    @State private var selected: SharedPlacePost?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appLanguageSettings) private var language
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let profile = store.profile {
                        Label(profile.displayName, systemImage: "person.crop.circle").font(SaveAtlasType.display(26))
                        if let handle = profile.handle { Text("@\(handle)").font(SaveAtlasType.body(14)).foregroundStyle(SaveAtlasPalette.muted) }
                        Text(language.localized(english: "\(profile.postCount) shared posts", traditionalChinese: "\(profile.postCount) 篇分享"))
                    }
                    SharedPostsGrid(store: store) { selected = $0 }
                }.padding(20)
            }
            .background(SaveAtlasPalette.canvas).foregroundStyle(SaveAtlasPalette.forest)
            .navigationTitle(language.localized(english: "Passport", traditionalChinese: "護照"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(language.localized(english: "Done", traditionalChinese: "完成")) { dismiss() } } }
            .task(id: store.filter) { await store.refresh(.author(authorID)) }
            .refreshable { await store.refresh(.author(authorID)) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh(.author(authorID)) } } }
            .sheet(item: $selected) { SharedPostDetail(initialPost: $0, store: store, onSaved: onSaved) }
        }
    }
}

struct PassportFollowersView: View {
    @State private var people: [SaveFollowedFriend] = []
    @State private var cursor: String?
    @State private var busy = false
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var language
    var body: some View {
        NavigationStack {
            List {
                if failed { SocialLoadError() }
                if !busy && !failed && people.isEmpty { Text(language.localized(english: "No followers yet", traditionalChinese: "還沒有粉絲")) }
                ForEach(people) { person in
                    VStack(alignment: .leading) {
                        Text(person.displayName)
                        if let handle = person.handleLabel { Text(handle).font(.caption).foregroundStyle(SaveAtlasPalette.muted) }
                    }
                }
                if busy { ProgressView() }
                if cursor != nil { Button(language.localized(english: "Load more", traditionalChinese: "載入更多")) { Task { await load(more: true) } }.disabled(busy) }
            }
            .navigationTitle(language.localized(english: "Followers", traditionalChinese: "粉絲"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(language.localized(english: "Done", traditionalChinese: "完成")) { dismiss() } } }
            .task { await load(more: false) }
            .refreshable { await load(more: false) }
        }
    }
    private func load(more: Bool) async {
        guard !PrivyAuthService.shared.isReviewerDemo else { return }
        let account = PrivyAuthService.shared.currentUserId
        busy = true; failed = false
        if !more { people = []; cursor = nil }
        defer { busy = false }
        do {
            let page = try await SupabaseService.shared.fetchFollowers(cursor: more ? cursor : nil)
            guard account == PrivyAuthService.shared.currentUserId, !Task.isCancelled else { return }
            let ids = Set(people.map(\.id))
            people += page.items.filter { !ids.contains($0.id) }; cursor = page.nextCursor
        } catch { failed = true }
    }
}
