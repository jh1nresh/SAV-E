import SwiftUI
import MapKit
import AVFoundation
import Speech
import CoreLocation

enum MapDetailDrawerItem: Identifiable {
    case savedPlace(Place)
    case reviewCandidate(PlaceReviewCandidate)
    case unsavedCandidate(SaveMapCandidate)
    case socialPlace(Place)

    var id: String {
        switch self {
        case .savedPlace(let place):
            return "saved-\(place.id)"
        case .reviewCandidate(let candidate):
            return "review-\(candidate.id.uuidString)"
        case .unsavedCandidate(let candidate):
            return "unsaved-\(candidate.id)"
        case .socialPlace(let place):
            return "social-\(place.id)"
        }
    }
}

enum DrawerLaunchTarget: Equatable {
    case ask
    case addLink
    case saved
    case review
}

struct DrawerLaunchRequest: Equatable {
    let id: UUID
    let target: DrawerLaunchTarget
    /// Trips P1: a question typed before the drawer opened. When present the
    /// drawer submits it immediately instead of focusing an empty field.
    let initialQuery: String?
    /// A tap focuses the field; resizing the Map card only reveals it.
    let focusesSearch: Bool

    init(
        id: UUID = UUID(),
        target: DrawerLaunchTarget,
        initialQuery: String? = nil,
        focusesSearch: Bool = true
    ) {
        self.id = id
        self.target = target
        self.initialQuery = initialQuery
        self.focusesSearch = focusesSearch
    }
}

struct MapSearchRequestGate {
    private(set) var currentID: UUID?

    mutating func begin() -> UUID {
        let requestID = UUID()
        currentID = requestID
        return requestID
    }

    mutating func cancel() {
        currentID = nil
    }

    func isCurrent(_ requestID: UUID) -> Bool {
        currentID == requestID
    }
}

struct AIDrawerView: View {
    private enum LinkAnalysisState: Equatable {
        case idle
        case analyzing
        case ready(Set<UUID>)
        case failed(String)
    }

    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: AIDrawerViewModel
    @Binding var drawerDetent: PresentationDetent
    @Binding var mapDetailDrawerItem: MapDetailDrawerItem?
    var launchRequest: DrawerLaunchRequest = DrawerLaunchRequest(target: .review)
    var captureTripName: String?
    var reviewCandidates: [PlaceReviewCandidate] = []
    var onSaveGoogleTakeoutImport: ([ImportedPlaceDraft]) async throws -> GoogleTakeoutSaveSummary = { _ in
        GoogleTakeoutSaveSummary(saved: 0, skippedDuplicates: 0, reviewDrafts: 0)
    }
    var onDeletePlace: (Place) async throws -> Void = { _ in }
    var onSaveCandidate: (PlaceReviewCandidate, String?) async throws -> Void = { _, _ in }
    var onRejectCandidate: (PlaceReviewCandidate) async throws -> Void = { _ in }
    var onSaveCandidateAsSourceOnly: (PlaceReviewCandidate) async throws -> Void = { _ in }
    var onInvestigateCandidateMore: (PlaceReviewCandidate) async throws -> Void = { _ in }
    var onSaveMapCandidate: (SaveMapCandidate) async throws -> Void = { _ in }
    var onUpdatePlaceVisibility: (Place, PlaceVisibility) async throws -> Void = { _, _ in }
    var onUpdatePlace: (Place) async throws -> Void = { _ in }
    var onFindRelatedSources: (Place, Bool) async throws -> RelatedPlaceSourcePack = { _, _ in
        throw SupabaseError.notConfigured
    }
    var onImportSharedTextAsReviewCandidates: (String) async throws -> [UUID] = { _ in [] }
    var onOpenReview: () -> Void = {}
    var onAddPlaceToTrip: (Place) -> Void = { _ in }
    var onSaveTripPlan: ((_ name: String, _ city: String, _ stops: [TripPlanPersistableStop]) async -> Trip?)? = nil
    var onPrepareMapSearch: (String) async -> MapCandidateSearchResult = { _ in .current([]) }
    /// Links exact-place map results to the Review clue they resolve, so
    /// saving one retires the clue from the queue.
    var onBeginExactSearchResolution: (PlaceReviewCandidate) -> Void = { _ in }
    var onClearMapSearchResults: () -> Void = {}
    var collaborativeLists: [SaveCollaborativeList] = []
    var onCreateList: (String, String?) -> SaveCollaborativeList = { title, note in
        SaveCollaborativeList(title: title, note: note)
    }
    var onAddPlaceToList: (Place, UUID) throws -> Void = { _, _ in }
    var onSaveSocialPlace: (Place) async throws -> Void = { _ in }
    var selectedCategories: Set<PlaceCategory> = []
    var onToggleCategory: (PlaceCategory) -> Void = { _ in }
    var selectedIntentFilters: Set<SaveMapDrawerIntent> = []
    var onToggleIntentFilter: (SaveMapDrawerIntent) -> Void = { _ in }
    var filteredPlaces: [Place] = []
    var isRefreshingNearbyFilter = false
    var nearbyFilterNeedsLocation = false
    var onOpenPassport: () -> Void = {}
    var onDismissMapDetailSheet: () -> Void = {}
    var onDismissMapDetail: () -> Void = {}
    /// "Find exact place" promises the map: when the search lands candidate
    /// pins, the host closes this drawer surface so the user sees them.
    var onShowMapCandidatesOnMap: () -> Void = {}
    @FocusState private var searchFocused: Bool
    @ScaledMetric(relativeTo: .body) private var commandIconDimension: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var commandBarMinHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var commandFieldMinHeight: CGFloat = 28
    @StateObject private var voiceQuery = VoiceQueryController()
    @State private var addSpotStatus: String?
    @State private var candidateActionInFlight: UUID?
    @State private var mapCandidateActionInFlight: String?
    @State private var isImportingURL = false
    @State private var linkAnalysisState: LinkAnalysisState = .idle
    @State private var showsSlowLoadingHint = false
    @State private var mapSearchTask: Task<Void, Never>?
    @State private var mapSearchRequestGate = MapSearchRequestGate()

