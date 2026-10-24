import SwiftUI
import UIKit

/// Shared Google photo source mark.
///
/// Single-line untranslated `Google Maps`, 12–16sp regular (weight 400).
/// Place the mark in the same container, above or below the photo — never
/// overlaid. Measure the full single-line width against the container, not
/// the thumbnail. If that width cannot fit, show a non-Google image.
/// DESIGN estimates (~65–76pt at 12sp, ~87–93pt at 16sp) are not measured
/// truth; `markWidth(for:)` is the live gate.
///
/// Map callouts over Apple MapView (`map.place.card`) must not show Google
/// photos at all (G6). Colors stay `#1F1F1F` / white. Google's terms on
/// wording and placement are still unverified.
enum GooglePlacesPhotoSourceMarkStyle {
    /// Single-line footer. The stacked Home mark is gone.
    case footer
}

enum GooglePlacesPhotoSourceMarkMetrics {
    static let text = "Google Maps"
    static let minPointSize: CGFloat = 12
    static let maxPointSize: CGFloat = 16
    static let rowHeight: CGFloat = 24
    static let gapAbove: CGFloat = 6
    /// GeometryReader initial width. 0 means unmeasured: do not show a
    /// Google photo until the live container width is known.
    static let typicalContainerWidth: CGFloat = 0
    static let lightInk = Color(hex: "1F1F1F")
    static let lightInkRGB = (r: 31.0 / 255.0, g: 31.0 / 255.0, b: 31.0 / 255.0)
    static let lightPaperRGB = (r: 1.0, g: 249.0 / 255.0, b: 235.0 / 255.0)
    static let darkPaperRGB = (r: 30.0 / 255.0, g: 28.0 / 255.0, b: 25.0 / 255.0)
    static let whiteRGB = (r: 1.0, g: 1.0, b: 1.0)

    enum SurfaceBackground {
        /// Home featured peek, Origin food, Trip paper (`SaveAtlasPalette.paper`).
        case paper
        /// Home recent stamp sits on Home canvas (`FFF9EB` / `1E1C19`).
        case recentCanvas
        /// Drawer search row (`SaveAtlasPalette.canvas` at 0.9 over cream).
        case drawerCanvas
        /// Drawer saved postcard (`SaveAtlasPalette.paper`).
        case postcardPaper
        /// Atlas selected-place card uses system `.regularMaterial`.
        case atlasMaterial
    }

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
        guard isGooglePhotoURL(url) else { return false }
        return canShowGooglePhoto(in: availableWidth, dynamicType: dynamicType)
    }

    static func isGooglePhotoURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return GooglePlacesPhotoURL.isGooglePlacesPhotoURL(url)
    }

    /// Own / friend / other non-Google photos may sit on a map callout.
    /// Google Places photos must not.
    static func mapSafePhotoURL(_ url: URL?) -> URL? {
        guard let url, !isGooglePhotoURL(url) else { return nil }
        return url
    }

    static func voiceOverLabel(language: AppLanguage) -> String {
        language.localized(english: "Photo: Google Maps", traditionalChinese: "照片來源：Google Maps")
    }

    static func contrastRatio(on surface: SurfaceBackground, dark: Bool) -> Double {
        let background: (r: Double, g: Double, b: Double)
        switch surface {
        case .paper, .recentCanvas, .drawerCanvas, .postcardPaper:
            background = dark ? darkPaperRGB : lightPaperRGB
        case .atlasMaterial:
            background = dark ? darkPaperRGB : whiteRGB
        }
        return GoogleMapsAttributionContrast.ratio(
            foreground: dark ? whiteRGB : lightInkRGB,
            background: background
        )
    }

    static func lightContrastRatio() -> Double {
        contrastRatio(on: .paper, dark: false)
    }

    static func darkContrastRatio() -> Double {
        contrastRatio(on: .paper, dark: true)
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

extension View {
    func readingGooglePhotoContainerWidth(_ width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width.wrappedValue = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        width.wrappedValue = newWidth
                    }
            }
        }
    }
}
