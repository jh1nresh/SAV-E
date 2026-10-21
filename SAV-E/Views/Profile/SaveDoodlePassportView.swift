import CoreLocation
import SwiftUI

/// Doodle v1 Passport: sticker grid, city list, and Collected (spec §7.4).
struct SaveDoodlePassportPage: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @EnvironmentObject private var session: SaveDoodleSession
    @ObservedObject private var locationService = LocationService.shared

    let places: [Place]
    var onOpenPlace: (Place) -> Void = { _ in }
    var onMarkVisited: (Place) async -> Bool = { _ in true }
    var onOpenCollected: () -> Void = {}
    var showsCloseButton = false
    var onClose: () -> Void = {}

    @State private var showsCityPicker = false
    @State private var stampingID: String?
    @State private var visitError: String?
    @State private var visitRevision = 0
    @State private var gridWidth: CGFloat = 0
    private let visitStore = SavePassportVisitStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, AtlasMetrics.statusBarHeight + SaveSpace.xs)
                    .padding(.bottom, SaveLayout.titleToMeta)

                subtitle
                    .padding(.bottom, SaveLayout.sectionGap)

                kraftPanel
                    .padding(.bottom, SaveLayout.sectionGap)

                citiesRow
            }
            .padding(.horizontal, SaveLayout.screenMargin)
            .padding(.bottom, SaveTileTownProductLock.rootTabScrollClearance)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SaveDottedBackground().ignoresSafeArea())
        .onAppear { visitRevision += 1 }
        .sheet(isPresented: $showsCityPicker) {
            cityPicker
        }
    }

    private var header: some View {
        HStack(spacing: SaveSpace.xs) {
            if showsCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .frame(width: SaveLayout.minTap, height: SaveLayout.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageSettings.localized(english: "Close", traditionalChinese: "關閉"))
                .accessibilityIdentifier("profile.close")
            }

            SaveDisplayTitle(
                text: languageSettings.localized(english: "Passport", traditionalChinese: "護照"),
                pointSize: 34,
                relativeTo: .largeTitle,
                locksPointSize: true
            )
            .accessibilityIdentifier("profile.brandLogo")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: SaveLayout.minTap, alignment: .leading)
    }

    private var subtitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: SaveSpace.tight) {
            Button { showsCityPicker = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: SaveSpace.tight) {
                    VStack(alignment: .leading, spacing: 0) {
                        SaveDisplayTitle(
                            text: cityTitle,
                            pointSize: 20,
                            relativeTo: .title3,
                            locksPointSize: true
                        )
                        Capsule()
                            .fill(SaveAtlasPalette.coral)
                            .frame(height: 2)
                            .padding(.top, 1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    Text("▾")
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.forest)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("passport.citySwitcher")
            .accessibilityLabel(cityTitle)

            Text("·")
                .font(SaveAtlasType.body(15))
                .foregroundStyle(SaveAtlasPalette.muted)

            Button(action: onOpenCollected) {
                Text(visitedLine)
                    .font(SaveAtlasType.body(15))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .frame(minHeight: SaveLayout.minTap, alignment: .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.stampProgress")
            .accessibilityLabel(visitedLine)

            Spacer(minLength: 0)
        }
        .frame(minHeight: SaveLayout.minTap, alignment: .leading)
    }

    private var kraftPanel: some View {
        VStack(alignment: .leading, spacing: SaveSpace.md) {
            if let visitError {
                Text(visitError)
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.stamp.visitError")
            }
            if showsEmptyPassport {
                emptyPassport
            } else {
                stickerGrid
                legend
            }
        }
        .padding(SaveDoodlePassportCatalog.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            SaveAtlasPalette.kraft,
            in: RoundedRectangle(cornerRadius: SaveAtlasPalette.cardRadius, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.stampGrid")
    }

    private var showsEmptyPassport: Bool {
        !SaveDoodlePassportCatalog.usesDoodleFace && cityPlaces.isEmpty
    }

    private var emptyPassport: some View {
        VStack(spacing: SaveSpace.md) {
            SaveDoodleElephant(size: SaveLayout.passportSlot)
            Text(languageSettings.localized(
                english: "No stickers yet",
                traditionalChinese: "還沒有貼紙"
            ))
            .font(SaveAtlasType.strong(17))
            .foregroundStyle(SaveAtlasPalette.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("passport.empty")
    }

    private var stickerGrid: some View {
        let columns = SaveDoodlePassportCatalog.columnCount(availableGridWidth: gridWidth > 0 ? gridWidth : 306)
        let items = Array(
            repeating: GridItem(
                .fixed(SaveDoodlePassportCatalog.slotSize),
                spacing: SaveDoodlePassportCatalog.minColumnGap
            ),
            count: columns
        )
        return LazyVGrid(columns: items, alignment: .leading, spacing: SaveDoodlePassportCatalog.rowGap) {
            ForEach(slots) { slot in
                slotButton(slot)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SaveDoodlePassportGridWidthKey.self,
                    value: proxy.size.width
                )
            }
        )
        .onPreferenceChange(SaveDoodlePassportGridWidthKey.self) { gridWidth = $0 }
    }

    private func slotButton(_ slot: SaveDoodlePassportSlot) -> some View {
        Button {
            handleTap(slot)
        } label: {
            SaveDoodlePassportSlotView(
                slot: slot,
                isStamping: stampingID == slot.id
            )
            .frame(maxWidth: .infinity)
            .frame(height: SaveDoodlePassportCatalog.slotSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: SaveLayout.minTap, minHeight: SaveLayout.minTap)
        .disabled({
            if case .empty = slot.content { return true }
            return false
        }())
        .accessibilityIdentifier(slotAccessibilityID(slot))
        .accessibilityLabel(slotAccessibilityLabel(slot))
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: SaveSpace.xs) {
                legendItems
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: SaveSpace.xs) {
                legendItems
            }
        }
        .font(SaveAtlasType.body(13))
        .foregroundStyle(SaveAtlasPalette.muted)
        .accessibilityIdentifier("passport.legend")
    }

    @ViewBuilder
    private var legendItems: some View {
        HStack(spacing: SaveSpace.tight) {
            legendSwatch(rank: .single)
            Text(languageSettings.localized(english: "single ring  1", traditionalChinese: "單圈  1"))
        }
        HStack(spacing: SaveSpace.tight) {
            legendSwatch(rank: .double)
            Text(languageSettings.localized(english: "double ring  3", traditionalChinese: "雙圈  3"))
        }
        HStack(spacing: SaveSpace.tight) {
            legendSwatch(rank: .gold)
            Text(languageSettings.localized(english: "gold  5", traditionalChinese: "金  5"))
        }
    }

    private func legendSwatch(rank: SavePassportStampRank) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(rank == .gold ? SaveDoodle.stampGold : SaveDoodle.stampRed)
            .frame(width: 8, height: 8)
    }

    private var citiesRow: some View {
        Button { showsCityPicker = true } label: {
            HStack(spacing: SaveSpace.tight) {
                Text(citiesLine)
                    .font(SaveAtlasType.body(15))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: SaveSpace.tight)
                Text("›")
                    .font(SaveAtlasType.strong(17))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
            .frame(maxWidth: .infinity, minHeight: SaveLayout.minTap, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("passport.cities")
        .accessibilityLabel(citiesLine)
    }

    private var cityPicker: some View {
        NavigationStack {
            List {
                if !locationService.isAuthorizationDenied {
                    Button {
                        session.city = .nearYou
                        showsCityPicker = false
                    } label: {
                        HStack {
                            Text(languageSettings.localized(
                                english: "Near you (current location)",
                                traditionalChinese: "附近（目前位置）"
                            ))
                            Spacer()
                            if case .nearYou = session.city {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SaveAtlasPalette.coral)
                            }
                        }
                    }
                    .accessibilityIdentifier("passport.city.nearYou")
                }
                ForEach(cityGroups) { group in
                    Button {
                        session.city = .city(group.id)
                        showsCityPicker = false
                    } label: {
                        HStack {
                            Text("\(group.displayName(language: languageSettings.language)) \(group.count)")
                            Spacer()
                            if case .city(let id) = resolvedSelection, id == group.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SaveAtlasPalette.coral)
                            }
                        }
                    }
                    .accessibilityIdentifier("passport.city.\(group.id)")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SaveAtlasPalette.paper)
            .navigationTitle(languageSettings.localized(english: "City", traditionalChinese: "城市"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(languageSettings.localized(english: "Close", traditionalChinese: "關閉")) {
                        showsCityPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var resolvedSelection: SaveDoodleCitySelection {
        SaveDoodleHomeCatalog.resolvedSelection(
            session.city,
            places: places,
            locationDenied: locationService.isAuthorizationDenied
        )
    }

    private var cityPlaces: [Place] {
        SaveDoodlePassportCatalog.cityPlaces(
            from: places,
            selection: session.city,
            location: passportLocation,
            locationDenied: locationService.isAuthorizationDenied
        )
    }

    private var slots: [SaveDoodlePassportSlot] {
        _ = visitRevision
        if SaveDoodlePassportCatalog.usesDoodleFace {
            return SaveDoodlePassportCatalog.doodleFaceSlots()
        }
        return SaveDoodlePassportCatalog.slots(
            from: places,
            selection: session.city,
            location: passportLocation,
            locationDenied: locationService.isAuthorizationDenied,
            visitStore: visitStore
        )
    }

    private var passportLocation: CLLocation? {
        locationService.isAuthorizationDenied ? nil : locationService.currentLocation
    }

    private var cityGroups: [SaveDoodleCityGroup] {
        SaveDoodleHomeCatalog.cityGroups(from: places)
    }

    private var cityTitle: String {
        if SaveDoodlePassportCatalog.usesDoodleFace {
            return SaveDoodlePassportCatalog.doodleFaceCityTitle
        }
        switch resolvedSelection {
        case .nearYou:
            if let first = cityPlaces.first,
               let name = SaveDoodleHomeCatalog.cityDisplayName(
                for: first,
                language: languageSettings.language
               ) {
                return name
            }
            return languageSettings.localized(english: "Nearby", traditionalChinese: "附近")
        case .city(let id):
            if let group = cityGroups.first(where: { $0.id == id }) {
                return group.displayName(language: languageSettings.language)
            }
            return SaveHomeSearch.cityLabel(
                for: id,
                traditionalChinese: languageSettings.language == .traditionalChinese
            ) ?? id
        }
    }

    private var visitedLine: String {
        if SaveDoodlePassportCatalog.usesDoodleFace {
            return SaveDoodlePassportCatalog.doodleFaceVisitedLine
        }
        let count = SaveDoodleHomeCatalog.cityCollectedCount(in: cityPlaces)
        return languageSettings.localized(
            english: "\(count.visited) of \(count.saved) visited",
            traditionalChinese: "已拜訪 \(count.visited) / \(count.saved)"
        )
    }

    private var citiesLine: String {
        if SaveDoodlePassportCatalog.usesDoodleFace {
            return SaveDoodlePassportCatalog.doodleFaceCitiesLine
        }
        let shown = cityGroups.prefix(2)
        let names = shown.map {
            "\($0.displayName(language: languageSettings.language)) \($0.count)"
        }
        let joined = names.joined(separator: " · ")
        if joined.isEmpty {
            return languageSettings.localized(english: "Cities", traditionalChinese: "城市")
        }
        return languageSettings.localized(
            english: "Cities: \(joined)",
            traditionalChinese: "城市：\(joined)"
        )
    }

    private func handleTap(_ slot: SaveDoodlePassportSlot) {
        guard case let .place(place, _, rank) = slot.content else { return }
        if rank == .none {
            visitError = nil
            Task {
                let didVisit = await onMarkVisited(place)
                if didVisit {
                    SaveHaptics.stamp()
                    stampingID = slot.id
                    visitStore.recordVisit(for: place.id)
                    try? await Task.sleep(nanoseconds: 420_000_000)
                    stampingID = nil
                } else {
                    SaveHaptics.warning()
                    visitError = languageSettings.localized(
                        english: "Couldn’t update this place. Please try again.",
                        traditionalChinese: "暫時無法更新這個地點，請再試一次。"
                    )
                }
            }
        } else {
            SaveHaptics.tap()
            onOpenPlace(place)
        }
    }

    private func slotAccessibilityID(_ slot: SaveDoodlePassportSlot) -> String {
        switch slot.content {
        case let .place(place, _, _):
            return "profile.stamp.\(place.id.uuidString)"
        case let .empty(index):
            return "profile.stamp.locked.\(index)"
        }
    }

    private func slotAccessibilityLabel(_ slot: SaveDoodlePassportSlot) -> String {
        switch slot.content {
        case let .place(place, _, rank):
            if rank == .none {
                return languageSettings.localized(
                    english: "\(place.name), not visited",
                    traditionalChinese: "\(place.name)，還沒去過"
                )
            }
            return languageSettings.localized(
                english: "\(place.name), visited",
                traditionalChinese: "\(place.name)，去過了"
            )
        case .empty:
            return languageSettings.localized(english: "Empty sticker", traditionalChinese: "空貼紙格")
        }
    }
}

private struct SaveDoodlePassportGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview("Passport light") {
    SaveDoodlePassportPreview()
        .preferredColorScheme(.light)
}

#Preview("Passport dark") {
    SaveDoodlePassportPreview()
        .preferredColorScheme(.dark)
}

private struct SaveDoodlePassportPreview: View {
    var body: some View {
        SaveDoodlePassportPage(
            places: ReviewDemoSeed.places()
        )
        .environmentObject(SaveDoodleSession(defaults: UserDefaults(suiteName: "save.doodle.passport.preview") ?? .standard))
        .background(SaveDottedBackground())
    }
}
