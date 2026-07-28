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
        onOpenSaves: @escaping () -> Void,
        onOpenPlace: @escaping (Place) -> Void,
        onOpenReview: @escaping (PlaceReviewCandidate) -> Void
    ) -> AtlasPresentation {
        let suggestedTrip = store.suggestedTrip
        var presentation = SaveAtlasRuntime.usesParityFixture
            ? AtlasPresentation.reference
            : liveRootPresentation(
                trip: suggestedTrip,
                places: mapViewModel.places,
                candidates: mapViewModel.reviewCandidates,
                selectedPlace: mapViewModel.selectedPlace
            )

        presentation.onCapture = onCapture
        presentation.onReviewAll = onReviewAll
        presentation.onOpenTrip = {
            guard let tripID = suggestedTrip?.id else { return }
            onOpenTrip(tripID)
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
        return presentation
    }

    static func library(
        places: [Place],
        candidates: [PlaceReviewCandidate],
        onCapture: @escaping () -> Void,
        onReviewAll: @escaping () -> Void,
        onOpenPlace: @escaping (Place) -> Void,
        onOpenReview: @escaping (PlaceReviewCandidate) -> Void
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
        return presentation
    }

    static func map(
        mapViewModel: MapViewModel,
        onOpenPlace: @escaping (Place) -> Void
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
            .prefix(3)
            .map(reviewPresentation)
        presentation.selectedMapPlace = (selectedPlace ?? places.first)
            .map(placePresentation)
            ?? .koffeeMameya

        if let trip {
            let selectedDay = max(1, trip.places.map(\.day).min() ?? 1)
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
}

struct SaveAtlasInteractiveRootMap: View {
    @ObservedObject var mapViewModel: MapViewModel
    let shouldFocusOnUserLocation: Bool
    let presentation: AtlasPresentation

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            MapView(
                viewModel: mapViewModel,
                shouldFocusOnUserLocationOnLaunch: shouldFocusOnUserLocation
            )
            .clipped()
            .placed(x: 0, y: 98, width: 402, height: 473)

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

            PlaceAtlasCard()
                .placed(x: 15, y: 550, width: 372, height: 238)
        }
        .frame(width: 402, height: 874)
        .clipped()
        .environment(\.atlasPresentation, presentation)
        .accessibilityIdentifier("map.root")
    }
}

struct SaveAtlasInteractiveTripMap: View {
    @ObservedObject var mapViewModel: MapViewModel
    let trip: Trip
    let presentation: AtlasPresentation
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            TripHeader(onBack: onBack)
                .placed(x: 0, y: 48, width: 402, height: 54)

            MapView(
                viewModel: mapViewModel,
                shouldFocusOnUserLocationOnLaunch: false,
                displayedPlaces: routePlaces,
                showsAuxiliaryPins: false,
                numberedPlacePositions: numberedPlacePositions,
                contextBadgeText: routeSummary
            )
            .clipped()
            .placed(x: 0, y: 102, width: 402, height: 450)

            PlaceAtlasCard()
                .placed(x: 15, y: 550, width: 372, height: 226)
        }
        .frame(width: 402, height: 874)
        .clipped()
        .environment(\.atlasPresentation, presentation)
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
