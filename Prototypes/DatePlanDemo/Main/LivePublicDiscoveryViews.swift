#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import ImageIO
import MapKit
import SwiftUI

@MainActor
struct LivePublicDiscoverySummary: View {
    @ObservedObject var model: LivePublicDiscoveryModel
    let onRetry: () -> Void
    let onMore: () -> Void
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(copy("Explore posts", "探索公開貼文"), systemImage: "sparkle.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if model.isLoading || model.isLoadingMore { ProgressView() }
            }
            if model.unavailable {
                Text(copy("Public posts aren’t available right now. Your saved places are in Mine.",
                          "公開貼文暫時無法載入。你的收藏仍可在「我的」查看。"))
                    .font(.caption).foregroundStyle(DateTheme.muted)
                Button(copy("Try again", "重新載入"), action: onRetry).frame(minHeight: 44)
            } else if let page = model.page {
                Text(page.posts.isEmpty
                     ? copy("No indexed posts in this area. Try another area.", "這個範圍還沒有已收錄的貼文，試試其他區域。")
                     : copy("\(page.posts.count) posts · \(page.venues.count) places", "\(page.posts.count) 篇貼文 · \(page.venues.count) 個地點"))
                    .font(.caption).foregroundStyle(DateTheme.muted)
                let connected = page.coverage.filter { $0.status == "connected" }.map { Self.platformName($0.platform) }
                Text(connected.isEmpty ? copy("No platforms connected", "尚未接通平台")
                     : copy("Indexed sources: ", "已收錄來源：") + connected.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(DateTheme.muted)
                if page.nextCursor != nil {
                    Button(copy("Show more posts", "顯示更多貼文"), action: onMore)
                        .disabled(model.isLoadingMore).frame(minHeight: 44)
                }
            } else {
                Text(copy("Finding public posts in this area…", "正在找這個範圍的公開貼文…"))
                    .font(.caption).foregroundStyle(DateTheme.muted)
            }
        }.accessibilityIdentifier("live.discovery.summary")
    }

    static func platformName(_ platform: String) -> String {
        switch platform { case "instagram": "Instagram"; case "threads": "Threads"; case "xiaohongshu": "小紅書"; default: platform }
    }
    private func copy(_ english: String, _ chinese: String) -> String { language.localized(english: english, traditionalChinese: chinese) }
}