    var body: some View {
        GeometryReader { proxy in
            if let mapDetailDrawerItem {
                mapDetailDrawer(for: mapDetailDrawerItem)
            } else {
                VStack(spacing: 0) {
                    searchBar
                    if showsContentArea(for: proxy.size.height) {
                        Divider().opacity(colorScheme == .dark ? 0.18 : 0.28)
                        contentArea
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background {
                    AtlasPostcardDrawerBackground(colorScheme: colorScheme)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer.root")
        .onChange(of: viewModel.drawerState) { _, state in
            guard mapDetailDrawerItem == nil else { return }
            if case .error = state { SaveHaptics.warning() }
            withAnimation(SaveTheme.Motion.standardSpring) {
                switch state {
                case .idle:             drawerDetent = collapsedDrawerDetent
                case .loading:          drawerDetent = .medium
                case .error:            drawerDetent = .medium
                case .saveSearchResults: drawerDetent = .medium
                case .displaying(let r):
                    drawerDetent = r.componentType == .tripItinerary ? .large : .medium
                }
            }
        }
        .onAppear {
            guard mapDetailDrawerItem == nil else { return }
            applyLaunchRequest(launchRequest)
        }
        .onChange(of: launchRequest) { _, request in
            applyLaunchRequest(request)
        }
        .onChange(of: voiceQuery.transcript) { _, transcript in
            guard voiceQuery.isListening else { return }
            viewModel.query = transcript
        }
        .onChange(of: voiceQuery.state) { _, state in
            switch state {
            case .denied:
                addSpotStatus = languageSettings.localized(
                    english: "Microphone or speech permission is off. Enable it in Settings to talk to Savvy.",
                    traditionalChinese: "麥克風或語音辨識權限已關閉。請到設定開啟後再和 Savvy 說話。"
                )
            case .unavailable:
                addSpotStatus = languageSettings.localized(
                    english: "Voice input is not available on this device right now.",
                    traditionalChinese: "這台裝置目前無法使用語音輸入。"
                )
            case .failed(let message):
                addSpotStatus = message
            default:
                break
            }
        }
    }

    private func mapDetailDrawer(for item: MapDetailDrawerItem) -> some View {
        MapDetailDrawerView(
            item: item,
            detent: $drawerDetent,
            captureTripName: captureTripName,
            editableLists: collaborativeLists.filter(\.canEdit),
            isWorkingReviewCandidateID: candidateActionInFlight,
            isWorkingMapCandidateID: mapCandidateActionInFlight,
            onClose: {
                closeMapDetail()
                onDismissMapDetailSheet()
            },
            onDeletePlace: { place in
                try await onDeletePlace(place)
                viewModel.removePlace(place)
                closeMapDetail()
            },
            onRecommendOrder: { place in
                closeMapDetail()
                viewModel.showFoodPlaceAnalysis(
                    for: place,
                    outputLanguage: languageSettings.language
                )
                withAnimation { drawerDetent = .large }
            },
            onPlanAroundPlace: { place in
                closeMapDetail()
                withAnimation { drawerDetent = .large }
                Task {
                    await viewModel.showPlanAround(
                        anchor: place,
                        reviewCandidates: reviewCandidates,
                        outputLanguage: languageSettings.language
                    )
                }
            },
            onFindExactPlaceCandidate: { candidate in
                findExactPlace(for: candidate)
            },
            onSaveCandidate: { candidate, nameOverride in
                performCandidateAction(candidate, successMessage: saveFeedback(for: candidate)) {
                    try await onSaveCandidate(candidate, nameOverride)
                    closeMapDetail()
                }
            },
            onRejectCandidate: { candidate in
                performCandidateAction(
                    candidate,
                    successMessage: languageSettings.localized(english: "Removed from Review.", traditionalChinese: "已從待確認移除。")
                ) {
                    try await onRejectCandidate(candidate)
                    closeMapDetail()
                }
            },
            onSaveCandidateAsSourceOnly: { candidate in
                performCandidateAction(
                    candidate,
                    successMessage: languageSettings.localized(english: "Source kept without creating a Map Stamp.", traditionalChinese: "已保留來源，不會建立地圖章。")
                ) {
                    try await onSaveCandidateAsSourceOnly(candidate)
                    closeMapDetail()
                    openReviewInbox()
                }
            },
            onInvestigateCandidateMore: { candidate in
                performCandidateAction(
                    candidate,
                    successMessage: languageSettings.localized(english: "Kept in Review for more investigation.", traditionalChinese: "已留在待確認，等待進一步調查。")
                ) {
                    try await onInvestigateCandidateMore(candidate)
                    addMoreClue(for: candidate)
                }
            },
            onSaveMapCandidate: { candidate in
                performMapCandidateAction(candidate) {
                    try await onSaveMapCandidate(candidate)
                    closeMapDetail()
                }
            },
            onSaveSocialPlace: { place in
                Task { await saveSocialPlace(place) }
            },
            onUpdatePlaceVisibility: { place, visibility in
                try await onUpdatePlaceVisibility(place, visibility)
            },
            onUpdatePlace: { place in
                try await onUpdatePlace(place)
            },
            onFindRelatedSources: { place, forceRefresh in
                try await onFindRelatedSources(place, forceRefresh)
            },
            onAddPlaceToTrip: onAddPlaceToTrip,
            onCreateList: createListForPicker,
            onAddPlaceToList: onAddPlaceToList
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: SaveTheme.Spacing.sm) {
            Image(systemName: commandBarIcon)
                .foregroundColor(commandBarTextColor)
                .font(.system(size: 13, weight: .bold))
                .frame(width: commandIconDimension, height: commandIconDimension)
                .background(commandIconFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(commandBarStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .symbolEffect(.pulse, isActive: isLoading)
                .accessibilityIdentifier("drawer.postcardChrome")

            TextField(languageSettings.text(.askPlaceholder), text: $viewModel.query)
                .font(SaveAtlasType.body(15))
                .foregroundColor(commandBarTextColor)
                .lineLimit(1)
                .frame(minHeight: commandFieldMinHeight)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { submitSearchField() }
                .onTapGesture {
                    withAnimation { drawerDetent = .medium }
                }
                .accessibilityIdentifier("drawer.commandField")

            if isLoading {
                Button(action: {
                    guard !isImportingURL else { return }
                    viewModel.cancelCurrentRequest()
                    withAnimation { drawerDetent = .medium }
                    searchFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(commandBarSecondaryText)
                }
            } else {
                commandBarTrailingActions
            }
        }
        .padding(.horizontal, SaveTheme.Spacing.md)
        .frame(minHeight: commandBarMinHeight)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(commandBarFill)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(commandBarStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, SaveTheme.Spacing.md)
        .padding(.vertical, SaveTheme.Spacing.sm)
        .frame(minHeight: collapsedDrawerHeight, alignment: .center)
        .background(.clear)
    }

    private var commandBarIcon: String {
        if isLoading { return "hourglass" }
        if voiceQuery.isListening { return "waveform" }
        return "magnifyingglass"
    }

    private var commandBarFill: Color {
        colorScheme == .dark
            ? Color.saveDrawerSurface.opacity(0.30)
            : SaveAtlasPalette.paper.opacity(0.98)
    }

    private var commandIconFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : SaveAtlasPalette.mint.opacity(0.82)
    }

    private var commandBarStroke: Color {
        Color.saveDrawerStroke.opacity(colorScheme == .dark ? 0.18 : 0.18)
    }

    private var commandBarTextColor: Color {
        colorScheme == .dark ? .white : SaveAtlasPalette.forest
    }

    private var commandBarSecondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.66) : Color.saveCocoa.opacity(0.72)
    }

    private func applyLaunchRequest(_ request: DrawerLaunchRequest) {
        cancelMapSearch()
        onClearMapSearchResults()
        mapDetailDrawerItem = nil
        onDismissMapDetail()
        viewModel.returnToCommands()
        searchFocused = false

        switch request.target {
        case .ask:
            withAnimation(SaveTheme.Motion.standardSpring) {
                drawerDetent = .medium
            }
            if let query = request.initialQuery?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !query.isEmpty {
                viewModel.query = query
                Task { @MainActor in
                    await Task.yield()
                    submitSearchField()
                }
            } else if request.focusesSearch {
                Task { @MainActor in
                    await Task.yield()
                    searchFocused = true
                }
            }
        case .addLink:
            if !isImportingURL {
                linkAnalysisState = .idle
            }
            withAnimation(SaveTheme.Motion.standardSpring) {
                drawerDetent = .medium
            }
            Task { @MainActor in
                await Task.yield()
                searchFocused = true
            }
        case .saved:
            withAnimation(SaveTheme.Motion.standardSpring) {
                drawerDetent = .medium
            }
        case .review:
            withAnimation(SaveTheme.Motion.standardSpring) {
                drawerDetent = .large
            }
        }
    }

    @ViewBuilder
    private var commandBarTrailingActions: some View {
        if hasActiveDrawerContent {
            Button(action: closeDrawerContent) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(commandBarSecondaryText)
            }
            .accessibilityLabel(languageSettings.text(.closeDrawerContent))
        } else if hasVisibleMapSearchResults {
            Button(action: closeMapSearchResults) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(commandBarSecondaryText)
            }
            .accessibilityLabel(languageSettings.localized(english: "Clear map search results", traditionalChinese: "清除地圖搜尋結果"))
        } else if !viewModel.query.isEmpty {
            Button(action: {
                viewModel.returnToCommands()
                searchFocused = true
                withAnimation { drawerDetent = .medium }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(commandBarSecondaryText)
            }
            .accessibilityLabel(languageSettings.localized(english: "Clear command", traditionalChinese: "清除指令"))

            Button(action: submitSearchField) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundColor(commandBarTextColor)
            }
            .accessibilityLabel(languageSettings.localized(english: "Ask Savvy", traditionalChinese: "詢問 Savvy"))
            .accessibilityIdentifier("drawer.submitCommand")
        } else {
            Button(action: toggleVoiceInput) {
                Image(systemName: voiceQuery.buttonIconName)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(commandBarTextColor)
                    .frame(width: 30, height: 30)
                    .background(voiceQuery.isListening ? Color.saveSignal.opacity(0.82) : commandIconFill)
                    .overlay(
                        Circle()
                            .stroke(commandBarStroke, lineWidth: 1)
                    )
                    .clipShape(Circle())
                    .symbolEffect(.pulse, isActive: voiceQuery.isListening)
                    // Keep the 30pt visual, but guarantee the 44pt minimum hit area.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(voiceQuery.isListening ? "Stop talking to Savvy" : "Talk to Savvy")

            PassportDrawerButton(
                fill: commandIconFill,
                stroke: commandBarStroke,
                foreground: commandBarTextColor,
                action: openProfile
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        VStack(spacing: 0) {
            if showsNavigationHeader {
                navigationHeader
            }

            contentBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var contentBody: some View {
        switch viewModel.drawerState {
        case .idle:
            commandHomeView

        case .loading:
            loadingStateView

        case .displaying(let response):
            ScrollView {
                VStack(spacing: 16) {
                    switch response.componentType {
                    case .placeList:
                        PlaceListComponent(
                            title: response.title ?? "Places",
                            places: viewModel.resolvePlaces(from: response.placeIds),
                            aiMessage: response.aiMessage,
                            onSelect: openSavedPlace
                        )

                    case .navigationCard:
                        if let place = viewModel.resolvePlace(id: response.navigationPlaceId) {
                            NavigationCardComponent(place: place, mode: response.transportMode)
                        } else {
                            messageView(languageSettings.localized(
                                english: "Couldn't find that place in your collection.",
                                traditionalChinese: "在你的地點記憶裡找不到這個地點。"
                            ))
                        }

                    case .tripItinerary:
                        TripItineraryComponent(
                            title: response.title ?? languageSettings.localized(
                                english: "Your Itinerary",
                                traditionalChinese: "你的行程"
                            ),
                            days: response.itineraryDays,
                            tripHealth: response.tripHealth,
                            aiMessage: response.aiMessage,
                            places: viewModel.places,
                            travelLegs: response.travelLegs,
                            onSaveTripPlan: onSaveTripPlan
                        )

                    case .message:
                        messageView(response.messageText ?? response.aiMessage ?? "")
                        if !response.followUpChoices.isEmpty {
                            SaveSearchFollowUpChoiceGrid(
                                title: languageSettings.localized(
                                    english: "Choose a next step",
                                    traditionalChinese: "選一個繼續"
                                ),
                                choices: response.followUpChoices,
                                onSelect: { choice in
                                    submitFollowUpChoice(choice)
                                }
                            )
                        }
                    }

                    AIResultActionBar(
                        onFollowUp: {
                            viewModel.query = ""
                            searchFocused = true
                            withAnimation { drawerDetent = .medium }
                        },
                        onNewQuestion: {
                            viewModel.startNewConversation()
                            searchFocused = true
                            withAnimation { drawerDetent = .medium }
                        }
                    )
                }
                .padding(.horizontal, SaveTheme.Spacing.lg)
                .padding(.vertical, SaveTheme.Spacing.lg)
            }

        case .saveSearchResults(let response):
            ScrollView {
                VStack(spacing: 16) {
                    SaveSearchResultsComponent(
                        response: response,
                        onSelectResult: { result in
                            openSearchResult(result)
                        },
                        onSelectFollowUpChoice: { choice in
                            submitFollowUpChoice(choice)
                        },
                        onSearchNearby: {
                            searchNearbyUnsavedCandidates(for: response.query)
                        }
                    )

                    AIResultActionBar(
                        onFollowUp: {
                            viewModel.query = ""
                            searchFocused = true
                            withAnimation { drawerDetent = .medium }
                        },
                        onNewQuestion: {
                            viewModel.startNewConversation()
                            searchFocused = true
                            withAnimation { drawerDetent = .medium }
                        }
                    )
                }
                .padding(.horizontal, SaveTheme.Spacing.lg)
                .padding(.vertical, SaveTheme.Spacing.lg)
            }

        case .error(let msg):
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "exclamationmark.triangle").foregroundColor(.saveCocoa)
                Text(localizedErrorMessage(msg))
                    .font(.caption).foregroundColor(.saveCocoa.opacity(0.74))
                    .multilineTextAlignment(.center).padding(.horizontal)
                HStack(spacing: 12) {
                    Button(languageSettings.text(.back)) {
                        viewModel.returnToCommands()
                        withAnimation { drawerDetent = .medium }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.saveCocoa.opacity(0.72))

                    Button(languageSettings.text(.tryAgain)) { Task { await submitDrawerQuery() } }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.saveCocoa)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Loading

    /// Branded "Memo is sorting" treatment. Memo leads, a quiescent symbol
    /// pulse signals progress without an infinite layout animation that would
    /// trip UI-test quiescence checks.
    private var loadingStateView: some View {
        VStack(spacing: SaveTheme.Spacing.md) {
            Spacer()

            ZStack(alignment: .bottomTrailing) {
                MemoMascotMark(size: 76)

                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.saveInk)
                    .frame(width: 30, height: 30)
                    .background(SaveAtlasPalette.kraft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(SaveAtlasPalette.line, lineWidth: 1.4)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .symbolEffect(.pulse, isActive: true)
                    .offset(x: 10, y: 8)
            }

            VStack(spacing: SaveTheme.Spacing.xs) {
                ProgressView().tint(.saveInk)
                Text(languageSettings.text(.memoSorting))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.saveCocoa.opacity(0.78))
                    .multilineTextAlignment(.center)

                // Long requests (5-10s) read as frozen and get cancelled —
                // reassure after a beat that work is still happening.
                if showsSlowLoadingHint {
                    Text(languageSettings.localized(
                        english: "Still on it — checking your saved places…",
                        traditionalChinese: "還在弄——正在翻你存過的地點…"
                    ))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveMutedText)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                }
            }
            .task {
                showsSlowLoadingHint = false
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(SaveTheme.Motion.standardSpring) {
                    showsSlowLoadingHint = true
                }
            }

            Button(action: {
                viewModel.cancelCurrentRequest()
                searchFocused = false
                withAnimation { drawerDetent = .medium }
            }) {
                Label(languageSettings.text(.cancel), systemImage: "xmark")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, SaveTheme.Spacing.md)
                    .padding(.vertical, SaveTheme.Spacing.sm)
                    .background(SaveAtlasPalette.paper.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(SaveAtlasPalette.line, lineWidth: 1.4)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var navigationHeader: some View {
        HStack(spacing: SaveTheme.Spacing.sm) {
            Button(action: {
                viewModel.returnToCommands()
                searchFocused = false
                withAnimation { drawerDetent = .medium }
            }) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .frame(width: 32, height: 32)
                    .background(SaveAtlasPalette.paper.opacity(0.62))
                    .overlay(
                        Circle()
                            .stroke(SaveAtlasPalette.line, lineWidth: 1.4)
                    )
                    .clipShape(Circle())
            }
            .accessibilityLabel(languageSettings.text(.backToCommands))

            VStack(alignment: .leading, spacing: 2) {
                Text(navigationTitle)
                    .font(SaveTheme.Typography.rowTitle)
                    .foregroundColor(.saveInk)
                    .lineLimit(1)
                Text(navigationSubtitle)
                    .font(.caption2)
                    .foregroundColor(.saveCocoa.opacity(0.72))
                    .lineLimit(1)
            }

            Spacer()

            Button(action: {
                viewModel.reset()
                searchFocused = false
                withAnimation { drawerDetent = collapsedDrawerDetent }
            }) {
                SaveIconTile(
                    systemName: "xmark",
                    size: 30,
                    iconSize: 11,
                    fill: SaveAtlasPalette.paper.opacity(0.72),
                    foreground: Color.saveCocoa.opacity(0.78),
                    strokeOpacity: 0.54,
                    cornerRadius: 9
                )
            }
            .accessibilityLabel(languageSettings.text(.closeDrawerContent))
        }
        .padding(.horizontal, SaveTheme.Spacing.lg)
        .padding(.vertical, SaveTheme.Spacing.sm)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.24 : 0.26)
                .background(Color.saveDrawerSurface.opacity(colorScheme == .dark ? 0.22 : 0.34))
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.saveDrawerStroke.opacity(colorScheme == .dark ? 0.13 : 0.18))
                .frame(height: 1)
        }
    }

    private var showsNavigationHeader: Bool {
        switch viewModel.drawerState {
        case .idle:
            return false
        case .loading, .displaying, .saveSearchResults, .error:
            return true
        }
    }

    private var navigationTitle: String {
        switch viewModel.drawerState {
        case .idle:
            return languageSettings.text(.appName)
        case .loading:
            return languageSettings.text(.thinking)
        case .displaying(let response):
            return response.title ?? languageSettings.text(.answer)
        case .saveSearchResults:
            return "Savvy results"
        case .error:
            return languageSettings.text(.couldntFinish)
        }
    }

    private var navigationSubtitle: String {
        switch viewModel.drawerState {
        case .idle:
            return languageSettings.text(.commands)
        case .loading:
            return languageSettings.text(.loadingSubtitle)
        case .displaying:
            return languageSettings.text(.answerSubtitle)
        case .saveSearchResults:
            return "Memory first, public discovery separate"
        case .error:
            return languageSettings.text(.errorSubtitle)
        }
    }

    private func messageView(_ text: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Text(text)
                .font(.subheadline)
                .foregroundColor(.saveInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func localizedErrorMessage(_ message: String) -> String {
        let normalized = message.lowercased()
        if normalized.contains("ai returned something unexpected") ||
            normalized.contains("ai request failed") ||
            normalized.contains("ai didn't return") ||
            normalized.contains("ai is busy") {
            return languageSettings.localized(
                english: "Savvy could not finish that request. Try again in a moment.",
                traditionalChinese: "Savvy 剛剛沒完成這個請求，請稍後再試一次。"
            )
        }
        return message
    }

    private var isLoading: Bool {
        if isImportingURL { return true }
        if case .loading = viewModel.drawerState { return true }
        return false
    }

    private func showsContentArea(for drawerHeight: CGFloat) -> Bool {
        let isCollapsed = drawerHeight <= collapsedDrawerHeight + 4
        if case .idle = viewModel.drawerState, isCollapsed { return false }
        return true
    }

    private var hasActiveDrawerContent: Bool {
        switch viewModel.drawerState {
        case .idle:
            return false
        case .loading, .displaying, .saveSearchResults, .error:
            return true
        }
    }

    private var hasVisibleMapSearchResults: Bool {
        !viewModel.mapCandidates.isEmpty
    }

    private var collapsedDrawerHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 160 : 132
    }

    private var collapsedDrawerDetent: PresentationDetent {
        dynamicTypeSize.isAccessibilitySize ? .medium : .height(132)
    }

    // MARK: - Idle suggestions

    private var commandHomeView: some View {
        suggestionsView
    }

    private var suggestionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    MemoMascotMark(size: 52, framed: false)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(languageSettings.localized(
                            english: "Search places or ask Savvy",
                            traditionalChinese: "搜尋地點或詢問 Savvy"
                        ))
                        .font(SaveAtlasType.strong(17))
                        .foregroundStyle(SaveAtlasPalette.forest)

                        Text(languageSettings.localized(
                            english: "This drawer stays with Map. Review and saved memory live in Saves.",
                            traditionalChinese: "這個抽屜只服務地圖；待確認與收藏都在 Saves。"
                        ))
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .saveAtlasPaper(radius: 16)
                .padding(.horizontal, SaveTheme.Spacing.lg)
                .accessibilityIdentifier("drawer.mapAssistant.intro")

                linkAnalysisStatusCard

                categoryFilterStrip

                if hasActiveMapFilters {
                    filteredMapStampsSection
                }

                if !viewModel.chatHistory.isEmpty {
                    NotebookBandLabel(languageSettings.localized(english: "Recent", traditionalChinese: "最近"))
                        .padding(.horizontal, SaveTheme.Spacing.lg)

                    ForEach(viewModel.chatHistory.prefix(5)) { entry in
                        Button(action: {
                            viewModel.query = entry.query
                            submitSearchField()
                        }) {
                            DrawerSuggestionRow(icon: "clock.arrow.circlepath", text: entry.query)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, SaveTheme.Spacing.lg)
                    }
                }

                NotebookBandLabel(languageSettings.localized(english: "Try asking", traditionalChinese: "試著問"))
                    .padding(.horizontal, SaveTheme.Spacing.lg)

                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: {
                        viewModel.query = suggestion
                        submitSearchField()
                    }) {
                        DrawerSuggestionRow(icon: "arrow.up.left", text: suggestion)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, SaveTheme.Spacing.lg)
                }

                if let addSpotStatus {
                    Text(addSpotStatus)
                        .font(.caption)
                        .foregroundColor(.saveCocoa.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, SaveTheme.Spacing.lg)
                }
            }
            .padding(.top, SaveTheme.Spacing.md)
            .padding(.bottom, 18)
        }
    }

    private var suggestions: [String] {
        SaveMVPDrawerEntryCopy.suggestions(language: languageSettings.language)
    }

    private var categoryFilterStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotebookBandLabel(languageSettings.localized(english: "Filters", traditionalChinese: "篩選"))
                .padding(.horizontal, SaveTheme.Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(PlaceCategory.allCases, id: \.self) { category in
                        CategoryPill(
                            category: category,
                            isSelected: selectedCategories.contains(category)
                        )
                        .onTapGesture { onToggleCategory(category) }
                    }

                    Rectangle()
                        .fill(SaveAtlasPalette.line.opacity(0.34))
                        .frame(width: 1, height: 22)
                        .padding(.horizontal, 2)

                    ForEach(SaveMapDrawerIntent.allCases) { intent in
                        SaveIntentFilterPill(
                            intent: intent,
                            language: languageSettings.language,
                            isSelected: selectedIntentFilters.contains(intent)
                        )
                        .onTapGesture { onToggleIntentFilter(intent) }
                    }
                }
                .padding(.horizontal, SaveTheme.Spacing.lg)
                .padding(.vertical, 2)
            }
        }
    }

    private var hasActiveMapFilters: Bool {
        !selectedCategories.isEmpty || !selectedIntentFilters.isEmpty
    }

    private var filteredMapStampsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotebookBandLabel(languageSettings.localized(english: "From your Savvy", traditionalChinese: "來自你的 Savvy"))
                .padding(.horizontal, SaveTheme.Spacing.lg)

            if isRefreshingNearbyFilter {
                Text(languageSettings.localized(
                    english: "Finding Map Stamps near you…",
                    traditionalChinese: "正在找附近的地圖章…"
                ))
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
                .padding(.horizontal, SaveTheme.Spacing.lg)
            } else if nearbyFilterNeedsLocation {
                Text(languageSettings.localized(
                    english: "Turn on location to filter nearby Map Stamps.",
                    traditionalChinese: "開啟定位後才能篩選附近的地圖章。"
                ))
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
                .padding(.horizontal, SaveTheme.Spacing.lg)
            } else if filteredPlaces.isEmpty {
                Text(languageSettings.localized(
                    english: "No Map Stamps match these filters.",
                    traditionalChinese: "沒有地圖章符合這些篩選。"
                ))
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
                .padding(.horizontal, SaveTheme.Spacing.lg)
            } else {
                ForEach(Array(filteredPlaces.prefix(8))) { place in
                    Button {
                        openSavedPlace(place)
                    } label: {
                        SaveFilteredStampRow(place: place, language: languageSettings.language)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, SaveTheme.Spacing.lg)
                    .accessibilityIdentifier("drawer.filter.result.\(place.id.uuidString)")
                }
            }
        }
        .accessibilityIdentifier("drawer.filter.results")
    }

    private func performCandidateAction(
        _ candidate: PlaceReviewCandidate,
        successMessage: String,
        action: @escaping () async throws -> Void
    ) {
        candidateActionInFlight = candidate.id
        Task {
            do {
                try await action()
                addSpotStatus = successMessage
            } catch {
                addSpotStatus = error.localizedDescription
            }
            candidateActionInFlight = nil
        }
    }

    private func performMapCandidateAction(
        _ candidate: SaveMapCandidate,
        action: @escaping () async throws -> Void
    ) {
        mapCandidateActionInFlight = candidate.id
        Task {
            do {
                try await action()
                let category = candidate.category?.displayName(language: languageSettings.language) ??
                    languageSettings.localized(english: "place", traditionalChinese: "地點")
                addSpotStatus = languageSettings.localized(
                    english: "Map Stamp saved · +1 \(candidate.category?.displayName.lowercased() ?? "place")",
                    traditionalChinese: "已保存地圖章 · +1 \(category)"
                )
            } catch {
                addSpotStatus = error.localizedDescription
            }
            mapCandidateActionInFlight = nil
        }
    }

    private func saveSocialPlace(_ place: Place) async {
        do {
            try await onSaveSocialPlace(place)
            addSpotStatus = languageSettings.localized(
                english: "Saved \(place.name) to your Savvy.",
                traditionalChinese: "已將「\(place.name)」保存到你的 Savvy。"
            )
            closeMapDetail()
        } catch {
            addSpotStatus = error.localizedDescription
        }
    }

    private func firstURL(in text: String) -> URL? {
        if let normalizedURL = SocialShareTextNormalizer.normalize(text).primaryURL {
            return normalizedURL
        }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?
            .matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .first { url in
                guard let scheme = url.scheme?.lowercased() else { return false }
                return scheme == "http" || scheme == "https"
            }
    }

    private func openReviewInbox() {
        mapDetailDrawerItem = nil
        onDismissMapDetail()
        viewModel.returnToCommands()
        searchFocused = false
        withAnimation { drawerDetent = .large }
    }

    private func openSavedPlace(_ place: Place) {
        prepareMapDetailOpening()
        viewModel.returnToCommands()
        mapDetailDrawerItem = .savedPlace(place)
        withAnimation(SaveTheme.Motion.standardSpring) {
            drawerDetent = .medium
        }
    }

    private func openReviewCandidateDetail(_ candidate: PlaceReviewCandidate) {
        prepareMapDetailOpening()
        viewModel.returnToCommands()
        mapDetailDrawerItem = .reviewCandidate(candidate)
        withAnimation(SaveTheme.Motion.standardSpring) {
            drawerDetent = .medium
        }
    }

    private func openMapCandidateDetail(_ candidate: SaveMapCandidate) {
        prepareMapDetailOpening()
        viewModel.returnToCommands()
        mapDetailDrawerItem = .unsavedCandidate(candidate)
        withAnimation(SaveTheme.Motion.standardSpring) {
            drawerDetent = .medium
        }
    }

    private func prepareMapDetailOpening() {
        searchFocused = false
    }

    private func reviewCandidate(for result: SaveSearchResult) -> PlaceReviewCandidate? {
        guard result.id.hasPrefix("review-candidate-") else { return nil }
        let rawID = String(result.id.dropFirst("review-candidate-".count))
        guard let id = UUID(uuidString: rawID) else { return nil }
        return reviewCandidates.first { $0.id == id }
    }

    private func openSearchResult(_ result: SaveSearchResult) {
        SaveHaptics.select()
        if let candidate = reviewCandidate(for: result) {
            openReviewCandidateDetail(candidate)
            return
        }

        switch result.objectType {
        case .savedPlace, .triedMemory:
            guard let place = savedPlace(for: result) else { return }
            openSavedPlace(place)
        case .mapVisibleUnsavedPlace:
            guard let candidate = mapCandidate(for: result) else { return }
            openMapCandidateDetail(candidate)
        default:
            viewModel.showSearchResult(result)
        }
    }

    private func savedPlace(for result: SaveSearchResult) -> Place? {
        guard result.id.hasPrefix("place-") else { return nil }
        let rawID = String(result.id.dropFirst("place-".count))
        guard let id = UUID(uuidString: rawID) else { return nil }
        return viewModel.places.first { $0.id == id }
    }

    private func mapCandidate(for result: SaveSearchResult) -> SaveMapCandidate? {
        guard result.id.hasPrefix("map-candidate-") else { return nil }
        let rawID = String(result.id.dropFirst("map-candidate-".count))
        return viewModel.mapCandidates.first { $0.id == rawID }
    }

    private func submitSearchField() {
        cancelMapSearch()
        onClearMapSearchResults()
        SaveHaptics.tap()
        voiceQuery.stop()
        searchFocused = false
        if firstURL(in: viewModel.query) != nil {
            importSharedTextToReviewCandidates(viewModel.query)
        } else if DeterministicTripPlanner().isItineraryRequest(
            viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
        ) {
            // Planning questions outrank place search: "plan a day in Taipei"
            // must reach the trip planner, not the map-candidate rail.
            Task {
                await submitDrawerQuery()
            }
        } else if viewModel.shouldSearchNearbyUnsavedCandidates(for: viewModel.query) {
            searchNearbyUnsavedCandidates(for: viewModel.query)
        } else if viewModel.shouldSearchExactMapCandidates(for: viewModel.query) {
            searchNearbyUnsavedCandidates(for: viewModel.query)
        } else if viewModel.shouldPrepareMapCandidates(for: viewModel.query) {
            searchNearbyUnsavedCandidates(for: viewModel.query)
        } else {
            Task {
                await submitDrawerQuery()
            }
        }
    }

    private func submitDrawerQuery() async {
        await viewModel.submit(
            reviewCandidates: reviewCandidates,
            outputLanguage: languageSettings.language
        )
    }

    private func submitFollowUpChoice(_ choice: SaveSearchFollowUpChoice) {
        SaveHaptics.tap()
        voiceQuery.stop()
        searchFocused = false
        viewModel.query = choice.prompt
        withAnimation { drawerDetent = .medium }
        Task {
            await submitDrawerQuery()
        }
    }

    private func searchNearbyUnsavedCandidates(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let isExactSearch = viewModel.shouldSearchExactMapCandidates(for: trimmed)
        let isExplicitPublicSearch = viewModel.shouldSearchNearbyUnsavedCandidates(for: trimmed)
        let fallbackQuery = viewModel.shouldSearchNearbyUnsavedCandidates(for: trimmed) || isExactSearch
            ? trimmed
            : "search nearby unsaved candidates for \(trimmed)"
        viewModel.query = trimmed
        addSpotStatus = isExactSearch
            ? languageSettings.localized(english: "Looking for exact map matches. Review the result before saving.", traditionalChinese: "正在找精確地圖結果。保存前請先確認結果。")
            : isExplicitPublicSearch
                ? languageSettings.localized(english: "Looking for nearby unsaved candidates. Your Savvy results stay separate.", traditionalChinese: "正在找附近未保存地點。這些會和你的 Savvy 記憶分開。")
                : languageSettings.localized(english: "Looking for nearby public options. Savvy memory still stays first.", traditionalChinese: "正在找附近公開候選地點。Savvy 記憶仍會優先。")
        withAnimation { drawerDetent = .medium }

        startMapSearch { requestID in
            let result = await onPrepareMapSearch(fallbackQuery)
            guard isCurrentMapSearch(requestID) else { return }
            guard case .current(let candidates) = result else { return }
            if candidates.isEmpty {
                viewModel.mapCandidates = []
                addSpotStatus = isExactSearch
                    ? languageSettings.localized(english: "No exact map match found yet. Try adding a city, address, or map link.", traditionalChinese: "目前找不到精確地圖結果。請補上城市、地址或地圖連結。")
                    : languageSettings.localized(english: "No nearby unsaved candidates found yet. Try a more specific place type or city.", traditionalChinese: "目前找不到附近未保存地點。請換成更明確的地點類型或城市。")
                await submitDrawerQuery()
            } else {
                viewModel.mapCandidates = candidates
                addSpotStatus = nil
                await submitDrawerQuery()
                withAnimation {
                    drawerDetent = .medium
                }
            }
        }
    }

    private func findExactPlace(for candidate: PlaceReviewCandidate) {
        let query = candidate.refinementQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            addMoreClue(for: candidate)
            return
        }
        mapDetailDrawerItem = nil
        searchFocused = false
        viewModel.query = query
        addSpotStatus = languageSettings.localized(
            english: "Finding exact place for \(candidate.name). Review the map match before saving.",
            traditionalChinese: "正在替「\(candidate.name)」找精確地點。保存前請先確認地圖結果。"
        )
        withAnimation { drawerDetent = .medium }

        startMapSearch { requestID in
            let result = await onPrepareMapSearch(query)
            guard isCurrentMapSearch(requestID) else { return }
            guard case .current(let candidates) = result else { return }
            if candidates.isEmpty {
                viewModel.mapCandidates = []
                addSpotStatus = languageSettings.localized(
                    english: "No exact map match found for \(candidate.name). Add a city, address, or map link as another clue.",
                    traditionalChinese: "找不到「\(candidate.name)」的精確地點。請再補城市、地址或地圖連結作為線索。"
                )
                openReviewCandidateDetail(candidate)
            } else {
                viewModel.mapCandidates = candidates
                addSpotStatus = nil
                // Saving one of these pins resolves the clue itself, so the
                // item leaves Review instead of lingering there.
                onBeginExactSearchResolution(candidate)
                // Take the user to the map itself: the camera has focused the
                // candidate pins, so close the drawer instead of covering the
                // map with a results list. Tapping a pin opens its receipt.
                onShowMapCandidatesOnMap()
            }
        }
    }

    private func toggleVoiceInput() {
        withAnimation { drawerDetent = .medium }
        searchFocused = false
        voiceQuery.toggle()
    }

    private func openProfile() {
        voiceQuery.stop()
        searchFocused = false
        onOpenPassport()
    }

    private func closeDrawerContent() {
        cancelMapSearch()
        voiceQuery.stop()
        let shouldClearMapSearch = hasVisibleMapSearchResults
        viewModel.reset()
        if shouldClearMapSearch {
            onClearMapSearchResults()
        }
        searchFocused = false
        withAnimation { drawerDetent = collapsedDrawerDetent }
    }

    private func closeMapSearchResults() {
        cancelMapSearch()
        voiceQuery.stop()
        viewModel.reset()
        onClearMapSearchResults()
        searchFocused = false
        addSpotStatus = nil
        withAnimation { drawerDetent = collapsedDrawerDetent }
    }

    private func closeMapDetail() {
        mapDetailDrawerItem = nil
        onDismissMapDetail()
        withAnimation(SaveTheme.Motion.standardSpring) {
            drawerDetent = collapsedDrawerDetent
        }
    }

    private func startMapSearch(_ operation: @escaping (UUID) async -> Void) {
        mapSearchTask?.cancel()
        let requestID = mapSearchRequestGate.begin()
        mapSearchTask = Task { await operation(requestID) }
    }

    private func isCurrentMapSearch(_ requestID: UUID) -> Bool {
        !Task.isCancelled && mapSearchRequestGate.isCurrent(requestID)
    }

    private func cancelMapSearch() {
        mapSearchTask?.cancel()
        mapSearchTask = nil
        mapSearchRequestGate.cancel()
    }

    private func importSharedTextToReviewCandidates(_ sharedText: String) {
        guard !isImportingURL else { return }
        searchFocused = false
        isImportingURL = true
        linkAnalysisState = .analyzing
        addSpotStatus = nil
        viewModel.returnToCommands()
        withAnimation { drawerDetent = .medium }

        Task {
            do {
                let candidateIDs = try await onImportSharedTextAsReviewCandidates(sharedText)
                linkAnalysisState = .ready(Set(candidateIDs))
                onOpenReview()
            } catch {
                linkAnalysisState = .failed(error.localizedDescription)
                viewModel.returnToCommands()
                withAnimation { drawerDetent = .medium }
            }
            isImportingURL = false
        }
    }

    @ViewBuilder
    private var linkAnalysisStatusCard: some View {
        switch linkAnalysisState {
        case .idle:
            EmptyView()
        case .analyzing:
            LinkAnalysisStatusCard(
                systemImage: "link.badge.plus",
                title: languageSettings.localized(english: "Analyzing link", traditionalChinese: "正在分析連結"),
                message: languageSettings.localized(
                    english: "Savvy is checking the source and extracting possible places. Nothing is saved to your map yet.",
                    traditionalChinese: "Savvy 正在檢查來源並找出可能地點；目前還不會存進你的地圖。"
                ),
                isLoading: true,
                tone: SaveAtlasPalette.kraft
            )
        case .ready(let candidateIDs):
            let count = candidateIDs.count
            LinkAnalysisStatusCard(
                systemImage: count == 0 ? "questionmark.circle.fill" : "checkmark.seal.fill",
                title: languageSettings.localized(
                    english: count == 0 ? "Needs another clue" : "Analysis ready",
                    traditionalChinese: count == 0 ? "需要更多線索" : "分析完成"
                ),
                message: languageSettings.localized(
                    english: count == 0
                        ? "No new place could be isolated. Try a map link, address, or clearer caption; no place was saved."
                        : "Found \(count) possible place\(count == 1 ? "" : "s"). Open each one, then confirm only the exact places you want to save.",
                    traditionalChinese: count == 0
                        ? "目前無法辨識出新地點。請補上地圖連結、地址或更清楚的貼文說明；尚未收藏任何地點。"
                        : "找到 \(count) 個可能地點。請逐一打開檢查，只確認你要收藏的精確地點。"
                ),
                isLoading: false,
                tone: count == 0 ? SaveAtlasPalette.kraft : SaveAtlasPalette.mint
            )
        case .failed(let message):
            LinkAnalysisStatusCard(
                systemImage: "exclamationmark.triangle.fill",
                title: languageSettings.localized(english: "Link analysis failed", traditionalChinese: "連結分析失敗"),
                message: message,
                isLoading: false,
                tone: .saveCoral
            )
        }
    }

    private func saveFeedback(for candidate: PlaceReviewCandidate) -> String {
        let category = PlaceCategory.inferred(from: "\(candidate.name) \(candidate.address)")
        return languageSettings.localized(
            english: "Map Stamp saved · +1 \(category.displayName.lowercased()) place",
            traditionalChinese: "已保存地圖章 · +1 \(category.displayName(language: languageSettings.language))"
        )
    }

    private func addMoreClue(for candidate: PlaceReviewCandidate) {
        mapDetailDrawerItem = nil
        viewModel.returnToCommands()
        viewModel.query = languageSettings.localized(
            english: "Add more clue for \(candidate.name): ",
            traditionalChinese: "替「\(candidate.name)」補更多線索："
        )
        addSpotStatus = languageSettings.localized(
            english: "Paste a caption, address, map link, or visible OCR text. Savvy will keep it in Review until the exact place is clear.",
            traditionalChinese: "貼上貼文說明、地址、地圖連結或看得到的 OCR 文字。Savvy 會先把它留在待確認，直到精確地點夠清楚。"
        )
        searchFocused = true
        withAnimation { drawerDetent = .medium }
    }

    private func createListForPicker() -> SaveCollaborativeList {
        onCreateList("Trip ideas", "")
    }
}

