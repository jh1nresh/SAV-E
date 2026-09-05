import SwiftUI

enum SaveAtlasRuntime {
    static var usesParityFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-atlas-parity-fixture")
    }
}

/// Home card art for one saved place. The URL is taken only from that place;
/// a missing photo is a deliberate placeholder, never another row's image.
enum HomePlaceCardArt {
    static func photoURL(for place: Place) -> URL? {
        place.businessPhotoURLStrings.first.flatMap(URL.init(string:))
    }
}

@MainActor
enum SaveAtlasPresentationFactory {
    static func root(
        store: TripPackStore,
        mapViewModel: MapViewModel,
        onCapture: @escaping () -> Void,
        onReviewAll: @escaping () -> Void,
        onOpenTrip: @escaping (UUID) -> Void,
        onOpenTrips: @escaping () -> Void,
        onOpenSaves: @escaping () -> Void,
        onOpenPlace: @escaping (Place) -> Void,
        onOpenReview: @escaping (PlaceReviewCandidate) -> Void,
        onOpenPassport: @escaping () -> Void
    ) -> AtlasPresentation {
        let tripPriority = store.homeTripPriority
        let displayedTrip = tripPriority?.trip
        var presentation = SaveAtlasRuntime.usesParityFixture
            ? AtlasPresentation.reference
            : liveRootPresentation(
                trip: displayedTrip,
                selectedTripDay: tripPriority?.selectedDay,
                places: mapViewModel.places,
                candidates: mapViewModel.reviewCandidates,
                selectedPlace: mapViewModel.selectedPlace
            )
        if !SaveAtlasRuntime.usesParityFixture {
            presentation.homePriority = homePriorityPresentation(
                tripPriority: tripPriority,
                mapStampCount: mapViewModel.places.count
            )
            presentation.tripsBetaLabel = "BETA"
        }

        presentation.onCapture = onCapture
        presentation.onReviewAll = onReviewAll
        presentation.onOpenTrip = {
            guard let tripID = displayedTrip?.id else { return }
            onOpenTrip(tripID)
        }
        let priorityKind = presentation.homePriority.kind
        presentation.onOpenHomePriority = {
            switch priorityKind {
            case .currentTrip, .upcomingTrip:
                let trip = displayedTrip
                    ?? (SaveAtlasRuntime.usesParityFixture ? store.suggestedTrip : nil)
                guard let tripID = trip?.id else { return }
                onOpenTrip(tripID)
            case .planFromStamps:
                onOpenTrips()
            case .capture:
                onCapture()
            }
        }
        presentation.onOpenSaves = onOpenSaves
        presentation.onOpenTrips = onOpenTrips
        presentation.onOpenPlace = { id in
            guard let place = mapViewModel.places.first(where: { $0.id.uuidString == id }) else {
                return
            }
            onOpenPlace(place)
        }
        presentation.onOpenReview = { id in
            guard let candidate = mapViewModel.reviewCandidates.first(where: {
                $0.id.uuidString == id
            }) else {
                return
            }
            onOpenReview(candidate)
        }
        presentation.onOpenPassport = onOpenPassport
        return presentation
    }

    static func library(
        places: [Place],
        candidates: [PlaceReviewCandidate],
        onCapture: @escaping () -> Void,
        onReviewAll: @escaping () -> Void,
        onOpenPlace: @escaping (Place) -> Void,
        onOpenReview: @escaping (PlaceReviewCandidate) -> Void,
        onSelectReview: @escaping () -> Void,
        onSelectMapStamps: @escaping () -> Void,
        onOpenPassport: @escaping () -> Void
    ) -> AtlasPresentation {
        var presentation = SaveAtlasRuntime.usesParityFixture
            ? AtlasPresentation.reference
            : liveRootPresentation(
                trip: nil,
                places: places,
                candidates: candidates,
                selectedPlace: nil
            )
        presentation.onCapture = onCapture
        presentation.onReviewAll = onReviewAll
        presentation.onOpenPlace = { id in
            guard let place = places.first(where: { $0.id.uuidString == id }) else { return }
            onOpenPlace(place)
        }
        presentation.onOpenReview = { id in
            guard let candidate = candidates.first(where: { $0.id.uuidString == id }) else {
                return
            }
            onOpenReview(candidate)
        }
        presentation.onSelectReview = onSelectReview
        presentation.onSelectMapStamps = onSelectMapStamps
        presentation.onOpenPassport = onOpenPassport
        return presentation
    }

