#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import MapKit
import SwiftUI
import UIKit

/// Presentation only. The owner supplies canonical save, directions and outing
/// actions; opening this view never saves a candidate or records a visit.
@MainActor
struct LivePlaceDetail: View {
    let pin: LiveMapPlace
    let isSaving: Bool
    let saveError: String?
    let ownerSubject: String?
    let sessionGeneration: Int?
    let onSave: (() -> Void)?
    let onOpenSaved: (() -> Void)?
    let onShowPocketCity: (() -> Void)?
    let onDirections: () -> Void
    let onAddToOuting: (() -> Void)?
    let canAddToOuting: Bool
    let onClose: () -> Void
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var information: LivePlaceInformationModel
    @StateObject private var websitePhoto: LiveBusinessWebsitePhotoModel
    @State private var nativeCardPresented = false
    @State private var reloadGeneration = 0

    init(pin: LiveMapPlace, isSaving: Bool, saveError: String?,
         ownerSubject: String? = nil, sessionGeneration: Int? = nil,
         informationModel: LivePlaceInformationModel? = nil, websitePhotoModel: LiveBusinessWebsitePhotoModel? = nil,
         onSave: (() -> Void)?, onOpenSaved: (() -> Void)?,
         onShowPocketCity: (() -> Void)? = nil, onDirections: @escaping () -> Void, onAddToOuting: (() -> Void)?,
         canAddToOuting: Bool, onClose: @escaping () -> Void) {
        self.pin = pin
        self.isSaving = isSaving
        self.saveError = saveError
        self.ownerSubject = ownerSubject
        self.sessionGeneration = sessionGeneration
        _information = StateObject(wrappedValue: informationModel ?? LivePlaceInformationModel())
        _websitePhoto = StateObject(wrappedValue: websitePhotoModel ?? LiveBusinessWebsitePhotoModel())
        self.onSave = onSave
        self.onOpenSaved = onOpenSaved
        self.onShowPocketCity = onShowPocketCity
        self.onDirections = onDirections
        self.onAddToOuting = onAddToOuting
        self.canAddToOuting = canAddToOuting
        self.onClose = onClose
    }

