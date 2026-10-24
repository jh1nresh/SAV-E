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
        case homeThumbs
        case homeThumbsZh
        case drawerThumbs
        case tripStop
        case originFood
        case atlasThumbs
        case layout375
        case layoutXXXL
        case layoutXSmall

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
            case .homeThumbs: return "Home thumbs"
            case .homeThumbsZh: return "Home zh-Hant"
            case .drawerThumbs: return "Drawer"
            case .tripStop: return "Trip stop"
            case .originFood: return "Origin food"
            case .atlasThumbs: return "Atlas card"
            case .layout375: return "375 width"
            case .layoutXXXL: return "XXXL"
            case .layoutXSmall: return "xSmall type"
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
        case .homeThumbs:
            homeThumbsScene()
                .environment(\.appLanguageSettings, Self.languageSettings(.english))
        case .homeThumbsZh:
            homeThumbsScene(identifier: "evidence.homeThumbsZh", languageNote: "zh-Hant VoiceOver")
                .environment(\.appLanguageSettings, Self.languageSettings(.traditionalChinese))
        case .drawerThumbs:
            ScrollView { drawerThumbsContent }
                .onAppear(perform: seedPhotoFixtures)
        case .tripStop:
            ScrollView { tripStopContent }
                .onAppear(perform: seedPhotoFixtures)
        case .originFood:
            ScrollView { originFoodContent }
                .onAppear(perform: seedPhotoFixtures)
        case .atlasThumbs:
            ScrollView { atlasThumbsContent }
                .onAppear(perform: seedPhotoFixtures)
        case .layout375:
            widthLockedScene(width: 375, identifier: "evidence.layout375")
        case .layoutXXXL:
            xxxlScene
        case .layoutXSmall:
            xSmallScene
        }
    }

    private func homeThumbsScene(
        identifier: String = "evidence.homeThumbs",
        languageNote: String = "en VoiceOver"
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Home featured 44pt and recent 52pt. Two-line Google / Maps under the thumb. \(languageNote).")
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .accessibilityIdentifier(identifier)
            SaveTileTownPeekCard(
                title: "Harbor Oven",
                subtitle: "Featured · Google",
                photoURL: Self.googleThumbURL,
                accessibilityNameID: "evidence.homeThumbs.featuredGoogle"
            )
            SaveTileTownPeekCard(
                title: "Own shot",
                subtitle: "Featured · own",
                photoURL: Self.ownThumbURL,
                accessibilityNameID: "evidence.homeThumbs.featuredOwn"
            )
            HStack(alignment: .top, spacing: 16) {
                SaveKraftStamp(
                    title: "Harbor Oven",
                    face: .photo(Self.googleThumbURL),
                    size: .recent,
                    accessibilityIdentifier: "evidence.homeThumbs.recentGoogle"
                )
                SaveKraftStamp(
                    title: "Own shot",
                    face: .photo(Self.ownThumbURL),
                    size: .recent,
                    accessibilityIdentifier: "evidence.homeThumbs.recentOwn"
                )
                SaveKraftStamp(
                    title: "Friend shot",
                    face: .photo(Self.friendThumbURL),
                    size: .recent,
                    accessibilityIdentifier: "evidence.homeThumbs.recentFriend"
                )
            }
        }
        .onAppear(perform: seedPhotoFixtures)
    }

    private var drawerThumbsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drawer search rows. Two-line Google / Maps under the 52pt thumb.")
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .accessibilityIdentifier("evidence.drawerThumbs")
            Text("Drawer · Google")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
                .accessibilityIdentifier("evidence.drawer.google")
            SaveSearchResultsComponent(response: Self.drawerResponse(photoURL: Self.googleThumbURL))
            Text("Drawer · own")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
                .accessibilityIdentifier("evidence.drawer.own")
            SaveSearchResultsComponent(response: Self.drawerResponse(photoURL: Self.ownThumbURL, title: "Own shot"))
        }
    }

    private var tripStopContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trip stop paper card. Two-line Google / Maps under the 70pt thumb.")
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .accessibilityIdentifier("evidence.tripStop")
            Text("Trip · Google")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
                .accessibilityIdentifier("evidence.trip.google")
            TripStopRow(
                stop: Self.tripStop(id: Self.tripGoogleStopID, name: "Harbor Oven"),
                place: Self.originPlace(id: Self.tripGooglePlaceID, name: "Harbor Oven", photoURL: Self.googleThumbURL),
                position: 1,
                isLast: false,
                canMoveEarlier: false,
                canMoveLater: true,
                onEdit: {},
                onMoveEarlier: {},
                onMoveLater: {}
            )
            Text("Trip · own")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
                .accessibilityIdentifier("evidence.trip.own")
            TripStopRow(
                stop: Self.tripStop(id: Self.tripOwnStopID, name: "Own shot"),
                place: Self.originPlace(id: Self.tripOwnPlaceID, name: "Own shot", photoURL: Self.ownThumbURL),
                position: 2,
                isLast: true,
                canMoveEarlier: true,
                canMoveLater: false,
                onEdit: {},
                onMoveEarlier: {},
                onMoveLater: {}
            )
        }
    }

    private var originFoodContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Origin food card. Two-line Google / Maps under the 326pt photo.")
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .accessibilityIdentifier("evidence.originFood")
            Text("Origin · Google")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
                .accessibilityIdentifier("evidence.origin.google")
            SaveOriginFoodCard(
                place: Self.originPlace(
                    id: Self.originGooglePlaceID,
                    name: "Harbor Oven",
                    photoURL: Self.googleThumbURL
                )
            )
            Text("Origin · own")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
                .accessibilityIdentifier("evidence.origin.own")
            SaveOriginFoodCard(
                place: Self.originPlace(
                    id: Self.originOwnPlaceID,
                    name: "Own shot",
                    photoURL: Self.ownThumbURL
                )
            )
        }
    }

    private var atlasThumbsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Atlas selected-place card. List/detail 56pt thumb, not a pin. Two-line Google / Maps under the thumb.")
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .accessibilityIdentifier("evidence.atlasThumbs")
            Text("Atlas · Google")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
                .accessibilityIdentifier("evidence.atlas.google")
            SaveAtlasLivePlaceCard(
                place: Self.originPlace(
                    id: Self.atlasGooglePlaceID,
                    name: "Harbor Oven",
                    photoURL: Self.googleThumbURL
                ),
                onClose: {},
                onOpen: {},
                onOpenAssistant: {},
                onPlanAround: {}
            )
            .frame(width: 372, height: 180)
            Text("Atlas · own")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
                .accessibilityIdentifier("evidence.atlas.own")
            SaveAtlasLivePlaceCard(
                place: Self.originPlace(
                    id: Self.atlasOwnPlaceID,
                    name: "Own shot",
                    photoURL: Self.ownThumbURL
                ),
                onClose: {},
                onOpen: {},
                onOpenAssistant: {},
                onPlanAround: {}
            )
            .frame(width: 372, height: 180)
        }
    }

    private func widthLockedScene(width: CGFloat, identifier: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("All marked surfaces at \(Int(width))pt.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .accessibilityIdentifier(identifier)
                homeThumbsScene()
                drawerThumbsContent
                tripStopContent
                originFoodContent
                atlasThumbsContent
            }
            .frame(width: width, alignment: .leading)
        }
        .onAppear(perform: seedPhotoFixtures)
    }

    private var xxxlScene: some View {
        widthLockedScene(width: 402, identifier: "evidence.layoutXXXL")
            .dynamicTypeSize(.xxxLarge)
    }

    private var xSmallScene: some View {
        widthLockedScene(width: 402, identifier: "evidence.layoutXSmall")
            .dynamicTypeSize(.xSmall)
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

    static let googleThumbURL = URL(
        string: "https://maps.googleapis.com/maps/api/place/photo?maxwidth=900&photo_reference=home-thumb"
    )!
    static let ownThumbURL = URL(string: "https://example.com/own-home-thumb.jpg")!
    static let friendThumbURL = URL(string: "https://cdn.instagram.com/friend-home-thumb.jpg")!

    static let tripGoogleStopID = UUID(uuidString: "20000000-0000-0000-0000-000000000306")!
    static let tripOwnStopID = UUID(uuidString: "20000000-0000-0000-0000-000000000307")!
    static let tripGooglePlaceID = UUID(uuidString: "21000000-0000-0000-0000-000000000306")!
    static let tripOwnPlaceID = UUID(uuidString: "21000000-0000-0000-0000-000000000307")!
    static let originGooglePlaceID = UUID(uuidString: "30000000-0000-0000-0000-000000000306")!
    static let originOwnPlaceID = UUID(uuidString: "30000000-0000-0000-0000-000000000307")!
    static let atlasGooglePlaceID = UUID(uuidString: "40000000-0000-0000-0000-000000000306")!
    static let atlasOwnPlaceID = UUID(uuidString: "40000000-0000-0000-0000-000000000307")!

    static func drawerResponse(photoURL: URL, title: String = "Harbor Oven") -> SaveSearchResponse {
        let result = SaveSearchResult(
            id: "evidence-drawer-\(title)",
            objectType: .mapVisibleUnsavedPlace,
            userState: .unsaved,
            title: title,
            subtitle: "Da'an, Taipei",
            statusLabel: "Not saved yet",
            sourceURL: nil,
            sourcePlatform: .googleMaps,
            category: .cafe,
            cityOrArea: "Taipei",
            latitude: 25.04,
            longitude: 121.54,
            rating: 4.6,
            reviewCount: 128,
            confidence: 0.82,
            missingInfo: [],
            evidence: [],
            recoveryQueries: [],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            canRunRecovery: false,
            isRecommendationShell: false,
            primaryAction: .savePlace,
            photoURL: photoURL.absoluteString
        )
        return SaveSearchResponse(
            query: title,
            fromYourSave: SaveSearchSection(
                id: "from-your-save",
                title: "From your Savvy",
                subtitle: "Memory first",
                results: []
            ),
            newRecommendations: SaveSearchSection(
                id: "public-discovery",
                label: "PUBLIC DISCOVERY",
                title: "Nearby",
                subtitle: "Not saved yet",
                results: [result]
            )
        )
    }

    static func tripStop(id: UUID, name: String) -> TripStop {
        TripStop(
            id: id,
            placeId: id,
            placeName: name,
            day: 1,
            orderIndex: 0,
            startTime: "10:00 AM",
            duration: 60,
            note: "Cafe stop"
        )
    }

    static func languageSettings(_ language: AppLanguage) -> AppLanguageSettings {
        let suite = "save.evidence.lang.\(language.rawValue)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(language.rawValue, forKey: "save.appLanguage")
        return AppLanguageSettings(userDefaults: defaults)
    }

    static func originPlace(id: UUID, name: String, photoURL: URL) -> Place {
        Place(
            id: id,
            name: name,
            address: "Da'an District, Taipei",
            latitude: 25.04,
            longitude: 121.54,
            category: .cafe,
            status: .wantToGo,
            note: "Neighborhood bakery",
            sourcePlatform: .other,
            businessPhotoUrls: [photoURL.absoluteString],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func seedPhotoFixtures() {
        CachedImageStore.shared.store(
            Self.renderPhoto(
                top: UIColor(red: 0.93, green: 0.90, blue: 0.82, alpha: 1),
                bottom: UIColor(red: 0.78, green: 0.84, blue: 0.74, alpha: 1),
                symbol: "cup.and.saucer.fill",
                tint: UIColor(red: 0.42, green: 0.28, blue: 0.16, alpha: 1)
            ),
            for: Self.googleThumbURL
        )
        CachedImageStore.shared.store(
            Self.renderPhoto(
                top: UIColor(red: 0.98, green: 0.86, blue: 0.70, alpha: 1),
                bottom: UIColor(red: 0.90, green: 0.55, blue: 0.42, alpha: 1),
                symbol: "person.crop.square",
                tint: UIColor(red: 0.28, green: 0.16, blue: 0.12, alpha: 1)
            ),
            for: Self.ownThumbURL
        )
        CachedImageStore.shared.store(
            Self.renderPhoto(
                top: UIColor(red: 0.72, green: 0.82, blue: 0.94, alpha: 1),
                bottom: UIColor(red: 0.42, green: 0.55, blue: 0.78, alpha: 1),
                symbol: "person.2.fill",
                tint: UIColor(red: 0.16, green: 0.22, blue: 0.38, alpha: 1)
            ),
            for: Self.friendThumbURL
        )
    }

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
