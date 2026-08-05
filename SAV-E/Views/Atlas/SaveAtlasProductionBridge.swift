import SwiftUI

enum SaveAtlasRuntime {
    static var usesParityFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-atlas-parity-fixture")
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
        onCapture: @escaping () -> Void,
        onOpenAssistant: @escaping () -> Void,
        onAskSubmit: @escaping (String) -> Void,
        onCreateTrip: @escaping () -> Void,
        onOpenTrip: @escaping (UUID) -> Void,
        onOpenPassport: @escaping () -> Void
    ) -> AtlasPresentation {
        var presentation = AtlasPresentation.reference

        if !SaveAtlasRuntime.usesParityFixture {
            presentation.tripSummaries = (
                store.currentTrips.map { tripSummary($0, timing: "CURRENT") }
                    + store.upcomingTrips.map { tripSummary($0, timing: "UPCOMING") }
                    + store.planningTrips.map { tripSummary($0, timing: "PLANNING") }
                    + store.pastTrips.map { tripSummary($0, timing: "PAST") }
            )
        }

        presentation.onCapture = onCapture
        presentation.onOpenAssistant = onOpenAssistant
        presentation.onAskSubmit = onAskSubmit
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
        presentation.reviewCount = candidates.count
        presentation.mapStampCount = places.count
        presentation.failedCount = candidates.filter {
            ["failed", "rejected"].contains($0.status.lowercased())
        }.count
        presentation.recentPlaces = places
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(2)
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
            .placed(x: 0, y: 91, width: 402, height: 697)

            BrandHeader {
                HStack(spacing: 7) {
                    Image(systemName: "star.circle")
                        .font(.system(size: 16))
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

            if let place = mapViewModel.selectedPlace {
                SaveAtlasLivePlaceCard(
                    place: place,
                    onClose: onClearSelection,
                    onOpen: {
                        presentation.onOpenPlace(place.id.uuidString)
                    },
                    onPlanAround: {
                        onPlanAroundPlace(place)
                    }
                )
                .id(place.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .placed(x: 15, y: 568, width: 372, height: 220)
            } else if !hidesCommandShelf {
                SaveAtlasMapCommandShelf(
                    mapStampCount: presentation.mapStampCount,
                    onOpenAssistant: presentation.onOpenAssistant
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .placed(x: 15, y: 676, width: 372, height: 112)
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

struct SaveAtlasMapCommandShelf: View {
    let mapStampCount: Int
    let onOpenAssistant: () -> Void

    var body: some View {
        Button(action: onOpenAssistant) {
            VStack(spacing: 8) {
                Capsule()
                    .fill(AtlasPalette.line.opacity(0.48))
                    .frame(width: 38, height: 4)
                    .accessibilityHidden(true)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AtlasPalette.forest)

                    Text("Search places or ask SAV-E")
                        .font(AtlasType.strong(16))
                        .foregroundStyle(AtlasPalette.ink)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 31, height: 31)
                        .background(AtlasPalette.coral, in: Circle())
                }

                HStack(spacing: 6) {
                    Image(systemName: "star.circle.fill")
                        .foregroundStyle(AtlasPalette.forest)
                    Text("\(mapStampCount) confirmed Map Stamps")
                    Spacer()
                    MemoMascotMark(size: 24, framed: false)
                }
                .font(AtlasType.regular(12))
                .foregroundStyle(AtlasPalette.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                AtlasPalette.paper,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AtlasPalette.line.opacity(0.32), lineWidth: 1)
            }
            .shadow(color: AtlasPalette.ink.opacity(0.08), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search places or ask SAV-E")
        .accessibilityHint("Opens the SAV-E assistant")
        .accessibilityIdentifier("map.command.search")
    }
}

private struct SaveAtlasLivePlaceCard: View {
    let place: Place
    let onClose: () -> Void
    let onOpen: () -> Void
    let onPlanAround: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Capsule()
                    .fill(AtlasPalette.line.opacity(0.48))
                    .frame(width: 38, height: 4)
                    .frame(maxWidth: .infinity)

                // Spec P2b: share moved here from the retired legacy strip —
                // the card is the only surface for a selected place.
                SavePlaceShareButton(content: .place(place)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AtlasPalette.ink)
                        .frame(width: 32, height: 32)
                        .background(AtlasPalette.canvas, in: Circle())
                }
                .accessibilityLabel("Share \(place.name)")
                .accessibilityIdentifier("map.place.share")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AtlasPalette.ink)
                        .frame(width: 32, height: 32)
                        .background(AtlasPalette.canvas, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close place preview")
                .accessibilityIdentifier("map.place.close")
            }
            .frame(height: 24)

            HStack(alignment: .top, spacing: 12) {
                SaveAtlasMapPlaceThumbnail(place: place)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(AtlasType.strong(22))
                        .foregroundStyle(AtlasPalette.forest)
                        .lineLimit(2)
                        .accessibilityIdentifier("map.place.name")

                    Text(primaryLocation(for: place))
                        .font(AtlasType.body(13))
                        .foregroundStyle(AtlasPalette.muted)
                        .lineLimit(savedNote == nil ? 2 : 1)
                        .accessibilityIdentifier("map.place.location")

                    // Spec P2b: surface the saved memory note the legacy
                    // strip context used to carry (read-only; edit stays in
                    // the expanded detail).
                    if let savedNote {
                        Text(savedNote)
                            .font(AtlasType.editorial(12))
                            .foregroundStyle(AtlasPalette.forest.opacity(0.85))
                            .lineLimit(1)
                            .accessibilityIdentifier("map.place.note")
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 7) {
                Label("Map Stamp", systemImage: "star.circle.fill")
                    .font(AtlasType.display(12))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 27)
                    .background(AtlasPalette.mint, in: Capsule())

                Text(place.category.displayName)
                    .font(AtlasType.display(12))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 27)
                    .background(AtlasPalette.sky.opacity(0.72), in: Capsule())

                if let rating = place.googleRating ?? place.rating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(AtlasType.display(12))
                        .padding(.horizontal, 9)
                        .frame(minHeight: 27)
                        .background(AtlasPalette.honey.opacity(0.82), in: Capsule())
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(AtlasPalette.ink)
            .accessibilityIdentifier("map.place.context")

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    HStack {
                        Spacer()
                        Text("Open details")
                            .font(AtlasType.strong(17))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .frame(minHeight: 42)
                    .background(AtlasPalette.coral, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.place.openDetails")

                // Spec P2b: plan-around moved onto the card from the retired
                // legacy strip's expanded sibling.
                Button(action: onPlanAround) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AtlasPalette.ink)
                        .frame(width: 42, height: 42)
                        .background(AtlasPalette.honey.opacity(0.82), in: RoundedRectangle(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(AtlasPalette.line.opacity(0.34), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Plan around \(place.name)")
                .accessibilityIdentifier("map.place.planAround")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            AtlasPalette.paper,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AtlasPalette.line.opacity(0.32), lineWidth: 1)
        }
        .shadow(color: AtlasPalette.ink.opacity(0.08), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.place.card")
    }

    private var savedNote: String? {
        place.note?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
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
        .frame(width: 64, height: 64)
        .background(AtlasPalette.mint.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
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
