import MapKit
import SwiftUI

struct HomeAtlasScreen: View {
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            BrandHeader {
                Button(action: presentation.onCapture) {
                    HStack(spacing: 7) {
                        Image(systemName: "link")
                            .font(.system(size: 15, weight: .medium))
                        Text("Paste a link")
                            .font(AtlasType.display(13))
                    }
                    .foregroundStyle(AtlasPalette.ink)
                    .frame(width: 120, height: 35)
                    .background(AtlasPalette.paper, in: Capsule())
                    .overlay {
                        Capsule().stroke(AtlasPalette.line.opacity(0.34), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.capture")
            }
            .placed(x: 0, y: 48, width: 402, height: 51)

            Group {
                switch presentation.homeHero.scene {
                case .tokyo:
                    Image("HomeAtlasScene")
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .accessibilityLabel("Illustrated Tokyo atlas")
                        .accessibilityIdentifier(
                            presentation.homeHero.source == .referenceTokyo
                                ? "prototype.home.atlas"
                                : "home.cityAtlas.tokyo"
                        )
                case .taipei:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneTaipei",
                        accessibilityIdentifier: "home.cityAtlas.taipei"
                    )
                case .newYork:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneNewYork",
                        accessibilityIdentifier: "home.cityAtlas.newYork"
                    )
                case .shanghai:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneShanghai",
                        accessibilityIdentifier: "home.cityAtlas.shanghai"
                    )
                case .beijing:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneBeijing",
                        accessibilityIdentifier: "home.cityAtlas.beijing"
                    )
                case .guangzhou:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneGuangzhou",
                        accessibilityIdentifier: "home.cityAtlas.guangzhou"
                    )
                case .shenzhen:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneShenzhen",
                        accessibilityIdentifier: "home.cityAtlas.shenzhen"
                    )
                case .chengdu:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneChengdu",
                        accessibilityIdentifier: "home.cityAtlas.chengdu"
                    )
                case .chongqing:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneChongqing",
                        accessibilityIdentifier: "home.cityAtlas.chongqing"
                    )
                case .tianjin:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneTianjin",
                        accessibilityIdentifier: "home.cityAtlas.tianjin"
                    )
                case .hangzhou:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneHangzhou",
                        accessibilityIdentifier: "home.cityAtlas.hangzhou"
                    )
                case .nanjing:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneNanjing",
                        accessibilityIdentifier: "home.cityAtlas.nanjing"
                    )
                case .wuhan:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneWuhan",
                        accessibilityIdentifier: "home.cityAtlas.wuhan"
                    )
                case .xian:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneXian",
                        accessibilityIdentifier: "home.cityAtlas.xian"
                    )
                case .suzhou:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneSuzhou",
                        accessibilityIdentifier: "home.cityAtlas.suzhou"
                    )
                case .qingdao:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneQingdao",
                        accessibilityIdentifier: "home.cityAtlas.qingdao"
                    )
                case .xiamen:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneXiamen",
                        accessibilityIdentifier: "home.cityAtlas.xiamen"
                    )
                case .changsha:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneChangsha",
                        accessibilityIdentifier: "home.cityAtlas.changsha"
                    )
                case .seoul:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneSeoul",
                        accessibilityIdentifier: "home.cityAtlas.seoul"
                    )
                case .southernCalifornia:
                    AtlasIllustratedCityHero(
                        hero: presentation.homeHero,
                        assetName: "HomeAtlasSceneSouthernCalifornia",
                        accessibilityIdentifier: "home.cityAtlas.southernCalifornia"
                    )
                case .regionalMap:
                    AtlasRegionalHomeHero(hero: presentation.homeHero)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: presentation.onOpenHomeHero)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens this region in Map")
            .accessibilityIdentifier("home.hero.openMap")
            .placed(x: 0, y: 99, width: 402, height: 274)

            HomeReviewCard()
                .placed(x: 5, y: 354, width: 392, height: 182)

            HomePriorityCard()
                .placed(x: 10, y: 542, width: 382, height: 105)

            HomeRecentStamps()
                .placed(x: 10, y: 650, width: 382, height: 133)
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.home")
    }
}

