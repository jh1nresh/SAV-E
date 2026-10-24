import SwiftUI
import UIKit

/// Shared Google photo source mark.
///
/// Home, Drawer, Trip, Origin, and the Atlas selected-place card
/// (`map.place.card`) use a two-line 10pt semibold stack under the
/// thumbnail (DESIGN). If that stack cannot fit at the thumb width,
/// show a non-Google image instead. Google's terms on wording and
/// placement are still unverified; do not overlay the photo without
/// HoP / founder.
enum GooglePlacesPhotoSourceMarkStyle {
    /// Two-line `Google` / `Maps` under a 44pt or 52pt Home thumb.
    case homeStacked
    /// Single-line footer on a wider card.
    case footer
}

enum GooglePlacesPhotoSourceMarkMetrics {
    static let text = "Google Maps"
    static let homeLines = ["Google", "Maps"]
    static let homeMinPointSize: CGFloat = 10
    static let homeGapAbove: CGFloat = 2
    static let homeReservedHeight: CGFloat = 24
    static let minPointSize: CGFloat = 12
    static let maxPointSize: CGFloat = 16
    static let rowHeight: CGFloat = 24
    static let gapAbove: CGFloat = 6
    static let lightInk = Color(hex: "1F1F1F")
    static let lightInkRGB = (r: 31.0 / 255.0, g: 31.0 / 255.0, b: 31.0 / 255.0)
    static let lightPaperRGB = (r: 1.0, g: 249.0 / 255.0, b: 235.0 / 255.0)
    static let darkPaperRGB = (r: 30.0 / 255.0, g: 28.0 / 255.0, b: 25.0 / 255.0)
    static let whiteRGB = (r: 1.0, g: 1.0, b: 1.0)

    static func pointSize(for dynamicType: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: uiCategory(dynamicType))
        let scaled = UIFontMetrics(forTextStyle: .body)
            .scaledValue(for: minPointSize, compatibleWith: traits)
        return min(maxPointSize, max(minPointSize, scaled))
    }

    static func homePointSize(for dynamicType: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: uiCategory(dynamicType))
        let scaled = UIFontMetrics(forTextStyle: .caption2)
            .scaledValue(for: homeMinPointSize, compatibleWith: traits)
        return max(homeMinPointSize, scaled)
    }

    static func markWidth(for dynamicType: DynamicTypeSize) -> CGFloat {
        let font = UIFont.systemFont(ofSize: pointSize(for: dynamicType), weight: .regular)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func homeMarkWidth(for dynamicType: DynamicTypeSize) -> CGFloat {
        let font = UIFont.systemFont(ofSize: homePointSize(for: dynamicType), weight: .semibold)
        return homeLines
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
    }

    static func homeMarkHeight(for dynamicType: DynamicTypeSize) -> CGFloat {
        let font = UIFont.systemFont(ofSize: homePointSize(for: dynamicType), weight: .semibold)
        return max(homeReservedHeight, ceil(font.lineHeight) * 2)
    }

    static func canShowGooglePhoto(in availableWidth: CGFloat, dynamicType: DynamicTypeSize) -> Bool {
        markWidth(for: dynamicType) <= availableWidth
    }

    static func canShowStackedMark(in availableWidth: CGFloat, dynamicType: DynamicTypeSize) -> Bool {
        homeMarkWidth(for: dynamicType) <= availableWidth
    }

    static func displaysGooglePhoto(
        _ url: URL?,
        availableWidth: CGFloat,
        dynamicType: DynamicTypeSize
    ) -> Bool {
        displaysStackedGooglePhoto(url, availableWidth: availableWidth, dynamicType: dynamicType)
    }

    static func displaysStackedGooglePhoto(
        _ url: URL?,
        availableWidth: CGFloat,
        dynamicType: DynamicTypeSize
    ) -> Bool {
        guard isGooglePhotoURL(url) else { return false }
        return canShowStackedMark(in: availableWidth, dynamicType: dynamicType)
    }

    static func isGooglePhotoURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return GooglePlacesPhotoURL.isGooglePlacesPhotoURL(url)
    }

    static func voiceOverLabel(language: AppLanguage) -> String {
        language.localized(english: "Photo: Google Maps", traditionalChinese: "照片來源：Google Maps")
    }

    static func lightContrastRatio() -> Double {
        GoogleMapsAttributionContrast.ratio(foreground: lightInkRGB, background: lightPaperRGB)
    }

    static func darkContrastRatio() -> Double {
        GoogleMapsAttributionContrast.ratio(foreground: whiteRGB, background: darkPaperRGB)
    }

    static func uiCategory(_ dynamicType: DynamicTypeSize) -> UIContentSizeCategory {
        switch dynamicType {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3, .accessibility4, .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

struct GooglePlacesPhotoSourceMark: View {
    var style: GooglePlacesPhotoSourceMarkStyle = .footer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        Group {
            switch style {
            case .homeStacked:
                homeStacked
            case .footer:
                footerSingle
            }
        }
        .accessibilityLabel(GooglePlacesPhotoSourceMarkMetrics.voiceOverLabel(language: languageSettings.language))
        .accessibilityIdentifier("place.photo.sourceMark")
    }

    private var markColor: Color {
        colorScheme == .dark
            ? Color.white
            : GooglePlacesPhotoSourceMarkMetrics.lightInk
    }

    private var homeStacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(GooglePlacesPhotoSourceMarkMetrics.homeLines, id: \.self) { line in
                Text(line)
                    .lineLimit(1)
                    .minimumScaleFactor(1.0)
            }
        }
        .font(.system(
            size: GooglePlacesPhotoSourceMarkMetrics.homePointSize(for: dynamicTypeSize),
            weight: .semibold
        ))
        .foregroundStyle(markColor)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: true, vertical: true)
        .frame(
            minHeight: GooglePlacesPhotoSourceMarkMetrics.homeMarkHeight(for: dynamicTypeSize),
            alignment: .topLeading
        )
    }

    private var footerSingle: some View {
        Text(GooglePlacesPhotoSourceMarkMetrics.text)
            .font(.system(
                size: GooglePlacesPhotoSourceMarkMetrics.pointSize(for: dynamicTypeSize),
                weight: .regular
            ))
            .foregroundStyle(markColor)
            .lineLimit(1)
            .minimumScaleFactor(1.0)
            .fixedSize(horizontal: true, vertical: true)
            .frame(
                height: GooglePlacesPhotoSourceMarkMetrics.rowHeight,
                alignment: .leading
            )
    }
}