    static func map(
        mapViewModel: MapViewModel,
        onOpenAssistant: @escaping () -> Void,
        onOpenPlace: @escaping (Place) -> Void,
        onOpenPassport: @escaping () -> Void
    ) -> AtlasPresentation {
        var presentation = SaveAtlasRuntime.usesParityFixture
            ? AtlasPresentation.reference
            : liveRootPresentation(
                trip: nil,
                places: mapViewModel.places,
                candidates: mapViewModel.reviewCandidates,
                selectedPlace: mapViewModel.selectedPlace
            )
        presentation.onOpenPlace = { id in
            guard let place = mapViewModel.places.first(where: { $0.id.uuidString == id }) else {
                return
            }
            onOpenPlace(place)
        }
        presentation.onOpenAssistant = onOpenAssistant
        presentation.onOpenPassport = onOpenPassport
        return presentation
    }

    static func trips(
        store: TripPackStore,
        savedPlaces: [Place] = [],
        language: AppLanguage = .english,
        onOpenAssistant: @escaping () -> Void,
        onAskSubmit: @escaping (String) -> Void,
        onCreateTrip: @escaping () -> Void,
        onOpenTrip: @escaping (UUID) -> Void,
        onOpenPassport: @escaping () -> Void
    ) -> AtlasPresentation {
        var presentation = AtlasPresentation.reference
        presentation.tripsBetaLabel = language.localized(
            english: "BETA",
            traditionalChinese: "測試版"
        )
        presentation.tripsBetaDetail = language.localized(
            english: "Trip planning is still improving.",
            traditionalChinese: "行程規劃品質仍在持續改善。"
        )
        presentation.allTripsLabel = language.localized(english: "All trips", traditionalChinese: "全部行程")

        if !SaveAtlasRuntime.usesParityFixture {
            presentation.tripSummaries = (
                store.currentTrips.map { tripSummary($0, timing: "CURRENT") }
                    + store.upcomingTrips.map { tripSummary($0, timing: "UPCOMING") }
                    + store.planningTrips.map { tripSummary($0, timing: "PLANNING") }
                    + store.pastTrips.map { tripSummary($0, timing: "PAST") }
            )
            presentation.tripRecommendations = SavedPlaceTripRecommender()
                .recommendations(from: savedPlaces, excludingAreasFrom: store.trips)
                .map { recommendationPresentation($0, language: language) }
        }

        presentation.onOpenAssistant = onOpenAssistant
        presentation.onAskSubmit = onAskSubmit
        // A recommendation runs the same ask path a typed question does, so
        // the answer lands in the same expanding surface.
        presentation.onPlanRecommendation = onAskSubmit
        presentation.onCreateTrip = onCreateTrip
        presentation.onOpenTripID = { id in
            let selectedTrip = UUID(uuidString: id)
                .flatMap { tripID in store.trips.first(where: { $0.id == tripID }) }
                ?? store.suggestedTrip
            guard let selectedTrip else { return }
            onOpenTrip(selectedTrip.id)
        }
        presentation.onOpenPassport = onOpenPassport
        return presentation
    }

    static func trip(
        trip: Trip,
        selectedDay: Int,
        places: [Place],
        onSelectDay: @escaping (Int) -> Void,
        onOpenStop: @escaping (TripStop) -> Void,
        onAddStop: @escaping () -> Void,
        onOpenPlace: @escaping (Place) -> Void
    ) -> AtlasPresentation {
        var presentation = SaveAtlasRuntime.usesParityFixture
            ? AtlasPresentation.reference
            : liveTripPresentation(trip: trip, selectedDay: selectedDay, places: places)

        presentation.onSelectDay = onSelectDay
        presentation.onOpenStop = { id in
            guard let stop = trip.places.first(where: { $0.id.uuidString == id }) else { return }
            onOpenStop(stop)
        }
        presentation.onAddStop = onAddStop
        presentation.onOpenPlace = { id in
            guard let place = places.first(where: { $0.id.uuidString == id }) else { return }
            onOpenPlace(place)
        }
        return presentation
    }