    var body: some View {
        fallbackCard
            .task(id: "\(pin.id):\(reloadGeneration)") { await loadInformation() }
            .onDisappear { information.cancel(); websitePhoto.cancel() }
            .sheet(isPresented: $nativeCardPresented) {
                if #available(iOS 18.0, *), let item = information.item {
                    LiveNativePlaceCard(item: item, onClose: { nativeCardPresented = false })
                        .presentationDetents([.large])
                }
            }
    }

    private func loadInformation() async {
        guard let ownerSubject, let sessionGeneration else { return }
        websitePhoto.cancel()
        await information.load(pin: pin, ownerSubject: ownerSubject, sessionGeneration: sessionGeneration)
        guard !Task.isCancelled else { return }
        if LiveBusinessPhotoSource.resolve(pin.place).hasPhoto { return }
        await websitePhoto.load(website: information.item?.url, ownerSubject: ownerSubject, generation: sessionGeneration)
    }

    private var fallbackCard: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    businessPhotos
                    identity
                    if pin.origin == .saved, let ownerSubject, let sessionGeneration {
                        LiveSavedVenuePostsEntry(place: pin.place, ownerSubject: ownerSubject,
                                                sessionGeneration: sessionGeneration)
                    }
                    Label(pin.place.category.displayName(language: language.language), systemImage: pin.place.category.iconName)
                        .font(.subheadline).foregroundStyle(DateTheme.muted)
                    address
                    neighborhoodMap
                    actions
                    businessInformation
                    if let saveError, !saveError.isEmpty {
                        Label(saveError, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(DateTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("live.place.saveError")
                    }
                    if information.isLoading {
                        ProgressView(copy("Loading place photos and details…", "正在取得店家照片與資訊…"))
                            .font(.subheadline).frame(minHeight: 44)
                    } else if let error = information.error {
                        Text(error.message(language: language.language))
                            .font(.caption).foregroundStyle(DateTheme.muted)
                        Button(copy("Reload place information", "重新取得店家資訊")) {
                            reloadGeneration &+= 1
                        }.frame(minHeight: 44)
                    }
                    if let creator = LiveCreatorCatalog.shared.match(pin.place) {
                        LiveCreatorSourceSection(entry: creator)
                    }
                    sourceLinks
                    if let onAddToOuting {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Button(action: onAddToOuting) {
                                Label(copy("Add to outing", "加入出遊清單"), systemImage: "plus")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).foregroundStyle(DateTheme.blue)
                            .disabled(!canAddToOuting || isSaving)
                            .accessibilityIdentifier("live.place.addToOuting")
                            Text(copy("Only place details are shared. Your notes and photos stay private.",
                                      "只分享地點資料，不包含你的筆記與照片。"))
                                .font(.caption).foregroundStyle(DateTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.clear)
            .foregroundStyle(DateTheme.ink).tint(DateTheme.blue)
            .navigationTitle(copy("Place", "地點"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(copy("Done", "完成"), action: onClose)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("live.place.close")
                }
            }
        }
    }

    @ViewBuilder
    private var neighborhoodMap: some View {
        if pin.place.isMapKitMappable {
            if let onShowPocketCity {
                Button(action: onShowPocketCity) {
                    Label(copy("Show in Pocket City", "在 Pocket City 顯示"), systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("live.place.map")
            }
        } else {
            Label(copy("Location unavailable", "尚無可顯示的位置"), systemImage: "mappin.slash")
                .font(.subheadline).foregroundStyle(DateTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: pin.place.name)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Label(sourceTitle, systemImage: sourceSymbol)
                    .font(.subheadline).foregroundStyle(DateTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("live.place.source")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
    }

    private var address: some View {
        Text(verbatim: pin.place.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
             ? copy("Address unavailable", "尚無地址") : LivePlaceAddress.display(pin.place.address))
            .font(.body).foregroundStyle(DateTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private var actions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) { primaryAction; directionsAction }
        } else {
            HStack(spacing: 10) { primaryAction; directionsAction }
        }
    }

    private var primaryAction: some View {
        let saved = pin.origin == .saved || onOpenSaved != nil
        return Button {
            if saved { onOpenSaved?() } else { onSave?() }
        } label: {
            HStack(spacing: 8) {
                if isSaving && !saved {
                    ProgressView().tint(DateTheme.actionInk)
                } else {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                }
                Text(saved
                     ? copy("Open saved", "開啟收藏")
                     : (isSaving ? copy("Saving…", "儲存中…") : copy("Save", "收藏")))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.body.weight(.semibold)).foregroundStyle(DateTheme.actionInk)
            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 48)
            .background(DateTheme.action, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || (saved ? onOpenSaved == nil : onSave == nil))
        .accessibilityIdentifier(saved ? "live.place.openSaved" : "live.place.save")
    }

    private var directionsAction: some View {
        Button(action: onDirections) {
            Label(copy("Directions", "路線"), systemImage: "arrow.turn.up.right")
                .font(.body.weight(.semibold)).foregroundStyle(DateTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 48)
                .background(DateTheme.soft, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain).disabled(!pin.place.isMapKitMappable)
        .accessibilityIdentifier("live.place.directions")
    }

    @ViewBuilder private var businessPhotos: some View {
        if LiveBusinessPhotoSource.resolve(pin.place).hasPhoto {
            LiveBusinessPhoto(place: pin.place).frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("live.place.businessPhoto")
            if case .bundled(let photo) = LiveBusinessPhotoSource.resolve(pin.place), let source = photo.original {
                Link(photo.credit, destination: source).font(.caption).foregroundStyle(DateTheme.muted)
            }
        } else if let image = websitePhoto.image {
            VStack(alignment: .leading, spacing: 4) {
                Image(uiImage: image).resizable().scaledToFill().frame(height: 200).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel(copy("Business website image", "店家網站圖片"))
                if let source = websitePhoto.sourceURL {
                    Link(copy("Image · business website", "圖片來源・店家網站"), destination: source)
                        .font(.caption).foregroundStyle(DateTheme.muted)
                }
            }.accessibilityIdentifier("live.place.businessPhoto")
        } else if information.isLoading || websitePhoto.isLoading {
            ProgressView(copy("Loading place photo…", "正在取得店家圖片…"))
                .frame(maxWidth: .infinity, minHeight: 130)
                .background(DateTheme.soft, in: RoundedRectangle(cornerRadius: 18))
        } else {
            Label(copy("Business photos unavailable", "暫無店家照片"), systemImage: "photo")
                .font(.subheadline).foregroundStyle(DateTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }

    @ViewBuilder private var businessInformation: some View {
        if let item = information.item {
            VStack(alignment: .leading, spacing: 4) {
                if let phone = item.phoneNumber, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label(phone, systemImage: "phone").font(.subheadline).textSelection(.enabled)
                        .frame(minHeight: 36)
                }
                if let url = item.url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                   url.user == nil, url.password == nil {
                    Link(destination: url) {
                        Label(copy("Website", "店家網站"), systemImage: "globe")
                            .font(.subheadline).frame(minHeight: 44)
                    }
                }
                if #available(iOS 18.0, *) {
                    Button { nativeCardPresented = true } label: {
                        Label(copy("More in Apple Maps", "Apple Maps 詳細資訊"), systemImage: "info.circle")
                            .font(.subheadline).frame(minHeight: 44)
                    }.accessibilityIdentifier("live.place.appleDetails")
                }
            }
        }
    }

    private var sourceLinks: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let url = LivePlaceSourceLink.url(for: pin) {
                Link(destination: url) {
                    HStack {
                        Label(copy("Source", "來源連結"), systemImage: "link")
                        Spacer(minLength: 8)
                        Text(url.host ?? "").lineLimit(1).truncationMode(.middle)
                        Image(systemName: "arrow.up.right").font(.caption)
                    }.font(.subheadline).frame(minHeight: 44)
                }.accessibilityIdentifier("live.place.sourceLink")
            } else if LiveCreatorCatalog.shared.match(pin.place) == nil {
                Label(copy("No source link attached", "未附來源連結"), systemImage: "link")
                    .font(.caption).foregroundStyle(DateTheme.muted).frame(minHeight: 32)
            }
        }
    }

    private var sourceTitle: String {
        switch pin.origin {
        case .saved:
            return pin.place.status == .visited
                ? copy("Saved · Marked visited", "已收藏・自行標記去過")
                : copy("Saved · Want to go", "已收藏・想去")
        case .search:
            return copy("Apple Maps result · Not saved", "Apple Maps 結果・尚未收藏")
        case .publicPost:
            return copy("Public post · Not saved", "公開貼文・尚未收藏")
        case .shared:
            return pin.sourceLabel == "朋友已分享"
                ? copy("Shared by friends · Not saved", "朋友分享・尚未收藏")
                : copy("Outing candidate · Not saved", "出遊候選・尚未收藏")
        }
    }

    private var sourceSymbol: String {
        switch pin.origin {
        case .saved: return "bookmark.fill"
        case .search: return "magnifyingglass"
        case .shared: return "person.2"
        case .publicPost: return "text.bubble"
        }
    }

    private func copy(_ english: String, _ traditionalChinese: String) -> String {
        language.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

// Source links never parse or rewrite the user's private note.
enum LivePlaceSourceLink {
    static func url(for pin: LiveMapPlace) -> URL? {
        guard pin.origin != .shared, let raw = pin.place.sourceUrl,
              let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

@available(iOS 18.0, *)
@MainActor
private struct LiveNativePlaceCard: UIViewControllerRepresentable {
    let item: MKMapItem
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> MKMapItemDetailViewController {
        let controller = MKMapItemDetailViewController(mapItem: item, displaysMap: true)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: MKMapItemDetailViewController, context: Context) {
        context.coordinator.onClose = onClose
        if controller.mapItem !== item { controller.mapItem = item }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    final class Coordinator: NSObject, MKMapItemDetailViewControllerDelegate {
        var onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func mapItemDetailViewControllerDidFinish(_ detailViewController: MKMapItemDetailViewController) { onClose() }
    }
}
/// Presentation and comparison only. Never overwrites provider/user address data.
/// Taiwan's municipality, street, house number and floor remain part of the key.
enum LivePlaceAddress {
    static func display(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let traditional = (trimmed.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? trimmed)
            .precomposedStringWithCompatibilityMapping.replacingOccurrences(of: "臺", with: "台")
        let compact = traditional.components(separatedBy: .whitespacesAndNewlines).joined()
        let country = #"(?:中國)?台灣(?:省)?"#
        let postal = #"(?:[0-9]{3,6})?"#
        let cities = "(?:台北市|新北市|桃園市|台中市|台南市|高雄市|基隆市|新竹市|嘉義市|新竹縣|苗栗縣|彰化縣|南投縣|雲林縣|嘉義縣|屏東縣|宜蘭縣|花蓮縣|台東縣|澎湖縣|金門縣|連江縣)"
        let prefix = "^" + postal + "(?:" + country + ")?" + postal
        guard compact.range(of: prefix + cities, options: .regularExpression) != nil else { return trimmed }
        var result = compact.replacingOccurrences(of: prefix, with: "", options: .regularExpression)
        // Collapse only an identical city/district prefix. Different districts
        // remain distinct even if their road and house number happen to match.
        let duplicate = "^(" + cities + "[^市縣區鄉鎮路街巷弄號0-9]{1,5}[區鄉鎮市])" + postal + "(?:" + country + ")?" + postal + #"\1"#
        result = result.replacingOccurrences(of: duplicate, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?<=[區鄉鎮])[^區鄉鎮市路街巷弄號\d]{1,8}里"#, with: "", options: .regularExpression)
        for (index, number) in Array("一二三四五六七八九十").enumerated() {
            result = result.replacingOccurrences(of: "\(number)段", with: "\(index + 1)段")
        }
        result = result.replacingOccurrences(of: #"(\d+)號之(\d+)號?"#, with: "$1之$2號", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(\d+)-(\d+)號"#, with: "$1之$2號", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)(b?\d+)f"#, with: "$1樓", options: .regularExpression)
        return result.replacingOccurrences(of: "一樓", with: "1樓")
    }
}

/// A Debug-bundled public creator reference. It never writes Place, user notes, or visits.
struct LiveCreatorCatalog: Decodable {
    struct Alias: Decodable { let provider: String; let id: String }
    struct MatchedPlace: Decodable {
        let name: String; let address: String; let latitude: Double; let longitude: Double
    }
    struct Original: Decodable, Identifiable {
        var id: String { url }
        let url: String
        let text: String
        let date: String
        let author: String
    }
    struct Entry: Decodable, Identifiable {
        var id: String { cid }
        let cid: String
        let name: String
        let address: String
        let latitude: Double
        let longitude: Double
        let placeId: String
        let lists: [String]
        let aliases: [Alias]
        let matchedPlaces: [MatchedPlace]?
        let posts: [Original]
    }
    let schemaVersion: Int
    let scope: String
    let creator: String
    let entries: [Entry]

    static let shared: Self = {
        guard let file = Bundle.main.url(forResource: "CreatorPlaceSources", withExtension: "json", subdirectory: "PocketCity"),
              let data = try? Data(contentsOf: file), data.count <= 2_000_000,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.valid else {
            return Self(schemaVersion: 1, scope: "local_creator_preview", creator: "zeke_6973", entries: [])
        }
        return value
    }()

    var valid: Bool {
        schemaVersion == 1 && scope == "local_creator_preview" && creator == "zeke_6973"
        && entries.count <= 2000 && Set(entries.map(\.cid)).count == entries.count
        && Set(entries.map(\.placeId)).count == entries.count
        && entries.allSatisfy { entry in
            entry.cid.range(of: #"^[1-9][0-9]{0,19}$"#, options: .regularExpression) != nil
            && !entry.name.isEmpty && !entry.address.isEmpty && !entry.placeId.isEmpty
            && entry.latitude.isFinite && entry.longitude.isFinite
            && abs(entry.latitude) <= 90 && abs(entry.longitude) <= 180
            && !entry.lists.isEmpty && entry.lists.allSatisfy { ["visited", "wish"].contains($0) }
            && (entry.matchedPlaces ?? []).allSatisfy {
                !$0.name.isEmpty && $0.latitude.isFinite && $0.longitude.isFinite
                && abs($0.latitude) <= 90 && abs($0.longitude) <= 180
            }
            && entry.posts.allSatisfy { post in
                post.author == creator && post.text.count <= 4000
                && post.url.range(of: #"^https://www\.threads\.com/@zeke_6973/post/[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
            }
        }
    }

    func entry(placeId: String?) -> Entry? {
        guard let placeId else { return nil }
        return entries.first { $0.placeId == placeId }
    }

    private static func nameKey(_ value: String) -> String {
        let traditional = value.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? value
        let folded = traditional.precomposedStringWithCompatibilityMapping.lowercased()
            .replacingOccurrences(of: "臺", with: "台").replacingOccurrences(of: "麵", with: "面")
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }
    private static func addressKey(_ value: String) -> String {
        LivePlaceAddress.display(value).precomposedStringWithCompatibilityMapping.lowercased()
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }
    func match(_ place: Place) -> Entry? {
        let key = LivePublicDiscoveryVenueKey(savedPlace: place)
        let matches = entries.filter { row in
            // Only paired names/addresses from the approved canonical match.
            // Never combine a brand alias with another branch's address.
            if (row.matchedPlaces ?? []).contains(where: { known in
                Self.nameKey(known.name) == Self.nameKey(place.name)
                && Self.addressKey(known.address) == Self.addressKey(place.address)
                && hypot((known.latitude - place.latitude) * 110540,
                         (known.longitude - place.longitude) * 111320 * cos(place.latitude * .pi / 180)) <= 65
            }) { return true }
            let distance = hypot((row.latitude - place.latitude) * 110540,
                                 (row.longitude - place.longitude) * 111320 * cos(place.latitude * .pi / 180))
            guard distance.isFinite, distance <= 65 else { return false }
            let identified = key.map { key in row.aliases.contains { $0.provider == key.provider && $0.id == key.id } } ?? false
            return identified || (Self.nameKey(row.name) == Self.nameKey(place.name)
                && Self.addressKey(row.address) == Self.addressKey(place.address))
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

@MainActor
struct LiveCreatorSourceSection: View {
    let entry: LiveCreatorCatalog.Entry
    @Environment(\.appLanguageSettings) private var language
    private func copy(_ en: String, _ zh: String) -> String {
        language.localized(english: en, traditionalChinese: zh)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(copy("Lala’s public list", "拉拉熊公開清單")).font(.subheadline.weight(.semibold))
            Text(entry.lists.map { $0 == "visited" ? copy("Creator visited", "作者去過") : copy("Creator wants to go", "作者想去") }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if let url = URL(string: "https://www.google.com/maps?cid=" + entry.cid) {
                Link(copy("View list place", "查看清單地點"), destination: url).frame(minHeight: 44)
            }
            ForEach(entry.posts) { post in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: post.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: post.url) {
                        Link("Threads · @\(post.author) · \(post.date)", destination: url)
                            .font(.caption).frame(minHeight: 44)
                    }
                }
            }
            Link(copy("List compiled by @2xin15__", "清單整理：@2xin15__"),
                 destination: URL(string: "https://2xin15.github.io/lala-food/")!)
                .font(.caption).frame(minHeight: 44)
            Text(copy("Transcribed from the public list; originals may change.", "公開清單轉錄 · 原文可能更新"))
                .font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("live.place.creatorSources")
    }
}
#endif
