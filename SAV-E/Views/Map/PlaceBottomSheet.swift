import SwiftUI
import UIKit

struct PlaceBasicInfoPanel: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption.weight(.bold))
                Text(languageSettings.localized(english: "Basic info", traditionalChinese: "基本資訊"))
                    .font(.caption.weight(.bold))
                Spacer()
            }
            .foregroundColor(.saveCocoa)

            VStack(spacing: 7) {
                PlaceInfoRow(icon: "star", title: languageSettings.localized(english: "Rating", traditionalChinese: "評分"), value: ratingText)
                if let reviewCountText {
                    PlaceInfoRow(icon: "text.bubble", title: languageSettings.localized(english: "Reviews", traditionalChinese: "評論"), value: reviewCountText)
                }
                PlaceInfoRow(icon: place.category.detailIconName, title: languageSettings.localized(english: "Category", traditionalChinese: "分類"), value: place.category.displayName(language: languageSettings.language))
                PlaceInfoRow(icon: "mappin", title: languageSettings.localized(english: "Address", traditionalChinese: "地址"), value: place.address.isEmpty ? languageSettings.localized(english: "No address saved", traditionalChinese: "尚未保存地址") : place.address)
                PlaceInfoRow(icon: "link", title: languageSettings.localized(english: "Source", traditionalChinese: "來源"), value: place.sourceConfirmationLabel(language: languageSettings.language))
                if let priceRange = place.priceRange {
                    PlaceInfoRow(icon: "tag", title: languageSettings.localized(english: "Price", traditionalChinese: "價格"), value: priceRange)
                }
                if let openingHours = place.openingHours?.trimmingCharacters(in: .whitespacesAndNewlines), !openingHours.isEmpty {
                    PlaceInfoRow(icon: "clock", title: languageSettings.localized(english: "Hours", traditionalChinese: "營業時間"), value: openingHours)
                }
            }
        }
        .padding(10)
        .saveNotebookSurface(cornerRadius: 12, fill: .saveNotebookPage, opacity: 0.64)
    }

    private var ratingText: String {
        if let rating = place.googleRating ?? place.rating {
            return String(format: "%.1f", rating)
        }
        return languageSettings.localized(english: "No rating yet", traditionalChinese: "尚無評分")
    }

    private var reviewCountText: String? {
        for line in place.sourceEvidence {
            let prefix = "External reviews:"
            guard line.localizedCaseInsensitiveContains(prefix) else { continue }
            let value = line
                .replacingOccurrences(of: prefix, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            return languageSettings.localized(english: "\(value) reviews", traditionalChinese: "\(value) 則評論")
        }
        return nil
    }
}

private struct PlaceInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SaveIconTile(
                systemName: icon,
                size: 22,
                iconSize: 10,
                fill: Color.saveCream.opacity(0.74),
                foreground: .saveCocoa,
                strokeOpacity: 0.54
            )
            .padding(.top, 1)

            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundColor(.saveCocoa)
                .frame(width: 58, alignment: .leading)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private extension PlaceCategory {
    var detailIconName: String {
        switch self {
        case .food: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .bar: return "wineglass"
        case .attraction: return "star"
        case .stay: return "bed.double"
        case .shopping: return "bag"
        }
    }
}

private struct PlaceMemoryChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(.saveCocoa)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.saveNotebookPage.opacity(0.50))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.34), lineWidth: 1))
    }
}

struct PlaceVerificationChip: Hashable {
    let icon: String
    let text: String
}

extension Place {
    var sourceConfirmationLabel: String {
        if primarySourceURL?.host(percentEncoded: false)?.localizedCaseInsensitiveContains("maps.apple.com") == true {
            return "Found on Apple Maps"
        }
        if primarySourceURL?.host(percentEncoded: false)?.localizedCaseInsensitiveContains("google") == true ||
            sourcePlatform == .googleMaps {
            return googlePlaceId == nil ? "Found on Google Maps" : "Google Places details"
        }
        if sourcePlatform != .other {
            return "Found on \(sourcePlatform.displayName)"
        }
        if googlePlaceId != nil {
            return "Google Places details"
        }
        return "Source saved"
    }