    private static func liveRootPresentation(
        trip: Trip?,
        selectedTripDay: Int? = nil,
        places: [Place],
        candidates: [PlaceReviewCandidate],
        selectedPlace: Place?
    ) -> AtlasPresentation {
        var presentation = AtlasPresentation.reference
        presentation.locksOneFaceHomeComposition = false
        presentation.reviewCount = candidates.count
        presentation.mapStampCount = places.count
        presentation.failedCount = candidates.filter {
            ["failed", "rejected"].contains($0.status.lowercased())
        }.count
        presentation.savedPlaces = places
            .sorted { $0.createdAt > $1.createdAt }
            .map(placePresentation)
        presentation.reviewItems = candidates
            .sorted { $0.createdAt > $1.createdAt }
            .map(reviewPresentation)
        presentation.selectedMapPlace = (selectedPlace ?? places.first)
            .map(placePresentation)
            ?? .koffeeMameya

        if let trip {
            let selectedDay = max(
                1,
                selectedTripDay ?? trip.places.map(\.day).min() ?? 1
            )
            presentation.tripName = trip.name
            presentation.tripCity = trip.city.isEmpty ? "Trip" : trip.city
            presentation.tripDayCount = dayCount(for: trip)
            presentation.selectedDay = selectedDay
            presentation.tripDateLabel = dateLabel(for: trip, day: selectedDay)
            presentation.tripStops = stopPresentations(
                trip: trip,
                selectedDay: selectedDay,
                places: places
            )
        } else {
            presentation.tripName = "Start a Trip"
            presentation.tripCity = "Trip"
            presentation.tripDayCount = 1
            presentation.selectedDay = 1
            presentation.tripDateLabel = "WHEN YOU’RE READY"
            presentation.tripStops = []
        }
        return presentation
    }

    static func homePriority(
        tripPriority: HomeTripPriority?,
        mapStampCount: Int
    ) -> AtlasHomePriorityPresentation {
        homePriorityPresentation(
            tripPriority: tripPriority,
            mapStampCount: mapStampCount
        )
    }

    private static func homePriorityPresentation(
        tripPriority: HomeTripPriority?,
        mapStampCount: Int
    ) -> AtlasHomePriorityPresentation {
        if let tripPriority {
            let stopDetail: String
            if let stop = tripPriority.nextStop {
                let time = stop.startTime?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nonEmpty
                    ?? "Time TBD"
                stopDetail = "Next stop: \(stop.placeName) · \(time)"
            } else {
                stopDetail = "Open the plan and choose what comes next"
            }

            switch tripPriority.timing {
            case .current:
                return AtlasHomePriorityPresentation(
                    kind: .currentTrip,
                    eyebrow: tripPriority.nextStopIsToday
                        ? "CONTINUE TODAY"
                        : "CONTINUE TRIP",
                    title: tripPriority.trip.name,
                    detail: stopDetail,
                    badge: "Day \(tripPriority.selectedDay) of \(dayCount(for: tripPriority.trip))",
                    systemName: "point.3.connected.trianglepath.dotted"
                )
            case .upcoming:
                let days = tripPriority.daysUntilStart ?? 1
                let stopCount = tripPriority.trip.places.count
                return AtlasHomePriorityPresentation(
                    kind: .upcomingTrip,
                    eyebrow: "COMING UP",
                    title: tripPriority.trip.name,
                    detail: stopCount == 0
                        ? "Open the Trip and add the first stop"
                        : "\(stopCount) \(stopCount == 1 ? "stop" : "stops") ready to review",
                    badge: "In \(days) \(days == 1 ? "day" : "days")",
                    systemName: "calendar"
                )
            }
        }

        if mapStampCount > 0 {
            return AtlasHomePriorityPresentation(
                kind: .planFromStamps,
                eyebrow: "READY TO PLAN",
                title: "Build a Trip",
                detail: "\(mapStampCount) Map Stamps are ready to organize",
                badge: nil,
                systemName: "point.3.connected.trianglepath.dotted"
            )
        }

        return AtlasHomePriorityPresentation(
            kind: .capture,
            eyebrow: "START HERE",
            title: "Save your first place",
            detail: "Paste or share a link to begin",
            badge: nil,
            systemName: "link"
        )
    }

    private static func liveTripPresentation(
        trip: Trip,
        selectedDay: Int,
        places: [Place]
    ) -> AtlasPresentation {
        var presentation = AtlasPresentation.reference
        presentation.tripName = trip.name
        presentation.tripCity = trip.city.isEmpty ? "Trip" : trip.city
        presentation.tripDayCount = dayCount(for: trip)
        presentation.selectedDay = selectedDay
        presentation.tripDateLabel = dateLabel(for: trip, day: selectedDay)
        presentation.tripStops = stopPresentations(
            trip: trip,
            selectedDay: selectedDay,
            places: places
        )
        presentation.mapStampCount = places.count

        let selectedStop = trip.places
            .sorted { ($0.day, $0.orderIndex) < ($1.day, $1.orderIndex) }
            .dropFirst()
            .first
            ?? trip.places.first
        presentation.selectedMapPlace = selectedStop
            .flatMap { stop in places.first(where: { $0.id == stop.placeId }) }
            .map(placePresentation)
            ?? places.first.map(placePresentation)
            ?? .koffeeMameya
        return presentation
    }