private struct LinkAnalysisStatusCard: View {
    let systemImage: String
    let title: String
    let message: String
    let isLoading: Bool
    let tone: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.saveInk)
                } else {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.saveInk)
                }
            }
            .frame(width: 34, height: 34)
            .background(tone.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.saveInk)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.saveCocoa.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .saveAtlasPaper(radius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("drawer.linkAnalysis.status")
    }
}

struct MapDetailDrawerView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let item: MapDetailDrawerItem
    @Binding var detent: PresentationDetent
    let captureTripName: String?
    let editableLists: [SaveCollaborativeList]
    let isWorkingReviewCandidateID: UUID?
    let isWorkingMapCandidateID: String?
    let onClose: () -> Void
    let onOpenInbox: (() -> Void)? = nil
    let onDeletePlace: (Place) async throws -> Void
    let onRecommendOrder: (Place) -> Void
    let onPlanAroundPlace: (Place) -> Void
    let onFindExactPlaceCandidate: (PlaceReviewCandidate) -> Void
    let onSaveCandidate: (PlaceReviewCandidate, String?) -> Void
    let onRejectCandidate: (PlaceReviewCandidate) -> Void
    let onSaveCandidateAsSourceOnly: (PlaceReviewCandidate) -> Void
    let onInvestigateCandidateMore: (PlaceReviewCandidate) -> Void
    let onSaveMapCandidate: (SaveMapCandidate) -> Void
    let onSaveSocialPlace: (Place) -> Void
    let onUpdatePlaceVisibility: (Place, PlaceVisibility) async throws -> Void
    let onUpdatePlace: (Place) async throws -> Void
    let onFindRelatedSources: (Place, Bool) async throws -> RelatedPlaceSourcePack
    let onAddPlaceToTrip: (Place) -> Void
    let onCreateList: () -> SaveCollaborativeList
    let onAddPlaceToList: (Place, UUID) throws -> Void
    @State private var statusMessage: String?

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.height <= 132 {
                SelectedPlaceCapsule(
                    item: item,
                    onExpand: expandDetail,
                    onClose: onClose
                )
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 0) {
                    expandedHeader
                    Divider()
                        .overlay(SaveAtlasPalette.line.opacity(0.28))
                        .padding(.horizontal, 18)
                    expandedContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background {
                    AtlasPostcardDrawerBackground(colorScheme: colorScheme)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place.detail.root")
    }

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    private var expandedHeader: some View {
        switch item {
        case .savedPlace(let place):
            liftedPostcardHeader(place)
        case .reviewCandidate(let candidate):
            reviewPostcardHeader(candidate)
        case .unsavedCandidate, .socialPlace:
            compactHeader
        }
    }

    private func liftedPostcardHeader(_ place: Place) -> some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 10) {
                SavePostcardPerforatedMedallion(
                    systemName: "star.fill",
                    tint: SaveAtlasPalette.mint,
                    edge: SaveAtlasPalette.forest
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(languageSettings.localized(
                        english: "Map Stamp · Confirmed",
                        traditionalChinese: "地圖章 · 已確認"
                    ))
                    .font(SaveAtlasType.strong(10))
                    .tracking(0.65)
                    .foregroundStyle(SaveAtlasPalette.forest)

                    Text(place.name)
                        .font(SaveAtlasType.strong(19, relativeTo: .headline))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)

                    Text(savedPlaceLocation(place))
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .lineLimit(1)
                        .accessibilityIdentifier("place.detail.postcardChrome")
                }

                Spacer(minLength: 4)

                shareAction
                    .frame(width: 38, height: 38)

                Button(action: onClose) {
                    SelectedPlaceCapsuleIcon(systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageSettings.localized(
                    english: "Close place detail",
                    traditionalChinese: "關閉地點詳情"
                ))
                .accessibilityIdentifier("drawer.place.close")
                .frame(width: 38, height: 38)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(SaveAtlasPalette.paper.opacity(0.98))
            .padding(5)
            .background {
                SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                    .fill(SaveAtlasPalette.mint.opacity(0.56))
            }
            .overlay {
                SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                    .stroke(
                        SaveAtlasPalette.forest.opacity(0.66),
                        style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                    )
            }

            SavePostcardMemoPeek(width: 72)
                .offset(x: -20, y: 31)
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 27)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer.saved.liftedPostcard")
    }

    private func reviewPostcardHeader(_ candidate: PlaceReviewCandidate) -> some View {
        let isSkyTicket = candidate.hasSavableLocation
        let fill = isSkyTicket ? SaveAtlasPalette.sky : SaveAtlasPalette.coral
        let edge = isSkyTicket ? SaveAtlasPalette.forest.opacity(0.46) : SaveAtlasPalette.coral

        return ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 10) {
                SavePostcardPerforatedMedallion(
                    systemName: isSkyTicket ? "camera.fill" : "questionmark",
                    tint: isSkyTicket ? SaveAtlasPalette.sky : SaveAtlasPalette.coral.opacity(0.42),
                    edge: edge
                )
                .accessibilityIdentifier("drawer.review.seal")

                VStack(alignment: .leading, spacing: 1) {
                    Text(isSkyTicket
                        ? languageSettings.localized(english: "Review Candidate", traditionalChinese: "待確認地點")
                        : languageSettings.localized(english: "Source Clue", traditionalChinese: "來源線索")
                    )
                    .font(SaveAtlasType.strong(10))
                    .tracking(0.65)
                    .foregroundStyle(isSkyTicket ? SaveAtlasPalette.forest : SaveAtlasPalette.coral)

                    Text(candidate.name)
                        .font(SaveAtlasType.strong(19, relativeTo: .headline))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .accessibilityIdentifier("drawer.review.title")

                    Text(reviewHeaderDetail(candidate))
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .lineLimit(1)
                        .accessibilityIdentifier("drawer.review.sourceLine")
                }

                Spacer(minLength: 4)

                shareAction
                    .frame(width: 38, height: 38)

                Button(action: onClose) {
                    SelectedPlaceCapsuleIcon(systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageSettings.localized(
                    english: "Close place detail",
                    traditionalChinese: "關閉地點詳情"
                ))
                .accessibilityIdentifier("drawer.place.close")
                .frame(width: 38, height: 38)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(SaveAtlasPalette.paper.opacity(0.98))
            .padding(5)
            .background {
                SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                    .fill(fill.opacity(isSkyTicket ? 0.56 : 0.28))
            }
            .overlay {
                SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                    .stroke(
                        edge,
                        style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                    )
            }

            SavePostcardMemoPeek(width: 72)
                .offset(x: -20, y: 31)
                .accessibilityIdentifier("drawer.review.memoPeek")
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 27)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer.postcard.ticketHeader")
    }

    private func reviewHeaderDetail(_ candidate: PlaceReviewCandidate) -> String {
        let address = candidate.address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty { return address }
        if let handle = candidate.sourceHandle, !handle.isEmpty {
            return handle.hasPrefix("@") ? handle : "@\(handle)"
        }
        if let city = candidate.city, !city.isEmpty { return city }
        return languageSettings.localized(english: "Needs your review", traditionalChinese: "需要你確認")
    }

    private func savedPlaceLocation(_ place: Place) -> String {
        let area = place.shareAreaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !area.isEmpty { return area }
        let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty
            ? languageSettings.localized(english: "Saved in your Savvy", traditionalChinese: "已收藏到 Savvy")
            : address
    }

    private var compactHeader: some View {
        HStack(spacing: 9) {
            PostcardDrawerSeal(
                systemImage: item.postcardSystemImage,
                tint: item.postcardTint
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.presentation.title)
                    .font(SaveAtlasType.strong(18, relativeTo: .headline))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(itemEyebrow)
                    .font(SaveAtlasType.display(10))
                    .tracking(0.45)
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityIdentifier("place.detail.postcardChrome")
            }
            .frame(maxWidth: .infinity)

            shareAction
                .frame(width: 38, height: 38)

            if let onOpenInbox {
                Button(action: onOpenInbox) {
                    SelectedPlaceCapsuleIcon(systemImage: "tray.full.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageSettings.localized(english: "Open Review", traditionalChinese: "打開待確認"))
                .accessibilityIdentifier("drawer.openReview")
                .frame(width: 38, height: 38)
            }

            Button(action: onClose) {
                SelectedPlaceCapsuleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageSettings.localized(english: "Close place detail", traditionalChinese: "關閉地點詳情"))
            .accessibilityIdentifier("drawer.place.close")
            .frame(width: 38, height: 38)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(SaveAtlasPalette.paper.opacity(0.98))
        .padding(5)
        .background {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .fill(item.postcardTint.opacity(0.58))
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .stroke(
                    SaveAtlasPalette.forest.opacity(0.58),
                    style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                )
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .accessibilityIdentifier("drawer.postcard.ticketHeader")
    }

    @ViewBuilder
    private var shareAction: some View {
        SavePlaceShareButton(content: item.shareContent) {
            SelectedPlaceCapsuleIcon(systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel(languageSettings.localized(english: "Share \(item.presentation.title)", traditionalChinese: "分享 \(item.presentation.title)"))
    }

    private func expandDetail() {
        withAnimation(SaveTheme.Motion.standardSpring) {
            detent = .medium
        }
    }

    private var itemEyebrow: String {
        localizedEyebrow(for: item, language: languageSettings.language)
    }

    private var expandedContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch item {
                case .savedPlace(let place):
                    SavedMapDetailDrawerContent(
                        place: place,
                        onRecommendOrder: { onRecommendOrder(place) },
                        onPlanAroundPlace: { onPlanAroundPlace(place) },
                        onAddToTrip: { onAddPlaceToTrip(place) },
                        onDeletePlace: {
                            try await onDeletePlace(place)
                        },
                        onUpdateVisibility: { visibility in
                            try await onUpdatePlaceVisibility(place, visibility)
                        },
                        onUpdatePlace: { updatedPlace in
                            try await onUpdatePlace(updatedPlace)
                        },
                        onFindRelatedSources: { selectedPlace, forceRefresh in
                            try await onFindRelatedSources(selectedPlace, forceRefresh)
                        }
                    )
                    .id(place.id)

                    AddToListPanel(
                        title: languageSettings.localized(english: "Add this Map Stamp to a list", traditionalChinese: "將這個地圖章加入清單"),
                        lists: editableLists,
                        onCreateList: onCreateList,
                        onAddToList: { listID in
                            do {
                                try onAddPlaceToList(place, listID)
                                statusMessage = languageSettings.localized(english: "Added \(place.name) to list.", traditionalChinese: "已將 \(place.name) 加入清單。")
                            } catch {
                                statusMessage = error.localizedDescription
                            }
                        }
                    )

                case .reviewCandidate(let candidate):
                    ReviewCandidateDetailCard(
                        candidate: candidate,
                        captureTripName: captureTripName,
                        isWorking: isWorkingReviewCandidateID == candidate.id,
                        onFindExactPlace: { onFindExactPlaceCandidate(candidate) },
                        onSave: { nameOverride in onSaveCandidate(candidate, nameOverride) },
                        onReject: { onRejectCandidate(candidate) },
                        onSaveSourceOnly: { onSaveCandidateAsSourceOnly(candidate) },
                        onInvestigateMore: { onInvestigateCandidateMore(candidate) }
                    )
                    .id(candidate.id)

                case .unsavedCandidate(let candidate):
                    UnsavedMapCandidateCard(
                        candidate: candidate,
                        isWorking: isWorkingMapCandidateID == candidate.id,
                        onSave: { onSaveMapCandidate($0) }
                    )
                case .socialPlace(let place):
                    SocialPlaceDetailCard(
                        place: place,
                        onSave: { onSaveSocialPlace(place) }
                    )
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.saveCocoa.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, SaveTheme.Spacing.lg)
            .padding(.top, SaveTheme.Spacing.lg)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("place.detail.scroll")
    }

}

private struct SelectedPlaceCapsule: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let item: MapDetailDrawerItem
    let onExpand: () -> Void
    let onOpenInbox: (() -> Void)? = nil
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            shareAction
                .frame(width: 44, height: 44)

            Button(action: onExpand) {
                VStack(spacing: 2) {
                    Text(item.presentation.title)
                        .font(SaveAtlasType.strong(17, relativeTo: .headline))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)

                    Text(itemEyebrow)
                        .font(SaveAtlasType.display(10))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("place.detail.postcardChrome")

                    Text(itemContextLine)
                        .font(SaveAtlasType.body(10))
                        .foregroundStyle(SaveAtlasPalette.muted.opacity(0.86))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                }
                .multilineTextAlignment(.center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageSettings.localized(english: "Open \(item.presentation.title) details", traditionalChinese: "打開 \(item.presentation.title) 詳情"))
            .accessibilityHint(languageSettings.localized(english: "Expands the selected place drawer", traditionalChinese: "展開選取的地點抽屜"))

            if let onOpenInbox {
                Button(action: onOpenInbox) {
                    SelectedPlaceCapsuleIcon(systemImage: "tray.full.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageSettings.localized(english: "Open Review", traditionalChinese: "打開待確認"))
                .accessibilityIdentifier("drawer.openReview")
                .frame(width: 44, height: 44)
            }

            Button(action: onClose) {
                SelectedPlaceCapsuleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageSettings.localized(english: "Close selected place", traditionalChinese: "關閉已選地點"))
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 10)
        .frame(height: 74)
        .background(
            SaveAtlasPalette.paper.opacity(0.98),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.32), lineWidth: 1)
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.07), radius: 7, y: 3)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    if value.translation.height < -12 {
                        onExpand()
                    }
                }
        )
    }

    @ViewBuilder
    private var shareAction: some View {
        SavePlaceShareButton(content: item.shareContent) {
            SelectedPlaceCapsuleIcon(systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel(languageSettings.localized(english: "Share \(item.presentation.title)", traditionalChinese: "分享 \(item.presentation.title)"))
    }

    private var itemEyebrow: String {
        localizedEyebrow(for: item, language: languageSettings.language)
    }

    private var itemContextLine: String {
        switch item {
        case .savedPlace(let place):
            let memoryState = place.status == .visited
                ? languageSettings.localized(english: "Tried memory", traditionalChinese: "去過的記憶")
                : languageSettings.localized(english: "Saved memory", traditionalChinese: "已保存記憶")
            return [place.category.displayName(language: languageSettings.language), memoryState].joined(separator: " · ")
        case .socialPlace(let place):
            return [
                place.category.displayName(language: languageSettings.language),
                languageSettings.localized(english: "Social signal", traditionalChinese: "社群訊號")
            ].joined(separator: " · ")
        case .reviewCandidate(let candidate):
            if candidate.hasSavableLocation {
                let address = candidate.address.trimmingCharacters(in: .whitespacesAndNewlines)
                return address.isEmpty
                    ? languageSettings.localized(english: "Likely match", traditionalChinese: "可能符合")
                    : address
            }
            if let city = candidate.city, !city.isEmpty { return city }
            return languageSettings.localized(english: "Source clue", traditionalChinese: "來源線索")
        case .unsavedCandidate(let candidate):
            var parts = [
                candidate.category?.displayName(language: languageSettings.language) ?? languageSettings.localized(english: "Place", traditionalChinese: "地點"),
                languageSettings.localized(english: "Map search", traditionalChinese: "地圖搜尋")
            ]
            if let distanceLabel = candidate.distanceLabel {
                parts.append(distanceLabel)
            }
            return parts.joined(separator: " · ")
        }
    }
}

private func localizedEyebrow(for item: MapDetailDrawerItem, language: AppLanguage) -> String {
    switch item {
    case .savedPlace:
        return language.localized(english: "Map Stamp · From your Savvy", traditionalChinese: "地圖章 · 來自你的 Savvy")
    case .reviewCandidate(let candidate):
        return candidate.hasSavableLocation
            ? language.localized(english: "Review Candidate · Check before saving", traditionalChinese: "待確認地點 · 保存前請先檢查")
            : language.localized(english: "Clue · Needs exact place", traditionalChinese: "線索 · 需要精確地點")
    case .unsavedCandidate, .socialPlace:
        return language.localized(english: "Public discovery · Not saved yet", traditionalChinese: "公開探索 · 尚未保存")
    }
}

private struct SelectedPlaceCapsuleIcon: View {
    let systemImage: String
    var fill: Color = SaveAtlasPalette.paper
    var foreground: Color = SaveAtlasPalette.forest

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(foreground)
            .frame(width: 38, height: 38)
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SaveAtlasPalette.line.opacity(0.38), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PostcardDrawerSeal: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(SaveAtlasPalette.forest)
            .frame(width: 42, height: 42)
            .background(tint, in: Circle())
            .overlay {
                Circle()
                    .stroke(
                        SaveAtlasPalette.line.opacity(0.34),
                        style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                    )
                    .padding(2)
            }
            .accessibilityHidden(true)
    }
}

