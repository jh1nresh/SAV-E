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
            }
        }
    }

    @State private var scene: Scene = .googleCarousel
    @State private var openedURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                scenePicker
                sceneBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(16)
            .background(Color.saveCream.ignoresSafeArea())
            .navigationTitle("Photo attribution")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("evidence.googlePhoto.root")
        }
        .environment(\.openURL, OpenURLAction { url in
            openedURL = url
            if url.host?.contains("contrib") == true {
                scene = .authorDestination
            } else {
                scene = .mapsDestination
            }
            return .handled
        })
        .onChange(of: scene) { _, _ in
            openedURL = nil
        }
    }

    private var scenePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Scene.allCases) { item in
                    Button(item.title) { scene = item }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(scene == item ? .saveCream : .saveInk)
                        .padding(.horizontal, 10)
                        .frame(minHeight: SaveLayout.minTap)
                        .background(scene == item ? Color.saveInk : Color.saveNotebookPage)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("evidence.scene.\(item.rawValue)")
                }
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
                url: openedURL ?? GooglePlacesPhotoAttributionEvidence.authorURI
            )
        case .mapsDestination:
            destinationPage(
                title: "Google Maps",
                url: openedURL ?? GooglePlacesPhotoAttributionEvidence.mapsURI
            )
        case .logoCloseup:
            VStack(alignment: .leading, spacing: 12) {
                Text("Logo 18dp · clear space 10/10/10/5")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveInk)
                // Compact row hides the nested logo from AX so the 44pt control
                // stays one hittable button. Keep a standalone logo here.
                GoogleMapsAttributionLogo()
                ZStack(alignment: .bottom) {
                    lightPhoto
                        .resizable()
                        .scaledToFill()
                    GooglePlacesPhotoAttributionBar(
                        authors: [GooglePlacesPhotoAttributionEvidence.janeDoe],
                        mapsURI: GooglePlacesPhotoAttributionEvidence.mapsURI,
                        compact: true
                    )
                }
                .frame(height: 140)
                .clipped()
                .scaleEffect(1.35, anchor: .bottomTrailing)
                .frame(height: 190, alignment: .bottomTrailing)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityIdentifier("evidence.logoCloseup")
        case .noAuthor:
            evidenceCard(title: "Harbor Oven") {
                PlaceBusinessPhotoCarousel(
                    imageURLs: [
                        "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=no-author"
                    ],
                    googlePlaceId: "ChIJNoAuthor"
                )
            }
        }
    }

    private var googleCarouselPage: some View {
        ZStack(alignment: .bottom) {
            lightPhoto
                .resizable()
                .scaledToFill()
                .onTapGesture { scene = .fullScreen }
                .accessibilityIdentifier("place.photo.carousel.page")
            GooglePlacesPhotoAttributionBar(
                authors: [GooglePlacesPhotoAttributionEvidence.janeDoe],
                mapsURI: GooglePlacesPhotoAttributionEvidence.mapsURI,
                compact: true,
                onCompactTap: { scene = .fullScreen }
            )
        }
        .frame(height: GoogleMapsAttributionMetrics.carouselHeight)
        .clipped()
    }

    private var userPhotoPage: some View {
        ZStack(alignment: .bottomLeading) {
            userPhoto
                .resizable()
                .scaledToFill()
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
        }
        .frame(height: GoogleMapsAttributionMetrics.carouselHeight)
        .clipped()
        .accessibilityIdentifier("evidence.userPhoto")
    }

    private func evidenceCard<Content: View>(
        title: String,
        sceneIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundColor(.saveInk)
                .modifier(OptionalAccessibilityIdentifier(sceneIdentifier))
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

    private func destinationPage(title: String, url: URL) -> some View {
        VStack(spacing: 0) {
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
                Text(url.host ?? url.absoluteString)
                    .font(.body)
                    .foregroundColor(.saveCocoa)
                Text("Opened from the attribution control. Live Places pages are not fetched in this evidence harness.")
                    .font(.caption)
                    .foregroundColor(.saveCocoa)
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
        .accessibilityIdentifier("evidence.openedPage")
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

private struct OptionalAccessibilityIdentifier: ViewModifier {
    var identifier: String?

    init(_ identifier: String?) {
        self.identifier = identifier
    }

    func body(content: Content) -> some View {
        if let identifier, !identifier.isEmpty {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
#endif