    private static func stopPresentations(
        trip: Trip,
        selectedDay: Int,
        places: [Place]
    ) -> [AtlasStopPresentation] {
        trip.places
            .filter { $0.day == selectedDay }
            .sorted { $0.orderIndex < $1.orderIndex }
            .prefix(4)
            .enumerated()
            .map { index, stop in
                let place = places.first { $0.id == stop.placeId }
                return AtlasStopPresentation(
                    id: stop.id.uuidString,
                    name: stop.placeName,
                    time: stop.startTime?.trimmingCharacters(in: .whitespacesAndNewlines)
                        .nonEmpty
                        ?? "Time TBD",
                    note: stop.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                        .nonEmpty
                        ?? place?.note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                        ?? place?.shareAreaLabel.nonEmpty
                        ?? "Confirmed Map Stamp",
                    imageName: stopImageName(for: stop.placeName, index: index),
                    imageHeight: [78, 82, 83, 84][min(index, 3)]
                )
            }
    }

    private static func placePresentation(_ place: Place) -> AtlasPlacePresentation {
        AtlasPlacePresentation(
            id: place.id.uuidString,
            name: place.name,
            area: place.shareAreaLabel.nonEmpty ?? place.address,
            region: SavedPlaceTripRecommender.areaLabel(for: place),
            photoURL: HomePlaceCardArt.photoURL(for: place),
            latitude: place.latitude,
            longitude: place.longitude,
            relativeDay: relativeDay(for: place.createdAt),
            note: place.note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? place.address
        )
    }

    private static func reviewPresentation(
        _ candidate: PlaceReviewCandidate
    ) -> AtlasReviewPresentation {
        let isSourceOnly = candidate.status.lowercased() == "source_only"
        return AtlasReviewPresentation(
            id: candidate.id.uuidString,
            kind: isSourceOnly ? .sourceOnly : .candidate,
            name: candidate.name,
            detail: reviewDetail(candidate)
        )
    }

    private static func reviewDetail(_ candidate: PlaceReviewCandidate) -> String {
        if candidate.status.lowercased() == "source_only" {
            return "Missing exact place"
        }
        if let handle = candidate.sourceHandle?.nonEmpty {
            return "From \(handle)"
        }
        let evidence = candidate.evidence.joined(separator: " ").lowercased()
        if evidence.contains("xiaohongshu") || evidence.contains("小紅書") {
            return "From Xiaohongshu"
        }
        if evidence.contains("instagram") {
            return "From Instagram"
        }
        if let city = candidate.city?.nonEmpty {
            return "From \(city)"
        }
        return "From shared link"
    }