private struct AtlasIllustratedCityHero: View {
    let hero: AtlasHomeHeroPresentation
    let assetName: String
    let accessibilityIdentifier: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    var body: some View {
        ZStack {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .clipped()

            Text(hero.title.uppercased())
                .font(AtlasType.strong(23))
                .tracking(2.4)
                .foregroundStyle(AtlasPalette.forest.opacity(0.76))
                .position(x: 201, y: 126)
                .accessibilityLabel(hero.title)
                .accessibilityIdentifier("home.region.title")

            Image("MemoMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 94, height: 94)
                .position(x: 201, y: 253)
                .offset(y: reduceMotion ? 0 : (isFloating ? -3 : 1))
                .accessibilityHidden(true)
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(hero.title), illustrated city atlas")
        .accessibilityIdentifier(accessibilityIdentifier)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
    }
}

private struct AtlasRegionalHomeHero: View {
    let hero: AtlasHomeHeroPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    var body: some View {
        ZStack {
            if let coordinate {
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            span: MKCoordinateSpan(
                                latitudeDelta: 0.12,
                                longitudeDelta: 0.12
                            )
                        )
                    ),
                    interactionModes: []
                ) {
                    Annotation("", coordinate: coordinate) {
                        regionalMarker
                    }
                }
                .mapStyle(.standard)
                .saturation(0.76)
                .contrast(0.96)
            } else {
                neutralAtlas
            }

            AtlasPalette.canvas
                .opacity(0.08)
                .allowsHitTesting(false)

            LinearGradient(
                colors: [
                    AtlasPalette.canvas.opacity(0.06),
                    .clear,
                    AtlasPalette.canvas.opacity(0.90),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack {
                HStack {
                    Spacer()
                    regionalBadge
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)

                Spacer()

                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hero.title)
                            .font(AtlasType.strong(25))
                            .foregroundStyle(AtlasPalette.forest)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .accessibilityIdentifier("home.region.title")

                        Text(hero.subtitle)
                            .font(AtlasType.body(12))
                            .foregroundStyle(AtlasPalette.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: landmarkSymbol)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(AtlasPalette.forest)
                        .frame(width: 48, height: 48)
                        .background(AtlasPalette.paper.opacity(0.94), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(AtlasPalette.line.opacity(0.34), lineWidth: 1)
                        }
                        .offset(y: reduceMotion ? 0 : (isFloating ? -4 : 2))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 17)
            }
        }
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(hero.title), \(hero.subtitle)")
        .accessibilityIdentifier("home.regionalHero")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = hero.latitude, let longitude = hero.longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var regionalMarker: some View {
        ZStack {
            Circle()
                .fill(AtlasPalette.coral.opacity(0.20))
                .frame(width: isFloating && !reduceMotion ? 58 : 42)
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(AtlasPalette.coral, in: Circle())
                .overlay {
                    Circle()
                        .stroke(AtlasPalette.paper, lineWidth: 3)
                }
        }
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: 2.8).repeatForever(autoreverses: true),
            value: isFloating
        )
    }

    private var regionalBadge: some View {
        Label(badgeTitle, systemImage: "location.circle.fill")
            .font(AtlasType.display(12))
            .foregroundStyle(AtlasPalette.ink)
            .padding(.horizontal, 11)
            .frame(minHeight: 31)
            .background(AtlasPalette.paper.opacity(0.94), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(AtlasPalette.line.opacity(0.30), lineWidth: 1)
            }
    }

    private var badgeTitle: String {
        switch hero.source {
        case .currentRegion:
            return "Around you"
        case .savedPlace:
            return "From your Map Stamps"
        case .neutral, .referenceTokyo:
            return "Your atlas"
        }
    }

    private var landmarkSymbol: String {
        switch hero.countryCode?.uppercased() {
        case "JP", "TW", "KR", "CN", "TH", "SG":
            return "building.columns.fill"
        case "US", "CA", "MX":
            return "building.2.fill"
        case "FR", "GB", "DE", "IT", "ES", "NL", "CH", "AT":
            return "tram.fill"
        case "AU", "NZ":
            return "water.waves"
        default:
            return "mountain.2.fill"
        }
    }

    private var neutralAtlas: some View {
        LinearGradient(
            colors: [
                AtlasPalette.sky.opacity(0.72),
                AtlasPalette.mint.opacity(0.72),
                AtlasPalette.canvas,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 132, weight: .ultraLight))
                .foregroundStyle(AtlasPalette.forest.opacity(0.18))
        }
    }
}

private struct HomeReviewCard: View {
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(AtlasPalette.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(AtlasPalette.line.opacity(0.30), lineWidth: 1)
                }
                .shadow(color: AtlasPalette.ink.opacity(0.04), radius: 4, y: 1)

            Text(reviewHeadline)
                .font(AtlasType.strong(24))
                .foregroundStyle(AtlasPalette.forest)
                .position(x: 196, y: 32)

            Text("Review and decide what’s worth saving.")
                .font(AtlasType.body(13))
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 196, y: 58)

            Button(action: presentation.onReviewAll) {
                HStack {
                    Spacer()
                    Text("Review clues")
                        .font(AtlasType.strong(16))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .regular))
                        .padding(.trailing, 14)
                }
                .foregroundStyle(.white)
                .frame(width: 296, height: 41)
                .background(
                    LinearGradient(
                        colors: [AtlasPalette.coral, AtlasPalette.coral.opacity(0.90)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .position(x: 196, y: 93)
            .accessibilityIdentifier("home.review")

            Rectangle()
                .fill(AtlasPalette.line.opacity(0.30))
                .frame(width: 1, height: 39)
                .position(x: 196, y: 151)

            HomeMetric(
                value: "\(presentation.reviewCount)",
                label: "to review",
                systemName: "timer",
                tint: AtlasPalette.lavender
            )
            .frame(width: 150, height: 42)
            .position(x: 121, y: 150)

            HomeMetric(
                value: "\(presentation.mapStampCount)",
                label: "Map Stamps",
                systemName: "arrow.up.right",
                tint: AtlasPalette.mint
            )
            .frame(width: 150, height: 42)
            .position(x: 274, y: 150)
        }
    }

    private var reviewHeadline: String {
        let count = presentation.reviewCount
        guard count > 0 else { return "You’re all caught up" }
        return "\(count) \(count == 1 ? "clue needs" : "clues need") your help"
    }
}

private struct HomeMetric: View {
    let value: String
    let label: String
    let systemName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AtlasPalette.ink)
                .frame(width: 38, height: 38)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: -1) {
                Text(value)
                    .font(AtlasType.strong(22))
                    .foregroundStyle(AtlasPalette.forest)
                Text(label)
                    .font(AtlasType.body(12))
                    .foregroundStyle(AtlasPalette.muted)
            }
        }
    }
}

private struct HomePriorityCard: View {
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        let priority = presentation.homePriority

        VStack(alignment: .leading, spacing: 8) {
            Text(priority.eyebrow)
                .font(AtlasType.strong(11))
                .tracking(1.2)
                .foregroundStyle(AtlasPalette.muted)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(priority.title)
                    .font(AtlasType.strong(21))
                    .foregroundStyle(AtlasPalette.forest)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let badge = priority.badge {
                    Text(badge)
                        .font(AtlasType.display(12))
                        .foregroundStyle(AtlasPalette.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(priorityBadgeColor, in: Capsule())
                }
            }

            HStack(spacing: 9) {
                Image(systemName: priority.systemName)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(AtlasPalette.forest)

                Text(priority.detail)
                    .font(AtlasType.regular(12))
                    .foregroundStyle(AtlasPalette.muted)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AtlasPalette.muted)
            }

