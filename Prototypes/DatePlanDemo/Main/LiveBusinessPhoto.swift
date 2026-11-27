#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import SwiftUI
import ImageIO
import CoreLocation

/// A read-only choice from existing business metadata, not a venue lookup or photo verifier.
enum LiveBusinessPhotoSource: Equatable {
    case available(URL)
    case bundled(LiveBundledBusinessPhoto)
    case missingMetadata
    case providerRestricted
    case unsupportedMetadata

    var hasPhoto: Bool {
        switch self {
        case .available, .bundled: true
        default: false
        }
    }

    static func resolve(_ place: Place) -> Self {
        let values = (place.businessPhotoUrls ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let bundled = LiveBundledBusinessPhoto.resolve(place)
        guard !values.isEmpty else { return bundled.map(Self.bundled) ?? .missingMetadata }
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
        return bundled.map(Self.bundled) ?? (hasRestrictedPhoto ? .providerRestricted : .unsupportedMetadata)
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
            case .bundled(let photo):
                if let image = LiveBundledPhotoImage.image(photo) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .accessibilityLabel(photo.alt)
                } else {
                    fallback(copy("Photo could not load", "照片暫時無法載入"))
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
/// Public, licensed Pocket City thumbnails. Never uses imported post screenshots or
/// guesses by brand name. Existing records can match a reviewed street address only
/// when the name and WGS84 coordinate also agree; ambiguous branches stay without a photo.
struct LiveBundledBusinessPhoto: Decodable, Equatable {
    let id: String
    let name: String
    let point: [Double]
    let file: String
    let alt: String
    let credit: String
    let commonsFile: String
    let width: Int
    let height: Int
    let streetAddress: String

    var aspectRatio: CGFloat { CGFloat(width) / CGFloat(height) }
    var original: URL? {
        var url = URLComponents(string: "https://commons.wikimedia.org")!
        url.path = "/wiki/File:" + commonsFile
        return url.url
    }
    var fileURL: URL? {
        guard file.range(of: #"^[A-Za-z0-9_-]+\.jpg$"#, options: .regularExpression) != nil else { return nil }
        return Bundle.main.url(forResource: file, withExtension: nil, subdirectory: "PocketCity/assets/place-photos")
    }
    static let catalog: [Self] = {
        guard let url = Bundle.main.url(forResource: "place-photo-data", withExtension: "js", subdirectory: "PocketCity"),
              let module = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return decode(module)
    }()
    static func decode(_ module: String) -> [Self] {
        let text = module.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("export default "), text.hasSuffix(";") else { return [] }
        let json = String(text.dropFirst("export default ".count).dropLast())
        guard let rows = try? JSONDecoder().decode([Self].self, from: Data(json.utf8)),
              Set(rows.map(\.id)).count == rows.count else { return [] }
        return rows.filter { $0.point.count == 2 && $0.point.allSatisfy(\.isFinite)
            && (-180...180).contains($0.point[0]) && (-90...90).contains($0.point[1])
            && (1...20000).contains($0.width) && (1...20000).contains($0.height)
            && !$0.credit.isEmpty && !$0.commonsFile.isEmpty }
    }
    static func resolve(_ place: Place) -> Self? {
        match(place, in: catalog).flatMap { $0.fileURL == nil ? nil : $0 }
    }
    static func match(_ place: Place, in rows: [Self]) -> Self? {
        guard place.isMapKitMappable else { return nil }
        let providerID = place.providerPlaceId ?? ""
        let canonical = providerID.replacingOccurrences(of: #"^osm-(node|way|relation)-(\d+)$"#,
                                                        with: "poi/$1/$2", options: .regularExpression)
        let hasAtlasID = canonical.hasPrefix("poi/")
        let matches = rows.filter { photo in
            guard photo.point.count == 2 else { return false }
            let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = location.distance(from: CLLocation(latitude: photo.point[1], longitude: photo.point[0]))
            if hasAtlasID { return photo.id == canonical && distance <= 60 }
            return distance <= 35 && normalized(place.name) == normalized(photo.name)
                && !photo.streetAddress.isEmpty
                && normalized(place.address).hasSuffix(normalized(photo.streetAddress))
        }
        return matches.count == 1 ? matches[0] : nil
    }
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "zh_TW"))
            .replacingOccurrences(of: "臺", with: "台")
            .components(separatedBy: .whitespacesAndNewlines).joined()
    }
}

@MainActor
private enum LiveBundledPhotoImage {
    static let cache = NSCache<NSURL, UIImage>()
    static func image(_ photo: LiveBundledBusinessPhoto) -> UIImage? {
        guard let url = photo.fileURL else { return nil }
        if let image = cache.object(forKey: url as NSURL) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.totalCostLimit = 12 * 1024 * 1024
        cache.setObject(image, forKey: url as NSURL, cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }
}
#endif
