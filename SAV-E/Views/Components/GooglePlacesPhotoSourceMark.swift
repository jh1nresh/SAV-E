import SwiftUI
import UIKit

/// v2 Google photo source mark. Single-line "Google Maps", 12–16sp Regular.
/// Layout chrome is owned by the call site (footer vs below-thumb).
/// Surfaces that cannot fit this string at the current Dynamic Type
/// must show a non-Google image instead of this mark.
enum GooglePlacesPhotoSourceMarkMetrics {
    static let text = "Google Maps"
    static let minPointSize: CGFloat = 12
    static let maxPointSize: CGFloat = 16
    static let rowHeight: CGFloat = 24
    static let gapAbove: CGFloat = 6
    static let lightInk = Color(hex: "1F1F1F")

    static func pointSize(for dynamicType: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: uiCategory(dynamicType))
        let scaled = UIFontMetrics(forTextStyle: .body)
            .scaledValue(for: minPointSize, compatibleWith: traits)
        return min(maxPointSize, max(minPointSize, scaled))
    }

    static func markWidth(for dynamicType: DynamicTypeSize) -> CGFloat {
        let font = UIFont.systemFont(ofSize: pointSize(for: dynamicType), weight: .regular)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func canShowGooglePhoto(in availableWidth: CGFloat, dynamicType: DynamicTypeSize) -> Bool {
        markWidth(for: dynamicType) <= availableWidth
    }

    static func displaysGooglePhoto(
        _ url: URL?,
        availableWidth: CGFloat,
        dynamicType: DynamicTypeSize
    ) -> Bool {
        guard let url, GooglePlacesPhotoURL.isGooglePlacesPhotoURL(url) else { return false }
        return canShowGooglePhoto(in: availableWidth, dynamicType: dynamicType)
    }

    static func voiceOverLabel(language: AppLanguage) -> String {
        language.localized(english: "Photo: Google Maps", traditionalChinese: "照片來源：Google Maps")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(GooglePlacesPhotoSourceMarkMetrics.text)
            .font(.system(
                size: GooglePlacesPhotoSourceMarkMetrics.pointSize(for: dynamicTypeSize),
                weight: .regular
            ))
            .foregroundStyle(
                colorScheme == .dark
                    ? Color.white
                    : GooglePlacesPhotoSourceMarkMetrics.lightInk
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .frame(
                height: GooglePlacesPhotoSourceMarkMetrics.rowHeight,
                alignment: .leading
            )
            .accessibilityHidden(true)
            .accessibilityIdentifier("place.photo.sourceMark")
    }
}
