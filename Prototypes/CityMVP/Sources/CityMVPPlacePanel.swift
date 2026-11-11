#if SAVVY_CITY_MVP
import MapKit
import SwiftUI

struct CityMVPPlacePanel: View {
    private static let controlHeight: CGFloat = 58
    static var minimumCompactHeight: CGFloat { controlHeight + 8 }

    let name: String
    let detail: String
    let saved: Place?
    let candidate: SaveMapCandidate?
    let photoCredit: CityPinArtwork.Photo?
    let onSave: (SaveMapCandidate) async throws -> Void
    let onClose: () -> Void
    var compact = false
    var onExpandedHeight: (CGFloat) -> Void = { _ in }
    var onCompactHeight: (CGFloat) -> Void = { _ in }
    @State private var showsDetails = false
    @State private var saving = false
    @State private var error: String?
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        VStack(spacing: 0) {
            if compact {
                HStack(spacing: 8) {
                    Button { showsDetails = true } label: {
                        HStack(spacing: 10) {
                            thumbnail(diameter: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(name).font(.headline).lineLimit(1)
                                Text(saved == nil ? t("Unsaved place", "未收藏地點") : t("Map Stamp · Saved", "Map Stamp · 已收藏"))
                                    .font(.caption).foregroundStyle(CityMVPStyle.blue)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.up").font(.caption.bold())
                        }.frame(minHeight: Self.controlHeight).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("cityMVP.placeDetails")
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .frame(width: Self.controlHeight, height: Self.controlHeight).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(t("Close place", "關閉地點"))
                }
                .padding(.horizontal, 12).padding(.vertical, 4)
                .foregroundStyle(CityMVPStyle.ink)
                .cityMVPGlass(in: RoundedRectangle(cornerRadius: 24))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onCompactHeight($0) }
            } else {
                expandedContent
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onExpandedHeight($0) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cityMVP.placePanel")
        .sheet(isPresented: $showsDetails) {
            NavigationStack {
                ScrollView { expandedContent.padding(16) }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(t("Done", "完成")) { showsDetails = false }
                                .accessibilityIdentifier("cityMVP.placeDetails.done")
                        }
                    }
            }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail(diameter: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(saved == nil ? t("Unsaved place", "未收藏地點") : t("Map Stamp · Saved", "Map Stamp · 已收藏"))
                        .font(.caption.weight(.semibold)).foregroundStyle(CityMVPStyle.blue)
                    if !detail.isEmpty {
                        Text(detail).font(.subheadline).foregroundStyle(CityMVPStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                        .frame(width: Self.controlHeight, height: Self.controlHeight)
                        .background(CityMVPStyle.surface, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel(t("Close place", "關閉地點"))
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
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
            if photoCredit != nil || candidate?.sourceURL != nil {
                sourceLinks
            }
        }
        .padding(16)
        .foregroundStyle(CityMVPStyle.ink)
        .cityMVPGlass(in: RoundedRectangle(cornerRadius: 28))
    }

    private func thumbnail(diameter: CGFloat) -> some View {
        Group {
            if let photoCredit {
                Image(uiImage: photoCredit.image).resizable().scaledToFill()
            } else {
                Image(systemName: saved == nil ? "mappin" : "bookmark.fill")
                    .font(.system(size: diameter * 0.38, weight: .semibold))
                    .foregroundStyle(CityMVPStyle.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CityMVPStyle.selected)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(CityMVPStyle.rim, lineWidth: 2))
        .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
        .accessibilityHidden(true)
    }

    private var sourceLinks: some View {
        HStack(alignment: .top, spacing: 12) {
            if let rawURL = candidate?.sourceURL, let url = URL(string: rawURL), url.scheme == "https" {
                Link(destination: url) {
                    Text(t("View source", "查看來源"))
                        .frame(maxWidth: .infinity, minHeight: Self.controlHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
            if let photoCredit {
                Link(destination: photoCredit.source) {
                    Text(t("Photo: \(photoCredit.author)", "照片：\(photoCredit.author)"))
                        .frame(maxWidth: .infinity, minHeight: Self.controlHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
        .font(.caption.weight(.semibold))
    }

    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol).font(.headline)
                .frame(maxWidth: .infinity, minHeight: Self.controlHeight)
                .foregroundStyle(.white)
                .background(CityMVPStyle.actionFill, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}
#endif
