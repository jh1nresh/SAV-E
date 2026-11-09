#if SAVVY_CITY_MVP
import MapKit
import SwiftUI

struct CityMVPPlacePanel: View {
    let name: String
    let detail: String
    let saved: Place?
    let candidate: SaveMapCandidate?
    let photoCredit: CityPinArtwork.Photo?
    let onSave: (SaveMapCandidate) async throws -> Void
    let onClose: () -> Void
    @State private var saving = false
    @State private var error: String?
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: saved == nil ? "mappin" : "bookmark.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(CityMVPStyle.blue)
                    .background(CityMVPStyle.selected, in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.title3.weight(.bold)).lineLimit(2)
                    Text(saved == nil ? t("Unsaved place", "未收藏地點") : t("Map Stamp · Saved", "Map Stamp · 已收藏"))
                        .font(.caption.weight(.semibold)).foregroundStyle(CityMVPStyle.blue)
                    if !detail.isEmpty {
                        Text(detail).font(.subheadline).foregroundStyle(CityMVPStyle.muted).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                        .frame(width: 44, height: 44).background(CityMVPStyle.surface, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel(t("Close place", "關閉地點"))
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if photoCredit != nil || candidate?.sourceURL != nil {
                HStack(spacing: 12) {
                    if let rawURL = candidate?.sourceURL, let url = URL(string: rawURL), url.scheme == "https" {
                        Link(t("View source", "查看來源"), destination: url)
                    }
                    if let photoCredit {
                        Link(t("Photo: \(photoCredit.author)", "照片：\(photoCredit.author)"),
                             destination: photoCredit.source)
                    }
                }
                .font(.caption.weight(.semibold))
            }
            if let saved, saved.isMapKitMappable {
                action(t("Directions", "導航"), symbol: "arrow.turn.up.right") {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: saved.coordinate))
                    item.name = saved.name
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                }
            } else if let candidate {
                action(saving ? t("Saving…", "收藏中…") : t("Save this place", "收藏這個地點"),
                       symbol: "bookmark") {
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await onSave(candidate) }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(saving)
            }
        }
        .padding(16)
        .foregroundStyle(CityMVPStyle.ink)
        .cityMVPGlass(in: RoundedRectangle(cornerRadius: 28))
        .accessibilityIdentifier("cityMVP.placePanel")
    }

    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol).font(.headline)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(CityMVPStyle.actionFill, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}
#endif