            Rectangle()
                .fill(AtlasPalette.line.opacity(0.30))
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: presentation.onOpenHomePriority)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(priority.eyebrow), \(priority.title), \(priority.detail)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var priorityBadgeColor: Color {
        switch presentation.homePriority.kind {
        case .currentTrip:
            AtlasPalette.lavender
        case .upcomingTrip:
            AtlasPalette.honey.opacity(0.72)
        case .planFromStamps, .capture:
            AtlasPalette.mint
        }
    }

    private var accessibilityIdentifier: String {
        switch presentation.homePriority.kind {
        case .currentTrip:
            "home.trip.current"
        case .upcomingTrip:
            "home.trip.upcoming"
        case .planFromStamps:
            "home.priority.plan"
        case .capture:
            "home.priority.capture"
        }
    }
}

private struct HomeRecentStamps: View {
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("RECENT MAP STAMPS")
                .font(AtlasType.strong(11))
                .tracking(1.1)
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 78, y: 14)

            Button("See all", action: presentation.onOpenSaves)
                .font(AtlasType.display(12))
                .foregroundStyle(AtlasPalette.ink)
                .buttonStyle(.plain)
                .position(x: 354, y: 14)
                .accessibilityIdentifier("home.saves")

            ForEach(Array(presentation.recentPlaces.prefix(2).enumerated()), id: \.element.id) { index, place in
                HomeStampRow(place: place) {
                    presentation.onOpenPlace(place.id)
                }
                .placed(x: 0, y: 27 + CGFloat(index * 51), width: 382, height: 51)
            }
        }
        .accessibilityIdentifier("home.recentSaves")
    }
}

private struct HomeStampRow: View {
    let place: AtlasPlacePresentation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                RoundStamp(text: "", style: .mapStamp)

                VStack(alignment: .leading, spacing: 0) {
                    Text(place.name)
                        .font(AtlasType.strong(15))
                        .foregroundStyle(AtlasPalette.ink)
                    Text("\(place.area) · Confirmed")
                        .font(AtlasType.regular(11))
                        .foregroundStyle(AtlasPalette.muted)
                }

                Spacer()

                Text(place.relativeDay)
                    .font(AtlasType.regular(11))
                    .foregroundStyle(AtlasPalette.muted)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AtlasPalette.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
        .accessibilityIdentifier("saves.place.\(place.id)")
    }
}

struct TripsAtlasScreen: View {
    @Environment(\.atlasPresentation) private var presentation

    /// Spec P3: Trips is a flow layout now, not a fixed `.placed()` canvas.
    /// The tab bar overlays the canvas from y 786, so the pinned bottom row
    /// keeps this much clearance.
    private static let tabBarClearance: CGFloat = AtlasMetrics.height - 786 + 14

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: AtlasMetrics.statusBarHeight)
                    .accessibilityHidden(true)

                BrandHeader {
                    Button(action: presentation.onCapture) {
                        Image(systemName: "link")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AtlasPalette.ink)
                            .frame(width: 40, height: 40)
                            .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 13))
                            .overlay {
                                RoundedRectangle(cornerRadius: 13)
                                    .stroke(AtlasPalette.line.opacity(0.30), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Paste or share a link")
                    .accessibilityIdentifier("trips.capture")
                }
                .frame(height: 50)

                VStack(alignment: .leading, spacing: 1) {
                    Text("YOUR LITTLE ATLAS")
                        .font(AtlasType.display(11))
                        .tracking(1.1)
                        .foregroundStyle(AtlasPalette.muted)
                    Text("Trips")
                        .font(AtlasType.strong(30))
                        .foregroundStyle(AtlasPalette.forest)
                    Text("Confirmed Map Stamps, arranged into journeys.")
                        .font(AtlasType.regular(14))
                        .foregroundStyle(AtlasPalette.muted)
                }
                .padding(.horizontal, 13)
                .padding(.top, 7)

                heroScene
                    .padding(.top, 7)

                HStack {
                    Text("NEXT JOURNEYS")
                        .font(AtlasType.strong(11))
                        .tracking(1.1)
                        .foregroundStyle(AtlasPalette.muted)
                    Spacer()
                    Text("\(presentation.tripSummaries.count) total")
                        .font(AtlasType.regular(12))
                        .foregroundStyle(AtlasPalette.muted)
                }
                .padding(.horizontal, 17)
                .padding(.top, 16)

                if !presentation.tripRecommendations.isEmpty {
                    // Planning suggestions built from the user's own confirmed
                    // Map Stamps — Trips proposes instead of waiting to be asked.
                    VStack(spacing: 9) {
                        ForEach(presentation.tripRecommendations) { recommendation in
                            TripRecommendationCard(
                                recommendation: recommendation,
                                onPlan: { presentation.onPlanRecommendation(recommendation.planningQuery) }
                            )
                        }
                    }
                    .padding(.horizontal, 17)
                    .padding(.top, 11)
                } else if presentation.tripSummaries.dropFirst().isEmpty {
                    // Spec P3: the old empty 208pt paper panel collapses to a
                    // one-line hint.
                    Text("Your next trip can begin with one confirmed Map Stamp.")
                        .font(AtlasType.regular(13))
                        .foregroundStyle(AtlasPalette.muted)
                        .padding(.horizontal, 17)
                        .padding(.top, 10)
                } else {
                    VStack(spacing: 11) {
                        ForEach(Array(presentation.tripSummaries.dropFirst().prefix(2))) { trip in
                            CompactTripTicket(trip: trip)
                                .frame(height: 98)
                        }
                    }
                    .padding(.horizontal, 17)
                    .padding(.top, 12)
                }

                Spacer(minLength: 12)

                HStack(spacing: 10) {
                    TripsAskField(onSubmit: presentation.onAskSubmit)

                    Button(action: presentation.onCreateTrip) {
                        Image(systemName: "plus")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(AtlasPalette.coral, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start a new Trip")
                    .accessibilityIdentifier("trips.create")
                }
                .padding(.horizontal, 17)
                .padding(.bottom, Self.tabBarClearance)
            }
            .frame(width: AtlasMetrics.width, alignment: .topLeading)
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trips.home")
    }

    /// Illustrated map scene with the featured trip postcard resting on its
    /// lower half and Memo peeking over the top edge.
    private var heroScene: some View {
        ZStack(alignment: .top) {
            Image("MapAtlasScene")
                .resizable()
                .scaledToFill()
                .saturation(0.82)
                .frame(width: AtlasMetrics.width, height: 211)
                .clipped()
                .overlay(AtlasPalette.canvas.opacity(0.08))
                .accessibilityHidden(true)

            MemoMark(size: 67)
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(.trailing, 32)
                .padding(.top, 8)
                .accessibilityHidden(true)

            Group {
                if let featured = presentation.tripSummaries.first {
                    FeaturedTripPostcard(trip: featured)
                } else {
                    EmptyTripPostcard()
                }
            }
            .frame(height: 139)
            .padding(.horizontal, 17)
            .padding(.top, 72)
        }
        .frame(height: 211)
    }
}

