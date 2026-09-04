import SwiftUI

struct SavePlanView: View {
    let savedPlaces: [Place]
    let mapCandidates: [SaveMapCandidate]
    @ObservedObject var tripStore: TripPackStore
    let onOpenTrip: (UUID) -> Void
    let onOpenPassport: () -> Void

    @Environment(\.appLanguageSettings) private var languageSettings
    @State private var selectedArea: String = ""
    @State private var days: Int = 2
    @State private var pace: ItineraryPace = .balanced
    @State private var usesArrival = false
    @State private var usesDeparture = false
    @State private var arrivalDate = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var departureDate = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var draft: SaveAIResponse?
    @State private var isPlanning = false
    @State private var planError: String?

    private var areas: [String] {
        SavePlanDraftBuilder.areas(from: savedPlaces)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()

            BrandHeader {
                EmptyView()
            }
            .placed(x: 0, y: 48, width: AtlasMetrics.width, height: 51)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heading
                    composer
                    if let draft {
                        draftCanvas(draft)
                    }
                    savedTrips
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 108)
            }
            .placed(x: 0, y: 105, width: AtlasMetrics.width, height: 674)
            if isPlanning {
                Color.black.opacity(0.08)
                    .frame(width: AtlasMetrics.width, height: AtlasMetrics.height)
                    .allowsHitTesting(true)
                ProgressView()
                    .padding(20)
                    .background(SaveAtlasPalette.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .placed(
                        x: (AtlasMetrics.width - 120) / 2,
                        y: 360,
                        width: 120,
                        height: 120
                    )
            }
        }
        .frame(width: AtlasMetrics.width, height: AtlasMetrics.height)
        .environment(\.atlasPresentation, atlasPresentation)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.root")
        .onAppear(perform: selectDefaultArea)
        .onChange(of: areas) { _, _ in selectDefaultArea() }
        .alert(
            localized("Couldn’t draft that plan", "無法排出這版行程"),
            isPresented: Binding(
                get: { planError != nil },
                set: { if !$0 { planError = nil } }
            )
        ) {
            Button(languageSettings.text(.ok)) { planError = nil }
        } message: {
            Text(planError ?? "")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localized("PLAN · FROM YOUR STAMPS", "規劃 · 從你的地圖章"))
                .font(SaveAtlasType.body(10))
                .tracking(1.15)
                .foregroundStyle(SaveAtlasPalette.muted)
            Text(localized("Draft a day you can walk.", "排出你可以走的一天。"))
                .font(SaveAtlasType.display(28, relativeTo: .title))
                .foregroundStyle(SaveAtlasPalette.forest)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Text(localized(
                "Map Stamps first. Unsaved attractions stay labeled. Savvy does not book flights or hotels.",
                "先用地圖章。未存景點會分開標記。Savvy 不會代訂機票或飯店。"
            ))
            .font(SaveAtlasType.body(13))
            .foregroundStyle(SaveAtlasPalette.muted)
        }
        .accessibilityIdentifier("plan.heading")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Composer", "行程條件"))
                .font(SaveAtlasType.strong(13))
                .tracking(0.65)
                .foregroundStyle(SaveAtlasPalette.forest)

            if areas.isEmpty {
                Text(localized(
                    "Save a few Map Stamps first, then Plan can arrange them.",
                    "先存幾個地圖章，Plan 才能幫你排。"
                ))
                .font(SaveAtlasType.body(14))
                .foregroundStyle(SaveAtlasPalette.muted)
                .accessibilityIdentifier("plan.emptyStamps")
            } else {
                areaChips
                dayAndPace
                travelWindows
                Button(action: planFromStamps) {
                    Text(localized("Plan from Map Stamps", "用地圖章規劃"))
                        .font(SaveAtlasType.strong(16))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(SaveAtlasPalette.coral)
                .disabled(isPlanning || selectedArea.isEmpty)
                .accessibilityIdentifier("plan.compose")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SaveAtlasPalette.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.45), lineWidth: 1)
        }
        .accessibilityIdentifier("plan.composer")
    }

    private var areaChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("CITY", "城市"))
                .font(SaveAtlasType.strong(11))
                .tracking(0.8)
                .foregroundStyle(SaveAtlasPalette.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(areas, id: \.self) { area in
                        Button {
                            selectedArea = area
                        } label: {
                            Text(area)
                                .font(SaveAtlasType.display(13))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .foregroundStyle(SaveAtlasPalette.ink)
                                .background(
                                    SaveAtlasPalette.kraft.opacity(selectedArea == area ? 0.72 : 0.28),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule().stroke(SaveAtlasPalette.line.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("plan.area.\(area)")
                    }
                }
            }
        }
    }

    private var dayAndPace: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localized("Days", "天數"))
                    .font(SaveAtlasType.body(14))
                    .foregroundStyle(SaveAtlasPalette.ink)
                Spacer()
                Stepper(value: $days, in: 1...7) {
                    Text("\(days)")
                        .font(SaveAtlasType.strong(16))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .accessibilityIdentifier("plan.days")
            }

            HStack(spacing: 8) {
                paceChip(.relaxed, title: localized("Relaxed", "輕鬆"))
                paceChip(.balanced, title: localized("Balanced", "適中"))
                paceChip(.packed, title: localized("Packed", "緊湊"))
            }
        }
    }

    private func paceChip(_ value: ItineraryPace, title: String) -> some View {
        Button {
            pace = value
        } label: {
            Text(title)
                .font(SaveAtlasType.display(13))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(SaveAtlasPalette.ink)
                .background(
                    SaveAtlasPalette.kraft.opacity(pace == value ? 0.72 : 0.28),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan.pace.\(value.rawValue)")
    }

    private var travelWindows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(localized("Arrival flight time", "抵達班機時間"), isOn: $usesArrival)
                .font(SaveAtlasType.body(14))
                .tint(SaveAtlasPalette.forest)
                .accessibilityIdentifier("plan.arrival.toggle")
            if usesArrival {
                DatePicker(
                    localized("Arrive", "抵達"),
                    selection: $arrivalDate,
                    displayedComponents: .hourAndMinute
                )
                .font(SaveAtlasType.body(14))
                .accessibilityIdentifier("plan.arrival.time")
            }
            Toggle(localized("Departure flight time", "離開班機時間"), isOn: $usesDeparture)
                .font(SaveAtlasType.body(14))
                .tint(SaveAtlasPalette.forest)
                .accessibilityIdentifier("plan.departure.toggle")
            if usesDeparture {
                DatePicker(
                    localized("Depart", "出發"),
                    selection: $departureDate,
                    displayedComponents: .hourAndMinute
                )
                .font(SaveAtlasType.body(14))
                .accessibilityIdentifier("plan.departure.time")
            }
            Text(localized(
                "These clocks only shrink the walking day. Savvy does not buy tickets or rooms.",
                "這些時間只用來縮短可走路程；Savvy 不會代買機票或訂房。"
            ))
            .font(SaveAtlasType.body(12))
            .foregroundStyle(SaveAtlasPalette.muted)
        }
    }

    @ViewBuilder
    private func draftCanvas(_ draft: SaveAIResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TripItineraryComponent(
                title: draft.title ?? localized("Plan draft", "行程草稿"),
                days: draft.itineraryDays,
                tripHealth: draft.tripHealth,
                aiMessage: draft.aiMessage,
                places: savedPlaces,
                travelLegs: draft.travelLegs,
                onSaveTripPlan: { name, city, stops in
                    await tripStore.createTrip(fromPlanNamed: name, city: city, stops: stops)
                }
            )
            .accessibilityIdentifier("plan.draft")
        }
    }

    @ViewBuilder
    private var savedTrips: some View {
        if !tripStore.trips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(localized("SAVED TRIPS", "已存行程"))
                    .font(SaveAtlasType.strong(11))
                    .tracking(0.8)
                    .foregroundStyle(SaveAtlasPalette.muted)
                ForEach(tripStore.trips.prefix(3)) { trip in
                    Button {
                        tripStore.selectTrip(trip.id)
                        onOpenTrip(trip.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.name)
                                    .font(SaveAtlasType.strong(16))
                                    .foregroundStyle(SaveAtlasPalette.forest)
                                Text(trip.city.isEmpty ? localized("No city yet", "尚未設定城市") : trip.city)
                                    .font(SaveAtlasType.body(12))
                                    .foregroundStyle(SaveAtlasPalette.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(SaveAtlasPalette.muted)
                        }
                        .padding(14)
                        .background(SaveAtlasPalette.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(SaveAtlasPalette.line.opacity(0.4), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("trips.card.\(trip.id.uuidString)")
                }
            }
        }
    }

    private var atlasPresentation: AtlasPresentation {
        var presentation = AtlasPresentation.reference
        presentation.onOpenPassport = onOpenPassport
        return presentation
    }

    private func selectDefaultArea() {
        if selectedArea.isEmpty || !areas.contains(selectedArea) {
            selectedArea = areas.first ?? ""
        }
    }

    private func planFromStamps() {
        isPlanning = true
        planError = nil
        let request = SavePlanRequest(
            area: selectedArea,
            days: days,
            pace: pace,
            arrivalMinutes: usesArrival ? minutes(from: arrivalDate) : nil,
            departureMinutes: usesDeparture ? minutes(from: departureDate) : nil,
            language: languageSettings.language
        )
        Task {
            defer { isPlanning = false }
            let first = SavePlanDraftBuilder.draft(
                request: request,
                savedPlaces: savedPlaces,
                unsavedCandidates: mapCandidates
            )
            guard var response = first else {
                planError = localized(
                    "Need confirmed Map Stamps in this city before Savvy can draft a plan.",
                    "這個城市還沒有已確認地圖章，沒辦法排出行程。"
                )
                return
            }
            let gaps = response.itineraryDays.flatMap { $0.health?.gaps ?? [] }
            if !gaps.isEmpty {
                let extras = await TripGapLocalOptionsService().candidates(
                    forGaps: gaps,
                    days: response.itineraryDays,
                    savedPlaces: savedPlaces
                )
                if !extras.isEmpty,
                   let enriched = SavePlanDraftBuilder.draft(
                    request: request,
                    savedPlaces: savedPlaces,
                    unsavedCandidates: extras + mapCandidates
                   ) {
                    response = enriched
                }
            }
            draft = response
        }
    }

    private func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }
}