    func sourceConfirmationLabel(language: AppLanguage) -> String {
        if primarySourceURL?.host(percentEncoded: false)?.localizedCaseInsensitiveContains("maps.apple.com") == true {
            return language.localized(english: "Found on Apple Maps", traditionalChinese: "來自 Apple Maps")
        }
        if primarySourceURL?.host(percentEncoded: false)?.localizedCaseInsensitiveContains("google") == true ||
            sourcePlatform == .googleMaps {
            return googlePlaceId == nil
                ? language.localized(english: "Found on Google Maps", traditionalChinese: "來自 Google Maps")
                : language.localized(english: "Google Places details", traditionalChinese: "Google Places 詳細資料")
        }
        if sourcePlatform != .other {
            return language.localized(english: "Found on \(sourcePlatform.displayName)", traditionalChinese: "來自 \(sourcePlatform.displayName)")
        }
        if googlePlaceId != nil {
            return language.localized(english: "Google Places details", traditionalChinese: "Google Places 詳細資料")
        }
        return language.localized(english: "Source saved", traditionalChinese: "已保存來源")
    }

    var cleanMemoryNote: String? {
        guard let note = userFacingNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return nil
        }
        // `places.note` is unclassified user memory. Strip only lines Savvy
        // itself marked; do not hide user-authored Recommender:/Source handle:
        // /Analysis method: text by prefix.
        let cleanedLines = note
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                let normalizedLine = line.normalizedSummaryText
                return !SavvyGeneratedLine.isMarked(line) &&
                normalizedLine != name.normalizedSummaryText &&
                normalizedLine != address.normalizedSummaryText
            }
        guard !cleanedLines.isEmpty else { return nil }
        return cleanedLines.joined(separator: "\n")
    }

    func verificationChips(sourceLabel: String? = nil) -> [PlaceVerificationChip] {
        var chips: [PlaceVerificationChip] = []
        if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chips.append(PlaceVerificationChip(icon: "mappin.and.ellipse", text: "Address saved"))
        }
        chips.append(PlaceVerificationChip(icon: "link", text: sourceLabel ?? sourceConfirmationLabel))
        if googlePlaceId != nil || googleRating != nil || googlePriceLevel != nil || openingHours != nil {
            chips.append(PlaceVerificationChip(icon: "building.2.fill", text: "Google Places details"))
        }
        return chips
    }

    func verificationChips(language: AppLanguage, sourceLabel: String? = nil) -> [PlaceVerificationChip] {
        var chips: [PlaceVerificationChip] = []
        if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chips.append(PlaceVerificationChip(
                icon: "mappin.and.ellipse",
                text: language.localized(english: "Address saved", traditionalChinese: "已保存地址")
            ))
        }
        chips.append(PlaceVerificationChip(icon: "link", text: sourceLabel ?? sourceConfirmationLabel(language: language)))
        if googlePlaceId != nil || googleRating != nil || googlePriceLevel != nil || openingHours != nil {
            chips.append(PlaceVerificationChip(
                icon: "building.2.fill",
                text: language.localized(english: "Google Places details", traditionalChinese: "Google Places 詳細資料")
            ))
        }
        return chips
    }

    var memorySummary: String {
        if let note = cleanMemoryNote {
            return note
        }
        if let dishes = extractedDishes, !dishes.isEmpty {
            return "Saved for \(dishes.prefix(3).joined(separator: ", "))."
        }
        if let recommender = recommender?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommender.isEmpty {
            return "Recommended by \(recommender)."
        }
        switch status {
        case .visited:
            return "Marked visited in Savvy."
        case .wantToGo:
            return "Saved as a place to try."
        }
    }

    func memorySummary(language: AppLanguage) -> String {
        if let note = cleanMemoryNote {
            return note
        }
        if let dishes = extractedDishes, !dishes.isEmpty {
            return language.localized(
                english: "Saved for \(dishes.prefix(3).joined(separator: ", ")).",
                traditionalChinese: "為了 \(dishes.prefix(3).joined(separator: "、")) 存下。"
            )
        }
        if let recommender = recommender?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommender.isEmpty {
            return language.localized(english: "Recommended by \(recommender).", traditionalChinese: "\(recommender) 推薦。")
        }
        switch status {
        case .visited:
            return language.localized(english: "Marked visited in Savvy.", traditionalChinese: "已在 Savvy 標記為去過。")
        case .wantToGo:
            return language.localized(english: "Saved as a place to try.", traditionalChinese: "已存成想找時間去的地點。")
        }
    }
}