/// One-tap planning suggestion derived from confirmed Map Stamps.
private struct TripRecommendationCard: View {
    let recommendation: AtlasTripRecommendationPresentation
    let onPlan: () -> Void

    var body: some View {
        Button(action: onPlan) {
            HStack(spacing: 11) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AtlasPalette.forest)
                    .frame(width: 34, height: 34)
                    .background(AtlasPalette.mint.opacity(0.62), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    Text(recommendation.title)
                        .font(AtlasType.strong(15))
                        .foregroundStyle(AtlasPalette.forest)
                        .lineLimit(1)

                    Text(recommendation.subtitle)
                        .font(AtlasType.regular(12))
                        .foregroundStyle(AtlasPalette.muted)
                        .lineLimit(1)

                    if !recommendation.sampleNames.isEmpty {
                        Text(recommendation.sampleNames.joined(separator: " · "))
                            .font(AtlasType.editorial(11))
                            .foregroundStyle(AtlasPalette.muted.opacity(0.9))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(AtlasPalette.coral, in: Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AtlasPalette.line.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recommendation.title)
        .accessibilityHint(recommendation.subtitle)
        .accessibilityIdentifier("trips.recommendation.\(recommendation.id)")
    }
}

/// Trips P1: a real inline ask input replacing the old fake-input Button.
/// Idle rendering must stay pixel-equal to the previous button (placeholder is
/// drawn by hand, not by TextField) so Atlas parity crops keep passing.
private struct TripsAskField: View {
    let onSubmit: (String) -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    /// The resting row sits under the software keyboard (row bottom y≈772 in
    /// the flow layout, keyboard top ≈538 in canvas units). A fixed lift
    /// clears every current iPhone keyboard after ReferenceViewport scaling,
    /// so no keyboard-frame observation is needed.
    private let focusedLift: CGFloat = 264

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AtlasPalette.forest)

            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("Ask SAV-E to plan from your Map Stamps")
                        .font(AtlasType.strong(14))
                        .foregroundStyle(AtlasPalette.ink)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }

                TextField("", text: $query)
                    .font(AtlasType.strong(14))
                    .foregroundStyle(AtlasPalette.ink)
                    .tint(AtlasPalette.coral)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .accessibilityLabel("Ask SAV-E to plan from your Map Stamps")
                    .accessibilityIdentifier("trips.assistant.input")
            }

            Spacer(minLength: 0)

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 31, height: 31)
                    .background(AtlasPalette.coral, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask SAV-E")
            .accessibilityIdentifier("trips.assistant.submit")
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AtlasPalette.line.opacity(0.34), lineWidth: 1)
        }
        .shadow(
            color: AtlasPalette.ink.opacity(focused ? 0.14 : 0.06),
            radius: focused ? 10 : 6,
            y: focused ? 4 : 2
        )
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .offset(y: focused ? -focusedLift : 0)
        // Same curve as SaveTheme.Motion.standardSpring; SaveTheme itself is
        // not compiled into the AtlasPostcardPrototype target.
        .animation(.spring(response: 0.52, dampingFraction: 0.86), value: focused)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trips.assistant")
    }

    private func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            focused = true
            return
        }
        focused = false
        query = ""
        onSubmit(trimmed)
    }
}

private struct FeaturedTripPostcard: View {
    @Environment(\.atlasPresentation) private var presentation
    let trip: AtlasTripSummaryPresentation

    var body: some View {
        Button {
            presentation.onOpenTripID(trip.id)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(trip.timing)
                        .font(AtlasType.strong(10))
                        .tracking(1)
                        .foregroundStyle(AtlasPalette.forest)
                        .padding(.horizontal, 10)
                        .frame(height: 25)
                        .background(AtlasPalette.mint, in: Capsule())
                    Spacer()
                    Text(trip.dateRange)
                        .font(AtlasType.display(12))
                        .foregroundStyle(AtlasPalette.muted)
                }

                Text(trip.name)
                    .font(AtlasType.strong(25))
                    .foregroundStyle(AtlasPalette.forest)

                HStack(spacing: 7) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(trip.city.isEmpty ? "Destination to decide" : trip.city)
                    Text("·")
                    Text("\(trip.stopCount) \(trip.stopCount == 1 ? "stop" : "stops")")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(AtlasType.regular(13))
                .foregroundStyle(AtlasPalette.muted)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(AtlasPalette.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(AtlasPalette.line.opacity(0.32), lineWidth: 1)
            }
            .shadow(color: AtlasPalette.ink.opacity(0.07), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trips.card.\(trip.id)")
    }
}

private struct CompactTripTicket: View {
    @Environment(\.atlasPresentation) private var presentation
    let trip: AtlasTripSummaryPresentation