    private static func dayCount(for trip: Trip) -> Int {
        let stopDayCount = trip.places.map(\.day).max() ?? 1
        guard let start = trip.startDate, let end = trip.endDate else {
            return max(1, stopDayCount)
        }
        let dateCount = (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return max(1, max(stopDayCount, dateCount))
    }

    private static func dateLabel(for trip: Trip, day: Int) -> String {
        guard let start = trip.startDate,
              let date = Calendar.current.date(byAdding: .day, value: day - 1, to: start)
        else {
            return "DAY \(day)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date).uppercased()
    }

    private static func relativeDay(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func stopImageName(for name: String, index: Int) -> String {
        let value = name.lowercased()
        if value.contains("tsukiji") { return "TsukijiThumbnail" }
        if value.contains("mameya") || value.contains("coffee") || value.contains("cafe") {
            return "KoffeeMameyaThumbnail"
        }
        if value.contains("teamlab") { return "TeamLabThumbnail" }
        if value.contains("shibuya") { return "ShibuyaSkyThumbnail" }
        return [
            "TsukijiThumbnail",
            "KoffeeMameyaThumbnail",
            "TeamLabThumbnail",
            "ShibuyaSkyThumbnail",
        ][min(index, 3)]
    }

    private static func recommendationPresentation(
        _ recommendation: SavedPlaceTripRecommendation,
        language: AppLanguage
    ) -> AtlasTripRecommendationPresentation {
        AtlasTripRecommendationPresentation(
            id: recommendation.id,
            title: recommendation.title(language: language),
            subtitle: recommendation.subtitle(language: language),
            sampleNames: recommendation.sampleNames,
            planningQuery: recommendation.planningQuery
        )
    }

    private static func tripSummary(
        _ trip: Trip,
        timing: String
    ) -> AtlasTripSummaryPresentation {
        AtlasTripSummaryPresentation(
            id: trip.id.uuidString,
            name: trip.name,
            city: trip.city,
            dateRange: trip.dateRangeText,
            stopCount: trip.places.count,
            timing: timing
        )
    }
}

struct SaveAtlasInteractiveRootMap: View {
    @ObservedObject var mapViewModel: MapViewModel
    let shouldFocusOnUserLocation: Bool
    // One bottom surface at a time: while the root drawer sheet is up, the
    // resting command shelf hides so two drawers never stack (spec P2).
    let hidesCommandShelf: Bool
    let presentation: AtlasPresentation
    let onClearSelection: () -> Void
    // Spec P2b: the Atlas card is the one surface per selected place, so it
    // carries the actions the retired legacy strip used to own.
    let onPlanAroundPlace: (Place) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            MapView(
                viewModel: mapViewModel,
                shouldFocusOnUserLocationOnLaunch: shouldFocusOnUserLocation
            )
            .clipped()
            .placed(x: 0, y: 0, width: 402, height: 874)

            // Apple Maps reference: top stays empty (weather only when wired).
            // Stamp count rides on search accessibility, not a persistent chip.

            if let place = mapViewModel.selectedPlace {
                SaveAtlasLivePlaceCard(
                    place: place,
                    onClose: onClearSelection,
                    onOpen: {
                        presentation.onOpenPlace(place.id.uuidString)
                    },
                    onOpenAssistant: presentation.onOpenAssistant,
                    onPlanAround: {
                        onPlanAroundPlace(place)
                    }
                )
                .id(place.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .placed(x: 15, y: 606, width: 372, height: 180)
            } else if !hidesCommandShelf {
                SaveAtlasMapCommandShelf(
                    mapStampCount: presentation.mapStampCount,
                    onOpenAssistant: presentation.onOpenAssistant,
                    onOpenPassport: presentation.onOpenPassport
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .placed(x: 15, y: 730, width: 372, height: 56)
            }
        }
        .animation(SaveTheme.Motion.standardSpring, value: mapViewModel.selectedPlace?.id)
        .frame(width: 402, height: 874)
        .clipped()
        .environment(\.atlasPresentation, presentation)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.root")
    }
}

/// Collapsed Map search stop: Apple Maps floating frosted search capsule.
///
/// Matches the founder Apple Maps reference: one-row pill (no grabber),
/// magnifier + placeholder + mic + trailing identity control. Medium/large
/// stops stay on `SaveMapDrawerPanel`.
struct SaveAtlasMapCommandShelf: View {
    let mapStampCount: Int
    let onOpenAssistant: () -> Void
    let onOpenPassport: () -> Void

    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenAssistant) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)

                    Text(languageSettings.localized(english: "Search places", traditionalChinese: "搜尋地點"))
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search places")
            .accessibilityHint("Search saved places and the map")
            .accessibilityValue("\(mapStampCount) saved Map Stamps")
            .accessibilityIdentifier("map.command.search")

            // Apple Maps puts the account avatar inside the search capsule.
            // Savvy opens Passport from the same trailing slot.
            Button(action: onOpenPassport) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AtlasPalette.forest.opacity(0.85))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel("Open Passport")
            .accessibilityIdentifier("map.command.passport")
        }
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
        .background(SaveAtlasPalette.canvas, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct SaveAtlasLivePlaceCard: View {
    let place: Place
    let onClose: () -> Void
    let onOpen: () -> Void
    let onOpenAssistant: () -> Void
    let onPlanAround: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(AtlasPalette.line.opacity(0.48))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 11) {
                SaveAtlasMapPlaceThumbnail(place: place)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(AtlasType.strong(20))
                        .foregroundStyle(AtlasPalette.forest)
                        .lineLimit(1)
                        .accessibilityIdentifier("map.place.name")

                    Text(primaryLocation(for: place))
                        .font(AtlasType.body(13))
                        .foregroundStyle(AtlasPalette.muted)
                        .lineLimit(1)
                        .accessibilityIdentifier("map.place.location")
                }

                Spacer(minLength: 0)

                SavePlaceShareButton(content: .place(place)) {
                    mapCardIcon("square.and.arrow.up")
                }
                .accessibilityLabel("Share \(place.name)")
                .accessibilityIdentifier("map.place.share")

                Button(action: onClose) {
                    mapCardIcon("xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close place preview")
                .accessibilityIdentifier("map.place.close")
            }

            HStack(spacing: 8) {
                Button(action: onOpenAssistant) {
                    mapCardActionIcon("magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search places")
                .accessibilityIdentifier("map.place.search")

                Button(action: onOpen) {
                    HStack {
                        Spacer()
                        Text("Open details")
                            .font(AtlasType.strong(16))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .frame(height: 44)
                    .background(AtlasPalette.coral, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.place.openDetails")

                // Spec P2b: plan-around moved onto the card from the retired
                // legacy strip's expanded sibling.
                Button(action: onPlanAround) {
                    mapCardActionIcon("point.topleft.down.to.point.bottomright.curvepath")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Plan around \(place.name)")
                .accessibilityIdentifier("map.place.planAround")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Apple Maps selected-place peek is frosted glass over the map.
        // Full Memory Card detail stays notebook paper outside Map chrome.
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.place.card")
    }

    private func mapCardIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.primary.opacity(0.72))
            .frame(width: 36, height: 36)
            .background(.thinMaterial, in: Circle())
    }

    private func mapCardActionIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.72))
            .frame(width: 44, height: 44)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func primaryLocation(for place: Place) -> String {
        let area = place.shareAreaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !area.isEmpty { return area }
        let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? "Saved place" : address
    }

}

private struct SaveAtlasMapPlaceThumbnail: View {
    let place: Place

    var body: some View {
        Group {
            if let value = place.businessPhotoURLStrings.first,
               let url = URL(string: value) {
                CachedAsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 56, height: 56)
        .background(AtlasPalette.mint.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AtlasPalette.line.opacity(0.28), lineWidth: 1)
        }
    }

    private var fallback: some View {
        Image(systemName: place.category.iconName)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(AtlasPalette.forest)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SaveAtlasInteractiveTripMap: View {
    @ObservedObject var mapViewModel: MapViewModel
    let trip: Trip
    let presentation: AtlasPresentation
    let onBack: () -> Void
    let onShare: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            TripHeader(onBack: onBack, onShare: onShare)
                .placed(x: 0, y: 48, width: 402, height: 54)

            MapView(
                viewModel: mapViewModel,
                shouldFocusOnUserLocationOnLaunch: false,
                displayedPlaces: routePlaces,
                showsAuxiliaryPins: false,
                numberedPlacePositions: numberedPlacePositions,
                contextBadgeText: "DAY \(presentation.selectedDay) · \(routeSummary.uppercased())"
            )
            .clipped()
            .placed(x: 0, y: 102, width: 402, height: 450)

            TripMapPlaceCard()
                .placed(x: 15, y: 550, width: 372, height: 226)
        }
        .frame(width: 402, height: 874)
        .clipped()
        .environment(\.atlasPresentation, presentation)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.map")
        .onAppear(perform: applyRoute)
        .onChange(of: routePoints) { _, _ in applyRoute() }
        .onDisappear {
            mapViewModel.apply(
                MapActionData(
                    type: .resetPins,
                    placeIds: nil,
                    lat: nil,
                    lng: nil,
                    span: nil
                )
            )
        }
    }

    private var orderedPlaceIDs: [UUID] {
        trip.places
            .sorted { ($0.day, $0.orderIndex) < ($1.day, $1.orderIndex) }
            .map(\.placeId)
    }

    private var routePlaces: [Place] {
        mapViewModel.placesForRoute(placeIDs: orderedPlaceIDs)
    }

    private var routePoints: [RoutePoint] {
        routePlaces.map {
            RoutePoint(id: $0.id, latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var numberedPlacePositions: [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: routePoints.enumerated().map { ($0.element.id, $0.offset + 1) }
        )
    }

    private var routeSummary: String {
        routePoints.count == 1 ? "1 confirmed stop" : "\(routePoints.count) confirmed stops"
    }

    private func applyRoute() {
        mapViewModel.apply(
            MapActionData(
                type: .showRoute,
                placeIds: routePoints.map(\.id.uuidString),
                lat: nil,
                lng: nil,
                span: nil
            )
        )
    }

    private struct RoutePoint: Hashable {
        let id: UUID
        let latitude: Double
        let longitude: Double
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