private extension String {
    var normalizedSummaryText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

// MARK: - Simple Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(subviews: subviews, proposal: proposal)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, proposal: proposal)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(subviews: Subviews, proposal: ProposedViewSize) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalHeight = y + rowHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}

struct PlaceDetailActionLabel: View {
    var title: String
    var systemImage: String
    var fill: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
            )
    }
}

struct PlaceInsightSummaryPanel: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let place: Place
    var fallbackSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.badge.checkmark")
                    .font(.caption.weight(.bold))
                Text(languageSettings.localized(english: "Memory summary", traditionalChinese: "記憶摘要"))
                    .font(.caption.weight(.bold))
                Spacer()
            }
            .foregroundColor(.saveCocoa)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(summaryLines, id: \.text) { line in
                    PlaceSummaryLine(icon: line.icon, text: line.text)
                }
            }
        }
        .padding(12)
        .background(Color.saveNotebookPage.opacity(0.50))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.35), lineWidth: 1)
        )
    }

    private var summaryLines: [(icon: String, text: String)] {
        var lines: [(icon: String, text: String)] = []
        if let whySavedSummary {
            lines.append(("sparkles", whySavedSummary))
        } else {
            lines.append(("sparkles", condensedFallbackSummary))
        }
        if let reviewSummary {
            lines.append(("star.fill", reviewSummary))
        }
        if let practicalInfo {
            lines.append(("info.circle", practicalInfo))
        }
        if let sourceSummary {
            lines.append(("link", sourceSummary))
        }
        return Array(lines.prefix(4))
    }

    private var condensedFallbackSummary: String {
        let firstLine = fallbackSummary
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fallbackSummary
        let value = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 120 else { return value }
        return String(value.prefix(117)) + "..."
    }

    private var whySavedSummary: String? {
        var parts: [String] = []
        if !place.savedRecommendedItems.isEmpty {
            let names = place.savedRecommendedItems.prefix(3).map(\.name).filter { !$0.isEmpty }
            if !names.isEmpty {
                parts.append(languageSettings.localized(
                    english: "saved for \(names.joined(separator: ", "))",
                    traditionalChinese: "為了 \(names.joined(separator: "、")) 存下"
                ))
            }
        }
        let highlights = place.savedPlaceHighlights.prefix(2).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !highlights.isEmpty {
            parts.append(highlights.joined(separator: " · "))
        }
        if let recommender = cleaned(place.recommender) ?? cleaned(place.savedSourceHandle) {
            parts.append(languageSettings.localized(english: "from \(recommender)", traditionalChinese: "來自 \(recommender)"))
        }
        guard !parts.isEmpty else { return nil }
        let prefix = place.status == .visited
            ? languageSettings.localized(english: "Visited", traditionalChinese: "去過")
            : languageSettings.localized(english: "Want to try", traditionalChinese: "想找時間去")
        return "\(prefix): \(parts.joined(separator: " · "))"
    }

    private var practicalInfo: String? {
        var parts: [String] = []
        if let openingHours = cleaned(place.openingHours) {
            parts.append(languageSettings.localized(english: "Hours: \(openingHours)", traditionalChinese: "營業時間：\(openingHours)"))
        }
        if let priceRange = cleaned(place.priceRange) {
            parts.append(languageSettings.localized(english: "Price: \(priceRange)", traditionalChinese: "價格：\(priceRange)"))
        }
        let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty {
            parts.append(languageSettings.localized(english: "Address: \(address)", traditionalChinese: "地址：\(address)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var reviewSummary: String? {
        var parts: [String] = []
        if let rating = place.googleRating ?? place.rating {
            let value = String(format: "%.1f", rating)
            parts.append(languageSettings.localized(english: "\(value) stars", traditionalChinese: "\(value) 星"))
        }
        if let reviewCountText = reviewCountText {
            parts.append(reviewCountText)
        }
        return parts.isEmpty ? nil : languageSettings.localized(english: "Reviews: \(parts.joined(separator: " · "))", traditionalChinese: "評論：\(parts.joined(separator: " · "))")
    }

    private var recommendationSummary: String? {
        if let dishes = place.extractedDishes, !dishes.isEmpty {
            return languageSettings.localized(
                english: "Saved for: \(dishes.prefix(4).joined(separator: ", "))",
                traditionalChinese: "為了這些存下：\(dishes.prefix(4).joined(separator: "、"))"
            )
        }
        if let recommender = cleaned(place.recommender) {
            return languageSettings.localized(english: "Recommended by: \(recommender)", traditionalChinese: "推薦人：\(recommender)")
        }
        return nil
    }

    private var sourceSummary: String? {
        var parts: [String] = []
        parts.append(place.sourceConfirmationLabel(language: languageSettings.language))
        if place.googlePlaceId != nil || place.googleRating != nil || place.googlePriceLevel != nil || place.openingHours != nil {
            parts.append(languageSettings.localized(english: "map-enriched", traditionalChinese: "已用地圖資料補強"))
        }
        return parts.isEmpty ? nil : languageSettings.localized(
            english: "Evidence: \(parts.joined(separator: " · "))",
            traditionalChinese: "證據：\(parts.joined(separator: " · "))"
        )
    }

    private var reviewCountText: String? {
        for line in place.sourceEvidence {
            let prefix = "External reviews:"
            guard line.localizedCaseInsensitiveContains(prefix) else { continue }
            let value = line
                .replacingOccurrences(of: prefix, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            return languageSettings.localized(english: "\(value) reviews", traditionalChinese: "\(value) 則評論")
        }
        return nil
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}

private struct PlaceSummaryLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundColor(.saveCocoa)
                .frame(width: 16)
                .padding(.top, 2)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PlaceBusinessPhotoCarousel: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    var imageURLs: [String]
    var isSearching = false
    var googlePlaceId: String? = nil
    var googleMapsURI: URL? = nil

    @State private var expandedPhoto: PlacePhotoPage?

    var body: some View {
        ZStack(alignment: showsGoogleAttribution ? .topLeading : .bottomLeading) {
            if photoPages.isEmpty {
                fallbackVisual
                    .frame(height: GoogleMapsAttributionMetrics.carouselHeight)
                    .accessibilityIdentifier("place.photo.carousel.empty")
            } else {
                TabView {
                    ForEach(Array(photoPages.enumerated()), id: \.offset) { index, page in
                        ZStack(alignment: .bottom) {
                            photoImage(page.url)
                                .onTapGesture {
                                    if page.isGooglePlacesPhoto {
                                        expandedPhoto = page
                                    }
                                }
                                .accessibilityIdentifier("place.photo.carousel.page")
                            if page.isGooglePlacesPhoto {
                                GooglePlacesPhotoAttributionBar(
                                    authors: page.authors,
                                    mapsURI: page.mapsURI,
                                    compact: true,
                                    onCompactTap: { expandedPhoto = page }
                                )
                            }
                        }
                        .frame(height: GoogleMapsAttributionMetrics.carouselHeight)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: photoPages.count > 1 ? .automatic : .never))
                .frame(height: GoogleMapsAttributionMetrics.carouselHeight)
            }

            HStack(spacing: 6) {
                Image(systemName: photoPages.isEmpty ? (isSearching ? "hourglass" : "photo") : "camera.fill")
                    .font(.caption2.weight(.bold))
                Text(photoPages.isEmpty ? emptyPhotoLabel : photoLabel)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundColor(.saveInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.saveNotebookPage.opacity(0.66))
            .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
            .clipShape(Capsule())
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.35), lineWidth: 1)
        )
        .fullScreenCover(item: $expandedPhoto) { page in
            GooglePlacesPhotoViewer(
                page: page,
                onClose: { expandedPhoto = nil }
            )
        }
    }

    private var photoPages: [PlacePhotoPage] {
        PlacePhotoPage.pages(
            imageURLs: imageURLs,
            googlePlaceId: googlePlaceId,
            googleMapsURI: googleMapsURI
        )
    }

    private var showsGoogleAttribution: Bool {
        photoPages.contains(where: \.isGooglePlacesPhoto)
    }

    private var photoLabel: String {
        photoPages.count > 1
            ? languageSettings.localized(
                english: "\(photoPages.count) business photos",
                traditionalChinese: "\(photoPages.count) 張商家照片"
            )
            : languageSettings.localized(english: "Business photo", traditionalChinese: "商家照片")
    }

    private var emptyPhotoLabel: String {
        isSearching
            ? languageSettings.localized(english: "Finding business photo", traditionalChinese: "正在尋找商家照片")
            : languageSettings.localized(english: "No business photo available", traditionalChinese: "尚無商家照片")
    }

    private var fallbackVisual: some View {
        Rectangle()
            .fill(SaveAtlasPalette.coral)
            .overlay {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(SaveTheme.Colors.cream)
            }
    }

    @ViewBuilder
    private func photoImage(_ url: URL) -> some View {
        CachedAsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                fallbackVisual
            case .empty:
                ProgressView()
                    .tint(.saveInk)
            @unknown default:
                fallbackVisual
            }
        }
    }
}

