import MapKit
import SwiftUI

struct TripsHomeView: View {
    @ObservedObject var store: TripPackStore
    @ObservedObject var mapViewModel: MapViewModel
    let storageScope: ContentStorageScope
    let onOpenCapture: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var showsCreateTrip = false

    var body: some View {
        NavigationStack {
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
                .padding(.bottom, 108)
            }
            .background(Color.saveCream.ignoresSafeArea())
            .navigationTitle(localized("Trips", "行程"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsCreateTrip = true
                    } label: {
                        Label(localized("New Trip", "新增行程"), systemImage: "plus")
                    }
                    .accessibilityIdentifier("trips.create")
                }
            }
            .safeAreaInset(edge: .bottom) {
                captureButton
            }
            .refreshable {
                await store.load()
            }
        }
        .sheet(isPresented: $showsCreateTrip) {
            NewTripPackView { name, city, startDate, endDate in
                if let trip = await store.createTrip(
                    name: name,
                    city: city,
                    startDate: startDate,
                    endDate: endDate
                ) {
                    store.selectTrip(trip.id)
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
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
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
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.savePaper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var captureButton: some View {
        Button {
            onOpenCapture()
        } label: {
            Label(localized("Paste / Share Link", "貼上／分享連結"), systemImage: "link.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.saveCoral)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("trips.capture")
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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(trips) { trip in
                    NavigationLink {
                        TripWorkspaceView(
                            tripID: trip.id,
                            store: store,
                            mapViewModel: mapViewModel,
                            storageScope: storageScope,
                            onOpenCapture: onOpenCapture
                        )
                    } label: {
                        TripPackCard(trip: trip)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { store.selectTrip(trip.id) })
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
        HStack(spacing: 14) {
            Image(systemName: "suitcase.rolling.fill")
                .font(.title2)
                .foregroundStyle(Color.saveCoral)
                .frame(width: 48, height: 48)
                .background(Color.saveHoney.opacity(0.38), in: RoundedRectangle(cornerRadius: 15))

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(.headline)
                    .foregroundStyle(Color.saveInk)
                Text([trip.city, trip.dateRangeText].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(languageSettings.localized(
                    english: "\(trip.places.count) confirmed stops",
                    traditionalChinese: "\(trip.places.count) 個已確認地點"
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.saveCocoa)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(Color.savePaper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.32), lineWidth: 1)
        }
    }
}

private struct NewTripPackView: View {
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
                    TextField(localized("City or area", "城市或區域"), text: $city)
                }
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
            }
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
                }
            }
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private enum TripWorkspaceTab: Hashable {
    case plan
    case map
    case inbox
    case share
}

private struct TripWorkspaceView: View {
    let tripID: UUID
    @ObservedObject var store: TripPackStore
    @ObservedObject var mapViewModel: MapViewModel
    let storageScope: ContentStorageScope
    let onOpenCapture: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var selectedTab: TripWorkspaceTab = .plan

    var body: some View {
        Group {
            if let trip = store.trips.first(where: { $0.id == tripID }) {
                TabView(selection: $selectedTab) {
                    TripPlanView(trip: trip, store: store, savedPlaces: mapViewModel.places)
                        .tabItem { Label(localized("Plan", "日程"), systemImage: "list.number") }
                        .tag(TripWorkspaceTab.plan)
                        .accessibilityIdentifier("trip.tab.plan")

                    TripMapView(trip: trip, mapViewModel: mapViewModel)
                        .tabItem { Label(localized("Map", "地圖"), systemImage: "map") }
                        .tag(TripWorkspaceTab.map)
                        .accessibilityIdentifier("trip.tab.map")

                    TripInboxView(
                        candidates: mapViewModel.reviewCandidates,
                        onSelect: mapViewModel.selectReviewCandidate,
                        onOpenCapture: onOpenCapture
                    )
                    .tabItem { Label(localized("Inbox", "收件匣"), systemImage: "tray") }
                    .badge(mapViewModel.reviewCandidates.count)
                    .tag(TripWorkspaceTab.inbox)
                    .accessibilityIdentifier("trip.tab.inbox")

                    TripPackShareView(
                        trip: trip,
                        places: mapViewModel.places,
                        storageScope: storageScope
                    )
                        .tabItem { Label(localized("Share", "分享"), systemImage: "square.and.arrow.up") }
                        .tag(TripWorkspaceTab.share)
                        .accessibilityIdentifier("trip.tab.share")
                }
                .navigationTitle(trip.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onOpenCapture) {
                            Image(systemName: "link.badge.plus")
                        }
                        .accessibilityLabel(localized("Paste or share link", "貼上或分享連結"))
                    }
                }
                .accessibilityIdentifier("trip.workspace.\(trip.id.uuidString)")
            } else {
                ContentUnavailableView(
                    localized("Trip unavailable", "找不到行程"),
                    systemImage: "suitcase.rolling",
                    description: Text(localized("Return to Trips and open it again.", "請回到行程首頁後重新打開。"))
                )
            }
        }
        .onAppear { store.selectTrip(tripID) }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct TripPlanView: View {
    let trip: Trip
    @ObservedObject var store: TripPackStore
    let savedPlaces: [Place]
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var showsPlacePicker = false

    var body: some View {
        List {
            if trip.places.isEmpty {
                ContentUnavailableView {
                    Label(localized("No stops yet", "還沒有行程地點"), systemImage: "mappin.and.ellipse")
                } description: {
                    Text(localized(
                        "Confirm a link in Inbox, or choose an existing Map Stamp.",
                        "先在收件匣確認連結，或選擇既有地圖章。"
                    ))
                } actions: {
                    Button(localized("Add from SAV-E", "從 SAV-E 加入")) { showsPlacePicker = true }
                }
            } else {
                ForEach(groupedStops, id: \.day) { group in
                    Section(localized("Day \(group.day)", "第 \(group.day) 天")) {
                        ForEach(Array(group.stops.enumerated()), id: \.element.id) { index, stop in
                            TripStopRow(
                                stop: stop,
                                canMoveEarlier: index > 0 && !store.isSaving,
                                canMoveLater: index < group.stops.count - 1 && !store.isSaving,
                                onMoveEarlier: {
                                    Task { _ = await store.moveStop(stop.id, in: trip.id, by: -1) }
                                },
                                onMoveLater: {
                                    Task { _ = await store.moveStop(stop.id, in: trip.id, by: 1) }
                                }
                            )
                        }
                    }
                }
            }

            Section {
                Button {
                    showsPlacePicker = true
                } label: {
                    Label(localized("Add confirmed Map Stamp", "加入已確認地圖章"), systemImage: "plus.circle")
                }
                .disabled(availablePlaces.isEmpty)
            }
        }
        .overlay(alignment: .top) {
            if store.isSaving {
                ProgressView(localized("Saving…", "正在保存…"))
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showsPlacePicker) {
            SavedPlacePicker(places: availablePlaces) { place in
                Task { _ = await store.addConfirmedPlace(place, to: trip.id) }
            }
        }
    }

    private var groupedStops: [(day: Int, stops: [TripStop])] {
        Dictionary(grouping: trip.places, by: \.day)
            .map { day, stops in
                (day, stops.sorted { $0.orderIndex < $1.orderIndex })
            }
            .sorted { $0.day < $1.day }
    }

    private var availablePlaces: [Place] {
        let usedIDs = Set(trip.places.map(\.placeId))
        return savedPlaces.filter { !usedIDs.contains($0.id) }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct TripStopRow: View {
    let stop: TripStop
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.saveCoral)
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.placeName)
                    .font(.body.weight(.semibold))
                if let startTime = stop.startTime, !startTime.isEmpty {
                    Text(startTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 4) {
                moveButton(systemImage: "arrow.up", enabled: canMoveEarlier, action: onMoveEarlier)
                    .accessibilityLabel(localized("Move earlier", "往前移"))
                    .accessibilityIdentifier("trip.stop.\(stop.id.uuidString).moveEarlier")
                moveButton(systemImage: "arrow.down", enabled: canMoveLater, action: onMoveLater)
                    .accessibilityLabel(localized("Move later", "往後移"))
                    .accessibilityIdentifier("trip.stop.\(stop.id.uuidString).moveLater")
            }
        }
        .accessibilityIdentifier("trip.stop.\(stop.id.uuidString)")
    }

    private func moveButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}

private struct SavedPlacePicker: View {
    let places: [Place]
    let onSelect: (Place) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(filteredPlaces) { place in
                Button {
                    onSelect(place)
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
            .navigationTitle(localized("Add Map Stamp", "加入地圖章"))
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

    var body: some View {
        MapView(
            viewModel: mapViewModel,
            shouldFocusOnUserLocationOnLaunch: true,
            displayedPlaces: mapViewModel.placesForRoute(placeIDs: orderedPlaceIDs),
            showsAuxiliaryPins: false
        )
            .onAppear {
                mapViewModel.apply(MapActionData(
                    type: .showRoute,
                    placeIds: orderedPlaceIDs.map(\.uuidString),
                    lat: nil,
                    lng: nil,
                    span: nil
                ))
            }
            .onDisappear {
                mapViewModel.apply(MapActionData(type: .resetPins, placeIds: nil, lat: nil, lng: nil, span: nil))
            }
            .accessibilityIdentifier("trip.map")
    }

    private var orderedPlaceIDs: [UUID] {
        trip.places
            .sorted { ($0.day, $0.orderIndex) < ($1.day, $1.orderIndex) }
            .map(\.placeId)
    }
}

private struct TripInboxView: View {
    let candidates: [PlaceReviewCandidate]
    let onSelect: (PlaceReviewCandidate) -> Void
    let onOpenCapture: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        List {
            Section {
                Text(localized(
                    "Candidates stay outside the Trip Pack until you confirm the exact place.",
                    "候選地點會留在 Trip Pack 外，直到你確認精確地點。"
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section(localized("Waiting for confirmation", "等待確認")) {
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

            Section {
                Button(action: onOpenCapture) {
                    Label(localized("Paste / Share Link", "貼上／分享連結"), systemImage: "link.badge.plus")
                }
            }
        }
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
        }
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
