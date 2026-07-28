import MapKit
import SwiftUI

struct TripsHomeView: View {
    @ObservedObject var store: TripPackStore
    let onOpenDrawer: (DrawerLaunchTarget, UUID?) -> Void
    let onOpenTrip: (UUID) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var showsCreateTrip = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                introCard
                tripSection(
                    title: localized("Current", "目前行程"),
                    emptyText: localized("No trip is underway.", "目前沒有進行中的行程。"),
                    trips: store.currentTrips
                )
                tripSection(
                    title: localized("Upcoming", "即將到來"),
                    emptyText: localized("Create your next Trip Pack when you are ready.", "準備好時，建立下一個 Trip Pack。"),
                    trips: store.upcomingTrips
                )
                if !store.planningTrips.isEmpty {
                    tripSection(
                        title: localized("Planning", "規劃中"),
                        emptyText: "",
                        trips: store.planningTrips
                    )
                }
                if !store.pastTrips.isEmpty {
                    tripSection(
                        title: localized("Past", "過往行程"),
                        emptyText: "",
                        trips: store.pastTrips
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(SaveDottedBackground().ignoresSafeArea())
        .navigationTitle(localized("Trips", "行程"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                SaveGlobalCaptureToolbarButton {
                    onOpenDrawer(.addLink, nil)
                }

                Button {
                    showsCreateTrip = true
                } label: {
                    Label(localized("New Trip", "新增行程"), systemImage: "plus")
                }
                .accessibilityIdentifier("trips.create")
            }
        }
        .refreshable {
            await store.load()
        }
        .tint(Color.saveCoralInk)
        .sheet(isPresented: $showsCreateTrip) {
            NewTripPackView { name, city, startDate, endDate in
                if let trip = await store.createTrip(
                    name: name,
                    city: city,
                    startDate: startDate,
                    endDate: endDate
                ) {
                    store.selectTrip(trip.id)
                    onOpenTrip(trip.id)
                }
            }
        }
        .alert(
            localized("Trip could not sync", "行程無法同步"),
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.clearStatus() } }
            )
        ) {
            Button(languageSettings.text(.ok)) { store.clearStatus() }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .overlay {
            if store.isLoading && store.trips.isEmpty {
                ProgressView(localized("Loading Trip Packs…", "正在載入 Trip Packs…"))
                    .padding(20)
                    .saveNotebookSurface(
                        cornerRadius: 18,
                        opacity: 0.96,
                        strokeOpacity: 0.42,
                        lineWidth: 1.4
                    )
            }
        }
        .accessibilityIdentifier("trips.home")
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localized("Your confirmed places, arranged for the trip", "把已確認地點排成真正的行程"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.headline)
                .foregroundStyle(Color.saveInk)
            Text(localized(
                "Paste or share a link. SAV-E investigates it first; only a place you confirm can enter a Trip Pack.",
                "貼上或分享連結後，SAV-E 會先分析；只有你確認的地點才能加入 Trip Pack。"
            ))
            .font(.subheadline)
            .foregroundStyle(Color.saveMutedText)
            .fixedSize(horizontal: false, vertical: true)

            Text(localized(
                "Analyze  →  Review  →  Save  →  Plan",
                "分析  →  確認  →  收藏  →  規劃"
            ))
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.saveCoralInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.saveCoral.opacity(0.18), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .saveNotebookSurface(
            cornerRadius: 20,
            opacity: 0.96,
            strokeOpacity: 0.42,
            lineWidth: 1.4
        )
    }

    @ViewBuilder
    private func tripSection(title: String, emptyText: String, trips: [Trip]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Color.saveInk)

            if trips.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(Color.saveMutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .saveNotebookSurface(
                        cornerRadius: 18,
                        opacity: 0.94,
                        strokeOpacity: 0.34
                    )
            } else {
                ForEach(trips) { trip in
                    Button {
                        store.selectTrip(trip.id)
                        onOpenTrip(trip.id)
                    } label: {
                        TripPackCard(trip: trip)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trips.card.\(trip.id.uuidString)")
                }
            }
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct TripPackCard: View {
    let trip: Trip
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SaveIconTile(
                systemName: "suitcase.rolling.fill",
                size: 48,
                fill: .saveHoney,
                foreground: .saveInk,
                cornerRadius: 15
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(.headline)
                    .foregroundStyle(Color.saveInk)
                Text([trip.city, trip.dateRangeText].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Color.saveMutedText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(languageSettings.localized(
                    english: "\(trip.places.count) confirmed stops",
                    traditionalChinese: "\(trip.places.count) 個已確認地點"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.saveCoralInk)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(Color.saveMutedText)
                .padding(.top, 16)
        }
        .padding(16)
        .saveNotebookSurface(
            cornerRadius: 20,
            opacity: 0.96,
            strokeOpacity: 0.42,
            lineWidth: 1.4
        )
    }
}

struct NewTripPackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings
    let onCreate: (String, String, Date?, Date?) async -> Void
    @State private var name = ""
    @State private var city = ""
    @State private var hasDates = true
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(localized("Trip name", "行程名稱"), text: $name)
                        .accessibilityIdentifier("trip.create.name")
                    TextField(localized("City or area", "城市或區域"), text: $city)
                        .accessibilityIdentifier("trip.create.city")
                }
                .saveNotebookListRow()
                Section {
                    Toggle(localized("Set dates", "設定日期"), isOn: $hasDates)
                    if hasDates {
                        DatePicker(localized("Starts", "開始"), selection: $startDate, displayedComponents: .date)
                        DatePicker(
                            localized("Ends", "結束"),
                            selection: $endDate,
                            in: startDate...,
                            displayedComponents: .date
                        )
                    }
                }
                .saveNotebookListRow()
            }
            .saveNotebookListCanvas()
            .navigationTitle(localized("New Trip Pack", "新增 Trip Pack"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Cancel", "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("Create", "建立")) {
                        isCreating = true
                        Task {
                            await onCreate(
                                name.trimmingCharacters(in: .whitespacesAndNewlines),
                                city.trimmingCharacters(in: .whitespacesAndNewlines),
                                hasDates ? startDate : nil,
                                hasDates ? endDate : nil
                            )
                            isCreating = false
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                    .accessibilityIdentifier("trip.create.submit")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.create.sheet")
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private enum TripWorkspaceTab: Hashable, CaseIterable, Identifiable {
    case plan
    case map
    case inbox
    case share

    var id: Self { self }

    var atlasTitle: String {
        switch self {
        case .plan: "Plan"
        case .map: "Map"
        case .inbox: "Inbox"
        case .share: "Share"
        }
    }

    var atlasIcon: String {
        switch self {
        case .plan: "map"
        case .map: "globe.asia.australia"
        case .inbox: "envelope"
        case .share: "point.3.connected.trianglepath.dotted"
        }
    }
}

enum TripWorkspaceBadge {
    nonisolated static func label(for candidateCount: Int) -> String? {
        guard candidateCount > 0 else { return nil }
        return candidateCount > 99 ? "99+" : String(candidateCount)
    }
}

struct TripWorkspaceView: View {
    let tripID: UUID
    @ObservedObject var store: TripPackStore
    @ObservedObject var mapViewModel: MapViewModel
    let storageScope: ContentStorageScope
    let onOpenDrawer: (DrawerLaunchTarget, UUID?) -> Void
    let onOpenReviewCandidate: (PlaceReviewCandidate, UUID?) -> Void
    let onOpenSavedPlace: (Place) -> Void
    let onActiveTripChange: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var selectedTab: TripWorkspaceTab = .plan

    var body: some View {
        Group {
            if let trip = store.trips.first(where: { $0.id == tripID }) {
                ReferenceViewport {
                    ZStack(alignment: .topLeading) {
                        Group {
                            switch selectedTab {
                            case .plan:
                                TripPlanView(
                                    trip: trip,
                                    store: store,
                                    savedPlaces: mapViewModel.places,
                                    onBack: { dismiss() }
                                )
                            case .map:
                                TripMapView(
                                    trip: trip,
                                    mapViewModel: mapViewModel,
                                    onBack: { dismiss() },
                                    onOpenPlace: onOpenSavedPlace
                                )
                            case .inbox:
                                TripInboxView(
                                    tripName: trip.name,
                                    candidates: mapViewModel.reviewCandidates,
                                    onSelect: { onOpenReviewCandidate($0, trip.id) },
                                    onOpenCapture: { onOpenDrawer(.addLink, trip.id) }
                                )
                                .frame(width: 402, height: 786)
                                .clipped()
                            case .share:
                                TripPackShareView(
                                    trip: trip,
                                    places: mapViewModel.places,
                                    storageScope: storageScope
                                )
                                .frame(width: 402, height: 786)
                                .clipped()
                            }
                        }

                        AtlasTabBar(
                            items: TripWorkspaceTab.allCases,
                            selection: selectedTab,
                            title: \.atlasTitle,
                            icon: \.atlasIcon,
                            accessibilityPrefix: "trip.tab",
                            onSelect: { selectedTab = $0 }
                        )
                        .placed(x: 0, y: 786, width: 402, height: 76)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            } else {
                ContentUnavailableView(
                    localized("Trip unavailable", "找不到行程"),
                    systemImage: "suitcase.rolling",
                    description: Text(localized("Return to Trips and open it again.", "請回到行程首頁後重新打開。"))
                )
                .background(SaveDottedBackground().ignoresSafeArea())
            }
        }
        .tint(SaveAtlasPalette.forest)
        .onAppear {
            store.selectTrip(tripID)
            onActiveTripChange(tripID)
        }
        .onDisappear {
            onActiveTripChange(nil)
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct TripPlanView: View {
    let trip: Trip
    @ObservedObject var store: TripPackStore
    let savedPlaces: [Place]
    let onBack: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var showsPlacePicker = false
    @State private var selectedStop: TripStop?
    @State private var selectedDay = 1

    var body: some View {
        TripPlanScreen(onBack: onBack)
        .environment(\.atlasPresentation, atlasPresentation)
        .overlay(alignment: .top) {
            if store.isSaving {
                ProgressView(localized("Saving…", "正在保存…"))
                    .font(SaveAtlasType.display(13))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .saveAtlasPaper(radius: 40, shadow: true)
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showsPlacePicker) {
            SavedPlacePicker(places: availablePlaces, initialDay: resolvedSelectedDay) { place, day in
                Task { _ = await store.addConfirmedPlace(place, to: trip.id, day: day) }
            }
        }
        .sheet(item: $selectedStop) { stop in
            TripStopEditorView(
                stop: stop,
                onSave: { day, startTime, duration, note in
                    await store.updateStop(
                        stop.id,
                        in: trip.id,
                        day: day,
                        startTime: startTime,
                        duration: duration,
                        note: note
                    )
                },
                onRemove: {
                    await store.removeStop(stop.id, from: trip.id)
                }
            )
        }
        .onAppear(perform: normalizeSelectedDay)
        .onChange(of: availableDays) { _, _ in normalizeSelectedDay() }
        .accessibilityIdentifier("trip.plan")
    }

    private var atlasPresentation: AtlasPresentation {
        SaveAtlasPresentationFactory.trip(
            trip: trip,
            selectedDay: resolvedSelectedDay,
            places: savedPlaces,
            onSelectDay: { selectedDay = $0 },
            onOpenStop: { selectedStop = $0 },
            onAddStop: { showsPlacePicker = true },
            onOpenPlace: { _ in }
        )
    }

    private var availableDays: [Int] {
        Set(trip.places.map(\.day)).sorted()
    }

    private var resolvedSelectedDay: Int {
        availableDays.contains(selectedDay) ? selectedDay : (availableDays.first ?? 1)
    }

    private var groupedStops: [(day: Int, stops: [TripStop])] {
        Dictionary(grouping: trip.places, by: \.day)
            .map { day, stops in
                (day, stops.sorted { $0.orderIndex < $1.orderIndex })
            }
            .sorted { $0.day < $1.day }
    }

    private var displayedGroups: [(day: Int, stops: [TripStop])] {
        groupedStops.filter { $0.day == resolvedSelectedDay }
    }

    private var selectedDateText: String {
        guard let startDate = trip.startDate,
              let date = Calendar.current.date(byAdding: .day, value: resolvedSelectedDay - 1, to: startDate)
        else {
            return localized("DAY \(resolvedSelectedDay)", "第 \(resolvedSelectedDay) 天")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: languageSettings.language == .english ? "en_US" : "zh_Hant_TW")
        formatter.dateFormat = languageSettings.language == .english ? "EEEE, MMMM d" : "M月d日 EEEE"
        return formatter.string(from: date).uppercased()
    }

    private var tripHighlightsTitle: String {
        let city = trip.city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else {
            return localized("Trip highlights", "行程精選")
        }
        return localized("\(city) highlights", "\(city)精選")
    }

    private var stopCountText: String {
        let count = displayedGroups.first?.stops.count ?? 0
        return localized(
            count == 1 ? "1 stop" : "\(count) stops",
            "\(count) 個停靠點"
        )
    }

    private var availablePlaces: [Place] {
        let usedIDs = Set(trip.places.map(\.placeId))
        return savedPlaces.filter { !usedIDs.contains($0.id) }
    }

    private func savedPlace(for stop: TripStop) -> Place? {
        savedPlaces.first { $0.id == stop.placeId }
    }

    private func normalizeSelectedDay() {
        if !availableDays.isEmpty, !availableDays.contains(selectedDay) {
            selectedDay = availableDays[0]
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct TripDayTabs: View {
    let days: [Int]
    let selectedDay: Int
    let dayTitle: (Int) -> String
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    Button {
                        onSelect(day)
                    } label: {
                        Text(dayTitle(day))
                            .font(
                                day == selectedDay
                                    ? SaveAtlasType.strong(15)
                                    : SaveAtlasType.body(15)
                            )
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .frame(minWidth: 92, minHeight: 44)
                            .padding(.horizontal, 8)
                            .background(dayTint(for: day, selected: day == selectedDay))
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
                                .stroke(
                                    SaveAtlasPalette.line.opacity(day == selectedDay ? 0.38 : 0.24),
                                    lineWidth: 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(day == selectedDay ? .isSelected : [])
                    .accessibilityIdentifier("trip.day.\(day)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .frame(minHeight: 48)
        .background(SaveAtlasPalette.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SaveAtlasPalette.line.opacity(0.26))
                .frame(height: 1)
        }
    }

    private func dayTint(for day: Int, selected: Bool) -> Color {
        guard selected else { return SaveAtlasPalette.paper }
        return day.isMultiple(of: 2) ? SaveAtlasPalette.mint : SaveAtlasPalette.lavender
    }
}

private struct TripPlanTitleBlock: View {
    let eyebrow: String
    let title: String
    let stopCount: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(SaveAtlasType.strong(11))
                    .tracking(0.8)
                    .foregroundStyle(SaveAtlasPalette.muted)

                Text(title)
                    .font(SaveAtlasType.strong(26, relativeTo: .title2))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(stopCount)
                .font(SaveAtlasType.display(14))
                .foregroundStyle(SaveAtlasPalette.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(SaveAtlasPalette.mint, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(SaveAtlasPalette.forest.opacity(0.24), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trip.plan.summary")
    }
}

private struct TripStopRow: View {
    let stop: TripStop
    let place: Place?
    let position: Int
    let isLast: Bool
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let onEdit: () -> Void
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TripRouteNode(position: position, isLast: isLast)

            VStack(spacing: 8) {
                editButton
                moveControls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(10)
            .saveAtlasPaper(radius: 18, shadow: true)
        }
    }

    private var editButton: some View {
        Button(action: onEdit) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        TripStopThumbnail(place: place)
                        stopDetails
                        Image(systemName: "chevron.right")
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    HStack(spacing: 12) {
                        TripStopThumbnail(place: place)
                        stopDetails
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(SaveAtlasPalette.ink)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(localized("Edit \(stop.placeName)", "編輯 \(stop.placeName)"))
        .accessibilityIdentifier("trip.stop.\(stop.id.uuidString).edit")
    }

    private var stopDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stop.placeName)
                .font(SaveAtlasType.strong(17, relativeTo: .headline))
                .foregroundStyle(SaveAtlasPalette.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)

            if !scheduleSummary.isEmpty {
                Label(scheduleSummary, systemImage: "clock")
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .lineLimit(1)
            }

            if !noteSummary.isEmpty {
                Text(noteSummary)
                    .font(SaveAtlasType.regular(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moveControls: some View {
        HStack(spacing: 6) {
            moveButton(systemImage: "arrow.up", enabled: canMoveEarlier, action: onMoveEarlier)
                .accessibilityLabel(localized("Move earlier", "往前移"))
                .accessibilityIdentifier("trip.stop.\(stop.id.uuidString).moveEarlier")
            moveButton(systemImage: "arrow.down", enabled: canMoveLater, action: onMoveLater)
                .accessibilityLabel(localized("Move later", "往後移"))
                .accessibilityIdentifier("trip.stop.\(stop.id.uuidString).moveLater")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var scheduleSummary: String {
        [
            stop.startTime?.trimmingCharacters(in: .whitespacesAndNewlines),
            stop.duration.map {
                localized("\($0) min", "\($0) 分鐘")
            },
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " · ")
    }

    private var noteSummary: String {
        if let note = stop.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            return note
        }
        return place?.address.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func moveButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(width: 36, height: 36)
                .background(SaveAtlasPalette.mint.opacity(0.78), in: Circle())
                .overlay {
                    Circle()
                        .stroke(SaveAtlasPalette.forest.opacity(0.24), lineWidth: 1)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.30)
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct TripRouteNode: View {
    let position: Int
    let isLast: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text("\(position)")
                .font(SaveAtlasType.strong(17))
                .foregroundStyle(SaveAtlasPalette.ink)
                .frame(width: 38, height: 38)
                .background(SaveAtlasPalette.coral.opacity(0.90), in: Circle())
                .overlay {
                    Circle()
                        .stroke(SaveAtlasPalette.coral, lineWidth: 1)
                }

            if !isLast {
                VStack(spacing: 4) {
                    ForEach(0..<11, id: \.self) { _ in
                        Circle()
                            .fill(SaveAtlasPalette.line.opacity(0.58))
                            .frame(width: 2.5, height: 2.5)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(width: 42)
        .background(alignment: .top) {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(
                    position.isMultiple(of: 2)
                        ? SaveAtlasPalette.lavender.opacity(0.50)
                        : SaveAtlasPalette.sky.opacity(0.42)
                )
                .frame(width: 30, height: isLast ? 46 : 104)
                .offset(y: 6)
        }
        .accessibilityHidden(true)
    }
}

private struct TripStopThumbnail: View {
    let place: Place?

    var body: some View {
        Group {
            if let urlString = place?.businessPhotoURLStrings.first,
               let url = URL(string: urlString) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                            .tint(SaveAtlasPalette.forest)
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 70, height: 72)
        .background(SaveAtlasPalette.mint.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.28), lineWidth: 1)
        }
    }

    private var fallback: some View {
        Image(systemName: place?.category.iconName ?? "mappin.and.ellipse")
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(SaveAtlasPalette.forest)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TripStopEditorView: View {
    let stop: TripStop
    let onSave: (Int, String?, Int?, String?) async -> Bool
    let onRemove: () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var day: Int
    @State private var startTime: String
    @State private var duration: String
    @State private var note: String
    @State private var isSubmitting = false
    @State private var showsRemoveConfirmation = false

    init(
        stop: TripStop,
        onSave: @escaping (Int, String?, Int?, String?) async -> Bool,
        onRemove: @escaping () async -> Bool
    ) {
        self.stop = stop
        self.onSave = onSave
        self.onRemove = onRemove
        _day = State(initialValue: min(max(stop.day, 1), 365))
        _startTime = State(initialValue: stop.startTime ?? "")
        _duration = State(initialValue: stop.duration.map(String.init) ?? "")
        _note = State(initialValue: stop.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(localized("Schedule", "日程")) {
                    Stepper(value: $day, in: 1...365) {
                        LabeledContent(localized("Day", "天數"), value: "\(day)")
                    }
                    .accessibilityIdentifier("trip.stop.edit.dayPicker")

                    TextField(localized("Start time (for example, 09:30)", "開始時間（例如 09:30）"), text: $startTime)
                        .accessibilityIdentifier("trip.stop.edit.startTime")

                    TextField(localized("Duration in minutes", "停留分鐘數"), text: $duration)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("trip.stop.edit.duration")

                    if !durationIsValid {
                        Text(localized("Enter 1–1,440 minutes.", "請輸入 1 到 1,440 分鐘。"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .saveNotebookListRow()

                Section(localized("Private note", "私人筆記")) {
                    TextField(localized("Add a note", "加入筆記"), text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("trip.stop.edit.note")
                }
                .saveNotebookListRow()

                Section {
                    Button(localized("Remove from Trip Pack", "從 Trip Pack 移除"), role: .destructive) {
                        showsRemoveConfirmation = true
                    }
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("trip.stop.edit.remove")
                }
                .saveNotebookListRow()
            }
            .saveNotebookListCanvas()
            .navigationTitle(stop.placeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Cancel", "取消")) { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("Save", "保存")) {
                        save()
                    }
                    .disabled(!durationIsValid || isSubmitting)
                    .accessibilityIdentifier("trip.stop.edit.save")
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .alert(
            localized("Remove this stop?", "移除這個行程地點？"),
            isPresented: $showsRemoveConfirmation
        ) {
            Button(localized("Cancel", "取消"), role: .cancel) {}
            Button(localized("Remove", "移除"), role: .destructive) {
                remove()
            }
            .accessibilityIdentifier("trip.stop.edit.remove.confirm")
        } message: {
            Text(localized(
                "The confirmed Map Stamp stays in SAV-E; only this Trip Pack stop is removed.",
                "已確認地圖章仍會保留在 SAV-E，只會從這個 Trip Pack 移除。"
            ))
        }
        .accessibilityIdentifier("trip.stop.edit")
    }

    private var trimmedDuration: String {
        duration.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var durationIsValid: Bool {
        trimmedDuration.isEmpty || (Int(trimmedDuration).map { (1...1_440).contains($0) } ?? false)
    }

    private func save() {
        guard durationIsValid else { return }
        isSubmitting = true
        Task {
            let didSave = await onSave(
                day,
                optionalValue(startTime),
                trimmedDuration.isEmpty ? nil : Int(trimmedDuration),
                optionalValue(note)
            )
            isSubmitting = false
            if didSave {
                dismiss()
            }
        }
    }

    private func remove() {
        isSubmitting = true
        Task {
            let didRemove = await onRemove()
            isSubmitting = false
            if didRemove {
                dismiss()
            }
        }
    }

    private func optionalValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct SavedPlacePicker: View {
    let places: [Place]
    let onSelect: (Place, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var query = ""
    @State private var selectedDay: Int

    init(places: [Place], initialDay: Int, onSelect: @escaping (Place, Int) -> Void) {
        self.places = places
        self.onSelect = onSelect
        _selectedDay = State(initialValue: min(max(initialDay, 1), 365))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper(value: $selectedDay, in: 1...365) {
                        LabeledContent(localized("Destination day", "加入天數"), value: "\(selectedDay)")
                    }
                    .accessibilityIdentifier("trip.add.dayPicker")
                }
                .saveNotebookListRow()

                Section(localized("Saved places", "收藏地點")) {
                    ForEach(filteredPlaces) { place in
                        Button {
                            onSelect(place, selectedDay)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name).font(.body.weight(.semibold))
                                Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .saveNotebookListRow()
            }
            .listStyle(.insetGrouped)
            .saveNotebookListCanvas()
            .navigationTitle(localized("Add saved place", "加入收藏地點"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("Cancel", "取消")) { dismiss() }
                }
            }
        }
    }

    private var filteredPlaces: [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return places }
        return places.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.address.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct TripMapView: View {
    let trip: Trip
    @ObservedObject var mapViewModel: MapViewModel
    let onBack: () -> Void
    let onOpenPlace: (Place) -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        Group {
            if SaveAtlasRuntime.usesParityFixture {
                TripAtlasMapScreen(onBack: onBack)
                    .environment(\.atlasPresentation, atlasPresentation)
            } else {
                SaveAtlasInteractiveTripMap(
                    mapViewModel: mapViewModel,
                    trip: trip,
                    presentation: atlasPresentation,
                    onBack: onBack
                )
            }
        }
    }

    private var atlasPresentation: AtlasPresentation {
        SaveAtlasPresentationFactory.trip(
            trip: trip,
            selectedDay: trip.places.map(\.day).min() ?? 1,
            places: mapViewModel.places,
            onSelectDay: { _ in },
            onOpenStop: { _ in },
            onAddStop: {},
            onOpenPlace: onOpenPlace
        )
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
        var positions: [UUID: Int] = [:]
        for (index, id) in routePoints.map(\.id).enumerated() where positions[id] == nil {
            positions[id] = index + 1
        }
        return positions
    }

    private var routeSummary: String {
        let count = routePoints.count
        return languageSettings.localized(
            english: count == 1 ? "1 confirmed stop" : "\(count) confirmed stops",
            traditionalChinese: "\(count) 個已確認停靠點"
        )
    }

    private func applyRoute() {
        mapViewModel.apply(MapActionData(
            type: .showRoute,
            placeIds: routePoints.map(\.id.uuidString),
            lat: nil,
            lng: nil,
            span: nil
        ))
    }

    private struct RoutePoint: Hashable {
        let id: UUID
        let latitude: Double
        let longitude: Double
    }
}

private struct TripInboxView: View {
    let tripName: String
    let candidates: [PlaceReviewCandidate]
    let onSelect: (PlaceReviewCandidate) -> Void
    let onOpenCapture: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        List {
            Section {
                Text(localized(
                    "This is your SAV-E-wide Review queue. Confirm an exact place, then choose whether to add it to \(tripName).",
                    "這是 SAV-E 的全域待確認清單。確認精確地點後，再選擇是否加入「\(tripName)」。"
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .saveNotebookListRow()

            Section {
                Button(action: onOpenCapture) {
                    Label(localized("Add a link", "加入連結"), systemImage: "link.badge.plus")
                }
                .accessibilityIdentifier("trip.inbox.addLink")
            }
            .saveNotebookListRow()

            Section(localized("SAV-E Needs Review", "SAV-E 待確認")) {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        localized("Inbox is clear", "收件匣已清空"),
                        systemImage: "tray",
                        description: Text(localized("Share a link to start an investigation.", "分享連結即可開始分析。"))
                    )
                } else {
                    ForEach(candidates) { candidate in
                        Button {
                            onSelect(candidate)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.name).font(.body.weight(.semibold))
                                    Text(candidate.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("trip.inbox.candidate.\(candidate.id.uuidString)")
                    }
                }
            }
            .saveNotebookListRow()
        }
        .listStyle(.insetGrouped)
        .saveNotebookListCanvas()
        .accessibilityIdentifier("trip.inbox")
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct TripPackShareView: View {
    let trip: Trip
    let places: [Place]
    let storageScope: ContentStorageScope
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var kmlShareItem: TripPackKMLShareItem?
    @State private var isExportingKML = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if let shareURL {
                    ShareLink(item: shareURL) {
                        Label(localized("Share SAV-E Link", "分享 SAV-E 連結"), systemImage: "link")
                    }
                    .accessibilityIdentifier("trip.share.link")
                } else {
                    Label(
                        localized("Add at least one confirmed Map Stamp before sharing.", "至少加入一個已確認地圖章後才能分享。"),
                        systemImage: "info.circle"
                    )
                    .foregroundStyle(.secondary)
                }

                Button {
                    Task { await exportKML() }
                } label: {
                    if isExportingKML {
                        HStack {
                            ProgressView()
                            Text(localized("Preparing KML…", "正在準備 KML…"))
                        }
                    } else {
                        Label(localized("Export KML", "匯出 KML"), systemImage: "doc.badge.arrow.up")
                    }
                }
                .disabled(isExportingKML || orderedConfirmedPlaceIDs.isEmpty)
                .accessibilityIdentifier("trip.share.kml")
            } header: {
                Text(localized("Trip Pack", "Trip Pack"))
            } footer: {
                Text(localized(
                    "SAV-E links and KML include confirmed place details only. Private notes are excluded.",
                    "SAV-E 連結與 KML 只包含已確認地點；私人備註不會輸出。"
                ))
            }
            .saveNotebookListRow()
        }
        .listStyle(.insetGrouped)
        .saveNotebookListCanvas()
        .sheet(item: $kmlShareItem, onDismiss: cleanupKMLFile) { item in
            ShareSheet(items: [item.url])
                .accessibilityIdentifier("trip.share.kml.sheet")
        }
        .alert(
            localized("Couldn’t export KML", "無法匯出 KML"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(languageSettings.text(.ok)) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            if kmlShareItem == nil { cleanupKMLFile() }
        }
    }

    private var shareURL: URL? {
        SharedTripData.from(trip: trip, places: places)?.toURL()
    }

    private var orderedConfirmedPlaceIDs: [UUID] {
        let availableIDs = Set(places.map(\.id))
        var seen = Set<UUID>()
        return trip.places
            .sorted { ($0.day, $0.orderIndex) < ($1.day, $1.orderIndex) }
            .compactMap { stop in
                guard availableIDs.contains(stop.placeId), seen.insert(stop.placeId).inserted else { return nil }
                return stop.placeId
            }
    }

    private var kmlFileURL: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("save-trip-pack-\(trip.id.uuidString).kml")
    }

    private func exportKML() async {
        guard !orderedConfirmedPlaceIDs.isEmpty else { return }
        isExportingKML = true
        defer { isExportingKML = false }
        do {
            cleanupKMLFile()
            let data: Data
            if storageScope == .reviewerDemo {
                data = try TripKMLExportService.reviewerDemoData(
                    placeIDs: orderedConfirmedPlaceIDs,
                    places: places
                )
            } else {
                data = try await SupabaseService.shared.exportTrekKml(placeIds: orderedConfirmedPlaceIDs)
            }
            try data.write(to: kmlFileURL, options: [.atomic, .completeFileProtection])
            kmlShareItem = TripPackKMLShareItem(url: kmlFileURL)
        } catch {
            cleanupKMLFile()
            errorMessage = error.localizedDescription
        }
    }

    private func cleanupKMLFile() {
        guard FileManager.default.fileExists(atPath: kmlFileURL.path) else { return }
        try? FileManager.default.removeItem(at: kmlFileURL)
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct TripPackKMLShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