    var body: some View {
        Button {
            presentation.onOpenTripID(trip.id)
        } label: {
            HStack(spacing: 13) {
                VStack(spacing: 1) {
                    Image(systemName: "map")
                        .font(.system(size: 20, weight: .regular))
                    Text("\(trip.stopCount)")
                        .font(AtlasType.strong(14))
                }
                .foregroundStyle(AtlasPalette.forest)
                .frame(width: 52, height: 62)
                .background(ticketTint, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.timing)
                        .font(AtlasType.display(10))
                        .tracking(0.9)
                        .foregroundStyle(AtlasPalette.muted)
                    Text(trip.name)
                        .font(AtlasType.strong(18))
                        .foregroundStyle(AtlasPalette.forest)
                        .lineLimit(1)
                    Text([trip.city, trip.dateRange].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(AtlasType.regular(12))
                        .foregroundStyle(AtlasPalette.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AtlasPalette.ink)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 94)
            .atlasPaper(radius: 18, shadow: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("trips.card.\(trip.id)")
    }

    private var ticketTint: Color {
        trip.timing == "UPCOMING" ? AtlasPalette.sky : AtlasPalette.lavender
    }
}

private struct EmptyTripPostcard: View {
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "map")
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(AtlasPalette.forest)
            Text("No journeys yet")
                .font(AtlasType.strong(21))
                .foregroundStyle(AtlasPalette.forest)
            Text("Confirm a place, then start your first Trip.")
                .font(AtlasType.regular(13))
                .foregroundStyle(AtlasPalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .atlasPaper(radius: 20, shadow: true)
    }
}

struct SavesPocketScreen: View {
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            BrandHeader {
                Button(action: presentation.onCapture) {
                    Image(systemName: "link")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(AtlasPalette.ink)
                        .frame(width: 40, height: 40)
                        .background(AtlasPalette.honey.opacity(0.78), in: RoundedRectangle(cornerRadius: 13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(AtlasPalette.line.opacity(0.28), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("root.capture")
            }
            .placed(x: 0, y: 48, width: 402, height: 50)

            SavesTitleBlock()
                .placed(x: 10, y: 103, width: 382, height: 101)
                .accessibilityIdentifier("prototype.saves.title")

            Image("SavesMemoSorting")
                .resizable()
                .scaledToFit()
                .placed(x: 286, y: 100, width: 112, height: 112)
                .accessibilityLabel("Memo sorting saved cards")

            HStack(spacing: 10) {
                Button(action: presentation.onSelectReview) {
                    PocketCount(
                        label: "Review",
                        value: "\(presentation.reviewCount)",
                        tint: AtlasPalette.coral.opacity(0.52)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("saves.segment.review")

                Button(action: presentation.onSelectMapStamps) {
                    PocketCount(
                        label: "Map Stamps",
                        value: "\(presentation.mapStampCount)",
                        tint: AtlasPalette.mint
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("saves.segment.mapStamps")
            }
            .placed(x: 10, y: 216, width: 382, height: 43)
            .accessibilityIdentifier("prototype.saves.counts")

            SavesTickets()
                .placed(x: 10, y: 278, width: 382, height: 333)

            SavesEnvelopePanel()
                .placed(x: 0, y: 568, width: 402, height: 207)
                .accessibilityIdentifier("prototype.saves.envelope")
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.saves")
    }
}

private struct SavesTitleBlock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("YOUR PLACE MEMORY")
                .font(AtlasType.strong(11))
                .tracking(1.15)
                .foregroundStyle(AtlasPalette.muted)

            Text("Saves")
                .font(AtlasType.strong(34))
                .foregroundStyle(AtlasPalette.forest)

            Text("Clues you’ve saved from links and notes.")
                .font(AtlasType.body(15))
                .foregroundStyle(AtlasPalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PocketCount: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
            Text(value)
                .font(AtlasType.strong(16))
                .frame(width: 25, height: 25)
                .background(tint, in: Circle())
        }
        .font(AtlasType.display(14))
        .foregroundStyle(AtlasPalette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AtlasPalette.line.opacity(0.30), lineWidth: 1)
        }
    }
}

private struct SavesEnvelopePanel: View {
    private let sealInk = Color(red: 0.66, green: 0.32, blue: 0.22)
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("SavesEnvelope")
                .resizable()
                .scaledToFill()
                .clipped()

            Text("Full review queue")
                .font(AtlasType.editorial(20))
                .foregroundStyle(AtlasPalette.ink)
                .position(x: 181, y: 82)

            Path { path in
                path.move(to: CGPoint(x: 111, y: 105))
                path.addLine(to: CGPoint(x: 253, y: 105))
            }
            .stroke(
                AtlasPalette.line.opacity(0.68),
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
            )

            VStack(spacing: -3) {
                Text("\(presentation.reviewCount)")
                    .font(AtlasType.editorial(29))
                Text("need your\nreview")
                    .font(AtlasType.regular(10))
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
            }
            .foregroundStyle(sealInk)
            .frame(width: 58, height: 78)
            .position(x: 333, y: 91)
        }
        .frame(width: 402, height: 207)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Full review queue, \(presentation.reviewCount) need your review")
    }
}

private struct SavesTickets: View {
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(presentation.reviewItems.prefix(3).enumerated()), id: \.element.id) { index, item in
                ReviewTicket(item: item) {
                    presentation.onOpenReview(item.id)
                }
                .placed(
                    x: 0,
                    y: ticketY(index),
                    width: 382,
                    height: index == 2 ? 118 : 111
                )
            }
        }
    }

    private func ticketY(_ index: Int) -> CGFloat {
        [0, 107, 210][min(index, 2)]
    }
}

private struct ReviewTicket: View {
    let item: AtlasReviewPresentation
    let onOpen: () -> Void

    private var tint: Color {
        item.kind == .sourceOnly
            ? Color(red: 1.0, green: 0.79, blue: 0.72)
            : AtlasPalette.sky
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScallopedRectangle(depth: 3, pitch: 10)
                .fill(tint.opacity(0.94))
                .shadow(color: AtlasPalette.ink.opacity(0.06), radius: 4, y: 2)

            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AtlasPalette.paper)
                .padding(5)

