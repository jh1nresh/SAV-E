import SwiftUI

/// Doodle v1 Passport: sticker grid, city list, and Collected (spec §7.4).
struct SaveDoodlePassportPage: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @EnvironmentObject private var session: SaveDoodleSession
    @ObservedObject private var locationService = LocationService.shared

    let places: [Place]
    var collectionMode: SavePassportCollectionMode = .collection
    var onOpenPlace: (Place) -> Void = { _ in }
    var onMarkVisited: (Place) async -> Bool = { _ in true }
    var onOpenCollected: () -> Void = {}
    var showsCloseButton = false
    var onClose: () -> Void = {}

    @State private var showsCityPicker = false
    @State private var stampingID: String?
    @State private var visitRevision = 0
    @State private var gridWidth: CGFloat = 0
    @State private var visitError: String?
    private let visitStore = SavePassportVisitStore.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, AtlasMetrics.statusBarHeight + SaveSpace.lg)
                    .padding(.bottom, SaveSpace.sm)

                subtitle
                    .padding(.bottom, SaveSpace.xl)

                kraftPanel
                    .padding(.bottom, SaveLayout.sectionGap)
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
                pointSize: SaveDoodlePassportCatalog.titlePointSize,
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
                HStack(alignment: .center, spacing: SaveSpace.tight) {
                    SaveDoodleHandwriting(
                        text: cityTitle,
                        pointSize: SaveDoodlePassportCatalog.subtitlePointSize,
                        locksPointSize: true
                    )
                    SaveDoodleSolidCaret()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("passport.citySwitcher")
            .accessibilityLabel(cityTitle)

            SaveDoodleHandwriting(
                text: "·",
                pointSize: SaveDoodlePassportCatalog.subtitlePointSize,
                locksPointSize: true
            )

            Button(action: onOpenCollected) {
                SaveDoodleHandwriting(
                    text: visitedLine,
                    pointSize: SaveDoodlePassportCatalog.subtitlePointSize,
                    locksPointSize: true
                )
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
        let columns = SaveDoodlePassportCatalog.columnCount(
            availableGridWidth: measuredGridWidth
        )
        return VStack(alignment: .leading, spacing: SaveSpace.md) {
            if showsEmptyPassport {
                emptyPassport
            } else {
                stickerGrid
                legend
            }
            if let visitError {
                Text(visitError)
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("profile.stamp.visitError")
            }
            citiesRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { gridWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in gridWidth = width }
            }
        )
        .padding(SaveDoodlePassportCatalog.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(
                cornerRadius: SaveDoodlePassportCatalog.panelCornerRadius,
                style: .continuous
            )
            .fill(SaveDoodlePassportChrome.panelFill)
            .overlay {
                RoundedRectangle(
                    cornerRadius: SaveDoodlePassportCatalog.panelCornerRadius,
                    style: .continuous
                )
                .stroke(
                    SaveDoodlePassportChrome.panelStroke,
                    lineWidth: SaveDoodlePassportCatalog.panelStrokeWidth
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.stampGrid")
        .accessibilityValue("\(columns)")
    }

    /// Compact 375pt after 24pt screen + panel insets. Measuring the
    /// LazyVGrid's container feeds the column count from proposed width.
    private var measuredGridWidth: CGFloat {
        gridWidth > 0 ? gridWidth : 279
    }

    private var showsEmptyPassport: Bool {
        !SaveDoodlePassportCatalog.usesDoodleFace && cityPlaces.isEmpty
    }

    private var emptyPassport: some View {
        VStack(spacing: SaveSpace.md) {
            MemoMascotMark(size: SaveLayout.passportSlot, framed: false)
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
        let columns = SaveDoodlePassportCatalog.columnCount(availableGridWidth: measuredGridWidth)
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
            .frame(height: SaveDoodlePassportCatalog.cardHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: SaveLayout.minTap, minHeight: SaveLayout.minTap)
        .disabled({
            if stampingID != nil { return true }
            if case .empty = slot.content { return true }
            return false
        }())
        .accessibilityIdentifier(slotAccessibilityID(slot))
        .accessibilityLabel(slotAccessibilityLabel(slot))
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            legendItems
                .fixedSize(horizontal: true, vertical: false)
            legendItems
        }
        .accessibilityIdentifier("passport.legend")
    }

    private var legendItems: some View {
        HStack(alignment: .center, spacing: SaveSpace.tight) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(SaveDoodlePassportChrome.legendSwatch)
                .frame(
                    width: SaveDoodlePassportCatalog.legendSwatchSize,
                    height: SaveDoodlePassportCatalog.legendSwatchSize
                )
            SaveDoodleHandwriting(
                text: languageSettings.localized(
                    english: "single ring 1 · double ring 3 · gold 5",
                    traditionalChinese: "單圈 1 · 雙圈 3 · 金 5"
                ),
                pointSize: 18,
                relativeTo: .footnote
            )
        }
    }

    private var citiesRow: some View {
        Button { showsCityPicker = true } label: {
            HStack(spacing: SaveSpace.tight) {
                SaveDoodleHandwriting(
                    text: citiesLine,
                    pointSize: 20,
                    relativeTo: .body,
                    lineLimit: 1,
                    minimumScaleFactor: 0.85
                )
                Spacer(minLength: SaveSpace.tight)
                SaveDoodleHandwriting(
                    text: "›",
                    pointSize: 20,
                    color: SaveAtlasPalette.ink,
                    relativeTo: .body
                )
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
                ForEach(SaveDoodlePassportCatalog.pickerCityGroups(from: places, selection: session.city)) { group in
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
        SaveDoodlePassportCatalog.resolvedSelection(
            session.city,
            places: places,
            locationDenied: locationService.isAuthorizationDenied
        )
    }

    private var cityPlaces: [Place] {
        let scoped = SaveDoodlePassportCatalog.cityPlaces(
            from: places,
            selection: session.city,
            location: locationService.isAuthorizationDenied ? nil : locationService.currentLocation,
            locationDenied: locationService.isAuthorizationDenied
        )
        return scoped
    }

    private var slots: [SaveDoodlePassportSlot] {
        _ = visitRevision
        if SaveDoodlePassportCatalog.usesDoodleFace {
            return SaveDoodlePassportCatalog.doodleFaceSlots()
        }
        return SaveDoodlePassportCatalog.slots(
            from: places,
            selection: session.city,
            location: locationService.isAuthorizationDenied ? nil : locationService.currentLocation,
            locationDenied: locationService.isAuthorizationDenied,
            visitStore: visitStore
        )
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
        let progress = SaveDoodlePassportCatalog.progress(in: cityPlaces, collectionMode: collectionMode)
        return languageSettings.localized(
            english: "\(progress.visited) of \(progress.total) visited",
            traditionalChinese: "已拜訪 \(progress.visited) / \(progress.total)"
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
            guard stampingID == nil else { return }
            SaveHaptics.stamp()
            stampingID = slot.id
            Task {
                let didVisit = await onMarkVisited(place)
                if didVisit {
                    visitStore.recordVisit(for: place.id)
                    visitError = nil
                } else {
                    visitError = languageSettings.localized(
                        english: "Couldn’t update this place. Please try again.",
                        traditionalChinese: "暫時無法更新這個地點，請再試一次。"
                    )
                }
                try? await Task.sleep(nanoseconds: 420_000_000)
                stampingID = nil
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

/// Caveat + Iansui cascade. Latin uses Caveat-SemiBold; zh-Hant stays on
/// the Iansui fallback already registered in `SaveDisplayType`.
struct SaveDoodleHandwriting: View {
    let text: String
    var pointSize: CGFloat
    var color: Color = SaveAtlasPalette.ink
    var locksPointSize: Bool = false
    var relativeTo: Font.TextStyle = .body
    var lineLimit: Int? = nil
    var minimumScaleFactor: CGFloat = 1

    var body: some View {
        Text(text)
            .font(
                locksPointSize
                    ? SaveDisplayType.fixed(pointSize)
                    : SaveDisplayType.display(pointSize, relativeTo: relativeTo)
            )
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor)
    }
}

/// Solid ▼. Caveat has no black triangle glyph, so this stays a drawn mark
/// in the same ink as the subtitle handwriting.
struct SaveDoodleSolidCaret: View {
    var size: CGFloat = 9
    var color: Color = SaveAtlasPalette.ink

    var body: some View {
        Canvas { context, canvasSize in
            var path = Path()
            path.move(to: CGPoint(x: canvasSize.width * 0.50, y: canvasSize.height * 0.88))
            path.addLine(to: CGPoint(x: canvasSize.width * 0.08, y: canvasSize.height * 0.18))
            path.addLine(to: CGPoint(x: canvasSize.width * 0.92, y: canvasSize.height * 0.18))
            path.closeSubpath()
            context.fill(path, with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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
