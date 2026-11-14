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
         onDirections: @escaping () -> Void, onAddToOuting: (() -> Void)?,
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
        if case .available = LiveBusinessPhotoSource.resolve(pin.place) { return }
        await websitePhoto.load(website: information.item?.url, ownerSubject: ownerSubject, generation: sessionGeneration)
    }

    private var fallbackCard: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    businessPhotos
                    identity
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
            .background(DateTheme.canvas.ignoresSafeArea())
            .foregroundStyle(DateTheme.ink).tint(DateTheme.blue)
            .navigationTitle(copy("Place", "地點"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DateTheme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
            Map(position: .constant(.region(MKCoordinateRegion(
                center: pin.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.010)
            ))), interactionModes: []) {
                Marker(pin.place.name, systemImage: pin.origin == .saved ? "bookmark.fill" : "mappin",
                       coordinate: pin.coordinate)
            }
            .mapStyle(.standard(elevation: .flat))
            .tint(DateTheme.blue)
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            // Keep MapKit's own Apple attribution and legal controls visible.
            // Empty interaction modes disable camera gestures without covering them.
            .accessibilityLabel(copy("Map for \(pin.place.name)", "\(pin.place.name) 的位置地圖"))
            .accessibilityIdentifier("live.place.map")
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
             ? copy("Address unavailable", "尚無地址") : pin.place.address)
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
        Button {
            if pin.origin == .saved { onOpenSaved?() } else { onSave?() }
        } label: {
            HStack(spacing: 8) {
                if isSaving && pin.origin != .saved {
                    ProgressView().tint(DateTheme.actionInk)
                } else {
                    Image(systemName: pin.origin == .saved ? "bookmark.fill" : "bookmark")
                }
                Text(pin.origin == .saved
                     ? copy("Open saved", "開啟收藏")
                     : (isSaving ? copy("Saving…", "儲存中…") : copy("Save", "收藏")))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.body.weight(.semibold)).foregroundStyle(DateTheme.actionInk)
            .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 48)
            .background(DateTheme.action, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || (pin.origin == .saved ? onOpenSaved == nil : onSave == nil))
        .accessibilityIdentifier(pin.origin == .saved ? "live.place.openSaved" : "live.place.save")
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
        if case .available = LiveBusinessPhotoSource.resolve(pin.place) {
            LiveBusinessPhoto(place: pin.place).frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("live.place.businessPhoto")
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
            } else {
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
#endif