private struct PostcardDetailPaper<Content: View>: View {
    let tint: Color
    let accessibilityIdentifier: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .background {
            SavePostcardScallopedRectangle(depth: 3, pitch: 11)
                .fill(SaveAtlasPalette.paper)
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 3, pitch: 11)
                .stroke(
                    tint.opacity(0.88),
                    style: StrokeStyle(lineWidth: 1.15, dash: [2.5, 2.5])
                )
        }
        .overlay(alignment: .topTrailing) {
            Circle()
                .stroke(tint.opacity(0.56), lineWidth: 1.2)
                .frame(width: 46, height: 46)
                .overlay {
                    Circle()
                        .stroke(tint.opacity(0.32), lineWidth: 1)
                        .frame(width: 34, height: 34)
                }
                .offset(x: -12, y: 10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.055), radius: 5, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct PostcardReceiptSection<Content: View>: View {
    let title: String
    let systemImage: String
    var tint: Color = SaveAtlasPalette.line
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(SaveAtlasType.strong(12))
                Text(title.uppercased())
                    .font(SaveAtlasType.strong(11))
                    .tracking(0.55)
                Spacer(minLength: 0)
            }
            .foregroundStyle(SaveAtlasPalette.forest)

            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            SaveAtlasPalette.paper
                .overlay {
                    VStack(spacing: 18) {
                        ForEach(0..<4, id: \.self) { _ in
                            Rectangle()
                                .fill(SaveAtlasPalette.line.opacity(0.13))
                                .frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 8)
                }
        }
        .overlay {
            Rectangle()
                .stroke(
                    tint.opacity(0.54),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        }
    }
}