struct PlacePhotoPage: Identifiable, Hashable {
    let id: String
    let url: URL
    let isGooglePlacesPhoto: Bool
    let authors: [GooglePlacePhotoAuthor]
    let mapsURI: URL?

    static func pages(
        imageURLs: [String],
        googlePlaceId: String?,
        googleMapsURI: URL?
    ) -> [PlacePhotoPage] {
        imageURLs.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
            let isGoogle = GooglePlacesPhotoURL.isGooglePlacesPhotoURL(url)
            let record = GooglePlacePhotoSessionStore.record(for: url)
            let authors = record?.authors ?? []
            // G1: a Google photo without author data must not render as an
            // unattributed image. Drop it so the coral placeholder can show.
            if isGoogle && authors.isEmpty { return nil }
            let mapsURI = record?.googleMapsURI
                ?? googleMapsURI
                ?? GooglePlacesHTMLAttribution.mapsURL(placeId: googlePlaceId)
            return PlacePhotoPage(
                id: trimmed,
                url: url,
                isGooglePlacesPhoto: isGoogle,
                authors: authors,
                mapsURI: isGoogle ? mapsURI : nil
            )
        }
    }
}

struct GooglePlacesPhotoAttributionBar: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.appLanguageSettings) private var languageSettings
    var authors: [GooglePlacePhotoAuthor]
    var mapsURI: URL?
    var compact = false
    var onCompactTap: (() -> Void)? = nil

    var body: some View {
        Group {
            if compact {
                compactRow
            } else {
                expandedStack
            }
        }
        .padding(.leading, GoogleMapsAttributionMetrics.clearSpaceLeading)
        .padding(.trailing, GoogleMapsAttributionMetrics.clearSpaceTrailing)
        .padding(.top, GoogleMapsAttributionMetrics.clearSpaceTop)
        .padding(.bottom, GoogleMapsAttributionMetrics.clearSpaceBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    .black.opacity(GoogleMapsAttributionMetrics.gradientTopOpacity),
                    .black.opacity(GoogleMapsAttributionMetrics.gradientBottomOpacity),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// P1-1 / P1-5: one 44pt row (author left, logo right) opens the viewer.
    /// Identifier lives on a UIKit `UIButton`. Hidden SwiftUI children and a
    /// nested logo identifier previously swallowed `place.photo.attribution.row`
    /// so `app.buttons` never saw it.
    private var compactRow: some View {
        ZStack {
            compactVisualRow
            GooglePlacesAttributionHitButton(
                identifier: "place.photo.attribution.row",
                label: compactAccessibilityLabel,
                action: { onCompactTap?() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: GoogleMapsAttributionMetrics.minimumTapTarget)
        .contentShape(Rectangle())
    }

    /// Visual-only. No accessibility identifiers or hidden flags — those steal
    /// the parent Button's identifier in XCTest.
    private var compactVisualRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if let author = authors.first {
                attributionText(author.displayName, style: .caption, weight: .semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Image("GoogleMapsLogoOnImage")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: GoogleMapsAttributionMetrics.logoHeight)
        }
        .frame(maxWidth: .infinity, minHeight: GoogleMapsAttributionMetrics.minimumTapTarget, alignment: .center)
        .allowsHitTesting(false)
    }

    private var expandedStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            authorButtons

            HStack(alignment: .center, spacing: 8) {
                if let mapsURI {
                    Button {
                        openURL(mapsURI)
                    } label: {
                        attributionText(
                            languageSettings.localized(
                                english: "View on Google Maps",
                                traditionalChinese: "在 Google Maps 查看"
                            ),
                            style: .footnote,
                            weight: .regular
                        )
                        .frame(maxWidth: .infinity, minHeight: GoogleMapsAttributionMetrics.minimumTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("place.photo.attribution.viewOnMaps")
                }

                Spacer(minLength: 8)
                GoogleMapsAttributionLogo()
            }
        }
    }

    /// P1-3: every author is shown, joined with 「、」, each tappable.
    private var authorButtons: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(authors.enumerated()), id: \.offset) { index, author in
                if index > 0 {
                    attributionText("、", style: .footnote, weight: .regular)
                }
                Button {
                    if let uri = author.uri { openURL(uri) }
                } label: {
                    attributionText(author.displayName, style: .footnote, weight: .semibold)
                        .underline(author.uri != nil)
                        .frame(minHeight: GoogleMapsAttributionMetrics.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(author.uri == nil)
                .accessibilityIdentifier(
                    index == 0
                        ? "place.photo.attribution.author"
                        : "place.photo.attribution.author.\(index)"
                )
                .accessibilityLabel(
                    languageSettings.localized(
                        english: "Photo by \(author.displayName)",
                        traditionalChinese: "照片作者 \(author.displayName)"
                    )
                )
            }
        }
    }

    private var compactAccessibilityLabel: String {
        guard let author = authors.first else {
            return languageSettings.localized(
                english: "Open Google photo",
                traditionalChinese: "開啟 Google 照片"
            )
        }
        return languageSettings.localized(
            english: "Photo by \(author.displayName)",
            traditionalChinese: "照片作者 \(author.displayName)"
        )
    }

    private func attributionText(_ text: String, style: Font, weight: Font.Weight) -> some View {
        Text(text)
            .font(style.weight(weight))
            .foregroundStyle(.white)
            .shadow(
                color: .black.opacity(GoogleMapsAttributionMetrics.authorShadowOpacity),
                radius: 2
            )
            .lineLimit(1)
    }
}

/// UIKit button so XCTest reads `accessibilityIdentifier` from a real UIButton
/// (`isAccessibilityElement = true`). SwiftUI child views cannot swallow it.
private struct GooglePlacesAttributionHitButton: UIViewRepresentable {
    var identifier: String
    var label: String
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = FillAttributionButton(type: .custom)
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        button.isAccessibilityElement = true
        button.accessibilityTraits = .button
        button.isUserInteractionEnabled = true
        button.backgroundColor = .clear
        button.addTarget(context.coordinator, action: #selector(Coordinator.invoke), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        button.isAccessibilityElement = true
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func invoke() { action() }
    }
}

private final class FillAttributionButton: UIButton {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: GoogleMapsAttributionMetrics.minimumTapTarget)
    }
}

