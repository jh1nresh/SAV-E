#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import SwiftUI

/// A read-only choice from existing business metadata, not a venue lookup or photo verifier.
enum LiveBusinessPhotoSource: Equatable {
    case available(URL)
    case missingMetadata
    case providerRestricted
    case unsupportedMetadata

    static func resolve(_ place: Place) -> Self {
        let values = (place.businessPhotoUrls ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return .missingMetadata }
        let sourceImage = place.sourceImageUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        var hasRestrictedPhoto = false
        for value in values {
            // `businessPhotoURLStrings` also appends sourceImageUrl, and source merging can
            // put that image in this array. A post/screenshot is not business-photo proof.
            guard let url = URL(string: value),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil else { continue }
            guard let safeURL = GooglePlacesPhotoSourceMarkMetrics.mapSafePhotoURL(url) else {
                hasRestrictedPhoto = true
                continue
            }
            guard value != sourceImage else { continue }
            return .available(safeURL)
        }
        return hasRestrictedPhoto ? .providerRestricted : .unsupportedMetadata
    }
}

/// Caller supplies the size and clipping shape (for example, a pin circle or library tile).
/// This component never enriches, persists or shares the Place or its private images.
@MainActor
struct LiveBusinessPhoto: View {
    let place: Place
    @Environment(\.appLanguageSettings) private var language

    init(place: Place) { self.place = place }

    var body: some View {
        Group {
            switch LiveBusinessPhotoSource.resolve(place) {
            case .available(let url):
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .accessibilityLabel(copy("Place photo", "地點照片"))
                    case .failure:
                        fallback(copy("Photo could not load", "照片暫時無法載入"))
                    case .empty:
                        fallback(copy("Loading photo", "照片載入中"))
                    @unknown default:
                        fallback(copy("Photo unavailable", "照片暫時無法顯示"))
                    }
                }
            case .missingMetadata:
                fallback(copy("Business photo unavailable", "暫無店家照片"))
            case .providerRestricted:
                fallback(copy("This photo source is unavailable on this map", "此地圖無法顯示這個來源的照片"))
            case .unsupportedMetadata:
                fallback(copy("No supported business photo", "尚無適用的商家照片"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DateTheme.soft)
    }

    private func fallback(_ status: String) -> some View {
        Image(systemName: place.category.iconName)
            .font(.system(.title2, design: .rounded, weight: .medium))
            .foregroundStyle(DateTheme.blue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(copy("Place category", "地點分類"))
            .accessibilityValue(status)
    }

    private func copy(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}
#endif