            PerforatedMedallion(systemName: item.icon, tint: tint)
                .position(x: 47, y: 55)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.eyebrow)
                    .font(AtlasType.strong(11))
                    .tracking(0.6)
                    .foregroundStyle(
                        item.kind == .sourceOnly ? AtlasPalette.coral : Color(red: 0.10, green: 0.48, blue: 0.70)
                    )
                Text(item.name)
                    .font(AtlasType.strong(19))
                    .foregroundStyle(AtlasPalette.ink)
                    .lineLimit(1)
                Text(item.detail)
                    .font(AtlasType.body(13))
                    .foregroundStyle(AtlasPalette.muted)
            }
            .frame(width: 190, alignment: .leading)
            .position(x: 181, y: 55)

            Button(action: onOpen) {
                Text(item.actionTitle)
                    .font(AtlasType.display(14))
                    .foregroundStyle(AtlasPalette.ink)
                    .frame(width: item.kind == .sourceOnly ? 82 : 68, height: 38)
                    .background(tint.opacity(0.84), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AtlasPalette.ink.opacity(0.22), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .frame(width: item.kind == .sourceOnly ? 88 : 74, height: 44)
                .position(x: item.kind == .sourceOnly ? 313 : 316, y: 55)
                .accessibilityLabel("\(item.actionTitle) \(item.name)")
                .accessibilityIdentifier("saves.reviewCandidate.\(item.id)")
        }
    }
}

struct TripPlanScreen: View {
    let onBack: () -> Void
    let onShare: (() -> Void)?
    @Environment(\.atlasPresentation) private var presentation

    init(onBack: @escaping () -> Void, onShare: (() -> Void)? = nil) {
        self.onBack = onBack
        self.onShare = onShare
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            TripHeader(onBack: onBack, onShare: onShare)
                .placed(x: 0, y: 48, width: 402, height: 54)

            DayTabs()
                .placed(x: 0, y: 102, width: 402, height: 47)

            PlanTitleBlock()
                .placed(x: 6, y: 168, width: 390, height: 58)

            Image("PlanRouteRibbon")
                .resizable()
                .scaledToFill()
                .clipped()
                .placed(x: 0, y: 229, width: 64, height: 493)
                .accessibilityLabel("Day 2 route")
                .accessibilityIdentifier("prototype.plan.route")

            PlanStops(stops: Array(presentation.tripStops.prefix(4)))
                .placed(x: 61, y: 238, width: 332, height: 478)

            Button(action: presentation.onAddStop) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18, weight: .regular))
                    Text("Add stop")
                        .font(AtlasType.display(16))
                }
                .foregroundStyle(AtlasPalette.ink)
                .frame(width: 140, height: 40)
                .background(AtlasPalette.mint, in: Capsule())
                .overlay {
                    Capsule().stroke(AtlasPalette.forest.opacity(0.30), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .placed(x: 122, y: 728, width: 140, height: 40)
            .accessibilityIdentifier("trip.plan.addStop")
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.plan")
    }
}

struct TripHeader: View {
    let onBack: () -> Void
    let onShare: (() -> Void)?
    @Environment(\.atlasPresentation) private var presentation

    init(onBack: @escaping () -> Void, onShare: (() -> Void)? = nil) {
        self.onBack = onBack
        self.onShare = onShare
    }

    var body: some View {
        ZStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(AtlasPalette.ink)
                    .frame(width: 40, height: 40)
                    .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(AtlasPalette.line.opacity(0.32), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .position(x: 22, y: 27)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("trip.back")

            Text(presentation.tripName)
                .font(AtlasType.strong(23))
                .foregroundStyle(AtlasPalette.forest)

            if let onShare {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AtlasPalette.forest)
                        .frame(width: 40, height: 40)
                        .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(AtlasPalette.line.opacity(0.32), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .position(x: 375, y: 27)
                .accessibilityLabel("Share Trip")
                .accessibilityIdentifier("trip.share.action")
            } else {
                MemoMark(size: 48)
                    .position(x: 375, y: 26)
            }
        }
    }
}

private struct DayTabs: View {
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...max(1, presentation.tripDayCount), id: \.self) { day in
                Button {
                    presentation.onSelectDay(day)
                } label: {
                    DayTab(
                        title: "Day \(day)",
                        tint: dayTint(day),
                        selected: day == presentation.selectedDay
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(day == presentation.selectedDay ? .isSelected : [])
                .accessibilityIdentifier("trip.day.\(day)")
            }
        }
        .padding(.horizontal, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtlasPalette.line.opacity(0.26))
                .frame(height: 1)
        }
    }

    private func dayTint(_ day: Int) -> Color {
        guard day == presentation.selectedDay else { return AtlasPalette.paper }
        return day.isMultiple(of: 2) ? AtlasPalette.mint : AtlasPalette.lavender
    }
}

private struct DayTab: View {
    let title: String
    let tint: Color
    let selected: Bool

    var body: some View {
        Text(title)
            .font(selected ? AtlasType.strong(15) : AtlasType.body(15))
            .foregroundStyle(AtlasPalette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 13,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 13
                )
            )
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 13,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 13
                )
                .stroke(AtlasPalette.line.opacity(selected ? 0.32 : 0.24), lineWidth: 1)
            }
    }
}

private struct PlanTitleBlock: View {
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.tripDateLabel)
                    .font(AtlasType.strong(11))
                    .tracking(0.8)
                    .foregroundStyle(AtlasPalette.muted)

                Text("\(presentation.tripCity) highlights")
                    .font(AtlasType.strong(26))
                    .foregroundStyle(AtlasPalette.forest)
            }

            Spacer()

            Text("\(presentation.tripStops.count) stops")
                .font(AtlasType.display(14))
                .foregroundStyle(AtlasPalette.ink)
                .frame(width: 70, height: 29)
                .background(AtlasPalette.mint, in: Capsule())
                .overlay {
                    Capsule().stroke(AtlasPalette.forest.opacity(0.24), lineWidth: 1)
                }
        }
    }
}