@MainActor
struct LivePublicDiscoveryDetail: View {
    let venue: LivePublicDiscoveryVenue
    let ownerSubject: String
    let sessionGeneration: Int
    let alreadySaved: Bool
    let isSaving: Bool
    let saveError: String?
    let onSave: () -> Void
    let onDirections: () -> Void
    let onClose: () -> Void
    var discoveryExpiresAt: Date? = nil
    var onGuideDestination: ((LivePublicGuideDestination) -> Void)? = nil
    @State private var guidePresented = false
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(copy("Public posts", "公開貼文"), systemImage: "globe.asia.australia")
                            .font(.caption.weight(.semibold)).foregroundStyle(DateTheme.blue)
                        Text(venue.place.name).font(.title2.weight(.bold))
                        Text(venue.place.address).font(.subheadline).foregroundStyle(DateTheme.muted)
                        Text(copy("Check the place before saving. Posts are their authors’ views.",
                                  "收藏前請確認地點；貼文內容代表原作者的分享。"))
                            .font(.caption).foregroundStyle(DateTheme.muted)
                    }
                    HStack(spacing: 12) {
                        Button(action: onSave) {
                            Label(alreadySaved ? copy("Saved", "已收藏") : copy("Confirm & save", "確認地點並收藏"),
                                  systemImage: alreadySaved ? "bookmark.fill" : "bookmark")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.plain).foregroundStyle(DateTheme.actionInk)
                            .background(DateTheme.action, in: Capsule()).disabled(alreadySaved || isSaving)
                        Button(action: onDirections) {
                            Image(systemName: "arrow.turn.up.right").frame(width: 48, height: 48)
                        }.buttonStyle(.plain).background(DateTheme.soft, in: Circle())
                            .accessibilityLabel(copy("Walking directions", "步行導航"))
                    }
                    if onGuideDestination != nil, discoveryExpiresAt != nil {
                        Button { guidePresented = true } label: {
                            Label(copy("Plan with friends", "和朋友一起安排"), systemImage: "person.2")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.plain).background(DateTheme.soft, in: Capsule())
                            .disabled(isSaving).accessibilityIdentifier("live.discovery.guide")
                    }
                    if isSaving { ProgressView(copy("Saving…", "正在收藏…")) }
                    if let saveError { Text(saveError).font(.caption).foregroundStyle(DateTheme.ink) }
                    ForEach(venue.posts) { post in
                        VStack(alignment: .leading, spacing: 12) {
                            if post.cover != nil {
                                LivePublicPostCover(post: post, ownerSubject: ownerSubject, sessionGeneration: sessionGeneration)
                                    .frame(height: 190).clipped().clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(post.authorName ?? post.authorHandle ?? copy("Author unavailable", "作者資料暫缺"))
                                        .font(.subheadline.weight(.semibold))
                                    Text(LivePublicDiscoverySummary.platformName(post.platform))
                                        .font(.caption).foregroundStyle(DateTheme.muted)
                                }
                                Spacer()
                                if let date = post.publishedAt.flatMap(LivePublicPostCover.date) {
                                    Text(date, style: .date).font(.caption2).foregroundStyle(DateTheme.muted)
                                }
                            }
                            if !post.title.isEmpty { Text(post.title).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
                            if let url = URL(string: post.sourceURL) {
                                Link(destination: url) {
                                    Label(copy("Read original post", "查看原始貼文"), systemImage: "arrow.up.right")
                                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                                }.tint(DateTheme.blue)
                            }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                    }
                }.padding(20)
            }.background(DateTheme.canvas).foregroundStyle(DateTheme.ink)
                .navigationTitle(copy("\(venue.posts.count) posts", "\(venue.posts.count) 篇貼文"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(copy("Close", "關閉"), action: onClose) } }
        }.accessibilityIdentifier("live.discovery.detail")
            .sheet(isPresented: $guidePresented) {
                if let expiry = discoveryExpiresAt {
                    LivePublicGuideChooser(venue: venue, expiresAt: expiry, ownerSubject: ownerSubject,
                        sessionGeneration: sessionGeneration, onDestination: { target in
                            guidePresented = false; onGuideDestination?(target)
                        }, onClose: { guidePresented = false })
                        .presentationDetents([.large]).presentationBackground(DateTheme.canvas)
                }
            }
    }
    private func copy(_ english: String, _ chinese: String) -> String { language.localized(english: english, traditionalChinese: chinese) }
}

@MainActor
struct LivePublicPostCover: View {
    let post: LivePublicDiscoveryPost
    let ownerSubject: String
    let sessionGeneration: Int
    @State private var image: UIImage?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else {
                Image(systemName: "photo").font(.title2).foregroundStyle(DateTheme.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(DateTheme.soft)
            }
        }
        .accessibilityLabel(language.localized(english: "Original post preview", traditionalChinese: "原始貼文預覽"))
        .task(id: "\(post.id):\(post.cover?.url ?? ""):\(scenePhase == .active)") {
            image = nil
            guard scenePhase == .active, currentSession, let cover = post.cover,
                  let url = cover.previewURL(at: Date(), platform: post.platform),
                  let expires = Self.date(cover.expiresAt), expires > Date() else { return }
            do {
                let data = try await PublicPostImageRead.data(url)
                guard !Task.isCancelled, scenePhase == .active, currentSession, expires > Date(),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 800,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else { return }
                image = UIImage(cgImage: thumbnail)
            } catch { image = nil }
        }
        .onDisappear { image = nil }
    }
    private var currentSession: Bool {
        let auth = PrivyAuthService.shared
        guard case .authenticated(let owner) = auth.authState else { return false }
        return owner == ownerSubject && auth.sessionGeneration == sessionGeneration
    }
    static func date(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private final class PublicPostImageRead: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated static func data(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8; configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.httpShouldHandleCookies = false
        let (bytes, response) = try await session.bytes(for: request, delegate: PublicPostImageRead())
        let maximum = 2 * 1_024 * 1_024
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType?.hasPrefix("image/") == true,
              response.expectedContentLength <= maximum else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximum else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
#endif
