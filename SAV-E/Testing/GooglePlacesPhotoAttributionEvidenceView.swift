#if DEBUG
import SwiftUI

enum GooglePlacesPhotoAttributionEvidence {
    static let launchArgument = "--uitest-google-photo-attribution"

    static var isLaunchEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static let authorURI = URL(string: "https://maps.google.com/maps/contrib/123456789")!
    static let mapsURI = URL(string: "https://maps.google.com/?cid=1&q=Harbor+Oven")!

    static let janeDoe = GooglePlacePhotoAuthor(
        displayName: "Jane Doe",
        uri: authorURI
    )

    static let alexChen = GooglePlacePhotoAuthor(
        displayName: "Alex Chen",
        uri: URL(string: "https://maps.google.com/maps/contrib/987654321")!
    )

    static let googlePage = PlacePhotoPage(
        id: "evidence-google",
        url: URL(string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=evidence")!,
        isGooglePlacesPhoto: true,
        authors: [janeDoe, alexChen],
        mapsURI: mapsURI
    )
}

/// Isolated card gallery so CI can capture real simulator chrome without
/// signing in or hitting live Places photo URLs.
struct GooglePlacesPhotoAttributionEvidenceView: View {
    enum Scene: String, CaseIterable, Identifiable {
        case googleCarousel
        case userPhoto
        case fullScreen
        case authorDestination
        case mapsDestination
        case logoCloseup
        case noAuthor
        case mixedCard
        case mapPins
        case cityPage
        case reportEntry

        var id: String { rawValue }

        var title: String {
            switch self {
            case .googleCarousel: return "Google carousel"
            case .userPhoto: return "Own photo"
            case .fullScreen: return "Full screen"
            case .authorDestination: return "Author page"
            case .mapsDestination: return "Maps page"
            case .logoCloseup: return "Logo close-up"
            case .noAuthor: return "No author"
            case .mixedCard: return "Mixed card"
            case .mapPins: return "Map pins"
            case .cityPage: return "City page"
            case .reportEntry: return "Report"
            }
        }
    }