private extension MapDetailDrawerItem {
    var postcardSystemImage: String {
        switch self {
        case .savedPlace:
            return "star.fill"
        case .reviewCandidate(let candidate):
            return candidate.hasReliableCoordinates ? "camera.fill" : "magnifyingglass"
        case .unsavedCandidate:
            return "mappin.and.ellipse"
        case .socialPlace:
            return "person.2.fill"
        }
    }

    var postcardTint: Color {
        switch self {
        case .savedPlace:
            return SaveAtlasPalette.mint
        case .reviewCandidate(let candidate):
            return candidate.hasReliableCoordinates
                ? SaveAtlasPalette.sky
                : SaveAtlasPalette.coral.opacity(0.34)
        case .unsavedCandidate:
            return SaveAtlasPalette.lavender
        case .socialPlace:
            return SaveAtlasPalette.honey.opacity(0.72)
        }
    }

    var presentation: SavePlaceDrawerPresentation {
        switch self {
        case .savedPlace(let place):
            return SavePlaceDrawerPresentation(place: place)
        case .reviewCandidate(let candidate):
            return SavePlaceDrawerPresentation(reviewCandidate: candidate)
        case .unsavedCandidate(let candidate):
            return SavePlaceDrawerPresentation(mapCandidate: candidate)
        case .socialPlace(let place):
            return .unsavedMapCandidate(
                title: place.name,
                contextLine: "\(place.category.displayName) · \(place.socialSignal?.displayText ?? "Social signal")",
                trustLine: "Social signal, not saved in your Savvy yet."
            )
        }
    }

    var title: String {
        presentation.title
    }

    var subtitle: String {
        presentation.eyebrow
    }

    var contextLine: String? {
        presentation.contextLine
    }

    var trustLine: String {
        presentation.trustLine
    }

    var shareSubject: String {
        switch self {
        case .savedPlace(let place), .socialPlace(let place):
            return place.shareSubject
        case .reviewCandidate(let candidate):
            return candidate.shareSubject
        case .unsavedCandidate(let candidate):
            return candidate.shareSubject
        }
    }

    var shareURL: URL? {
        switch self {
        case .savedPlace(let place), .socialPlace(let place):
            return place.saveShareURL
        case .reviewCandidate(let candidate):
            return candidate.saveShareURL
        case .unsavedCandidate(let candidate):
            return candidate.saveShareURL
        }
    }

    var shareText: String {
        switch self {
        case .savedPlace(let place), .socialPlace(let place):
            return place.shareText
        case .reviewCandidate(let candidate):
            return candidate.shareText
        case .unsavedCandidate(let candidate):
            return candidate.shareText
        }
    }

    var shareContent: SavePlaceShareContent {
        switch self {
        case .savedPlace(let place), .socialPlace(let place):
            return .place(place)
        case .reviewCandidate(let candidate):
            return .reviewCandidate(candidate)
        case .unsavedCandidate(let candidate):
            return .mapCandidate(candidate)
        }
    }
}

private struct AtlasPostcardDrawerBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        SaveAtlasPalette.canvas
            .overlay {
                Image("PaperTexture")
                    .resizable(resizingMode: .tile)
                    .opacity(colorScheme == .dark ? 0.02 : 0.045)
            }
            .overlay {
                LinearGradient(
                    colors: [
                        SaveAtlasPalette.paper.opacity(colorScheme == .dark ? 0.40 : 0.86),
                        SaveAtlasPalette.canvas.opacity(0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .overlay {
                Canvas { context, size in
                    let spacing: CGFloat = 18
                    for x in stride(from: CGFloat(9), through: size.width, by: spacing) {
                        for y in stride(from: CGFloat(9), through: size.height, by: spacing) {
                            context.fill(
                                Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                                with: .color(SaveAtlasPalette.line.opacity(0.07))
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                HStack(spacing: 7) {
                    ForEach(0..<24, id: \.self) { _ in
                        Circle()
                            .fill(SaveAtlasPalette.line.opacity(0.18))
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .ignoresSafeArea()
    }
}

private struct SavedMapDetailDrawerContent: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let place: Place
    let onRecommendOrder: () -> Void
    let onPlanAroundPlace: () -> Void
    let onAddToTrip: () -> Void
    let onDeletePlace: () async throws -> Void
    let onUpdateVisibility: (PlaceVisibility) async throws -> Void
    let onUpdatePlace: (Place) async throws -> Void
    let onFindRelatedSources: (Place, Bool) async throws -> RelatedPlaceSourcePack
    @Environment(\.openURL) private var openURL
    @State private var enrichedPlace: Place?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var isEditingPlace = false
    @State private var isSavingPlaceEdit = false
    @State private var editName = ""
    @State private var editAddress = ""
    @State private var editError: String?
    @State private var isEnrichingBusinessDetails = false
    @State private var localVisibility: PlaceVisibility?
    @State private var isUpdatingVisibility = false
    @State private var visibilityError: String?

    private var detailPlace: Place {
        var value = place
        if let enrichedPlace, enrichedPlace.id == place.id {
            value = enrichedPlace
        }
        if let localVisibility {
            value.visibility = localVisibility
        }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            postcardIdentity

            // Business photo gallery: the postcard corner shows one shot, but
            // enrichment fetches several — surface them all as a swipeable
            // carousel once there is more than the header photo.
            if detailPlace.businessPhotoURLStrings.count > 1 || isEnrichingBusinessDetails {
                PlaceBusinessPhotoCarousel(
                    imageURLs: detailPlace.businessPhotoURLStrings,
                    isSearching: isEnrichingBusinessDetails
                )
                .accessibilityIdentifier("drawer.saved.photoCarousel")
            }

            FlowLayout(spacing: 8) {
                CategoryPill(category: detailPlace.category, isSelected: true)
                if let rating = detailPlace.googleRating ?? detailPlace.rating {
                    MapDetailChip(icon: "star.fill", text: String(format: "%.1f", rating))
                }
                if let priceRange = detailPlace.priceRange {
                    MapDetailChip(icon: "tag.fill", text: priceRange)
                }
                ForEach(detailPlace.verificationChips(language: languageSettings.language, sourceLabel: detailPlace.sourceConfirmationLabel(language: languageSettings.language)), id: \.text) { chip in
                    MapDetailChip(icon: chip.icon, text: chip.text)
                }
            }

            Button(action: onAddToTrip) {
                Label(
                    languageSettings.localized(english: "Add to Trip", traditionalChinese: "加入行程"),
                    systemImage: "suitcase.rolling.fill"
                )
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(SaveAtlasPalette.coral)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SaveAtlasPalette.ink.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("drawer.saved.addToTrip")

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(SaveAtlasPalette.forest)
                Text(detailPlace.sourceConfirmationLabel(language: languageSettings.language))
                Spacer(minLength: 8)
                Text(savedDateLabel)
            }
            .font(SaveAtlasType.body(11))
            .foregroundStyle(SaveAtlasPalette.muted)
            .padding(.vertical, 8)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(SaveAtlasPalette.line.opacity(0.28))
                    .frame(height: 1)
            }

            HStack(spacing: 8) {
                SavePlaceShareButton(content: .place(detailPlace)) {
                    PlaceDetailActionLabel(
                        title: languageSettings.localized(english: "Share", traditionalChinese: "分享"),
                        systemImage: "square.and.arrow.up",
                        fill: SaveAtlasPalette.paper
                    )
                }

                Button {
                    if let providerURL = detailPlace.providerMapDestinationURL {
                        openURL(providerURL)
                    } else {
                        NavigationService.navigate(to: detailPlace.coordinate, name: detailPlace.name)
                    }
                } label: {
                    PlaceDetailActionLabel(
                        title: detailPlace.providerMapDestinationURL == nil
                            ? languageSettings.localized(english: "Maps", traditionalChinese: "地圖")
                            : languageSettings.localized(english: "Amap", traditionalChinese: "高德地圖"),
                        systemImage: "map.fill",
                        fill: SaveAtlasPalette.paper
                    )
                }

                if let sourceURL = detailPlace.primarySourceURL {
                    Button {
                        openURL(sourceURL)
                    } label: {
                        PlaceDetailActionLabel(
                            title: languageSettings.localized(english: "Source", traditionalChinese: "來源"),
                            systemImage: "link",
                            fill: SaveAtlasPalette.paper
                        )
                    }
                }
            }

            Button(action: onPlanAroundPlace) {
                PlaceDetailActionLabel(
                    title: languageSettings.localized(
                        english: "Plan around this Map Stamp",
                        traditionalChinese: "以這個地圖章規劃"
                    ),
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                    fill: SaveAtlasPalette.honey.opacity(0.62)
                )
            }

            // One fact, one home: rating/price live in the chips row, hours in
            // Basic info, the note in "Your saved memory", the source in the
            // confirmation line — the old Memory summary panel repeated all
            // four and is gone.
            PlaceBasicInfoPanel(place: detailPlace)

            if isEditingPlace {
                placeEditor
            }

            Menu {
                Button(action: beginPlaceEdit) {
                    Label(languageSettings.text(.edit), systemImage: "pencil")
                }

                Section(languageSettings.localized(english: "Visibility", traditionalChinese: "可見範圍")) {
                    ForEach(PlaceVisibility.allCases, id: \.self) { visibility in
                        Button {
                            Task { await updateVisibility(visibility) }
                        } label: {
                            Label(
                                visibility.displayName(language: languageSettings.language),
                                systemImage: visibility.systemImage
                            )
                        }
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(languageSettings.localized(english: "Delete", traditionalChinese: "刪除"), systemImage: "trash")
                }
            } label: {
                Label(languageSettings.localized(english: "More", traditionalChinese: "更多"), systemImage: "ellipsis.circle")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.saveCocoa)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(SaveAtlasPalette.paper.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(SaveAtlasPalette.line.opacity(0.3), lineWidth: 1)
                    )
            }
            .disabled(isSavingPlaceEdit || isUpdatingVisibility)
            .accessibilityIdentifier("drawer.saved.more")

            RelatedPlaceSourcesPanel(
                place: detailPlace,
                discover: onFindRelatedSources
            )

            if let deleteError {
                Text(deleteError)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.red)
            }
            if let editError {
                Text(editError)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.red)
            }
            if let visibilityError {
                Text(visibilityError)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveError)
            }
        }
        .padding(14)
        .background {
            SavePostcardScallopedRectangle(depth: 3, pitch: 11)
                .fill(SaveAtlasPalette.paper)
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 3, pitch: 11)
                .stroke(
                    SaveAtlasPalette.line.opacity(0.46),
                    style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                )
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.055), radius: 5, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer.saved.postcardBody")
        .confirmationDialog(
            languageSettings.localized(english: "Delete \(place.name)?", traditionalChinese: "刪除「\(place.name)」？"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(languageSettings.localized(english: "Delete Place", traditionalChinese: "刪除地點"), role: .destructive) {
                Task { await deletePlace() }
            }
            Button(languageSettings.text(.cancel), role: .cancel) {}
        } message: {
            Text(languageSettings.localized(english: "This removes the Map Stamp from Savvy.", traditionalChinese: "這會從 Savvy 移除這個地圖章。"))
        }
        .task(id: place.id) {
            await enrichBusinessDetails()
        }
    }

    private var postcardIdentity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SavedPostcardPhoto(
                    imageURLs: detailPlace.businessPhotoURLStrings,
                    isSearching: isEnrichingBusinessDetails
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(languageSettings.localized(
                        english: "TO YOUR Savvy",
                        traditionalChinese: "寄給你的 Savvy"
                    ))
                    .font(SaveAtlasType.strong(10))
                    .tracking(0.75)
                    .foregroundStyle(SaveAtlasPalette.muted)

                    Text(detailPlace.name)
                        .font(SaveAtlasType.strong(20, relativeTo: .headline))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .lineLimit(2)

                    Text(postcardLocation)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .lineLimit(2)

                    Text(detailPlace.category.displayName(language: languageSettings.language))
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)

                    Label(
                        languageSettings.localized(
                            english: "Confirmed Map Stamp",
                            traditionalChinese: "已確認地圖章"
                        ),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(SaveAtlasType.display(11))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 24)
                    .background(SaveAtlasPalette.mint, in: Capsule())
                }

                Spacer(minLength: 0)

                VStack(spacing: 11) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(SaveAtlasPalette.line.opacity(0.36))
                            .frame(width: 36, height: 1)
                    }
                }
                .padding(.top, 5)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(languageSettings.localized(
                    english: "Your saved memory",
                    traditionalChinese: "你的收藏記憶"
                ))
                .font(SaveAtlasType.strong(12))
                .foregroundStyle(SaveAtlasPalette.forest)

                Text(memorySummary)
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                VStack(spacing: 18) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(SaveAtlasPalette.line.opacity(0.18))
                            .frame(height: 1)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer.saved.postalIdentity")
    }

    private var postcardLocation: String {
        let area = detailPlace.shareAreaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !area.isEmpty { return area }
        let address = detailPlace.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty
            ? languageSettings.localized(english: "Saved place", traditionalChinese: "已收藏地點")
            : address
    }

    private var savedDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: languageSettings.language == .traditionalChinese
            ? "zh_Hant_TW"
            : "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: detailPlace.createdAt)
    }

    private var memorySummary: String {
        detailPlace.memorySummary(language: languageSettings.language)
    }

    private func enrichBusinessDetails() async {
        isEnrichingBusinessDetails = true
        defer { isEnrichingBusinessDetails = false }
        guard let updatedPlace = await PlaceBusinessEnricher.enrich(detailPlace) else { return }
        guard place.id == updatedPlace.id else { return }
        enrichedPlace = updatedPlace
        // Persist so enriched photos/hours survive relaunch and sync across
        // devices; previously they lived only in this view's state. Demo and
        // offline sessions simply skip the write.
        try? await SupabaseService.shared.updatePlace(updatedPlace)
    }

    private var placeEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(languageSettings.localized(english: "Place name", traditionalChinese: "地點名稱"), text: $editName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(SaveAtlasPalette.paper.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            TextField(languageSettings.localized(english: "Address", traditionalChinese: "地址"), text: $editAddress)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(SaveAtlasPalette.paper.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    isEditingPlace = false
                    editError = nil
                } label: {
                    PlaceDetailActionLabel(title: languageSettings.text(.cancel), systemImage: "xmark", fill: SaveAtlasPalette.paper)
                }
                .disabled(isSavingPlaceEdit)

                Button {
                    savePlaceEdit()
                } label: {
                    PlaceDetailActionLabel(
                        title: isSavingPlaceEdit ? languageSettings.text(.saving) : languageSettings.text(.save),
                        systemImage: "checkmark",
                        fill: SaveAtlasPalette.kraft.opacity(0.8)
                    )
                }
                .disabled(isSavingPlaceEdit)
            }
        }
        .padding(10)
        .background(SaveAtlasPalette.paper.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.35), lineWidth: 1)
        )
    }

    private func beginPlaceEdit() {
        editName = detailPlace.name
        editAddress = detailPlace.address
        editError = nil
        isEditingPlace = true
    }

    private func updateVisibility(_ visibility: PlaceVisibility) async {
        guard visibility != detailPlace.effectiveVisibility else { return }
        let previousVisibility = localVisibility
        isUpdatingVisibility = true
        visibilityError = nil
        localVisibility = visibility
        defer { isUpdatingVisibility = false }

        do {
            try await onUpdateVisibility(visibility)
        } catch {
            localVisibility = previousVisibility
            visibilityError = error.localizedDescription
        }
    }

    private func savePlaceEdit() {
        let trimmedName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = editAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            editError = languageSettings.localized(english: "Place name cannot be empty.", traditionalChinese: "地點名稱不能空白。")
            return
        }

        isSavingPlaceEdit = true
        editError = nil

        var updatedPlace = detailPlace
        updatedPlace.name = trimmedName
        updatedPlace.address = trimmedAddress.isEmpty ? detailPlace.address : trimmedAddress

        Task {
            do {
                try await onUpdatePlace(updatedPlace)
                await MainActor.run {
                    enrichedPlace = updatedPlace
                    isEditingPlace = false
                    isSavingPlaceEdit = false
                }
            } catch {
                await MainActor.run {
                    editError = error.localizedDescription
                    isSavingPlaceEdit = false
                }
            }
        }
    }

    private func deletePlace() async {
        guard !isDeleting else { return }
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }

        do {
            try await onDeletePlace()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

private struct SavedPostcardPhoto: View {
    let imageURLs: [String]
    let isSearching: Bool

    var body: some View {
        Group {
            if let urlString = imageURLs.first,
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
        .frame(width: 104, height: 104)
        .background(SaveAtlasPalette.mint.opacity(0.46))
        .clipped()
        .padding(4)
        .background(SaveAtlasPalette.paper)
        .overlay {
            Rectangle()
                .stroke(SaveAtlasPalette.line.opacity(0.52), lineWidth: 1)
        }
        .rotationEffect(.degrees(-1.2))
        .shadow(color: SaveAtlasPalette.ink.opacity(0.06), radius: 3, y: 2)
        .accessibilityLabel(isSearching ? "Finding business photo" : "Saved place photo")
    }

    private var fallback: some View {
        Rectangle()
            .fill(SaveAtlasPalette.mint.opacity(0.48))
            .overlay {
                Image(systemName: isSearching ? "hourglass" : "photo.on.rectangle.angled")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SaveAtlasPalette.forest.opacity(0.72))
            }
    }
}

private struct SocialPlaceDetailCard: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let place: Place
    let onSave: () -> Void

    var body: some View {
        PostcardDetailPaper(
            tint: SaveAtlasPalette.honey,
            accessibilityIdentifier: "drawer.social.postcardBody"
        ) {
            PlaceBusinessPhotoCarousel(imageURLs: place.businessPhotoURLStrings)

            HStack(spacing: 8) {
                CategoryPill(category: place.category, isSelected: true)
                if let rating = place.googleRating ?? place.rating {
                    MapDetailChip(icon: "star.fill", text: String(format: "%.1f", rating))
                }
                Spacer(minLength: 0)
            }

            if let signal = place.socialSignal {
                PostcardReceiptSection(
                    title: languageSettings.localized(english: "Social signal", traditionalChinese: "社群訊號"),
                    systemImage: signal.kind.pinSystemImage,
                    tint: SaveAtlasPalette.honey
                ) {
                    Label(signal.displayText, systemImage: signal.kind.pinSystemImage)
                        .font(SaveAtlasType.strong(13))
                        .foregroundStyle(SaveAtlasPalette.ink)
                    Text(signal.detailText)
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }
            }

            PostcardReceiptSection(
                title: languageSettings.localized(english: "Place receipt", traditionalChinese: "地點憑證"),
                systemImage: "mappin.and.ellipse",
                tint: SaveAtlasPalette.honey
            ) {
                VStack(spacing: 8) {
                    UnsavedCandidateInfoRow(
                        title: languageSettings.localized(english: "Category", traditionalChinese: "類別"),
                        value: place.category.displayName(language: languageSettings.language)
                    )
                    UnsavedCandidateInfoRow(
                        title: languageSettings.localized(english: "Address", traditionalChinese: "地址"),
                        value: place.address.isEmpty
                            ? languageSettings.localized(english: "Address not confirmed", traditionalChinese: "地址尚未確認")
                            : place.address
                    )
                    UnsavedCandidateInfoRow(
                        title: languageSettings.localized(english: "Source", traditionalChinese: "來源"),
                        value: place.sourceConfirmationLabel(language: languageSettings.language)
                    )
                }

                Text(place.memorySummary(language: languageSettings.language))
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onSave) {
                Label(languageSettings.localized(english: "Save to my Savvy", traditionalChinese: "保存到我的 Savvy"), systemImage: "plus.circle.fill")
                    .font(SaveAtlasType.strong(14))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(SaveAtlasPalette.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(SaveAtlasPalette.ink.opacity(0.18), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("drawer.social.primaryAction")
        }
    }
}

private struct MapDetailChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(.saveCocoa)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(SaveAtlasPalette.paper.opacity(0.38))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(SaveAtlasPalette.line.opacity(0.30), lineWidth: 1))
    }
}

private struct AddToListPanel: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let title: String
    let lists: [SaveCollaborativeList]
    let onCreateList: () -> SaveCollaborativeList
    let onAddToList: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: "person.2.wave.2.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.saveInk)
                Spacer()
            }

            if lists.isEmpty {
                Button(action: {
                    let list = onCreateList()
                    onAddToList(list.id)
                }) {
                    Label(languageSettings.localized(english: "Create list and add", traditionalChinese: "建立清單並加入"), systemImage: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.saveInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(SaveAtlasPalette.kraft.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(SaveAtlasPalette.line, lineWidth: 1.4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(lists) { list in
                        Button(list.title) {
                            onAddToList(list.id)
                        }
                    }
                    Divider()
                    Button(languageSettings.localized(english: "New list", traditionalChinese: "新清單")) {
                        let list = onCreateList()
                        onAddToList(list.id)
                    }
                } label: {
                    Label(languageSettings.localized(english: "Choose list", traditionalChinese: "選擇清單"), systemImage: "list.bullet.rectangle")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.saveInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(SaveAtlasPalette.kraft.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(SaveAtlasPalette.line, lineWidth: 1.4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .padding(12)
        .background(SaveAtlasPalette.canvas.opacity(0.32))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.26), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor
private final class VoiceQueryController: NSObject, ObservableObject {
    enum VoiceState: Equatable {
        case idle
        case requestingPermission
        case listening
        case denied
        case unavailable
        case failed(String)
    }

    @Published var state: VoiceState = .idle
    @Published var transcript = ""

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var isListening: Bool {
        state == .listening
    }

    var buttonIconName: String {
        isListening ? "stop.fill" : "mic.fill"
    }

    override init() {
        super.init()
        recognizer?.delegate = self
    }

    func toggle() {
        if isListening {
            stopListening()
        } else {
            Task { await startListening() }
        }
    }

    private func startListening() async {
        guard recognizer?.isAvailable == true else {
            state = .unavailable
            return
        }

        state = .requestingPermission
        let speechStatus = await requestSpeechAuthorization()
        let micGranted = await requestMicrophoneAuthorization()
        guard speechStatus == .authorized, micGranted else {
            state = .denied
            return
        }

        do {
            try beginRecognition()
        } catch {
            state = .failed(error.localizedDescription)
            stopListening()
        }
    }

    private func beginRecognition() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        state = .listening

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stopListening()
                    }
                }
                if let error {
                    self.state = .failed(error.localizedDescription)
                    self.stopListening()
                }
            }
        }
    }

    func stop() {
        stopListening()
    }

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        if isListening {
            state = .idle
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

extension VoiceQueryController: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available, self.state == .listening {
                self.state = .unavailable
                self.stopListening()
            }
        }
    }
}

private struct NotebookBandLabel: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        // Spec P2: kraft chip treatment + editorial condensed type replaces
        // the legacy honey-yellow notebook band.
        HStack(spacing: 7) {
            Text(title.uppercased())
                .font(SaveAtlasType.display(11))
                .tracking(1.1)
                .foregroundColor(SaveAtlasPalette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(SaveAtlasPalette.kraft.opacity(0.58))
                .overlay(Capsule().stroke(SaveAtlasPalette.line.opacity(0.62), lineWidth: 1))
                .clipShape(Capsule())
            Rectangle()
                .fill(SaveAtlasPalette.line.opacity(0.28))
                .frame(height: 1)
        }
        .padding(.top, 2)
    }
}

