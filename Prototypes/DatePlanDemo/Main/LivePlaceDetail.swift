#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import MapKit
import SwiftUI

/// Presentation only. The owner supplies canonical save, directions and outing
/// actions; opening this view never saves a candidate or records a visit.
@MainActor
struct LivePlaceDetail: View {
    let pin: LiveMapPlace
    let isSaving: Bool
    let saveError: String?
    let onSave: (() -> Void)?
    let onOpenSaved: (() -> Void)?
    let onDirections: () -> Void
    let onAddToOuting: (() -> Void)?
    let canAddToOuting: Bool
    let onClose: () -> Void
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var noteExpanded = false

    init(pin: LiveMapPlace, isSaving: Bool, saveError: String?,
         onSave: (() -> Void)?, onOpenSaved: (() -> Void)?,
         onDirections: @escaping () -> Void, onAddToOuting: (() -> Void)?,
         canAddToOuting: Bool, onClose: @escaping () -> Void) {
        self.pin = pin
        self.isSaving = isSaving
        self.saveError = saveError
        self.onSave = onSave
        self.onOpenSaved = onOpenSaved
        self.onDirections = onDirections
        self.onAddToOuting = onAddToOuting
        self.canAddToOuting = canAddToOuting
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    neighborhoodMap
                    identity
                    address
                    actions
                    if let saveError, !saveError.isEmpty {
                        Label(saveError, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(DateTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("live.place.saveError")
                    }
                    note
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
        .onChange(of: pin.id) { _, _ in noteExpanded = false }
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
            if case .available = LiveBusinessPhotoSource.resolve(pin.place) {
                LiveBusinessPhoto(place: pin.place)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
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

    @ViewBuilder
    private var note: some View {
        if pin.origin == .saved, let note = pin.place.note,
           !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Button { noteExpanded.toggle() } label: {
                    HStack {
                        Text(copy("Your note", "你的筆記")).font(.headline)
                        Spacer(minLength: 8)
                        Image(systemName: noteExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(DateTheme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(noteExpanded
                    ? copy("Collapse your note", "收合你的筆記")
                    : copy("Read your full note", "閱讀完整筆記"))
                .accessibilityIdentifier("live.place.note.toggle")
                Text(verbatim: note).font(.body)
                    .lineLimit(noteExpanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("live.place.note")
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
#endif