struct GoogleMapsAttributionLogo: View {
    /// Official on-imagery logo (light outline). Used on photos and the
    /// black viewer; a separate white wordmark is not in the shipped assets.
    var body: some View {
        Image("GoogleMapsLogoOnImage")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(height: GoogleMapsAttributionMetrics.logoHeight)
            .accessibilityLabel("Google Maps")
            .accessibilityIdentifier("place.photo.attribution.logo")
    }
}

struct GooglePlacesPhotoViewer: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let page: PlacePhotoPage
    var fixtureImage: Image? = nil
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    if let fixtureImage {
                        fixtureImage
                            .resizable()
                            .scaledToFit()
                    } else {
                        CachedAsyncImage(url: page.url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                            case .empty:
                                ProgressView().tint(.white)
                            default:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("place.photo.viewer.image")

                if page.isGooglePlacesPhoto {
                    GooglePlacesPhotoAttributionBar(
                        authors: page.authors,
                        mapsURI: page.mapsURI,
                        compact: false
                    )
                }
            }

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: GoogleMapsAttributionMetrics.minimumTapTarget, height: GoogleMapsAttributionMetrics.minimumTapTarget)
            }
            .padding(16)
            .accessibilityIdentifier("place.photo.viewer.close")
            .accessibilityLabel(languageSettings.localized(english: "Close", traditionalChinese: "關閉"))
        }
    }
}