private struct ReviewCandidateDetailCard: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    var candidate: PlaceReviewCandidate
    var captureTripName: String?
    var isWorking: Bool
    var onFindExactPlace: () -> Void
    var onSave: (String?) -> Void
    var onReject: () -> Void
    var onSaveSourceOnly: () -> Void
    var onInvestigateMore: () -> Void
    @State private var displayNameDraft: String

    init(
        candidate: PlaceReviewCandidate,
        captureTripName: String?,
        isWorking: Bool,
        onFindExactPlace: @escaping () -> Void,
        onSave: @escaping (String?) -> Void,
        onReject: @escaping () -> Void,
        onSaveSourceOnly: @escaping () -> Void,
        onInvestigateMore: @escaping () -> Void
    ) {
        self.candidate = candidate
        self.captureTripName = captureTripName
        self.isWorking = isWorking
        self.onFindExactPlace = onFindExactPlace
        self.onSave = onSave
        self.onReject = onReject
        self.onSaveSourceOnly = onSaveSourceOnly
        self.onInvestigateMore = onInvestigateMore
        _displayNameDraft = State(initialValue: candidate.name)
    }

    var body: some View {
        PostcardDetailPaper(
            tint: candidate.hasSavableLocation ? SaveAtlasPalette.sky : SaveAtlasPalette.coral,
            accessibilityIdentifier: "drawer.review.postcardBody"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    CandidateActionButton(
                        title: primaryActionTitle,
                        systemImage: primaryAction.systemImage,
                        fill: SaveAtlasPalette.coral,
                        foreground: .white,
                        disabled: isWorking,
                        action: performPrimaryAction
                    )
                    .accessibilityIdentifier("drawer.review.primaryAction")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("drawer.review.firstViewport")

                VStack(alignment: .leading, spacing: 12) {
                    ReviewCandidateContextHero(
                        candidate: candidate,
                        captureTripName: captureTripName,
                        eyebrow: presentationEyebrow,
                        title: presentation.title,
                        contextLine: presentationContextLine,
                        // Tapping the hero map jumps straight to the live map with
                        // this clue's candidates pinned.
                        onOpenOnMap: onFindExactPlace
                    )

                    ReviewCandidateNextStepPanel(candidate: candidate)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(languageSettings.localized(english: "Place name", traditionalChinese: "地點名稱"))
                            .font(SaveAtlasType.strong(10))
                            .tracking(0.45)
                            .foregroundStyle(SaveAtlasPalette.muted)
                        TextField(candidate.name, text: $displayNameDraft)
                            .textFieldStyle(.plain)
                            .font(SaveAtlasType.body(15))
                            .foregroundStyle(SaveAtlasPalette.ink)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .background(SaveAtlasPalette.paper)
                            .overlay(
                                Rectangle()
                                    .stroke(SaveAtlasPalette.line.opacity(0.42), lineWidth: 1)
                            )
                    }

                    CandidateActionButton(
                        title: languageSettings.localized(english: "Investigate", traditionalChinese: "繼續調查"),
                        systemImage: "sparkle.magnifyingglass",
                        fill: SaveAtlasPalette.paper,
                        disabled: isWorking,
                        action: onInvestigateMore
                    )

                    Menu {
                        // When the primary action is Confirm (candidate already
                        // has coordinates), re-running the exact-place search had
                        // no entry point — a wrong match left the user stuck.
                        if primaryAction.confirmsMapStamp {
                            Button(action: onFindExactPlace) {
                                Label(languageSettings.localized(english: "Find exact place", traditionalChinese: "找出精確地點"), systemImage: "location.magnifyingglass")
                            }
                        }
                        Button(action: onSaveSourceOnly) {
                            Label(languageSettings.localized(english: "Keep source only", traditionalChinese: "只留來源"), systemImage: "tray.and.arrow.down")
                        }
                        Button(role: .destructive, action: onReject) {
                            Label(languageSettings.localized(english: "Not this place", traditionalChinese: "不是這間"), systemImage: "xmark")
                        }
                    } label: {
                        Label(languageSettings.localized(english: "More review actions", traditionalChinese: "更多確認動作"), systemImage: "ellipsis.circle")
                            .font(SaveAtlasType.strong(12))
                            .foregroundStyle(SaveAtlasPalette.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(SaveAtlasPalette.paper)
                            .overlay(
                                Rectangle()
                                    .stroke(SaveAtlasPalette.line.opacity(0.42), lineWidth: 1)
                            )
                    }
                    .disabled(isWorking)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("drawer.review.belowFold")
            }
        }
        .opacity(isWorking ? 0.65 : 1)
    }

    private var presentation: SavePlaceDrawerPresentation {
        SavePlaceDrawerPresentation(reviewCandidate: candidate)
    }

    private var primaryAction: SavePlaceActionResolution {
        SavePlaceActionResolution(candidate: candidate)
    }

    private var primaryActionTitle: String {
        if primaryAction.confirmsMapStamp {
            return languageSettings.localized(english: "Confirm", traditionalChinese: "確認")
        }
        return primaryAction.kind.displayName(language: languageSettings.language)
    }

    private var presentationEyebrow: String {
        if candidate.status == "source_only" {
            return languageSettings.localized(english: "Source-only clue · Not on your map", traditionalChinese: "只留來源的線索 · 不會出現在地圖")
        }
        return candidate.hasSavableLocation
            ? languageSettings.localized(english: "Review Candidate · Check before saving", traditionalChinese: "待確認地點 · 保存前請先檢查")
            : languageSettings.localized(english: "Clue · Needs exact place", traditionalChinese: "線索 · 需要精確地點")
    }

    private var presentationContextLine: String {
        if candidate.hasSavableLocation {
            let address = candidate.address.trimmingCharacters(in: .whitespacesAndNewlines)
            return address.isEmpty
                ? languageSettings.localized(english: "Likely match", traditionalChinese: "可能符合")
                : address
        }
        if let city = candidate.city, !city.isEmpty { return city }
        return languageSettings.localized(english: "Source clue", traditionalChinese: "來源線索")
    }

    private var presentationTrustLine: String {
        candidate.hasSavableLocation
            ? languageSettings.localized(
                english: "Savvy found a likely place. Review the evidence before stamping it to your map.",
                traditionalChinese: "Savvy 找到可能的地點。存成地圖章前，請先確認證據。"
            )
            : languageSettings.localized(
                english: "Savvy found a source, but not enough proof for a place yet.",
                traditionalChinese: "Savvy 找到來源，但還沒有足夠證據確認成地點。"
            )
    }

    private func performPrimaryAction() {
        if primaryAction.confirmsMapStamp {
            onSave(nameOverride)
        } else {
            onFindExactPlace()
        }
    }

    private var nameOverride: String? {
        let trimmed = displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != original else { return nil }
        return trimmed
    }
}

struct ReviewSourceReceiptPresentation: Equatable {
    let sourceURL: URL?
    let sourcePlatform: SourcePlatform
    let domain: String?
    let handle: String?
    let summary: String?

    init(candidate: PlaceReviewCandidate) {
        let sourceURL = Self.evidenceValue(after: ["Source URL:"], in: candidate.evidence)
            .flatMap(Self.firstURL(in:))
        self.sourceURL = sourceURL
        sourcePlatform = SourcePlatform.from(urlString: sourceURL?.absoluteString)
        if let host = sourceURL?.host()?.lowercased() {
            domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        } else {
            domain = nil
        }
        handle = Self.normalizedHandle(Self.evidenceValue(
            after: ["Creator handle:", "Source handle:"],
            in: candidate.evidence
        ))
        summary = Self.summary(for: candidate)
    }

    private static func firstURL(in line: String) -> URL? {
        line
            .split(whereSeparator: \.isWhitespace)
            .compactMap { rawToken -> URL? in
                let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]{}.,;\"'"))
                guard token.hasPrefix("http://") || token.hasPrefix("https://") else { return nil }
                return URL(string: token)
            }
            .first
    }

    private static func evidenceValue(after prefixes: [String], in evidence: [String]) -> String? {
        for line in evidence.flatMap({ $0.components(separatedBy: .newlines) }) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let prefix = prefixes.first(where: {
                trimmed.range(of: $0, options: [.anchored, .caseInsensitive]) != nil
            }) {
                let value = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private static func normalizedHandle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
    }

    private static func summary(for candidate: PlaceReviewCandidate) -> String? {
        let preferredPrefixes = [
            "Caption:", "Post caption:", "Caption snippet:", "Source text:", "Source title:"
        ]
        return evidenceValue(after: preferredPrefixes, in: candidate.evidence).map(limited)
    }

    private static func limited(_ value: String) -> String {
        guard value.count > 150 else { return value }
        return "\(value.prefix(147))…"
    }
}

private struct ReviewCandidateContextHero: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let candidate: PlaceReviewCandidate
    let captureTripName: String?
    let eyebrow: String
    let title: String
    let contextLine: String
    var onOpenOnMap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let captureTripName = normalizedCaptureTripName {
                Text(languageSettings.localized(
                    english: "Collecting for \(captureTripName)",
                    traditionalChinese: "為「\(captureTripName)」收集"
                ))
                .font(SaveAtlasType.strong(10))
                .tracking(0.45)
                .foregroundStyle(SaveAtlasPalette.forest)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(SaveAtlasPalette.kraft.opacity(0.58), in: Capsule())
            }

            Text(eyebrow)
                .font(SaveAtlasType.strong(10))
                .tracking(0.55)
                .foregroundStyle(SaveAtlasPalette.muted)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

            Text(title)
                .font(SaveAtlasType.strong(20, relativeTo: .headline))
                .foregroundStyle(SaveAtlasPalette.forest)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

            Text(contextLine)
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

            sourceReceiptCanvas

            if let onOpenOnMap, coordinate != nil {
                Button(action: onOpenOnMap) {
                    Text(languageSettings.localized(
                        english: "Open on the map",
                        traditionalChinese: "在地圖上打開"
                    ))
                    .font(SaveAtlasType.strong(12))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(SaveAtlasPalette.paper)
                    .overlay {
                        Rectangle()
                            .stroke(SaveAtlasPalette.line.opacity(0.42), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("drawer.review.heroMap")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SaveAtlasPalette.paper)
        .overlay {
            Rectangle()
                .stroke(SaveAtlasPalette.line.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer.review.contextHero")
        .accessibilityLabel(accessibilityLabel)
    }

    private var sourceReceiptCanvas: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(sourcePlatformLabel, systemImage: sourcePlatformSymbol)
                .font(SaveAtlasType.strong(11))
                .foregroundStyle(SaveAtlasPalette.forest)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(SaveAtlasPalette.sky.opacity(0.62), in: Capsule())

            if let handle = sourceReceipt.handle {
                Text(languageSettings.localized(
                    english: "Source account \(handle)",
                    traditionalChinese: "來源帳號 \(handle)"
                ))
                .font(SaveAtlasType.strong(15, relativeTo: .headline))
                .foregroundStyle(SaveAtlasPalette.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            } else if let domain = sourceReceipt.domain {
                Text(domain)
                    .font(SaveAtlasType.strong(15, relativeTo: .headline))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            }

            Text(sourceReceipt.summary ?? languageSettings.localized(
                english: "Source preserved. Add an address, map link, or clearer caption to identify the exact place.",
                traditionalChinese: "來源已保留。補上地址、地圖連結或更清楚的貼文說明，才能找到精確地點。"
            ))
            .font(SaveAtlasType.body(12))
            .foregroundStyle(SaveAtlasPalette.muted)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(SaveAtlasPalette.canvas.opacity(0.72))
        .overlay {
            Rectangle()
                .stroke(SaveAtlasPalette.line.opacity(0.22), lineWidth: 1)
        }
    }

    private var sourceReceipt: ReviewSourceReceiptPresentation {
        ReviewSourceReceiptPresentation(candidate: candidate)
    }

    private var sourcePlatformLabel: String {
        switch sourceReceipt.sourcePlatform {
        case .instagram:
            return "Instagram"
        case .threads:
            return "Threads"
        case .xiaohongshu:
            return languageSettings.localized(english: "Xiaohongshu", traditionalChinese: "小紅書")
        case .douyin:
            return languageSettings.localized(english: "Douyin", traditionalChinese: "抖音")
        case .dianping:
            return languageSettings.localized(english: "Dianping", traditionalChinese: "大眾點評")
        case .meituan:
            return languageSettings.localized(english: "Meituan", traditionalChinese: "美團")
        case .taobaoInstantCommerce:
            return languageSettings.localized(english: "Taobao Instant Commerce", traditionalChinese: "淘寶閃購")
        case .googleMaps:
            return "Google Maps"
        case .appleMaps:
            return languageSettings.localized(english: "Apple Maps", traditionalChinese: "Apple 地圖")
        case .amap:
            return languageSettings.localized(english: "Amap", traditionalChinese: "高德地圖")
        case .baidu:
            return languageSettings.localized(english: "Baidu Maps", traditionalChinese: "百度地圖")
        case .other:
            return languageSettings.localized(english: "Web source", traditionalChinese: "網頁來源")
        }
    }

    private var sourcePlatformSymbol: String {
        switch sourceReceipt.sourcePlatform {
        case .instagram: return "camera.fill"
        case .threads: return "text.bubble.fill"
        case .xiaohongshu: return "book.closed.fill"
        case .douyin: return "music.note"
        case .dianping, .meituan, .taobaoInstantCommerce: return "fork.knife"
        case .googleMaps, .appleMaps, .amap, .baidu: return "map.fill"
        case .other: return "link"
        }
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard candidate.hasReliableCoordinates,
              let latitude = candidate.latitude,
              let longitude = candidate.longitude,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var normalizedCaptureTripName: String? {
        guard let captureTripName else { return nil }
        let trimmed = captureTripName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var accessibilityLabel: String {
        var parts = [eyebrow, title, contextLine, sourcePlatformLabel]
        if let handle = sourceReceipt.handle {
            parts.append(handle)
        } else if let domain = sourceReceipt.domain {
            parts.append(domain)
        }
        if let summary = sourceReceipt.summary {
            parts.append(summary)
        }
        if let normalizedCaptureTripName {
            parts.append(languageSettings.localized(
                english: "Collecting for trip \(normalizedCaptureTripName)",
                traditionalChinese: "正在為行程「\(normalizedCaptureTripName)」收集"
            ))
        }
        return parts.joined(separator: ", ")
    }
}

private struct ReviewCandidateNextStepPanel: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.openURL) private var openURL
    var candidate: PlaceReviewCandidate

    var body: some View {
        PostcardReceiptSection(
            title: languageSettings.localized(english: "Next step", traditionalChinese: "下一步"),
            systemImage: candidate.hasReliableCoordinates || candidate.hasProviderMap ? "checkmark.seal.fill" : "sparkle.magnifyingglass",
            tint: candidate.hasReliableCoordinates || candidate.hasProviderMap ? SaveAtlasPalette.sky : SaveAtlasPalette.coral
        ) {
            Text(nextStepText)
                .font(SaveAtlasType.strong(13))
                .foregroundStyle(SaveAtlasPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(summaryText)
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let actionURL {
                Button {
                    openURL(actionURL)
                } label: {
                    Label(actionTitle, systemImage: candidate.hasProviderMap ? "map.fill" : "link")
                        .font(SaveAtlasType.strong(11))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(SaveAtlasPalette.sky.opacity(0.52))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(SaveAtlasPalette.forest.opacity(0.32), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageSettings.localized(english: "Open review candidate source", traditionalChinese: "打開待確認地點來源"))
            }
        }
    }

    private var nextStepText: String {
        if candidate.hasReliableCoordinates {
            return languageSettings.localized(
                english: "Check the name/address. If it is correct, tap Save Map Stamp.",
                traditionalChinese: "確認名稱和地址正確後，點「存成地圖章」。"
            )
        }
        if candidate.hasProviderMap {
            return languageSettings.localized(
                english: "Open the exact Amap place to verify it, then confirm to save this Map Stamp.",
                traditionalChinese: "先開啟精確的高德地點確認，正確後即可確認並保存這個地圖章。"
            )
        }
        return languageSettings.localized(
            english: "Tap Find exact place. If no match appears, add one more clue.",
            traditionalChinese: "先點「找精確地點」。找不到時，再補一個線索。"
        )
    }

    private var summaryText: String {
        if candidate.hasReliableCoordinates {
            let address = candidate.address.trimmingCharacters(in: .whitespacesAndNewlines)
            if !address.isEmpty {
                return languageSettings.localized(
                    english: "Savvy found \(candidate.name) at \(address).",
                    traditionalChinese: "Savvy 找到「\(candidate.name)」：\(address)。"
                )
            }
            return languageSettings.localized(
                english: "Savvy found a likely map match for \(candidate.name).",
                traditionalChinese: "Savvy 找到「\(candidate.name)」的可能地圖結果。"
            )
        }
        if candidate.hasProviderMap {
            return languageSettings.localized(
                english: "The exact Amap location is ready to save without being mislabeled as an Apple Map pin.",
                traditionalChinese: "精確高德位置已可保存；Savvy 不會把它錯標成 Apple 地圖座標。"
            )
        }

        let missing = candidate.missingInfo
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: "、")
        if !missing.isEmpty {
            return languageSettings.localized(
                english: "Still missing: \(missing).",
                traditionalChinese: "還缺：\(missing)。"
            )
        }
        return languageSettings.localized(
            english: "Savvy saved the source clue, but still needs an exact place before saving.",
            traditionalChinese: "Savvy 已保存來源線索，但保存前仍需要精確地點。"
        )
    }

    private var sourceURL: URL? {
        candidate.evidence.compactMap(Self.firstURL(in:)).first
    }

    private var actionURL: URL? {
        candidate.providerMapURL ?? sourceURL
    }

    private var actionTitle: String {
        if candidate.hasProviderMap {
            return languageSettings.localized(english: "Open in Amap", traditionalChinese: "用高德地圖開啟")
        }
        return languageSettings.localized(english: "Open source", traditionalChinese: "打開來源")
    }

    private static func firstURL(in line: String) -> URL? {
        line
            .split(whereSeparator: \.isWhitespace)
            .compactMap { rawToken -> URL? in
                let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]{}.,;\"'"))
                if token.hasPrefix("http://") || token.hasPrefix("https://") {
                    return URL(string: token)
                }
                return nil
            }
            .first
    }
}

private struct UnsavedMapCandidateCard: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    var candidate: SaveMapCandidate
    var isWorking: Bool
    var onSave: (SaveMapCandidate) -> Void
    @State private var enrichedCandidate: SaveMapCandidate?
    @State private var isEnrichingPhoto = false

    /// The candidate this card renders: prefers the freshly enriched Google
    /// Places details (photos, rating, hours, address), otherwise whatever the
    /// tap carried. Enrichment happens here because the map's selection-bound
    /// enrichment dies the moment the detail surface clears the selection.
    private var displayCandidate: SaveMapCandidate {
        if let enrichedCandidate, enrichedCandidate.id == candidate.id {
            return enrichedCandidate
        }
        return candidate
    }

    private var displayPhotoURLStrings: [String] {
        displayCandidate.businessPhotoURLStrings
    }

    var body: some View {
        PostcardDetailPaper(
            tint: SaveAtlasPalette.lavender,
            accessibilityIdentifier: "drawer.unsaved.postcardBody"
        ) {
            HStack(alignment: .top, spacing: 8) {
                UnsavedCandidateFact(title: languageSettings.localized(english: "Rating", traditionalChinese: "評分"), value: ratingText)
                UnsavedCandidateFact(title: languageSettings.localized(english: "Reviews", traditionalChinese: "評論"), value: reviewText ?? "—")
                UnsavedCandidateFact(
                    title: languageSettings.localized(english: "Distance", traditionalChinese: "距離"),
                    value: displayCandidate.distanceLabel ?? languageSettings.localized(english: "On map", traditionalChinese: "在地圖上"),
                    valueColor: displayCandidate.distanceLabel == nil ? .saveCocoa.opacity(0.68) : .saveInk
                )
            }
            .padding(.vertical, 2)

            PlaceBusinessPhotoCarousel(
                imageURLs: displayPhotoURLStrings,
                isSearching: isEnrichingPhoto
            )

            PostcardReceiptSection(
                title: languageSettings.localized(english: "Place receipt", traditionalChinese: "地點憑證"),
                systemImage: "info.circle.fill",
                tint: SaveAtlasPalette.lavender
            ) {
                VStack(spacing: 8) {
                    UnsavedCandidateInfoRow(title: languageSettings.localized(english: "Rating", traditionalChinese: "評分"), value: ratingText)
                    if let reviewText {
                        UnsavedCandidateInfoRow(
                            title: languageSettings.localized(english: "Reviews", traditionalChinese: "評論"),
                            value: languageSettings.localized(english: "\(reviewText) reviews", traditionalChinese: "\(reviewText) 則評論")
                        )
                    }
                    if let hoursText {
                        UnsavedCandidateInfoRow(title: languageSettings.localized(english: "Hours", traditionalChinese: "營業時間"), value: hoursText)
                    }
                    if let distanceLabel = displayCandidate.distanceLabel {
                        UnsavedCandidateInfoRow(title: languageSettings.localized(english: "Distance", traditionalChinese: "距離"), value: distanceLabel)
                    }
                    UnsavedCandidateInfoRow(title: languageSettings.localized(english: "Category", traditionalChinese: "類別"), value: categoryText)
                    UnsavedCandidateInfoRow(title: languageSettings.localized(english: "Address", traditionalChinese: "地址"), value: displayCandidate.subtitle)
                    UnsavedCandidateInfoRow(title: languageSettings.localized(english: "State", traditionalChinese: "狀態"), value: unsavedStateText)
                    UnsavedCandidateInfoRow(title: languageSettings.localized(english: "Source", traditionalChinese: "來源"), value: sourceSummary)
                }
            }

            PostcardReceiptSection(
                title: languageSettings.localized(english: "Quick take", traditionalChinese: "快速判斷"),
                systemImage: "text.alignleft",
                tint: SaveAtlasPalette.lavender
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    UnsavedCandidateQuickLine(text: quickTakeSummary)
                    if let ratingSummary {
                        UnsavedCandidateQuickLine(text: ratingSummary)
                    }
                }
            }

            HStack(spacing: 8) {
                CandidateActionButton(
                    title: isWorking
                        ? languageSettings.localized(english: "Saving", traditionalChinese: "保存中")
                        : SaveSearchPrimaryAction.savePlace.displayName(language: languageSettings.language),
                    systemImage: presentation.primaryActionSystemImage,
                    fill: SaveAtlasPalette.coral,
                    foreground: .white,
                    disabled: isWorking,
                    action: { onSave(displayCandidate) }
                )
                .accessibilityIdentifier("drawer.unsaved.primaryAction")

                if let sourceURL = candidate.sourceURL, let url = URL(string: sourceURL) {
                    Link(destination: url) {
                        CandidateActionLabel(
                            title: languageSettings.localized(english: "Maps", traditionalChinese: "地圖"),
                            systemImage: "map",
                            fill: SaveAtlasPalette.paper
                        )
                    }
                }
            }
        }
        .opacity(isWorking ? 0.65 : 1)
        .task(id: candidate.id) {
            await enrichCandidatePhotos()
        }
    }

    /// Fire-and-forget full enrichment (photos, rating, hours, address) so
    /// unsaved candidates show business details everywhere. Never blocks the
    /// card; the carousel shows its "Finding business photo" placeholder until
    /// details arrive, and stays graceful on failure (we simply keep whatever
    /// the candidate already had).
    private func enrichCandidatePhotos() async {
        // Clear any details carried over from a previously reused card so
        // candidate B never keeps showing candidate A's enriched details.
        enrichedCandidate = nil
        isEnrichingPhoto = true
        defer { isEnrichingPhoto = false }
        guard let updated = await PlaceBusinessEnricher.enrichedCandidate(candidate) else { return }
        // The .task is cancelled when candidate.id changes, so this guards against
        // writing a stale result after the card was reused.
        guard !Task.isCancelled else { return }
        enrichedCandidate = updated
    }

    private var ratingText: String {
        guard let rating = displayCandidate.rating else { return "—" }
        return String(format: "%.1f", rating)
    }

    private var reviewText: String? {
        displayCandidate.reviewCount.map {
            NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal)
        }
    }

    private var hoursText: String? {
        displayCandidate.evidence.compactMap { evidence -> String? in
            guard let range = evidence.range(of: "Hours:", options: [.caseInsensitive]) else { return nil }
            let value = evidence[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }.first
    }

    private var quickTakeSummary: String {
        var parts = [
            categoryText,
            languageSettings.localized(english: "unsaved map result", traditionalChinese: "未保存的地圖結果")
        ]
        if let distanceLabel = displayCandidate.distanceLabel {
            parts.append(distanceLabel)
        }
        return parts.joined(separator: " · ")
    }

    private var ratingSummary: String? {
        guard ratingText != "—" || reviewText != nil else { return nil }
        var parts: [String] = []
        if ratingText != "—" {
            parts.append(languageSettings.localized(english: "Rating \(ratingText)", traditionalChinese: "評分 \(ratingText)"))
        }
        if let reviewText {
            parts.append(languageSettings.localized(english: "\(reviewText) reviews", traditionalChinese: "\(reviewText) 則評論"))
        }
        return parts.joined(separator: " · ")
    }

    private var sourceSummary: String {
        if candidate.evidence.contains(where: { $0.localizedCaseInsensitiveCompare("Apple Maps POI") == .orderedSame }) {
            return languageSettings.localized(english: "Selected from Apple Maps · Map search", traditionalChinese: "從 Apple 地圖選取 · 地圖搜尋")
        }
        if let searchQuery = displayCandidate.evidence.compactMap({ line -> String? in
            guard let range = line.range(of: "Search:", options: [.caseInsensitive]) else {
                return nil
            }
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }).first {
            return languageSettings.localized(english: "Map search · \(searchQuery)", traditionalChinese: "地圖搜尋 · \(searchQuery)")
        }
        return languageSettings.localized(english: "Map search", traditionalChinese: "地圖搜尋")
    }

    private var presentation: SavePlaceDrawerPresentation {
        SavePlaceDrawerPresentation(mapCandidate: candidate)
    }

    private var categoryText: String {
        displayCandidate.category?.displayName(language: languageSettings.language) ?? languageSettings.localized(english: "Place", traditionalChinese: "地點")
    }

    private var unsavedStateText: String {
        languageSettings.localized(english: "Public discovery · Not saved yet", traditionalChinese: "公開探索 · 尚未保存")
    }
}

private struct UnsavedCandidateInfoRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundColor(.saveCocoa.opacity(0.72))
                .frame(width: 58, alignment: .leading)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct UnsavedCandidateQuickLine: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.saveCocoa.opacity(0.64))
                .frame(width: 4, height: 4)
                .padding(.top, 7)

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct UnsavedCandidateFact: View {
    var title: String
    var value: String
    var valueColor: Color = .saveInk

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.saveCocoa.opacity(0.70))
                .lineLimit(1)

            Text(value)
                .font(.caption.weight(.bold))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension PlaceCategory {
    var outlineIconName: String {
        switch self {
        case .food: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .bar: return "wineglass"
        case .attraction: return "star"
        case .stay: return "bed.double"
        case .shopping: return "bag"
        }
    }
}

private struct StampChip: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.24))
            .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
            .clipShape(Capsule())
    }
}

private struct CandidateActionButton: View {
    var title: String
    var systemImage: String
    var fill: Color = SaveAtlasPalette.paper
    var foreground: Color = .saveInk
    var disabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            CandidateActionLabel(
                title: title,
                systemImage: systemImage,
                fill: fill,
                foreground: foreground
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct CandidateActionLabel: View {
    var title: String
    var systemImage: String
    var fill: Color = SaveAtlasPalette.paper
    var foreground: Color = .saveInk

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundColor(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(SaveAtlasPalette.line, lineWidth: 1.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PassportDrawerButton: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    var fill: Color
    var stroke: Color
    var foreground: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundColor(foreground)
                .frame(width: 30, height: 30)
                .background(fill)
                .overlay(Circle().stroke(stroke, lineWidth: 1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(languageSettings.localized(english: "Open Savvy Passport", traditionalChinese: "打開 Savvy 護照"))
        .accessibilityIdentifier("drawer.profile")
    }
}

private struct DrawerSuggestionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    var icon: String
    var text: String

    var body: some View {
        // Spec P2: Atlas paper surface replaces the flat translucent-white
        // material row.
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundColor(SaveAtlasPalette.forest)
                .frame(width: 28, height: 28)
                .background(SaveAtlasPalette.canvas)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(SaveAtlasPalette.line.opacity(0.42), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(text)
                .font(SaveAtlasType.body(15))
                .fontWeight(.semibold)
                .foregroundColor(SaveAtlasPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.bold))
                .foregroundColor(SaveAtlasPalette.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            SaveAtlasPalette.paper,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AIResultActionBar: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    var onFollowUp: () -> Void
    var onNewQuestion: () -> Void

    var body: some View {
        // Spec P2: postage-coral primary + paper secondary replace the
        // honey/cream notebook pair.
        HStack(spacing: 9) {
            Button(action: onFollowUp) {
                Label(languageSettings.localized(english: "Follow up", traditionalChinese: "追問"), systemImage: "text.bubble")
                    .font(SaveAtlasType.strong(13))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SaveAtlasPalette.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onNewQuestion) {
                Label(languageSettings.localized(english: "New", traditionalChinese: "新的"), systemImage: "plus.bubble")
                    .font(SaveAtlasType.strong(13))
                    .foregroundColor(SaveAtlasPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SaveAtlasPalette.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(SaveAtlasPalette.line.opacity(0.5), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(SaveAtlasPalette.canvas.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private enum AgentCommandTone {
    case signal, honey, sky, cocoa

    var color: Color {
        switch self {
        case .signal: return SaveAtlasPalette.coral
        case .honey: return SaveAtlasPalette.kraft
        case .sky: return SaveAtlasPalette.canvas
        case .cocoa: return SaveAtlasPalette.canvas
        }
    }

    var textColor: Color {
        switch self {
        case .signal: return SaveAtlasPalette.coral
        case .honey: return .saveInk
        case .sky: return .saveInk
        case .cocoa: return .saveInk
        }
    }

    var chipFill: Color {
        switch self {
        case .signal: return SaveAtlasPalette.coral.opacity(0.16)
        case .honey: return SaveAtlasPalette.kraft.opacity(0.58)
        case .sky: return SaveAtlasPalette.canvas
        case .cocoa: return SaveAtlasPalette.canvas
        }
    }
}

private struct AgentCommandRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let subtitle: String
    let commandLabel: String
    let tone: AgentCommandTone
    var isPrimary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: isPrimary ? 19 : 16, weight: .black))
                    .foregroundColor(.saveInk)
                    .frame(width: 40, height: 40)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(tone.color.opacity(isPrimary ? 0.34 : 0.20))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(SaveAtlasPalette.line.opacity(isPrimary ? 0.40 : 0.26), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(isPrimary ? .headline : .subheadline)
                        .fontWeight(.black)
                        .foregroundColor(.saveInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.saveInk.opacity(0.82))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.saveInk)
                        .padding(5)
                        .background(tone.chipFill)
                        .overlay(Circle().stroke(SaveAtlasPalette.line, lineWidth: 1))
                        .clipShape(Circle())
                    Text(commandLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundColor(tone.textColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(tone.chipFill)
                        .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                        .clipShape(Capsule())
                }
                .frame(maxWidth: 82, alignment: .trailing)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isPrimary ? .regularMaterial : .ultraThinMaterial)
                    .overlay(commandSurfaceTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SaveAtlasPalette.line.opacity(isPrimary ? 0.38 : 0.22), lineWidth: 1.1)
            )
            .overlay(alignment: .leading) {
                VStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(tone.color.opacity(0.35))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(width: 18)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private var commandSurfaceTint: Color {
        if isPrimary {
            return tone.color.opacity(colorScheme == .dark ? 0.30 : 0.36)
        }
        return colorScheme == .dark ? SaveAtlasPalette.paper.opacity(0.32) : Color.white.opacity(0.16)
    }
}

private struct AgentCommandCard: View {
    @Environment(\.colorScheme) private var colorScheme
    typealias Tone = AgentCommandTone

    let icon: String
    let title: String
    let subtitle: String
    let commandLabel: String
    let tone: AgentCommandTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.saveInk)
                        .frame(width: 34, height: 34)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.thinMaterial)
                                .overlay(tone.color.opacity(0.20))
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(SaveAtlasPalette.line.opacity(0.26), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(tone.color)
                        .padding(6)
                        .background(tone.color.opacity(0.24))
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.black)
                        .foregroundColor(.saveInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.saveInk.opacity(0.82))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(commandLabel.uppercased())
                    .font(.caption2)
                    .fontWeight(.black)
                    .foregroundColor(tone.textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tone.chipFill)
                    .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                    .clipShape(Capsule())

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 134, alignment: .topLeading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(commandSurfaceTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SaveAtlasPalette.line.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private var commandSurfaceTint: Color {
        colorScheme == .dark ? SaveAtlasPalette.paper.opacity(0.30) : Color.white.opacity(0.16)
    }
}