    @State private var scene: Scene = .googleCarousel
    @State private var openedURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Leaf only. A parent identifier here overwrote Harbor Oven,
                // the compact Button, and evidence.googleCarousel in XCTest.
                Text("Evidence")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveCocoa)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("evidence.googlePhoto.root")
                scenePicker
                sceneBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
            .background(Color.saveCream.ignoresSafeArea())
            .navigationTitle("Photo attribution")
            .navigationBarTitleDisplayMode(.inline)
        }
        .environment(\.openURL, OpenURLAction { url in
            openedURL = url
            // Path, not host. maps.google.com never contains "contrib".
            scene = Self.isAuthorDestination(url) ? .authorDestination : .mapsDestination
            return .handled
        })
        .onChange(of: scene) { _, _ in
            openedURL = nil
        }
    }

    private var scenePicker: some View {
        // Wrap so Logo close-up / No author stay on-screen. A horizontal
        // ScrollView left those chips at x=516+ where waitUntilHittable fails.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 80), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(Scene.allCases) { item in
                Button(item.title) { scene = item }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(scene == item ? .saveCream : .saveInk)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: SaveLayout.minTap)
                    .background(scene == item ? Color.saveInk : Color.saveNotebookPage)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("evidence.scene.\(item.rawValue)")
            }
        }
    }

    @ViewBuilder
    private var sceneBody: some View {
        switch scene {
        case .googleCarousel:
            evidenceCard(title: "Harbor Oven", sceneIdentifier: "evidence.googleCarousel") {
                googleCarouselPage
            }
        case .userPhoto:
            evidenceCard(title: "Harbor Oven") {
                userPhotoPage
            }
        case .fullScreen:
            GooglePlacesPhotoViewer(
                page: GooglePlacesPhotoAttributionEvidence.googlePage,
                fixtureImage: lightPhoto,
                onClose: {}
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .authorDestination:
            destinationPage(
                title: "Photo author",
                url: openedURL ?? GooglePlacesPhotoAttributionEvidence.authorURI,
                pageIdentifier: "evidence.openedPage.author"
            )
        case .mapsDestination:
            destinationPage(
                title: "Google Maps",
                url: openedURL ?? GooglePlacesPhotoAttributionEvidence.mapsURI,
                pageIdentifier: "evidence.openedPage.maps"
            )
        case .logoCloseup:
            VStack(alignment: .leading, spacing: 12) {
                Text("Logo 18dp · clear space 10/10/10/5")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .accessibilityIdentifier("evidence.logoCloseup")
                // Compact row has no nested logo identifier. Keep a standalone
                // logo here. Do not put evidence.logoCloseup on this VStack —
                // a parent id overwrites place.photo.attribution.logo.
                GoogleMapsAttributionLogo()
                GooglePlacesPhotoCardLayout.overlayCard {
                    lightPhoto
                        .resizable()
                        .scaledToFill()
                } overlay: {
                    GooglePlacesPhotoAttributionBar(
                        authors: [GooglePlacesPhotoAttributionEvidence.janeDoe],
                        mapsURI: GooglePlacesPhotoAttributionEvidence.mapsURI,
                        compact: true
                    )
                }
                .scaleEffect(1.35, anchor: .bottomTrailing)
                .frame(height: 190, alignment: .bottomTrailing)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .noAuthor:
            evidenceCard(title: "Harbor Oven") {
                PlaceBusinessPhotoCarousel(
                    imageURLs: [
                        "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=no-author"
                    ],
                    googlePlaceId: "ChIJNoAuthor"
                )
            }
        case .mixedCard:
            VStack(alignment: .leading, spacing: 12) {
                Text("Google page keeps attribution. Own photo has none.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .accessibilityIdentifier("evidence.mixedCard")
                googleCarouselPage
                userPhotoPage
            }
        case .mapPins:
            VStack(alignment: .leading, spacing: 12) {
                Text("Apple Map pins are symbols. No Google photos.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .accessibilityIdentifier("evidence.mapPins")
                HStack(spacing: 24) {
                    PlaceMapPin(place: Self.evidencePlace, isSelected: false) {}
                    PlaceMapPin(place: Self.evidencePlace, isSelected: true) {}
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding(16)
                .background(Color.saveNotebookPage)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .cityPage:
            VStack(alignment: .leading, spacing: 12) {
                Text("City cards do not show Google photos.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .accessibilityIdentifier("evidence.cityPage")
                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SaveAtlasPalette.coral)
                        .overlay {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(SaveTheme.Colors.cream)
                        }
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Harbor Oven")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.saveInk)
                        Text("Taipei · Da'an")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.saveCocoa)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Color.saveNotebookPage)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 1)
                )
            }
        case .reportEntry:
            VStack(alignment: .leading, spacing: 12) {
                Text("Report this photo on Google Maps")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .accessibilityIdentifier("evidence.reportEntry")
                GooglePlacesPhotoViewer(
                    page: GooglePlacesPhotoAttributionEvidence.googlePage,
                    fixtureImage: lightPhoto,
                    onClose: {}
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var googleCarouselPage: some View {
        GooglePlacesPhotoCardLayout.overlayCard {
            lightPhoto
                .resizable()
                .scaledToFill()
                .onTapGesture { scene = .fullScreen }
                .accessibilityIdentifier("place.photo.carousel.page")
        } overlay: {
            GooglePlacesPhotoAttributionBar(
                authors: [GooglePlacesPhotoAttributionEvidence.janeDoe],
                mapsURI: GooglePlacesPhotoAttributionEvidence.mapsURI,
                compact: true,
                onCompactTap: { scene = .fullScreen }
            )
        }
    }

    private var userPhotoPage: some View {
        GooglePlacesPhotoCardLayout.overlayCard {
            userPhoto
                .resizable()
                .scaledToFill()
        } overlay: {
            HStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.caption2.weight(.bold))
                Text("Your photo")
                    .font(.caption2.weight(.bold))
            }
            .foregroundColor(.saveInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.saveNotebookPage.opacity(0.66))
            .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
            .clipShape(Capsule())
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("evidence.userPhoto")
        }
    }

    private func evidenceCard<Content: View>(
        title: String,
        sceneIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let sceneIdentifier, !sceneIdentifier.isEmpty {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundColor(.saveInk)
                        .accessibilityIdentifier(sceneIdentifier)
                } else {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundColor(.saveInk)
                }
            }
            content()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(0.35), lineWidth: 1)
                )
        }
        .padding(14)
        .background(Color.saveNotebookPage)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1)
        )
    }

    private func destinationPage(title: String, url: URL, pageIdentifier: String) -> some View {
        // White "browser" page is always light. Adaptive saveInk/saveCocoa
        // flip to cream in Dark Mode and disappear on Color.white.
        let ink = Self.destinationInk
        let muted = Self.destinationMuted
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "safari")
                Text(url.absoluteString)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.saveInk)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: SaveLayout.minTap, alignment: .leading)
            .background(Color.saveNotebookPage)
            .accessibilityIdentifier("evidence.openedPage.url")

            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundColor(ink)
                    .accessibilityIdentifier(pageIdentifier)
                Text(url.host ?? url.absoluteString)
                    .font(.body)
                    .foregroundColor(muted)
                Text("Opened from the attribution control. Live Places pages are not fetched in this evidence harness.")
                    .font(.caption)
                    .foregroundColor(muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1)
        )
    }

    private var lightPhoto: Image {
        Image(uiImage: Self.renderPhoto(
            top: UIColor(red: 0.93, green: 0.90, blue: 0.82, alpha: 1),
            bottom: UIColor(red: 0.78, green: 0.84, blue: 0.74, alpha: 1),
            symbol: "cup.and.saucer.fill",
            tint: UIColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 1)
        ))
    }

    private var userPhoto: Image {
        Image(uiImage: Self.renderPhoto(
            top: UIColor(red: 0.98, green: 0.86, blue: 0.70, alpha: 1),
            bottom: UIColor(red: 0.90, green: 0.55, blue: 0.42, alpha: 1),
            symbol: "person.crop.square",
            tint: UIColor(red: 0.28, green: 0.16, blue: 0.12, alpha: 1)
        ))
    }

    /// Ink that stays 3A2415 in Dark Mode so title/body remain visible on white.
    static let destinationInk = Color(hex: "3A2415")
    static let destinationMuted = Color(hex: "7A5D45")

    static let evidencePlace = Place(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000306")!,
        name: "Harbor Oven",
        address: "Da'an District, Taipei",
        latitude: 25.04,
        longitude: 121.54,
        category: .cafe,
        status: .wantToGo,
        sourcePlatform: .other,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    static func isAuthorDestination(_ url: URL) -> Bool {
        url.path.lowercased().contains("/contrib")
            || url.absoluteString.lowercased().contains("/maps/contrib/")
    }

    private static func renderPhoto(top: UIColor, bottom: UIColor, symbol: String, tint: UIColor) -> UIImage {
        let size = CGSize(width: 720, height: 480)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            ) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
            let config = UIImage.SymbolConfiguration(pointSize: 96, weight: .semibold)
            if let symbolImage = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(tint, renderingMode: .alwaysOriginal)
            {
                let origin = CGPoint(
                    x: (size.width - symbolImage.size.width) / 2,
                    y: (size.height - symbolImage.size.height) / 2
                )
                symbolImage.draw(at: origin)
            }
        }
    }
}
#endif