private struct PlanStops: View {
    let stops: [AtlasStopPresentation]
    private let frames: [CGRect] = [
        CGRect(x: 0, y: 0, width: 332, height: 101),
        CGRect(x: 0, y: 122, width: 332, height: 105),
        CGRect(x: 0, y: 250, width: 332, height: 105),
        CGRect(x: 0, y: 376, width: 332, height: 102),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                AtlasItineraryStop(stop: stop)
                    .placed(
                        x: frames[index].minX,
                        y: frames[index].minY,
                        width: frames[index].width,
                        height: frames[index].height
                    )
            }
        }
    }
}

private struct AtlasItineraryStop: View {
    let stop: AtlasStopPresentation
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        Button {
            presentation.onOpenStop(stop.id)
        } label: {
            HStack(spacing: 18) {
                Image(stop.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 74, height: stop.imageHeight)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.name)
                        .font(AtlasType.strong(17))
                        .foregroundStyle(AtlasPalette.ink)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 13, weight: .regular))
                        Text(stop.time)
                            .font(AtlasType.body(13))
                    }
                    .foregroundStyle(AtlasPalette.muted)

                    Text(stop.note)
                        .font(AtlasType.regular(13))
                        .foregroundStyle(AtlasPalette.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(AtlasPalette.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(stop.name)")
        .padding(.leading, 11)
        .padding(.trailing, 16)
        .background(AtlasPalette.paper.opacity(0.97), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AtlasPalette.line.opacity(0.24), lineWidth: 1)
        }
        .accessibilityIdentifier("trip.stop.\(stop.id).edit")
    }
}

struct TripAtlasMapScreen: View {
    let onBack: () -> Void
    let onShare: (() -> Void)?
    @Environment(\.atlasPresentation) private var presentation

    init(onBack: @escaping () -> Void, onShare: (() -> Void)? = nil) {
        self.onBack = onBack
        self.onShare = onShare
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            TripHeader(onBack: onBack, onShare: onShare)
                .placed(x: 0, y: 48, width: 402, height: 54)
                .accessibilityIdentifier("prototype.trip.map.header")

            Image("MapAtlasScene")
                .resizable()
                .scaledToFill()
                .clipped()
                .placed(x: 0, y: 102, width: 402, height: 450)
                .accessibilityLabel("Tokyo Weekend route map")
                .accessibilityIdentifier("prototype.trip.map.atlas")

            HStack(spacing: 7) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 14, weight: .regular))
                Text("DAY \(presentation.selectedDay) · \(presentation.tripStops.count) STOPS")
                    .font(AtlasType.display(13))
            }
            .foregroundStyle(AtlasPalette.ink)
            .frame(width: 145, height: 31)
            .background(AtlasPalette.mint, in: Capsule())
            .overlay {
                Capsule().stroke(AtlasPalette.forest.opacity(0.24), lineWidth: 1)
            }
            .placed(x: 128, y: 114, width: 145, height: 31)
            .accessibilityLabel(
                "Day \(presentation.selectedDay), \(presentation.tripStops.count) stops"
            )

            TripMapPlaceCard()
                .placed(x: 15, y: 550, width: 372, height: 226)
                .accessibilityIdentifier("prototype.trip.map.placeCard")
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.trip.map")
    }
}

struct TripMapPlaceCard: View {
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AtlasPalette.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AtlasPalette.line.opacity(0.32), lineWidth: 1)
                }
                .shadow(color: AtlasPalette.ink.opacity(0.06), radius: 7, y: 2)

            RoundStamp(text: "2", style: .tripStop)
                .position(x: 44, y: 42)

            VStack(alignment: .leading, spacing: 1) {
                Text(stopEyebrow)
                    .font(AtlasType.display(11))
                    .tracking(0.7)
                    .foregroundStyle(AtlasPalette.muted)

                Text(presentation.selectedMapPlace.name)
                    .font(AtlasType.strong(23))
                    .foregroundStyle(AtlasPalette.forest)
            }
            .position(x: 176, y: 40)

            HStack(spacing: 6) {
                Image(systemName: "star.circle")
                    .font(.system(size: 13, weight: .regular))
                Text("Confirmed Map Stamp")
                    .font(AtlasType.display(13))
            }
            .foregroundStyle(AtlasPalette.ink)
            .frame(width: 183, height: 30)
            .background(AtlasPalette.mint, in: Capsule())
            .overlay {
                Capsule().stroke(AtlasPalette.forest.opacity(0.20), lineWidth: 1)
            }
            .position(x: 168, y: 91)

            Text(routeSummary)
                .font(AtlasType.body(13))
                .foregroundStyle(AtlasPalette.muted)
                .lineLimit(1)
                .position(x: 186, y: 132)

            Text(nextStopSummary)
                .font(AtlasType.regular(14))
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 171, y: 158)

            Button {
                presentation.onOpenPlace(presentation.selectedMapPlace.id)
            } label: {
                HStack(spacing: 10) {
                    Text("Open stop")
                        .font(AtlasType.strong(17))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .regular))
                }
                .foregroundStyle(.white)
                .frame(width: 160, height: 42)
                .background(AtlasPalette.coral, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .position(x: 95, y: 198)
            .accessibilityIdentifier("trip.map.openStop")
        }
    }

    private var selectedStopIndex: Int {
        let index = presentation.tripStops.firstIndex {
            $0.name == presentation.selectedMapPlace.name
        } ?? min(1, max(0, presentation.tripStops.count - 1))
        return index
    }

    private var stopEyebrow: String {
        guard presentation.tripStops.indices.contains(selectedStopIndex) else {
            return "CONFIRMED STOP"
        }
        let stop = presentation.tripStops[selectedStopIndex]
        return "STOP \(selectedStopIndex + 1) · \(stop.time)"
    }

    private var routeSummary: String {
        presentation.tripStops.prefix(3).map(\.name).joined(separator: "  →  ")
    }

    private var nextStopSummary: String {
        let nextIndex = selectedStopIndex + 1
        guard presentation.tripStops.indices.contains(nextIndex) else {
            return "Last stop of the day"
        }
        let next = presentation.tripStops[nextIndex]
        return "Next stop · \(next.name) at \(next.time)"
    }
}

struct TripSharePlaceholderScreen: View {
    let onBack: () -> Void

    var body: some View {
        TripPrototypePlaceholder(
            onBack: onBack,
            icon: "square.and.arrow.up",
            eyebrow: "TRIP SHARE",
            title: "Share this Trip",
            message: "SAV-E link and KML export will appear here.",
            note: "Not wired in this visual prototype",
            tint: AtlasPalette.lavender,
            identifier: "prototype.trip.share"
        )
    }
}

private struct TripPrototypePlaceholder: View {
    let onBack: () -> Void
    let icon: String
    let eyebrow: String
    let title: String
    let message: String
    let note: String
    let tint: Color
    let identifier: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            TripHeader(onBack: onBack)
                .placed(x: 0, y: 48, width: 402, height: 54)
                .accessibilityIdentifier("\(identifier).header")

            VStack(spacing: 18) {
                MemoMark(size: 88)
                    .frame(height: 104)

                Image(systemName: icon)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(AtlasPalette.forest)
                    .frame(width: 68, height: 68)
                    .background(tint, in: Circle())

                VStack(spacing: 7) {
                    Text(eyebrow)
                        .font(AtlasType.display(12))
                        .tracking(0.9)
                        .foregroundStyle(AtlasPalette.muted)

                    Text(title)
                        .font(AtlasType.strong(28))
                        .foregroundStyle(AtlasPalette.forest)

                    Text(message)
                        .font(AtlasType.regular(16))
                        .foregroundStyle(AtlasPalette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 285)
                }

                Text(note)
                    .font(AtlasType.display(13))
                    .foregroundStyle(AtlasPalette.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(tint.opacity(0.72), in: Capsule())
                    .overlay {
                        Capsule().stroke(AtlasPalette.forest.opacity(0.22), lineWidth: 1)
                    }
            }
            .frame(width: 350, height: 480)
            .background(AtlasPalette.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AtlasPalette.line.opacity(0.28), lineWidth: 1)
            }
            .placed(x: 26, y: 170, width: 350, height: 480)
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

struct RootAtlasMapScreen: View {
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            Image("MapAtlasScene")
                .resizable()
                .scaledToFill()
                .clipped()
                .placed(x: 0, y: 91, width: 402, height: 480)
                .accessibilityLabel("Illustrated Tokyo route map")
                .accessibilityIdentifier("prototype.map.atlas")

            BrandHeader {
                HStack(spacing: 7) {
                    Image(systemName: "star.circle")
                        .font(.system(size: 16, weight: .regular))
                    Text("\(presentation.mapStampCount) Map Stamps")
                        .font(AtlasType.display(14))
                }
                .foregroundStyle(AtlasPalette.ink)
                .frame(width: 157, height: 34)
                .background(AtlasPalette.mint, in: Capsule())
                .overlay {
                    Capsule().stroke(AtlasPalette.forest.opacity(0.24), lineWidth: 1)
                }
            }
            .background(AtlasPalette.canvas.opacity(0.96))
            .placed(x: 0, y: 48, width: 402, height: 50)
            .accessibilityIdentifier("prototype.map.header")

            PlaceAtlasCard()
                .placed(x: 15, y: 550, width: 372, height: 238)
                .accessibilityIdentifier("prototype.map.placeCard")
        }
        .frame(width: 402, height: 874)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prototype.map")
    }
}

struct PlaceAtlasCard: View {
    @Environment(\.atlasPresentation) private var presentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AtlasPalette.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AtlasPalette.line.opacity(0.32), lineWidth: 1)
                }
                .shadow(color: AtlasPalette.ink.opacity(0.06), radius: 7, y: 2)

            RoundStamp(text: "2", style: .tripStop)
                .position(x: 44, y: 42)

            Text(presentation.selectedMapPlace.name)
                .font(AtlasType.strong(23))
                .foregroundStyle(AtlasPalette.forest)
                .position(x: 170, y: 33)

            Text(presentation.selectedMapPlace.area)
                .font(AtlasType.body(14))
                .foregroundStyle(AtlasPalette.muted)
                .position(x: 111, y: 62)

            HStack(spacing: 6) {
                Image(systemName: "star.circle")
                    .font(.system(size: 13, weight: .regular))
                Text("Confirmed Map Stamp")
                    .font(AtlasType.display(13))
            }
            .foregroundStyle(AtlasPalette.ink)
            .frame(width: 183, height: 30)
            .background(AtlasPalette.mint, in: Capsule())
            .overlay {
                Capsule().stroke(AtlasPalette.forest.opacity(0.20), lineWidth: 1)
            }
            .position(x: 168, y: 91)

            Text(presentation.selectedMapPlace.note)
                .font(AtlasType.regular(14))
                .foregroundStyle(AtlasPalette.muted)
                .lineSpacing(3)
                .position(x: 182, y: 139)

            Button {
                presentation.onOpenPlace(presentation.selectedMapPlace.id)
            } label: {
                HStack {
                    Spacer()
                    Text("Open details")
                        .font(AtlasType.strong(17))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 18, weight: .regular))
                        .padding(.trailing, 14)
                }
                .foregroundStyle(.white)
                .frame(width: 226, height: 42)
                .background(AtlasPalette.coral, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .position(x: 133, y: 202)
            .accessibilityIdentifier("map.place.openDetails")

            Button(action: {}) {
                Image(systemName: "bookmark")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(AtlasPalette.forest)
                    .frame(width: 49, height: 42)
                    .background(AtlasPalette.paper, in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AtlasPalette.line.opacity(0.35), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .position(x: 328, y: 202)
            .accessibilityIdentifier("prototype.action.bookmark")
        }
    }
}
