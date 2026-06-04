import SwiftUI
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

private enum CommandDrawerTab: String, CaseIterable, Hashable {
    case saved
    case review
    case lists
    case friends

    static let publicTestCases: [CommandDrawerTab] = [.saved, .review]

    var title: String {
        switch self {
        case .saved: return "Stamps"
        case .review: return "Review"
        case .lists: return "Lists"
        case .friends: return "Friends"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .saved:
            return language.localized(english: "Stamps", traditionalChinese: "地圖章")
        case .review:
            return language.localized(english: "Review", traditionalChinese: "確認")
        case .lists:
            return language.localized(english: "Lists", traditionalChinese: "清單")
        case .friends:
            return language.localized(english: "Friends", traditionalChinese: "朋友")
        }
    }

    var systemImage: String {
        switch self {
        case .saved: return "list.bullet.rectangle"
        case .review: return "checklist.unchecked"
        case .lists: return "person.2.wave.2.fill"
        case .friends: return "person.2.fill"
        }
    }
}

struct AIDrawerView: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: AIDrawerViewModel
    @Binding var drawerDetent: PresentationDetent
    @Binding var mapDetailDrawerItem: MapDetailDrawerItem?
    var existingPlacesForImport: [Place] = []
    var reviewCandidates: [PlaceReviewCandidate] = []
    var onSaveGoogleTakeoutImport: ([ImportedPlaceDraft]) async throws -> GoogleTakeoutSaveSummary = { _ in
        GoogleTakeoutSaveSummary(saved: 0, skippedDuplicates: 0, reviewDrafts: 0)
    }
    var onDeletePlace: (Place) async throws -> Void = { _ in }
    var onSaveCandidate: (PlaceReviewCandidate, String?) async throws -> Void = { _, _ in }
    var onSaveMapCandidate: (SaveMapCandidate) async throws -> Void = { _ in }
    var onUpdatePlaceVisibility: (Place, PlaceVisibility) async throws -> Void = { _, _ in }
    var onUpdatePlace: (Place) async throws -> Void = { _ in }
    var onImportURLAsReviewCandidates: (URL) async throws -> Int = { _ in 0 }
    var onPrepareMapSearch: (String) async -> [SaveMapCandidate] = { _ in [] }
    var onClearMapSearchResults: () -> Void = {}
    var collaborativeLists: [SaveCollaborativeList] = []
    var onCreateList: (String, String?) -> SaveCollaborativeList = { title, note in
        SaveCollaborativeList(title: title, note: note)
    }
    var onAddPlaceToList: (Place, UUID) throws -> Void = { _, _ in }
    var onShareListURL: (SaveCollaborativeList, SaveListRole) -> URL? = { _, _ in nil }
    var onSaveListItem: (SaveListItem) async throws -> Void = { _ in }
    var onPlanList: (SaveCollaborativeList) async -> Void = { _ in }
    var socialLens: SaveSocialLens = .forYou
    var socialPlaces: [Place] = []
    var onSelectSocialLens: (SaveSocialLens) -> Void = { _ in }
    var onSaveSocialPlace: (Place) async throws -> Void = { _ in }
    var onFollowReferral: (String) async throws -> Void = { _ in }
    var selectedCategories: Set<PlaceCategory> = []
    var onToggleCategory: (PlaceCategory) -> Void = { _ in }
    var onOpenPassport: () -> Void = {}
    var onDismissMapDetail: () -> Void = {}
    @FocusState private var searchFocused: Bool
    @StateObject private var voiceQuery = VoiceQueryController()
    @State private var showGoogleTakeoutImport = false
    @State private var addSpotStatus: String?
    @State private var candidateActionInFlight: UUID?
    @State private var mapCandidateActionInFlight: String?
    @State private var showReviewInbox = false
    @State private var showSavedCategories = false
    @State private var isImportingURL = false
    @State private var showProfile = false
    @State private var showLists = false
    @State private var activeCommandTab: CommandDrawerTab = .saved
    @State private var selectedListID: UUID?
    @State private var newListTitle = ""
    @State private var newListNote = ""
    @State private var followReferralInput = ""
    @State private var isFollowingReferral = false
    @State private var followReferralMessage: String?

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
                    DrawerGlassBackground(colorScheme: colorScheme)
                }
            }
        }
        .sheet(isPresented: $showGoogleTakeoutImport) {
            GoogleTakeoutImportView(
                existingPlaces: existingPlacesForImport,
                onSave: onSaveGoogleTakeoutImport
            )
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(
                savedPlaces: viewModel.places,
                waitingClues: reviewCandidates.count,
                onUpdatePlaceVisibility: { place, visibility in
                    try await onUpdatePlaceVisibility(place, visibility)
                }
            )
        }
        .onChange(of: viewModel.drawerState) { _, state in
            guard mapDetailDrawerItem == nil else { return }
            withAnimation(.spring(duration: 0.3)) {
                switch state {
                case .idle:             drawerDetent = .fraction(0.34)
                case .loading:          drawerDetent = .medium
                case .error:            drawerDetent = .medium
                case .placeDetail:      drawerDetent = .medium
                case .reviewCandidateDetail: drawerDetent = .medium
                case .mapCandidateDetail: drawerDetent = .medium
                case .saveSearchResults: drawerDetent = .medium
                case .displaying(let r):
                    drawerDetent = r.componentType == .tripItinerary ? .large : .medium
                }
            }
        }
        .onChange(of: voiceQuery.transcript) { _, transcript in
            guard voiceQuery.isListening else { return }
            viewModel.query = transcript
        }
        .onChange(of: voiceQuery.state) { _, state in
            switch state {
            case .denied:
                addSpotStatus = "Microphone or speech permission is off. Enable it in Settings to talk to SAV-E."
            case .unavailable:
                addSpotStatus = "Voice input is not available on this device right now."
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
            editableLists: collaborativeLists.filter(\.canEdit),
            isWorkingReviewCandidateID: candidateActionInFlight,
            isWorkingMapCandidateID: mapCandidateActionInFlight,
            onClose: closeMapDetail,
            onDeletePlace: { place in
                try await onDeletePlace(place)
                viewModel.removePlace(place)
                closeMapDetail()
            },
            onPlanAroundPlace: { place in
                closeMapDetail()
                viewModel.query = "What should I order at \(place.name)?"
                Task { await submitDrawerQuery() }
            },
            onAddMoreClueCandidate: { candidate in
                addMoreClue(for: candidate)
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
            onCreateList: createListForPicker,
            onAddPlaceToList: onAddPlaceToList
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: commandBarIcon)
                .foregroundColor(commandBarTextColor)
                .font(.caption.weight(.black))
                .frame(width: 28, height: 28)
                .background(commandIconFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(commandBarStroke, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .symbolEffect(.pulse, isActive: isLoading)

            TextField(languageSettings.text(.askPlaceholder), text: $viewModel.query)
                .font(.subheadline)
                .foregroundColor(commandBarTextColor)
                .lineLimit(1)
                .frame(height: 24)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { submitSearchField() }
                .onTapGesture {
                    withAnimation { drawerDetent = .medium }
                }

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
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
                .opacity(colorScheme == .dark ? 0.50 : 0.32)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.08) : Color.white.opacity(0.06))
                )
                .overlay(commandBarFill)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(commandBarStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 72)
        .background(.clear)
    }

    private var commandBarIcon: String {
        if isLoading { return "hourglass" }
        if voiceQuery.isListening { return "waveform" }
        return "magnifyingglass"
    }

    private var commandBarFill: Color {
        colorScheme == .dark ? Color.black.opacity(0.12) : Color.saveCream.opacity(0.16)
    }

    private var commandIconFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.28)
    }

    private var commandBarStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.saveNotebookLine.opacity(0.18)
    }

    private var commandBarTextColor: Color {
        colorScheme == .dark ? .white : .saveInk
    }

    private var commandBarSecondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.66) : Color.saveCocoa.opacity(0.72)
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
                showSavedCategories = false
                showReviewInbox = false
                showLists = false
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
                    .font(.title3.weight(.black))
                    .foregroundColor(commandBarTextColor)
            }
            .accessibilityLabel(languageSettings.localized(english: "Ask SAV-E", traditionalChinese: "詢問 SAV-E"))
        } else {
            Button(action: toggleVoiceInput) {
                Image(systemName: voiceQuery.buttonIconName)
                    .font(.subheadline.weight(.black))
                    .foregroundColor(commandBarTextColor)
                    .frame(width: 30, height: 30)
                    .background(voiceQuery.isListening ? Color.saveSignal.opacity(0.82) : commandIconFill)
                    .overlay(
                        Circle()
                            .stroke(commandBarStroke, lineWidth: 1)
                    )
                    .clipShape(Circle())
                    .symbolEffect(.pulse, isActive: voiceQuery.isListening)
            }
            .accessibilityLabel(voiceQuery.isListening ? "Stop talking to SAV-E" : "Talk to SAV-E")

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
            VStack(spacing: 12) {
                Spacer()
                ProgressView().tint(.saveInk)
                Text(languageSettings.text(.memoSorting)).font(.subheadline).foregroundColor(.saveCocoa.opacity(0.78))
                Button(action: {
                    viewModel.cancelCurrentRequest()
                    searchFocused = false
                    withAnimation { drawerDetent = .medium }
                }) {
                    Label(languageSettings.text(.cancel), systemImage: "xmark")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.saveNotebookPage.opacity(0.62))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 1.4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)

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
                            messageView("Couldn't find that place in your collection.")
                        }

                    case .tripItinerary:
                        TripItineraryComponent(
                            title: response.title ?? "Your Itinerary",
                            days: response.itineraryDays,
                            aiMessage: response.aiMessage,
                            places: viewModel.places
                        )

                    case .message:
                        messageView(response.messageText ?? response.aiMessage ?? "")
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
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }

        case .saveSearchResults(let response):
            ScrollView {
                VStack(spacing: 16) {
                    SaveSearchResultsComponent(
                        response: response,
                        onSelectResult: { result in
                            openSearchResult(result)
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
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }

        case .placeDetail(let place):
            ScrollView {
                VStack(spacing: 12) {
                    PlaceBottomSheet(place: place) {
                        try await onDeletePlace(place)
                        viewModel.removePlace(place)
                        withAnimation(.spring(duration: 0.3)) {
                            drawerDetent = .height(72)
                        }
                    } onPlanAround: {
                        viewModel.query = "What should I order at \(place.name)?"
                        Task { await submitDrawerQuery() }
                    } onUpdateVisibility: { visibility in
                        try await onUpdatePlaceVisibility(place, visibility)
                    }

                    AddToListPanel(
                        title: "Add this Map Stamp to a list",
                        lists: collaborativeLists.filter(\.canEdit),
                        onCreateList: createListForPicker,
                        onAddToList: { listID in
                            do {
                                try onAddPlaceToList(place, listID)
                                addSpotStatus = "Added \(place.name) to list."
                            } catch {
                                addSpotStatus = error.localizedDescription
                            }
                        }
                    )
                }
                .padding(14)
            }

        case .reviewCandidateDetail(let candidate):
            ScrollView {
                ReviewCandidateDetailCard(
                    candidate: candidate,
                    isWorking: candidateActionInFlight == candidate.id,
                    onFindExactPlace: {
                        findExactPlace(for: candidate)
                    },
                    onAddMoreClue: {
                        addMoreClue(for: candidate)
                    },
                    onSave: { nameOverride in
                        performCandidateAction(candidate, successMessage: saveFeedback(for: candidate)) {
                            try await onSaveCandidate(candidate, nameOverride)
                            viewModel.returnToCommands()
                            showSavedCategories = false
                            showReviewInbox = false
                            showLists = false
                        }
                    }
                )
                .padding(14)
            }

        case .mapCandidateDetail(let candidate):
            ScrollView {
                VStack(spacing: 12) {
                    UnsavedMapCandidateCard(
                        candidate: candidate,
                        isWorking: mapCandidateActionInFlight == candidate.id,
                        onSave: {
                            performMapCandidateAction(candidate) {
                                try await onSaveMapCandidate(candidate)
                                viewModel.returnToCommands()
                                showSavedCategories = false
                                showReviewInbox = false
                                showLists = false
                            }
                        }
                    )
                }
                .padding(14)
            }

        case .error(let msg):
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "exclamationmark.triangle").foregroundColor(.saveCocoa)
                Text(msg)
                    .font(.caption).foregroundColor(.saveCocoa.opacity(0.74))
                    .multilineTextAlignment(.center).padding(.horizontal)
                HStack(spacing: 12) {
                    Button(languageSettings.text(.back)) {
                        viewModel.returnToCommands()
                        showSavedCategories = false
                        showReviewInbox = false
                        showLists = false
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

    private var navigationHeader: some View {
        HStack(spacing: 10) {
            Button(action: {
                viewModel.returnToCommands()
                showSavedCategories = false
                showReviewInbox = false
                showLists = false
                searchFocused = false
                withAnimation { drawerDetent = .medium }
            }) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .frame(width: 32, height: 32)
                    .background(Color.saveNotebookPage.opacity(0.62))
                    .overlay(
                        Circle()
                            .stroke(Color.saveNotebookLine, lineWidth: 2)
                    )
                    .clipShape(Circle())
            }
            .accessibilityLabel(languageSettings.text(.backToCommands))

            VStack(alignment: .leading, spacing: 2) {
                Text(navigationTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
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
                showSavedCategories = false
                showReviewInbox = false
                showLists = false
                searchFocused = false
                withAnimation { drawerDetent = .height(72) }
            }) {
                SaveIconTile(
                    systemName: "xmark",
                    size: 30,
                    iconSize: 11,
                    fill: Color.saveNotebookPage.opacity(0.72),
                    foreground: Color.saveCocoa.opacity(0.78),
                    strokeOpacity: 0.54,
                    cornerRadius: 9
                )
            }
            .accessibilityLabel(languageSettings.text(.closeDrawerContent))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.24 : 0.26)
                .background(colorScheme == .dark ? Color.black.opacity(0.03) : Color.white.opacity(0.04))
                .overlay(navigationHeaderTint)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.13) : Color.saveNotebookLine.opacity(0.18))
                .frame(height: 1)
        }
    }

    private var navigationHeaderTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.04) : Color.white.opacity(0.03)
    }

    private var showsNavigationHeader: Bool {
        switch viewModel.drawerState {
        case .idle:
            return false
        case .loading, .displaying, .saveSearchResults, .placeDetail, .reviewCandidateDetail, .mapCandidateDetail, .error:
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
            return "SAV-E results"
        case .placeDetail(let place):
            return place.name
        case .reviewCandidateDetail(let candidate):
            return candidate.name
        case .mapCandidateDetail(let candidate):
            return candidate.title
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
        case .placeDetail:
            return languageSettings.text(.placeDetailSubtitle)
        case .reviewCandidateDetail(let candidate):
            return candidate.hasReliableCoordinates ? "Map-ready Review Candidate" : "Needs address confirmation"
        case .mapCandidateDetail:
            return "Visible map place · not saved yet"
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

    private var isLoading: Bool {
        if isImportingURL { return true }
        if case .loading = viewModel.drawerState { return true }
        return false
    }

    private func showsContentArea(for drawerHeight: CGFloat) -> Bool {
        let isCollapsed = drawerHeight <= 96
        if case .idle = viewModel.drawerState, isCollapsed { return false }
        return true
    }

    private var hasActiveDrawerContent: Bool {
        switch viewModel.drawerState {
        case .idle:
            return false
        case .loading, .displaying, .saveSearchResults, .placeDetail, .reviewCandidateDetail, .mapCandidateDetail, .error:
            return true
        }
    }

    private var hasVisibleMapSearchResults: Bool {
        !viewModel.mapCandidates.isEmpty
    }

    // MARK: - Idle suggestions

    private var commandHomeView: some View {
        VStack(spacing: 0) {
            commandTabBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)

            switch activeCommandTab {
            case .saved:
                savedPlacesView
            case .review:
                reviewInboxView
            case .lists:
                collaborativeListsView
            case .friends:
                socialMapTabView
            }
        }
    }

    private var commandTabBar: some View {
        HStack(spacing: 7) {
            ForEach(CommandDrawerTab.publicTestCases, id: \.self) { tab in
                Button {
                    activeCommandTab = tab
                    showSavedCategories = false
                    showReviewInbox = false
                    showLists = false
                    searchFocused = false
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.caption2.weight(.black))
                        Text(tab.title(language: languageSettings.language))
                            .font(.caption.weight(.black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)
                    }
                    .foregroundColor(activeCommandTab == tab ? .saveInk : .saveCocoa.opacity(0.76))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(activeCommandTab == tab ? Color.saveHoney.opacity(0.62) : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.saveNotebookLine.opacity(activeCommandTab == tab ? 0.56 : 0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var socialMapTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                socialSignalSection
                if let addSpotStatus {
                    Text(addSpotStatus)
                        .font(.caption)
                        .foregroundColor(.saveCocoa.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private var suggestionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MemoryFlowCTA(
                    reviewCount: reviewCandidates.count,
                    stampCount: viewModel.places.count,
                    onReview: openReviewInbox,
                    onAsk: askFromSavedMemory
                )
                .padding(.horizontal, 16)

                categoryFilterStrip
                socialSignalSection

                if !viewModel.chatHistory.isEmpty {
                    NotebookBandLabel(languageSettings.localized(english: "Recent", traditionalChinese: "最近"))
                        .padding(.horizontal, 16)

                    ForEach(viewModel.chatHistory.prefix(5)) { entry in
                        Button(action: {
                            viewModel.query = entry.query
                            submitSearchField()
                        }) {
                            DrawerSuggestionRow(icon: "clock.arrow.circlepath", text: entry.query)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }

                NotebookBandLabel(languageSettings.localized(english: "Try asking", traditionalChinese: "試著問"))
                    .padding(.horizontal, 16)

                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: {
                        viewModel.query = suggestion
                        submitSearchField()
                    }) {
                        DrawerSuggestionRow(icon: "arrow.up.left", text: suggestion)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }

                if let addSpotStatus {
                    Text(addSpotStatus)
                        .font(.caption)
                        .foregroundColor(.saveCocoa.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
    }

    private var suggestions: [String] {
        switch languageSettings.language {
        case .english:
            return [
                "Date night from my Map Stamps",
                "Coffee from my saved places first",
                "Plan Tokyo from my Map Stamps",
                "What is nearby from my memory?",
                "Show Review clues",
            ]
        case .traditionalChinese:
            return [
                "用我的地圖章安排約會晚餐",
                "先從我存過的地方找咖啡",
                "用我的地圖章規劃東京",
                "我的記憶裡附近有什麼？",
                "顯示待確認線索",
            ]
        }
    }

    private var categoryFilterStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotebookBandLabel(languageSettings.localized(english: "Filters", traditionalChinese: "篩選"))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(PlaceCategory.allCases, id: \.self) { category in
                        CategoryPill(
                            category: category,
                            isSelected: selectedCategories.contains(category)
                        )
                        .onTapGesture { onToggleCategory(category) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
    }

    private var socialSignalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NotebookBandLabel(languageSettings.localized(english: "Friend signal", traditionalChinese: "朋友訊號"))
                .padding(.horizontal, 16)

            HStack(spacing: 7) {
                ForEach(SaveSocialLens.allCases, id: \.self) { lens in
                    Button {
                        onSelectSocialLens(lens)
                        withAnimation { drawerDetent = .medium }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: lens.systemImage)
                                .font(.caption2.weight(.black))
                            Text(lens.title(language: languageSettings.language))
                                .font(.caption.weight(.black))
                        }
                        .foregroundColor(socialLens == lens ? .saveInk : .saveCocoa.opacity(0.78))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(socialLens == lens ? Color.saveHoney.opacity(0.50) : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.24), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            if socialPlaces.isEmpty {
                followFriendEmptyState
            } else {
                ForEach(socialPlaces.prefix(3)) { place in
                    SocialPlaceRow(place: place) {
                        Task { await saveSocialPlace(place) }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var followFriendEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(socialSignalEmptyMessage)
                .font(.caption)
                .foregroundColor(.saveCocoa.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField(languageSettings.localized(english: "Paste referral code or link", traditionalChinese: "貼上推薦碼或連結"), text: $followReferralInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .frame(minHeight: 38)
                    .background(Color.saveNotebookPage.opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.saveNotebookLine.opacity(0.36), lineWidth: 1)
                    )

                Button {
                    Task { await followFriend() }
                } label: {
                    if isFollowingReferral {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 74, height: 38)
                    } else {
                        Text(languageSettings.localized(english: "Follow", traditionalChinese: "追蹤"))
                            .font(.caption.weight(.black))
                            .frame(width: 74, height: 38)
                    }
                }
                .foregroundColor(.saveInk)
                .background(Color.saveHoney.opacity(canFollowReferral ? 0.78 : 0.28))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(0.44), lineWidth: 1)
                )
                .disabled(!canFollowReferral || isFollowingReferral)
                .buttonStyle(.plain)
            }

            if let followReferralMessage {
                Text(followReferralMessage)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(isFollowReferralSuccessMessage(followReferralMessage) ? .saveSignal : .saveCocoa.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
    }

    private var canFollowReferral: Bool {
        !followReferralInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isFollowReferralSuccessMessage(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("followed") || message.contains("已追蹤")
    }

    private func followFriend() async {
        guard canFollowReferral, !isFollowingReferral else { return }
        isFollowingReferral = true
        followReferralMessage = nil
        defer { isFollowingReferral = false }

        do {
            try await onFollowReferral(followReferralInput)
            followReferralInput = ""
            followReferralMessage = languageSettings.localized(
                english: "Followed. Friends' saved places will appear here when shared.",
                traditionalChinese: "已追蹤。朋友分享已保存地點後，會出現在這裡。"
            )
            onSelectSocialLens(.friends)
            withAnimation { drawerDetent = .medium }
        } catch {
            followReferralMessage = languageSettings.localized(english: "Could not follow that code or link.", traditionalChinese: "無法追蹤這個推薦碼或連結。")
        }
    }

    private var socialSignalEmptyMessage: String {
        switch socialLens {
        case .forYou:
            return languageSettings.localized(
                english: "Friend-shared places will appear here when someone shares real saved spots with you.",
                traditionalChinese: "當朋友分享真實保存的地點給你時，會出現在這裡。"
            )
        case .friends:
            return languageSettings.localized(
                english: "No shared friend places yet. SAV-E only shows places friends chose to share.",
                traditionalChinese: "還沒有朋友分享的地點。SAV-E 只會顯示朋友選擇分享的地點。"
            )
        case .trending:
            return languageSettings.localized(
                english: "Trending stays empty until there is enough real shared place signal for this area and category.",
                traditionalChinese: "這個區域與分類累積足夠真實分享訊號後，熱門地點才會出現。"
            )
        }
    }

    private var savedPlacesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MemoryFlowCTA(
                    reviewCount: reviewCandidates.count,
                    stampCount: viewModel.places.count,
                    onReview: openReviewInbox,
                    onAsk: askFromSavedMemory
                )

                if !savedCategoryCounts.isEmpty {
                    SavedCategoryGrid(
                        categories: savedCategoryCounts,
                        selectedCategories: selectedCategories,
                        onToggle: onToggleCategory,
                        onClear: clearSelectedCategories
                    )
                }

                SavedPlacesSection(
                    places: savedPlacesForDrawer,
                    totalCount: viewModel.places.count,
                    isFiltered: !selectedCategories.isEmpty,
                    onSelect: openSavedPlace
                )

                if let addSpotStatus {
                    Text(addSpotStatus)
                        .font(.caption)
                        .foregroundColor(.saveCocoa.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private func clearSelectedCategories() {
        Array(selectedCategories).forEach { onToggleCategory($0) }
    }

    private var savedCategoryCounts: [(category: PlaceCategory, count: Int)] {
        PlaceCategory.allCases.compactMap { category in
            let count = viewModel.places.filter { $0.category == category }.count
            return count > 0 ? (category, count) : nil
        }
    }

    private var savedPlacesForDrawer: [Place] {
        var places = viewModel.places
        if !selectedCategories.isEmpty {
            places = places.filter { selectedCategories.contains($0.category) }
        }
        return places.sorted { $0.createdAt > $1.createdAt }
    }

    private var reviewInboxView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ReviewCandidatesSection(
                    candidates: reviewCandidates,
                    limit: nil,
                    onSelect: openReviewCandidateDetail
                )

                if let addSpotStatus {
                    Text(addSpotStatus)
                        .font(.caption)
                        .foregroundColor(.saveCocoa.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
    }

    private var collaborativeListsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 9) {
                    NotebookBandLabel(languageSettings.localized(english: "Create list", traditionalChinese: "建立清單"))
                    TextField(languageSettings.localized(english: "Tokyo cafes, OC weekend, NYC food", traditionalChinese: "東京咖啡、OC 週末、紐約美食"), text: $newListTitle)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .foregroundColor(.saveInk)
                        .padding(10)
                        .background(Color.saveNotebookPage.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.saveNotebookLine.opacity(0.5), lineWidth: 1.2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    TextField(languageSettings.localized(english: "Optional note", traditionalChinese: "選填備註"), text: $newListNote)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.saveCocoa)
                        .padding(10)
                        .background(Color.saveNotebookPage.opacity(0.54))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.saveNotebookLine.opacity(0.36), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    Button(action: createCollaborativeList) {
                        Label(languageSettings.localized(english: "Create list", traditionalChinese: "建立清單"), systemImage: "plus")
                            .font(.caption.weight(.black))
                            .foregroundColor(.saveInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.saveHoney.opacity(0.88))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(Color.saveCream.opacity(0.32))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if collaborativeLists.isEmpty {
                    Text(languageSettings.localized(
                        english: "Create a list, then add saved Map Stamps or unsaved map results from their detail cards.",
                        traditionalChinese: "先建立清單，再從地點詳情卡加入已保存地圖章或未保存的地圖結果。"
                    ))
                        .font(.caption)
                        .foregroundColor(.saveCocoa.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(collaborativeLists) { list in
                        CollaborativeListCard(
                            list: list,
                            isSelected: selectedListID == list.id,
                            existingPlaces: viewModel.places,
                            viewerURL: onShareListURL(list, .viewer),
                            editorURL: onShareListURL(list, .editor),
                            onSelect: {
                                selectedListID = selectedListID == list.id ? nil : list.id
                            },
                            onSaveItem: { item in
                                saveListItem(item)
                            },
                            onPlan: {
                                planCollaborativeList(list)
                            }
                        )
                    }
                }

                if let addSpotStatus {
                    Text(addSpotStatus)
                        .font(.caption)
                        .foregroundColor(.saveCocoa.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
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
                addSpotStatus = "Map Stamp saved · +1 \(candidate.category?.displayName.lowercased() ?? "place")"
            } catch {
                addSpotStatus = error.localizedDescription
            }
            mapCandidateActionInFlight = nil
        }
    }

    private func saveSocialPlace(_ place: Place) async {
        do {
            try await onSaveSocialPlace(place)
            addSpotStatus = "Saved \(place.name) to your SAV-E."
            closeMapDetail()
        } catch {
            addSpotStatus = error.localizedDescription
        }
    }

    private func focusAgentPrompt(_ prompt: String) {
        showSavedCategories = false
        showReviewInbox = false
        showLists = false
        viewModel.startNewConversation()
        viewModel.query = singleLinePrompt(prompt)
        withAnimation { drawerDetent = .medium }
        searchFocused = true
    }

    private func singleLinePrompt(_ prompt: String) -> String {
        prompt
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func firstURL(in text: String) -> URL? {
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
        viewModel.returnToCommands()
        activeCommandTab = .review
        searchFocused = false
        withAnimation { drawerDetent = .large }
    }

    private func askFromSavedMemory() {
        focusAgentPrompt("What should I pick from my saved places first?")
    }

    private func openSavedPlace(_ place: Place) {
        prepareMapDetailOpening()
        viewModel.showPlace(place)
        viewModel.returnToCommands()
        mapDetailDrawerItem = .savedPlace(place)
        withAnimation(.spring(duration: 0.28)) {
            drawerDetent = .fraction(0.34)
        }
    }

    private func openReviewCandidateDetail(_ candidate: PlaceReviewCandidate) {
        prepareMapDetailOpening()
        viewModel.showReviewCandidate(candidate)
        viewModel.returnToCommands()
        mapDetailDrawerItem = .reviewCandidate(candidate)
        withAnimation(.spring(duration: 0.28)) {
            drawerDetent = .fraction(0.34)
        }
    }

    private func openMapCandidateDetail(_ candidate: SaveMapCandidate) {
        prepareMapDetailOpening()
        viewModel.showMapCandidate(candidate)
        viewModel.returnToCommands()
        mapDetailDrawerItem = .unsavedCandidate(candidate)
        withAnimation(.spring(duration: 0.28)) {
            drawerDetent = .fraction(0.34)
        }
    }

    private func prepareMapDetailOpening() {
        showSavedCategories = false
        showReviewInbox = false
        showLists = false
        searchFocused = false
    }

    private func reviewCandidate(for result: SaveSearchResult) -> PlaceReviewCandidate? {
        guard result.id.hasPrefix("review-candidate-") else { return nil }
        let rawID = String(result.id.dropFirst("review-candidate-".count))
        guard let id = UUID(uuidString: rawID) else { return nil }
        return reviewCandidates.first { $0.id == id }
    }

    private func openSearchResult(_ result: SaveSearchResult) {
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
        voiceQuery.stop()
        searchFocused = false
        if let url = firstURL(in: viewModel.query) {
            importURLToReviewCandidates(url)
        } else if viewModel.shouldSearchNearbyUnsavedCandidates(for: viewModel.query) {
            searchNearbyUnsavedCandidates(for: viewModel.query)
        } else if viewModel.shouldSearchExactMapCandidates(for: viewModel.query) {
            searchNearbyUnsavedCandidates(for: viewModel.query)
        } else {
            let submittedQuery = viewModel.query
            Task {
                await submitDrawerQuery()
                if viewModel.shouldAutoSearchNearbyUnsavedCandidates() ||
                    viewModel.shouldPrepareNearbyCandidatesAfterAnswer(for: submittedQuery) {
                    searchNearbyUnsavedCandidates(for: submittedQuery)
                }
            }
        }
    }

    private func submitDrawerQuery() async {
        await viewModel.submit(
            reviewCandidates: reviewCandidates,
            outputLanguage: languageSettings.language
        )
    }

    private func searchNearbyUnsavedCandidates(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let isExactSearch = viewModel.shouldSearchExactMapCandidates(for: trimmed)
        let fallbackQuery = viewModel.shouldSearchNearbyUnsavedCandidates(for: trimmed) || isExactSearch
            ? trimmed
            : "search nearby unsaved candidates for \(trimmed)"
        viewModel.query = trimmed
        addSpotStatus = isExactSearch
            ? "Looking for exact map matches. Review the result before saving."
            : "Looking for nearby unsaved candidates. Your SAV-E results stay separate."
        withAnimation { drawerDetent = .medium }

        Task {
            let candidates = await onPrepareMapSearch(fallbackQuery)
            if candidates.isEmpty {
                viewModel.mapCandidates = []
                addSpotStatus = isExactSearch
                    ? "No exact map match found yet. Try adding a city, address, or map link."
                    : "No nearby unsaved candidates found yet. Try a more specific place type or city."
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
        showSavedCategories = false
        showReviewInbox = false
        showLists = false
        searchFocused = false
        viewModel.query = query
        addSpotStatus = "Finding exact place for \(candidate.name). Review the map match before saving."
        withAnimation { drawerDetent = .medium }

        Task {
            let candidates = await onPrepareMapSearch(query)
            if candidates.isEmpty {
                viewModel.mapCandidates = []
                addSpotStatus = "No exact map match found for \(candidate.name). Add a city, address, or map link as another clue."
                viewModel.showReviewCandidate(candidate)
            } else {
                viewModel.mapCandidates = candidates
                addSpotStatus = "Found \(candidates.count) possible map match\(candidates.count == 1 ? "" : "es") for \(candidate.name)."
                await viewModel.submit(reviewCandidates: reviewCandidates)
                withAnimation { drawerDetent = .medium }
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
        showProfile = true
        onOpenPassport()
    }

    private func closeDrawerContent() {
        voiceQuery.stop()
        let shouldClearMapSearch = hasVisibleMapSearchResults
        viewModel.reset()
        if shouldClearMapSearch {
            onClearMapSearchResults()
        }
        showSavedCategories = false
        showReviewInbox = false
        showLists = false
        searchFocused = false
        withAnimation { drawerDetent = .height(72) }
    }

    private func closeMapSearchResults() {
        voiceQuery.stop()
        viewModel.reset()
        onClearMapSearchResults()
        showSavedCategories = false
        showReviewInbox = false
        showLists = false
        searchFocused = false
        addSpotStatus = nil
        withAnimation { drawerDetent = .height(72) }
    }

    private func closeMapDetail() {
        mapDetailDrawerItem = nil
        onDismissMapDetail()
        withAnimation(.spring(duration: 0.28)) {
            drawerDetent = .height(72)
        }
    }

    private func importURLToReviewCandidates(_ url: URL) {
        guard !isImportingURL else { return }
        showSavedCategories = false
        showReviewInbox = false
        showLists = false
        searchFocused = false
        isImportingURL = true
        addSpotStatus = "Checking the link and saving possible places to Review..."
        viewModel.returnToCommands()
        withAnimation { drawerDetent = .medium }

        Task {
            do {
                let count = try await onImportURLAsReviewCandidates(url)
                addSpotStatus = count == 1
                    ? "Saved 1 possible place to Review. Check the receipt, then save it."
                    : "Saved \(count) possible places to Review. Check receipts before saving them."
                openReviewInbox()
            } catch {
                addSpotStatus = error.localizedDescription
                viewModel.showMessage(title: "Couldn’t add review candidate", message: error.localizedDescription)
            }
            isImportingURL = false
        }
    }

    private func saveFeedback(for candidate: PlaceReviewCandidate) -> String {
        let category = PlaceCategory.inferred(from: "\(candidate.name) \(candidate.address)")
        return "Map Stamp saved · +1 \(category.displayName.lowercased()) place"
    }

    private func addMoreClue(for candidate: PlaceReviewCandidate) {
        mapDetailDrawerItem = nil
        viewModel.returnToCommands()
        activeCommandTab = .review
        showSavedCategories = false
        showReviewInbox = true
        showLists = false
        viewModel.query = "Add more clue for \(candidate.name): "
        addSpotStatus = "Paste a caption, address, map link, or visible OCR text. SAV-E will keep it in Review until the exact place is clear."
        searchFocused = true
        withAnimation { drawerDetent = .medium }
    }

    private func createCollaborativeList() {
        let list = onCreateList(newListTitle, newListNote)
        selectedListID = list.id
        newListTitle = ""
        newListNote = ""
        addSpotStatus = "Created \(list.title)."
    }

    private func createListForPicker() -> SaveCollaborativeList {
        let title = newListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Trip ideas"
            : newListTitle
        let list = onCreateList(title, newListNote)
        selectedListID = list.id
        newListTitle = ""
        newListNote = ""
        return list
    }

    private func saveListItem(_ item: SaveListItem) {
        Task {
            do {
                try await onSaveListItem(item)
                addSpotStatus = "Saved \(item.title) to your SAV-E."
            } catch {
                addSpotStatus = error.localizedDescription
            }
        }
    }

    private func planCollaborativeList(_ list: SaveCollaborativeList) {
        Task {
            await onPlanList(list)
            viewModel.showCollaborativeListPlan(list)
            activeCommandTab = .lists
            withAnimation { drawerDetent = .large }
        }
    }
}

private struct DrawerGlassBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(materialOpacity)
            .background(baseTint)
            .overlay {
                LinearGradient(
                    colors: tintStops,
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(topStroke)
                    .frame(height: 1)
            }
            .ignoresSafeArea()
    }

    private var tintStops: [Color] {
        if colorScheme == .dark {
            return [
                Color.black.opacity(0.01),
                Color.black.opacity(0.03)
            ]
        }
        return [
            Color.white.opacity(0.01),
            Color.saveCream.opacity(0.02)
        ]
    }

    private var baseTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.04) : Color.white.opacity(0.03)
    }

    private var materialOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.24
    }

    private var topStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.24)
    }
}

private struct MapDetailDrawerView: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let item: MapDetailDrawerItem
    @Binding var detent: PresentationDetent
    let editableLists: [SaveCollaborativeList]
    let isWorkingReviewCandidateID: UUID?
    let isWorkingMapCandidateID: String?
    let onClose: () -> Void
    let onDeletePlace: (Place) async throws -> Void
    let onPlanAroundPlace: (Place) -> Void
    let onAddMoreClueCandidate: (PlaceReviewCandidate) -> Void
    let onFindExactPlaceCandidate: (PlaceReviewCandidate) -> Void
    let onSaveCandidate: (PlaceReviewCandidate, String?) -> Void
    let onSaveMapCandidate: (SaveMapCandidate) -> Void
    let onSaveSocialPlace: (Place) -> Void
    let onUpdatePlaceVisibility: (Place, PlaceVisibility) async throws -> Void
    let onUpdatePlace: (Place) async throws -> Void
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
                    compactHeader
                    Divider()
                        .opacity(colorScheme == .dark ? 0.18 : 0.24)
                        .padding(.horizontal, 18)
                    expandedContent
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background {
                    MapDetailDrawerBackground(colorScheme: colorScheme)
                }
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var compactHeader: some View {
        HStack(spacing: 12) {
            shareAction
                .frame(width: 44, height: 44)

            VStack(spacing: 4) {
                Text(item.presentation.title)
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                Text(item.presentation.eyebrow)
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveCocoa.opacity(0.76))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Button(action: onClose) {
                SelectedPlaceCapsuleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageSettings.localized(english: "Close place detail", traditionalChinese: "關閉地點詳情"))
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var shareAction: some View {
        SavePlaceShareButton(content: item.shareContent) {
            SelectedPlaceCapsuleIcon(systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel(languageSettings.localized(english: "Share \(item.presentation.title)", traditionalChinese: "分享 \(item.presentation.title)"))
    }

    private func expandDetail() {
        withAnimation(.spring(duration: 0.28)) {
            detent = .fraction(0.38)
        }
    }

    private var expandedContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch item {
                case .savedPlace(let place):
                    SavedMapDetailDrawerContent(
                        place: place,
                        onPlanAroundPlace: { onPlanAroundPlace(place) },
                        onDeletePlace: {
                            try await onDeletePlace(place)
                        },
                        onUpdateVisibility: { visibility in
                            try await onUpdatePlaceVisibility(place, visibility)
                        },
                        onUpdatePlace: { updatedPlace in
                            try await onUpdatePlace(updatedPlace)
                        }
                    )

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
                        isWorking: isWorkingReviewCandidateID == candidate.id,
                        onFindExactPlace: { onFindExactPlaceCandidate(candidate) },
                        onAddMoreClue: { onAddMoreClueCandidate(candidate) },
                        onSave: { nameOverride in onSaveCandidate(candidate, nameOverride) }
                    )

                case .unsavedCandidate(let candidate):
                    UnsavedMapCandidateCard(
                        candidate: candidate,
                        isWorking: isWorkingMapCandidateID == candidate.id,
                        onSave: { onSaveMapCandidate(candidate) }
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
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
    }

}

private struct SelectedPlaceCapsule: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let item: MapDetailDrawerItem
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            shareAction
                .frame(width: 44, height: 44)

            Button(action: onExpand) {
                VStack(spacing: 2) {
                    Text(item.presentation.title)
                        .font(.subheadline.weight(.black))
                        .foregroundColor(.saveInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)

                    Text(item.presentation.eyebrow)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.saveCocoa.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)

                    Text(item.presentation.contextLine)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.saveCocoa.opacity(0.58))
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

            Button(action: onClose) {
                SelectedPlaceCapsuleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageSettings.localized(english: "Close selected place", traditionalChinese: "關閉已選地點"))
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 2)
        .frame(height: 74)
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
}

private struct SelectedPlaceCapsuleIcon: View {
    let systemImage: String
    var fill: Color = Color.saveNotebookPage.opacity(0.72)
    var foreground: Color = .saveInk

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(foreground)
            .frame(width: 38, height: 38)
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(0.44), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension MapDetailDrawerItem {
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
                trustLine: "Social signal, not saved in your SAV-E yet."
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

private struct SocialPlaceRow: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let place: Place
    let onSave: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SaveMemoryBadge(state: .ready, size: 38)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(place.name)
                        .font(.subheadline.weight(.black))
                        .foregroundColor(.saveInk)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(place.category.displayName(language: languageSettings.language))
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveCocoa.opacity(0.74))
                }

                Text(place.address)
                    .font(.caption)
                    .foregroundColor(.saveCocoa.opacity(0.72))
                    .lineLimit(1)

                if let signal = place.socialSignal {
                    Label(signal.displayText, systemImage: signal.kind.pinSystemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.saveCocoa)
                        .lineLimit(1)
                }
            }

            Button(action: onSave) {
                Text(languageSettings.localized(english: "Save", traditionalChinese: "保存"))
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.saveHoney.opacity(0.78))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.32), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageSettings.localized(english: "Save \(place.name) to my SAV-E", traditionalChinese: "保存 \(place.name) 到我的 SAV-E"))
        }
        .padding(12)
        .saveNotebookSurface(cornerRadius: 14, fill: .saveNotebookPage, opacity: 0.62, strokeOpacity: 0.34, lineWidth: 1)
    }
}

private struct MapDetailDrawerBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(materialOpacity)
            .background(baseTint)
            .overlay {
                LinearGradient(
                    colors: tintStops,
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.42))
                    .frame(height: 1)
            }
            .ignoresSafeArea()
    }

    private var tintStops: [Color] {
        if colorScheme == .dark {
            return [
                Color.black.opacity(0.01),
                Color.black.opacity(0.04)
            ]
        }
        return [
            Color.white.opacity(0.01),
            Color.saveCream.opacity(0.02)
        ]
    }

    private var baseTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.04) : Color.white.opacity(0.03)
    }

    private var materialOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.24
    }
}

private struct SavedMapDetailDrawerContent: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let place: Place
    let onPlanAroundPlace: () -> Void
    let onDeletePlace: () async throws -> Void
    let onUpdateVisibility: (PlaceVisibility) async throws -> Void
    let onUpdatePlace: (Place) async throws -> Void
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

    private var detailPlace: Place {
        if let enrichedPlace, enrichedPlace.id == place.id {
            return enrichedPlace
        }
        return place
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaceBusinessPhotoCarousel(imageURLs: detailPlace.businessPhotoURLStrings)

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

            PlaceBasicInfoPanel(place: detailPlace)
            PlaceInsightSummaryPanel(place: detailPlace, fallbackSummary: memorySummary)
            PlaceVisibilityControl(
                visibility: detailPlace.effectiveVisibility,
                onChange: onUpdateVisibility
            )
            if isEditingPlace {
                placeEditor
            }

            HStack(spacing: 8) {
                Button(action: onPlanAroundPlace) {
                    PlaceDetailActionLabel(title: languageSettings.localized(english: "Order?", traditionalChinese: "點餐？"), systemImage: "fork.knife", fill: .saveHoney.opacity(0.78))
                }

                Button {
                    NavigationService.navigate(to: detailPlace.coordinate, name: detailPlace.name)
                } label: {
                    PlaceDetailActionLabel(title: languageSettings.localized(english: "Maps", traditionalChinese: "地圖"), systemImage: "map.fill", fill: Color.saveMint.opacity(0.32))
                }

                if let sourceURL = detailPlace.primarySourceURL {
                    Button {
                        openURL(sourceURL)
                    } label: {
                        PlaceDetailActionLabel(title: languageSettings.localized(english: "Source", traditionalChinese: "來源"), systemImage: "link", fill: Color.saveSky.opacity(0.20))
                    }
                }
            }

            Button(action: beginPlaceEdit) {
                PlaceDetailActionLabel(
                    title: isEditingPlace
                        ? languageSettings.localized(english: "Editing", traditionalChinese: "編輯中")
                        : languageSettings.text(.edit),
                    systemImage: "pencil",
                    fill: Color.saveNotebookPage
                )
            }
            .disabled(isSavingPlaceEdit)

            Menu {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(languageSettings.localized(english: "Delete", traditionalChinese: "刪除"), systemImage: "trash")
                }
            } label: {
                Label(languageSettings.localized(english: "More", traditionalChinese: "更多"), systemImage: "ellipsis.circle")
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveCocoa)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.saveNotebookPage.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.saveNotebookLine.opacity(0.3), lineWidth: 1)
                    )
            }

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
        }
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
            Text(languageSettings.localized(english: "This removes the Map Stamp from SAV-E.", traditionalChinese: "這會從 SAV-E 移除這個地圖章。"))
        }
        .task(id: place.id) {
            await enrichBusinessDetails()
        }
    }

    private var memorySummary: String {
        detailPlace.memorySummary(language: languageSettings.language)
    }

    private func enrichBusinessDetails() async {
        guard detailPlace.businessPhotoURLStrings.count < 2 ||
                detailPlace.googleRating == nil ||
                detailPlace.priceRange == nil ||
                detailPlace.openingHours == nil
        else { return }
        guard let update = await businessDetails(for: detailPlace) else { return }
        guard place.id == detailPlace.id else { return }

        var updatedPlace = detailPlace
        if !update.photoURLs.isEmpty {
            let urls = update.photoURLs.map(\.absoluteString)
            updatedPlace.sourceImageUrl = updatedPlace.sourceImageUrl ?? urls.first
            updatedPlace.businessPhotoUrls = urls
        }
        updatedPlace.googleRating = updatedPlace.googleRating ?? update.rating
        updatedPlace.priceRange = updatedPlace.priceRange ?? update.priceRange
        updatedPlace.openingHours = updatedPlace.openingHours ?? update.openingHours
        enrichedPlace = updatedPlace
    }

    private func businessDetails(for place: Place) async -> (photoURLs: [URL], rating: Double?, priceRange: String?, openingHours: String?)? {
        let service = GooglePlacesService.shared
        let details: GooglePlaceDetails?
        let fallbackMatch: GooglePlaceMatch?
        if let googlePlaceId = place.googlePlaceId {
            details = try? await service.getPlaceDetails(placeId: googlePlaceId)
            fallbackMatch = nil
        } else {
            guard let match = await bestGoogleMatch(for: place, service: service) else { return nil }
            details = try? await service.getPlaceDetails(placeId: match.id)
            fallbackMatch = match
        }

        let photoReferences = details?.photoReferences?.isEmpty == false
            ? details?.photoReferences ?? []
            : [fallbackMatch?.photoReference].compactMap { $0 }
        let photoURLs = photoReferences
            .prefix(6)
            .compactMap { service.photoURL(reference: $0, maxWidth: 900) }
        let priceLevel = details?.priceLevel ?? fallbackMatch?.priceLevel
        let hasDetails = !photoURLs.isEmpty ||
            details?.rating != nil ||
            fallbackMatch?.rating != nil ||
            priceLevel != nil ||
            details?.openingHours?.isEmpty == false
        guard hasDetails else { return nil }

        return (
            photoURLs,
            details?.rating ?? fallbackMatch?.rating,
            priceLevel.map { String(repeating: "$", count: max(1, $0)) },
            details?.openingHours?.first
        )
    }

    private func bestGoogleMatch(for place: Place, service: GooglePlacesServiceProtocol) async -> GooglePlaceMatch? {
        do {
            let matches = try await service.searchPlace(
                query: "\(place.name) \(place.address)",
                near: place.coordinate
            )
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            return matches.first { match in
                let matchLocation = CLLocation(latitude: match.latitude, longitude: match.longitude)
                let sameArea = placeLocation.distance(from: matchLocation) < 250
                let sameName = match.name.localizedCaseInsensitiveContains(place.name) ||
                    place.name.localizedCaseInsensitiveContains(match.name) ||
                    match.name.localizedCaseInsensitiveContains(place.businessLookupName) ||
                    place.businessLookupName.localizedCaseInsensitiveContains(match.name)
                return sameArea || sameName
            }
        } catch {
            return nil
        }
    }

    private var placeEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(languageSettings.localized(english: "Place name", traditionalChinese: "地點名稱"), text: $editName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.saveNotebookPage.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            TextField(languageSettings.localized(english: "Address", traditionalChinese: "地址"), text: $editAddress)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.saveNotebookPage.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 8) {
                Button {
                    isEditingPlace = false
                    editError = nil
                } label: {
                    PlaceDetailActionLabel(title: languageSettings.text(.cancel), systemImage: "xmark", fill: Color.saveNotebookPage)
                }
                .disabled(isSavingPlaceEdit)

                Button {
                    savePlaceEdit()
                } label: {
                    PlaceDetailActionLabel(
                        title: isSavingPlaceEdit ? languageSettings.text(.saving) : languageSettings.text(.save),
                        systemImage: "checkmark",
                        fill: .saveHoney.opacity(0.8)
                    )
                }
                .disabled(isSavingPlaceEdit)
            }
        }
        .padding(10)
        .background(Color.saveNotebookPage.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.35), lineWidth: 1)
        )
    }

    private func beginPlaceEdit() {
        editName = detailPlace.name
        editAddress = detailPlace.address
        editError = nil
        isEditingPlace = true
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

private struct SocialPlaceDetailCard: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let place: Place
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaceBusinessPhotoCarousel(imageURLs: place.businessPhotoURLStrings)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(place.name)
                        .font(.title3.weight(.black))
                        .foregroundColor(.saveInk)
                    Spacer()
                    CategoryPill(category: place.category, isSelected: true)
                }

                Text(place.address)
                    .font(.caption)
                    .foregroundColor(.saveCocoa.opacity(0.76))
            }

            if let signal = place.socialSignal {
                VStack(alignment: .leading, spacing: 6) {
                    Label(signal.displayText, systemImage: signal.kind.pinSystemImage)
                        .font(.subheadline.weight(.black))
                        .foregroundColor(.saveInk)
                    Text(signal.detailText)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.saveCocoa.opacity(0.78))
                }
                .padding(12)
                .background(Color.saveSky.opacity(signal.kind == .trending ? 0.16 : 0.24))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            PlaceBasicInfoPanel(place: place)
            PlaceInsightSummaryPanel(
                place: place,
                fallbackSummary: languageSettings.localized(
                    english: "This is a social map result. Save it to make it part of your own SAV-E memory.",
                    traditionalChinese: "這是社交地圖結果。保存後才會成為你自己的 SAV-E 記憶。"
                )
            )

            Button(action: onSave) {
                Label(languageSettings.localized(english: "Save to my SAV-E", traditionalChinese: "保存到我的 SAV-E"), systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.saveHoney)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.saveNotebookPage.opacity(0.52))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.32), lineWidth: 1)
        )
    }
}

private struct MapDetailChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.black))
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(.saveCocoa)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.saveNotebookPage.opacity(0.38))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.30), lineWidth: 1))
    }
}

private struct AddToListPanel: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let title: String
    let lists: [SaveCollaborativeList]
    let onCreateList: () -> SaveCollaborativeList
    let onAddToList: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: "person.2.wave.2.fill")
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveInk)
                Spacer()
            }

            if lists.isEmpty {
                Button(action: {
                    let list = onCreateList()
                    onAddToList(list.id)
                }) {
                    Label(languageSettings.localized(english: "Create list and add", traditionalChinese: "建立清單並加入"), systemImage: "plus")
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.savePink.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 1.4)
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
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.savePink.opacity(0.72))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 1.4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
        .padding(12)
        .background(Color.saveCream.opacity(0.32))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.26), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CollaborativeListCard: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let list: SaveCollaborativeList
    let isSelected: Bool
    let existingPlaces: [Place]
    let viewerURL: URL?
    let editorURL: URL?
    let onSelect: () -> Void
    let onSaveItem: (SaveListItem) -> Void
    let onPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.title3)
                        .foregroundColor(.saveInk)
                        .frame(width: 32, height: 32)
                        .background(Color.savePink.opacity(0.76))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(list.title)
                            .font(.subheadline.weight(.black))
                            .foregroundColor(.saveInk)
                            .lineLimit(2)
                        Text("\(list.placeCountLabel) · \(list.viewerRole.displayName)")
                            .font(.caption)
                            .foregroundColor(.saveCocoa.opacity(0.72))
                        if let note = list.note, !note.isEmpty {
                            Text(note)
                                .font(.caption2)
                                .foregroundColor(.saveCocoa.opacity(0.68))
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.saveCocoa.opacity(0.64))
                }
            }
            .buttonStyle(.plain)

            if isSelected {
                listActions
                listItems
            }
        }
        .padding(12)
        .background(Color.saveNotebookPage.opacity(0.62))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.32), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var listActions: some View {
        HStack(spacing: 8) {
            Button(action: onPlan) {
                Label(languageSettings.localized(english: "Plan", traditionalChinese: "規劃"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.saveSignal.opacity(0.56))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(list.items.isEmpty)

            if let viewerURL {
                ShareLink(item: viewerURL) {
                    Label(languageSettings.localized(english: "Viewer", traditionalChinese: "檢視者"), systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.saveHoney.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }

            if list.canEdit, let editorURL {
                ShareLink(item: editorURL) {
                    Label(languageSettings.localized(english: "Editor", traditionalChinese: "編輯者"), systemImage: "person.badge.plus")
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.saveMint.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
        }
    }

    private var listItems: some View {
        VStack(spacing: 8) {
            if list.items.isEmpty {
                Text(languageSettings.localized(
                    english: "Open a place or map result, then add it to this list.",
                    traditionalChinese: "打開地點或地圖結果後，就能加入這個清單。"
                ))
                    .font(.caption)
                    .foregroundColor(.saveCocoa.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(list.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        AsyncImage(url: item.photoURLs.first.flatMap(URL.init(string:))) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: item.source == .savedPlace ? "mappin.circle.fill" : "map")
                                .font(.subheadline)
                                .foregroundColor(.saveCocoa)
                        }
                        .frame(width: 42, height: 42)
                        .background(Color.saveCream.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.caption.weight(.bold))
                                .foregroundColor(.saveInk)
                                .lineLimit(2)
                            Text(item.subtitle)
                                .font(.caption2)
                                .foregroundColor(.saveCocoa.opacity(0.72))
                                .lineLimit(2)
                            Text(item.source.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(item.source == .savedPlace ? .saveCocoa : .saveCoral)
                        }

                        Spacer()

                        if item.alreadySaved(in: existingPlaces) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.saveSignal)
                                .accessibilityLabel(languageSettings.localized(english: "Already saved", traditionalChinese: "已保存"))
                        } else {
                            Button(action: { onSaveItem(item) }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.saveInk)
                            }
                            .accessibilityLabel(languageSettings.localized(english: "Save to my SAV-E", traditionalChinese: "保存到我的 SAV-E"))
                        }
                    }
                    .padding(9)
                    .background(Color.saveCream.opacity(0.34))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
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

private struct NotebookSpine: View {
    var color: Color
    var opacity: Double = 0.58

    var body: some View {
        VStack(spacing: 11) {
            ForEach(0..<4, id: \.self) { _ in
                Circle()
                    .fill(Color.saveNotebookPage)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(Color.saveCocoa.opacity(0.16), lineWidth: 1))
            }
            Spacer(minLength: 0)
        }
        .frame(width: 24)
        .padding(.top, 18)
        .background(color.opacity(opacity))
    }
}

private struct NotebookBandLabel: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.black))
                .foregroundColor(.saveInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.saveHoney)
                .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1.2))
                .clipShape(Capsule())
            Rectangle()
                .fill(Color.saveNotebookLine.opacity(0.28))
                .frame(height: 1)
        }
        .padding(.top, 2)
    }
}

private struct SavedPlacesSection: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @Environment(\.colorScheme) private var colorScheme
    var places: [Place]
    var totalCount: Int
    var isFiltered: Bool
    var onSelect: (Place) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            savedHeader

            if places.isEmpty {
                SavedPlacesEmptyState(isFiltered: isFiltered)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sectionedPlaces, id: \.category) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            SavedCategorySectionHeader(category: section.category, count: section.places.count)

                            VStack(spacing: 0) {
                                ForEach(Array(section.places.enumerated()), id: \.element.id) { index, place in
                                    SavedPlaceRow(place: place) {
                                        onSelect(place)
                                    }

                                    if index < section.places.count - 1 {
                                        Divider()
                                            .padding(.leading, 64)
                                    }
                                }
                            }
                            .background {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.regularMaterial)
                                    .overlay(groupTint)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.saveNotebookLine.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private var sectionedPlaces: [(category: PlaceCategory, places: [Place])] {
        PlaceCategory.allCases.compactMap { category in
            let categoryPlaces = places.filter { $0.category == category }
            return categoryPlaces.isEmpty ? nil : (category, categoryPlaces)
        }
    }

    private var savedHeader: some View {
        HStack(spacing: 5) {
            Text(languageSettings.localized(english: "Saved", traditionalChinese: "已保存"))
                .font(.title3.weight(.bold))
                .foregroundColor(.saveInk)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.saveCocoa.opacity(0.55))

            Spacer()

            Text("\(isFiltered ? places.count : totalCount)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundColor(.saveCocoa.opacity(0.78))
        }
        .padding(.horizontal, 2)
    }

    private var groupTint: Color {
        colorScheme == .dark ? Color.saveNotebookPage.opacity(0.58) : Color.white.opacity(0.30)
    }
}

private struct SavedCategorySectionHeader: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    var category: PlaceCategory
    var count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: category.iconName)
                .font(.caption.weight(.black))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(category.poiIconColor)
                .clipShape(Circle())

            Text(category.displayName(language: languageSettings.language))
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)

            Spacer(minLength: 0)

            Text("\(count)")
                .font(.caption2.monospacedDigit().weight(.black))
                .foregroundColor(.saveCocoa.opacity(0.78))
        }
        .padding(.horizontal, 4)
    }
}

private struct SavedPlaceRow: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    var place: Place
    var onSelect: () -> Void

    private var addressText: String {
        let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? languageSettings.localized(english: "Selected on map", traditionalChinese: "從地圖選取") : address
    }

    private var statusText: String {
        place.status == .visited
            ? languageSettings.localized(english: "Tried Map Stamp", traditionalChinese: "去過的地圖章")
            : languageSettings.localized(english: "Saved Map Stamp", traditionalChinese: "已保存地圖章")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: place.category.iconName)
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(place.category.poiIconColor)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.saveInk)
                        .lineLimit(1)

                    Text(addressText)
                        .font(.subheadline)
                        .foregroundColor(.saveMutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "ellipsis")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.saveInk)
                    .frame(width: 34, height: 34)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(place.name), \(statusText)")
        .accessibilityHint(languageSettings.localized(english: "Open Map Stamp details", traditionalChinese: "打開地圖章詳情"))
    }

}

private extension PlaceCategory {
    var poiIconColor: Color {
        switch self {
        case .food: return .saveSignal
        case .cafe: return .saveCocoa
        case .bar: return .savePink
        case .attraction: return .saveHoney
        case .stay: return .saveSky
        case .shopping: return .saveMint
        }
    }
}

private struct SavedPlacesEmptyState: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    var isFiltered: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle" : "mappin.slash")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.saveCocoa)
                .frame(width: 38, height: 38)
                .background(Color.saveHoney.opacity(0.34))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(isFiltered
                     ? languageSettings.localized(english: "No matching Map Stamps", traditionalChinese: "沒有符合條件的地圖章")
                     : languageSettings.localized(english: "No saved Map Stamps", traditionalChinese: "還沒有保存的地圖章"))
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.saveInk)

                Text(isFiltered
                     ? languageSettings.localized(english: "Clear filters to show every saved place.", traditionalChinese: "清除篩選即可顯示所有已保存地點。")
                     : languageSettings.localized(english: "Sign in and refresh SAV-E if this account should already have saved places.", traditionalChinese: "如果這個帳號應該已有保存地點，請登入後重新整理 SAV-E。"))
                    .font(.caption)
                    .foregroundColor(.saveMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.saveNotebookPage.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ReviewCandidatesSection: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @Environment(\.colorScheme) private var colorScheme
    var candidates: [PlaceReviewCandidate]
    var limit: Int? = 4
    var onSelect: (PlaceReviewCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            reviewHeader

            if candidates.isEmpty {
                ReviewCandidatesEmptyState()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedCandidates.enumerated()), id: \.element.id) { index, candidate in
                        ReviewCandidatePlaceRow(candidate: candidate) {
                            onSelect(candidate)
                        }

                        if index < displayedCandidates.count - 1 {
                            Divider()
                                .padding(.leading, 64)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(groupTint)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    private var reviewHeader: some View {
        HStack(spacing: 5) {
            Text(languageSettings.localized(english: "Review", traditionalChinese: "待確認"))
                .font(.title3.weight(.bold))
                .foregroundColor(.saveInk)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.saveCocoa.opacity(0.55))

            Spacer()

            Text("\(candidates.count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundColor(.saveCocoa.opacity(0.78))
        }
        .padding(.horizontal, 2)
    }

    private var groupTint: Color {
        colorScheme == .dark ? Color.saveNotebookPage.opacity(0.58) : Color.white.opacity(0.30)
    }

    private var displayedCandidates: [PlaceReviewCandidate] {
        guard let limit else { return candidates }
        return Array(candidates.prefix(limit))
    }
}

private struct ReviewCandidatePlaceRow: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    var candidate: PlaceReviewCandidate
    var onSelect: () -> Void

    private var addressText: String {
        if !candidate.address.isEmpty { return candidate.address }
        if let city = candidate.city, !city.isEmpty { return city }
        return languageSettings.localized(english: "Needs address confirmation", traditionalChinese: "需要確認地址")
    }

    private var statusText: String {
        candidate.hasReliableCoordinates
            ? languageSettings.localized(english: "Ready to review", traditionalChinese: "可以確認")
            : languageSettings.localized(english: "Needs info", traditionalChinese: "需要更多資訊")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.saveInk)
                        .lineLimit(1)

                    Text(addressText)
                        .font(.subheadline)
                        .foregroundColor(.saveMutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "ellipsis")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.saveInk)
                    .frame(width: 34, height: 34)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.name), \(statusText)")
        .accessibilityHint(languageSettings.localized(english: "Open review details before saving", traditionalChinese: "保存前先打開確認詳情"))
    }

}

private struct ReviewCandidatesEmptyState: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.saveInk)
                .frame(width: 34, height: 34)
                .background(Color.saveSky.opacity(0.54))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(languageSettings.localized(english: "No clues waiting", traditionalChinese: "沒有等待確認的線索"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.saveInk)

                Text(languageSettings.localized(
                    english: "Share a post, screenshot, or map link for SAV-E to investigate. Uncertain places wait here as Review Candidates until you save them as Map Stamps.",
                    traditionalChinese: "分享貼文、截圖或地圖連結給 SAV-E 調查。不確定的地點會先留在待確認，直到你保存成地圖章。"
                ))
                    .font(.caption)
                    .foregroundColor(.saveCocoa.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .saveNotebookPage(cornerRadius: 14)
    }
}

private struct ReviewCandidateDetailCard: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    var candidate: PlaceReviewCandidate
    var isWorking: Bool
    var onFindExactPlace: () -> Void
    var onAddMoreClue: () -> Void
    var onSave: (String?) -> Void
    @State private var displayNameDraft: String

    init(
        candidate: PlaceReviewCandidate,
        isWorking: Bool,
        onFindExactPlace: @escaping () -> Void,
        onAddMoreClue: @escaping () -> Void,
        onSave: @escaping (String?) -> Void
    ) {
        self.candidate = candidate
        self.isWorking = isWorking
        self.onFindExactPlace = onFindExactPlace
        self.onAddMoreClue = onAddMoreClue
        self.onSave = onSave
        _displayNameDraft = State(initialValue: candidate.name)
    }

    var body: some View {
        HStack(spacing: 0) {
            NotebookSpine(color: candidate.hasReliableCoordinates ? .saveSignal : .saveNotebookSpine)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 11) {
                    ReviewCandidateDetailIcon(candidate: candidate)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(presentation.eyebrow)
                            .font(.caption2.weight(.black))
                            .foregroundColor(.saveCocoa)
                            .lineLimit(1)

                        Text(presentation.title)
                            .font(.headline)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)
                            .lineLimit(2)

                        Text(presentation.contextLine)
                            .font(.caption)
                            .foregroundColor(.saveCocoa.opacity(0.74))
                            .lineLimit(2)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(languageSettings.localized(english: "Display name", traditionalChinese: "顯示名稱"))
                                .font(.caption2.weight(.black))
                                .foregroundColor(.saveCocoa.opacity(0.72))
                            TextField(languageSettings.localized(english: "Place name", traditionalChinese: "地點名稱"), text: $displayNameDraft)
                                .textFieldStyle(.plain)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.saveInk)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.saveNotebookPage.opacity(0.72))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(Color.saveNotebookLine.opacity(0.5), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .accessibilityLabel(languageSettings.localized(english: "Review candidate display name", traditionalChinese: "待確認地點顯示名稱"))
                        }

                        HStack(spacing: 6) {
                            if let confidence = candidate.confidence {
                                StampChip(
                                    text: languageSettings.localized(
                                        english: "\(Int(confidence * 100))% confidence",
                                        traditionalChinese: "\(Int(confidence * 100))% 信心"
                                    ),
                                    color: .saveCocoa
                                )
                            }
                            StampChip(
                                text: candidate.hasReliableCoordinates
                                    ? languageSettings.localized(english: "map ready", traditionalChinese: "地圖已就緒")
                                    : languageSettings.localized(english: "needs exact place", traditionalChinese: "需要精確地點"),
                                color: .saveHoney
                            )
                        }
                    }

                    Spacer(minLength: 0)
                }

                Text(presentation.trustLine)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveCocoa.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                ReviewCandidateProofPanel(candidate: candidate)

                HStack(spacing: 8) {
                    CandidateActionButton(
                        title: primaryAction.title,
                        systemImage: primaryAction.systemImage,
                        fill: .saveHoney,
                        disabled: isWorking,
                        action: performPrimaryAction
                    )
                    CandidateActionButton(
                        title: languageSettings.localized(english: "Add more clue", traditionalChinese: "補更多線索"),
                        systemImage: "plus.bubble",
                        fill: .saveNotebookPage,
                        disabled: isWorking,
                        action: onAddMoreClue
                    )
                }
            }
            .padding(12)
        }
        .saveNotebookPage(cornerRadius: 16)
        .opacity(isWorking ? 0.65 : 1)
    }

    private var presentation: SavePlaceDrawerPresentation {
        SavePlaceDrawerPresentation(reviewCandidate: candidate)
    }

    private var primaryAction: SavePlaceActionResolution {
        SavePlaceActionResolution(candidate: candidate)
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

private struct ReviewCandidateDetailIcon: View {
    var candidate: PlaceReviewCandidate

    var body: some View {
        Image(systemName: "mappin.circle.fill")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.red)
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
    }
}

private struct ReviewCandidateProofPanel: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    var candidate: PlaceReviewCandidate
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: candidate.hasReliableCoordinates ? "checkmark.seal.fill" : "doc.text.magnifyingglass")
                    .font(.caption.weight(.black))
                Text(candidate.hasReliableCoordinates
                     ? languageSettings.localized(english: "Ready to review", traditionalChinese: "可以確認")
                     : languageSettings.localized(english: "Needs one more clue", traditionalChinese: "還需要一個線索"))
                    .font(.caption.weight(.black))
                Spacer(minLength: 0)
                if let sourceURL {
                    Button {
                        openURL(sourceURL)
                    } label: {
                        Text(languageSettings.localized(english: "Open source", traditionalChinese: "打開來源"))
                            .font(.caption2.weight(.black))
                            .foregroundColor(.saveInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.saveHoney.opacity(0.72))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(languageSettings.localized(english: "Open review candidate source", traditionalChinese: "打開待確認地點來源"))
                }
            }
            .foregroundColor(.saveInk)

            proofSection(title: languageSettings.localized(english: "Found", traditionalChinese: "找到"), systemImage: "checkmark.circle.fill", items: foundItems, tone: .saveMint)
            proofSection(title: languageSettings.localized(english: "Missing", traditionalChinese: "還缺"), systemImage: "exclamationmark.triangle.fill", items: missingItems, tone: .saveHoney)
            proofSection(title: languageSettings.localized(english: "Tried", traditionalChinese: "查過"), systemImage: "text.magnifyingglass", items: triedItems, tone: .saveSky)
            nextActionRow
        }
        .padding(10)
        .background(Color.saveNotebookPage.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.24), lineWidth: 1)
        )
    }

    private func proofSection(title: String, systemImage: String, items: [String], tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveInk)
                    .frame(width: 18, height: 18)
                    .background(tone.opacity(0.64))
                    .clipShape(Circle())
                Text(title)
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveCocoa.opacity(0.72))
            }

            ForEach(items.prefix(3), id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .foregroundColor(.saveCocoa.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var nextActionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: candidate.hasReliableCoordinates ? "checkmark.seal" : "sparkle.magnifyingglass")
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 22, height: 22)
                .background(Color.savePink.opacity(0.72))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(languageSettings.localized(english: "Next action", traditionalChinese: "下一步"))
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveCocoa.opacity(0.72))
                Text(nextActionText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveCocoa.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var foundItems: [String] {
        var items: [String] = []
        items.append("Candidate: \(candidate.name)")
        if !candidate.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append("Address: \(candidate.address)")
        } else if let city = candidate.city, !city.isEmpty {
            items.append("Area: \(city)")
        }
        if candidate.hasReliableCoordinates {
            items.append("Coordinates verified")
        }
        if let sourceHandle = candidate.sourceHandle, !sourceHandle.isEmpty {
            items.append("Source handle: @\(sourceHandle)")
        }
        if items.count < 3 {
            items.append(contentsOf: cleanEvidenceLines(excluding: ["missing", "checked", "prepared", "next best clue"]))
        }
        return Array(unique(items).prefix(3))
    }

    private var missingItems: [String] {
        var items = candidate.missingInfo
            .map(cleanEvidenceLine)
            .filter { !$0.isEmpty }
        if !candidate.hasReliableCoordinates {
            if candidate.address.isEmpty { items.append("Exact address") }
            items.append("Verified coordinates")
        }
        if items.isEmpty {
            items.append(contentsOf: cleanEvidenceLines(including: ["required proof"]))
        }
        if items.isEmpty {
            items.append("Nothing obvious; check the place before confirming")
        }
        return Array(unique(items).prefix(3))
    }

    private var triedItems: [String] {
        let tried = cleanEvidenceLines(including: ["checked", "prepared", "google places", "public search", "ocr", "metadata", "caption", "recovery decision", "rejected evidence", "rejected clue type"])
        if !tried.isEmpty { return Array(tried.prefix(3)) }
        if sourceURL != nil { return ["Checked shared source"] }
        return ["Saved source evidence for review"]
    }

    private var nextActionText: String {
        if candidate.hasReliableCoordinates {
            return "Confirm Map Stamp after checking the name and address."
        }
        return "Find exact place, or add more clue if SAV-E still needs address or coordinates."
    }

    private var sourceURL: URL? {
        candidate.evidence.compactMap(Self.firstURL(in:)).first
    }

    private func cleanEvidenceLines(including keywords: [String]) -> [String] {
        cleanEvidenceLines { line in
            let lowered = line.lowercased()
            return keywords.contains { lowered.contains($0) }
        }
    }

    private func cleanEvidenceLines(excluding keywords: [String]) -> [String] {
        cleanEvidenceLines { line in
            let lowered = line.lowercased()
            return !keywords.contains { lowered.contains($0) }
        }
    }

    private func cleanEvidenceLines(where predicate: (String) -> Bool) -> [String] {
        candidate.evidence
            .map(cleanEvidenceLine)
            .filter { !$0.isEmpty && predicate($0) }
    }

    private func cleanEvidenceLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "Evidence tier:", with: "")
            .replacingOccurrences(of: "Next best clue:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func firstURL(in line: String) -> URL? {
        line
            .split(whereSeparator: \.isWhitespace)
            .compactMap { rawToken -> URL? in
                let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]{}.,;\"'"))
                if token.hasPrefix("http://") || token.hasPrefix("https://") {
                    return URL(string: token)
                }
                if token.contains("."),
                   !token.contains(" "),
                   !token.contains("@"),
                   !token.hasPrefix("#"),
                   let normalized = URL(string: "https://\(token)") {
                    return normalized
                }
                return nil
            }
            .first
    }
}

private struct UnsavedMapCandidateCard: View {
    var candidate: SaveMapCandidate
    var isWorking: Bool
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                CandidateActionButton(
                    title: isWorking ? "Saving" : presentation.primaryActionTitle,
                    systemImage: presentation.primaryActionSystemImage,
                    fill: .saveHoney,
                    disabled: isWorking,
                    action: onSave
                )

                if let sourceURL = candidate.sourceURL, let url = URL(string: sourceURL) {
                    Link(destination: url) {
                        CandidateActionLabel(
                            title: "Maps",
                            systemImage: "map",
                            fill: .saveNotebookPage
                        )
                    }
                }
            }

            HStack(alignment: .top, spacing: 8) {
                UnsavedCandidateFact(title: "Rating", value: ratingText)
                UnsavedCandidateFact(title: "Reviews", value: reviewText ?? "—")
                UnsavedCandidateFact(title: "Distance", value: candidate.distanceLabel ?? "On map", valueColor: candidate.distanceLabel == nil ? .saveCocoa.opacity(0.68) : .saveInk)
            }
            .padding(.vertical, 2)

            PlaceBusinessPhotoCarousel(imageURLs: candidate.businessPhotoURLStrings)

            UnsavedCandidateGlassSection(title: "Basic info", systemImage: "info.circle.fill") {
                VStack(spacing: 8) {
                    UnsavedCandidateInfoRow(title: "Rating", value: ratingText)
                    if let reviewText {
                        UnsavedCandidateInfoRow(title: "Reviews", value: "\(reviewText) reviews")
                    }
                    if let hoursText {
                        UnsavedCandidateInfoRow(title: "Hours", value: hoursText)
                    }
                    if let distanceLabel = candidate.distanceLabel {
                        UnsavedCandidateInfoRow(title: "Distance", value: distanceLabel)
                    }
                    UnsavedCandidateInfoRow(title: "Category", value: candidate.category?.displayName ?? "Place")
                    UnsavedCandidateInfoRow(title: "Address", value: candidate.subtitle)
                    UnsavedCandidateInfoRow(title: "State", value: presentation.eyebrow)
                    UnsavedCandidateInfoRow(title: "Source", value: sourceSummary)
                }
            }

            UnsavedCandidateGlassSection(title: "Quick take", systemImage: "text.alignleft") {
                VStack(alignment: .leading, spacing: 8) {
                    UnsavedCandidateQuickLine(text: quickTakeSummary)
                    if let ratingSummary {
                        UnsavedCandidateQuickLine(text: ratingSummary)
                    }
                }
            }
        }
        .padding(.horizontal, 2)
        .opacity(isWorking ? 0.65 : 1)
    }

    private var ratingText: String {
        guard let rating = candidate.rating else { return "—" }
        return String(format: "%.1f", rating)
    }

    private var reviewText: String? {
        candidate.reviewCount.map {
            NumberFormatter.localizedString(from: NSNumber(value: $0), number: .decimal)
        }
    }

    private var hoursText: String? {
        candidate.evidence.compactMap { evidence -> String? in
            guard let range = evidence.range(of: "Hours:", options: [.caseInsensitive]) else { return nil }
            let value = evidence[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }.first
    }

    private var quickTakeSummary: String {
        var parts = [candidate.category?.displayName ?? "Place", "unsaved map result"]
        if let distanceLabel = candidate.distanceLabel {
            parts.append(distanceLabel)
        }
        return parts.joined(separator: " · ")
    }

    private var ratingSummary: String? {
        guard ratingText != "—" || reviewText != nil else { return nil }
        var parts: [String] = []
        if ratingText != "—" {
            parts.append("Rating \(ratingText)")
        }
        if let reviewText {
            parts.append("\(reviewText) reviews")
        }
        return parts.joined(separator: " · ")
    }

    private var sourceSummary: String {
        if candidate.evidence.contains(where: { $0.localizedCaseInsensitiveCompare("Apple Maps POI") == .orderedSame }) {
            return "Selected from Apple Maps · Map search"
        }
        if let searchQuery = candidate.evidence.compactMap({ line -> String? in
            guard let range = line.range(of: "Search:", options: [.caseInsensitive]) else {
                return nil
            }
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }).first {
            return "Map search · \(searchQuery)"
        }
        return "Map search"
    }

    private var presentation: SavePlaceDrawerPresentation {
        SavePlaceDrawerPresentation(mapCandidate: candidate)
    }
}

private struct UnsavedCandidateGlassSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var title: String
    var systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.black))
                Text(title)
                    .font(.caption.weight(.black))
                Spacer(minLength: 0)
            }
            .foregroundColor(.saveCocoa.opacity(0.86))

            content()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(sectionTint)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var sectionTint: Color {
        colorScheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.18)
    }
}

private struct UnsavedCandidateInfoRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption2.weight(.black))
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
                .font(.caption.weight(.black))
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
            .font(.caption2.weight(.black))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.24))
            .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
            .clipShape(Capsule())
    }
}

private struct CandidateActionButton: View {
    var title: String
    var systemImage: String
    var fill: Color = .saveNotebookPage
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
    var fill: Color = .saveNotebookPage
    var foreground: Color = .saveInk

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.black))
            .foregroundColor(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct PassportDrawerButton: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    var fill: Color
    var stroke: Color
    var foreground: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title3.weight(.black))
                .foregroundColor(foreground)
                .frame(width: 30, height: 30)
                .background(fill)
                .overlay(Circle().stroke(stroke, lineWidth: 1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(languageSettings.localized(english: "Open SAV-E Passport", traditionalChinese: "打開 SAV-E 護照"))
    }
}

private struct MemoryFlowCTA: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @Environment(\.colorScheme) private var colorScheme
    var reviewCount: Int
    var stampCount: Int
    var onReview: () -> Void
    var onAsk: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(languageSettings.localized(english: "PLACE MEMORY", traditionalChinese: "地點記憶"))
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.saveHoney.opacity(colorScheme == .dark ? 0.34 : 0.50))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.28), lineWidth: 1))

                Text(languageSettings.localized(
                    english: "Save what friends send. Ask when it matters.",
                    traditionalChinese: "存下朋友傳來的地點，需要時再問。"
                ))
                    .font(.headline.weight(.black))
                    .foregroundColor(.saveInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(languageSettings.localized(
                    english: "New places wait in Review first. Confirm them into Map Stamps, then SAV-E answers from what you saved.",
                    traditionalChinese: "新地點會先進待確認。確認成地圖章後，SAV-E 才會用你存過的內容回答。"
                ))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveCocoa.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                flowStep(number: "1", title: languageSettings.localized(english: "Review", traditionalChinese: "確認"), count: reviewCount, tint: .saveHoney)
                flowStep(number: "2", title: languageSettings.localized(english: "Stamp", traditionalChinese: "地圖章"), count: stampCount, tint: .saveMint)
                flowStep(number: "3", title: languageSettings.localized(english: "Ask", traditionalChinese: "詢問"), count: nil, tint: .saveSky)
            }

            HStack(spacing: 10) {
                Button(action: onReview) {
                    HStack(spacing: 7) {
                        Image(systemName: "checklist.unchecked")
                            .font(.caption.weight(.black))
                        Text(reviewButtonTitle)
                            .font(.caption.weight(.black))
                    }
                    .foregroundColor(.saveInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.saveHoney.opacity(colorScheme == .dark ? 0.42 : 0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.saveNotebookLine.opacity(0.30), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onAsk) {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.black))
                        Text(languageSettings.localized(english: "Ask saved", traditionalChinese: "問已保存"))
                            .font(.caption.weight(.black))
                    }
                    .foregroundColor(.saveInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.saveNotebookLine.opacity(0.24), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? .regularMaterial : .ultraThinMaterial)
                .overlay(Color.saveNotebookPage.opacity(colorScheme == .dark ? 0.30 : 0.18))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(colorScheme == .dark ? 0.30 : 0.20), lineWidth: 1.1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(languageSettings.localized(
            english: "Review clues, save Map Stamps, ask your saved memory",
            traditionalChinese: "確認線索，保存地圖章，再詢問你的地點記憶"
        ))
    }

    private var reviewButtonTitle: String {
        if reviewCount > 0 {
            return languageSettings.localized(english: "Review \(reviewCount)", traditionalChinese: "確認 \(reviewCount)")
        }
        return languageSettings.localized(english: "Open Review", traditionalChinese: "打開待確認")
    }

    private func flowStep(number: String, title: String, count: Int?, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(number)
                .font(.caption2.monospacedDigit().weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 18, height: 18)
                .background(tint.opacity(colorScheme == .dark ? 0.34 : 0.52))
                .clipShape(Circle())

            Text(title)
                .font(.caption2.weight(.black))
                .foregroundColor(.saveCocoa.opacity(0.78))
                .lineLimit(1)

            if let count, count > 0 {
                Text("\(count)")
                    .font(.caption2.monospacedDigit().weight(.black))
                    .foregroundColor(.saveInk)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.20))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SavedCategoryGrid: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let categories: [(category: PlaceCategory, count: Int)]
    let selectedCategories: Set<PlaceCategory>
    let onToggle: (PlaceCategory) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(languageSettings.localized(english: "Categories", traditionalChinese: "分類"))
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveCocoa.opacity(0.72))

                Spacer()

                if !selectedCategories.isEmpty {
                    Button(action: onClear) {
                        Text(languageSettings.localized(english: "All", traditionalChinese: "全部"))
                            .font(.caption2.weight(.black))
                            .foregroundColor(.saveInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.saveHoney.opacity(0.56))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.32), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(languageSettings.localized(english: "Show all saved categories", traditionalChinese: "顯示所有已保存分類"))
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(categories, id: \.category) { bucket in
                    SavedCategoryGridButton(
                        category: bucket.category,
                        count: bucket.count,
                        isSelected: selectedCategories.contains(bucket.category)
                    ) {
                        onToggle(bucket.category)
                    }
                }
            }
        }
    }
}

private struct SavedCategoryGridButton: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    var category: PlaceCategory
    var count: Int
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: category.iconName)
                    .font(.caption.weight(.black))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(category.poiIconColor.opacity(isSelected ? 1 : 0.72))
                    .clipShape(Circle())

                Text(category.displayName(language: languageSettings.language))
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 4)

                Text("\(count)")
                    .font(.caption2.monospacedDigit().weight(.black))
                    .foregroundColor(.saveCocoa.opacity(0.74))
            }
            .frame(height: 38)
            .padding(.horizontal, 9)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.saveHoney.opacity(0.42) : Color.saveNotebookPage.opacity(0.72))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(isSelected ? 0.50 : 0.20), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(languageSettings.localized(
            english: "\(category.displayName(language: .english)), \(count) saved",
            traditionalChinese: "\(category.displayName(language: .traditionalChinese))，已保存 \(count) 個"
        ))
    }
}

private struct DrawerSuggestionRow: View {
    @Environment(\.colorScheme) private var colorScheme
    var icon: String
    var text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 28, height: 28)
                .background(Color.saveMint.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 1.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(colorScheme == .dark ? .white : .saveInk)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.black))
                .foregroundColor(.saveCocoa.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(Color.white.opacity(0.16))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AIResultActionBar: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    var onFollowUp: () -> Void
    var onNewQuestion: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onFollowUp) {
                Label(languageSettings.localized(english: "Follow up", traditionalChinese: "追問"), systemImage: "text.bubble")
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.saveHoney)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.4)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            Button(action: onNewQuestion) {
                Label(languageSettings.localized(english: "New", traditionalChinese: "新的"), systemImage: "plus.bubble")
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.saveMint.opacity(0.74))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.4)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.saveNotebookPage.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private enum AgentCommandTone {
    case signal, honey, sky, cocoa

    var color: Color {
        switch self {
        case .signal: return .saveSignal
        case .honey: return .saveHoney
        case .sky: return .saveSky
        case .cocoa: return .saveMint
        }
    }

    var textColor: Color {
        switch self {
        case .signal: return .saveSignal
        case .honey: return .saveInk
        case .sky: return .saveInk
        case .cocoa: return .saveInk
        }
    }

    var chipFill: Color {
        switch self {
        case .signal: return .saveSignal.opacity(0.18)
        case .honey: return .saveHoney.opacity(0.58)
        case .sky: return .saveSky.opacity(0.46)
        case .cocoa: return .saveMint.opacity(0.54)
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
                            .stroke(Color.saveNotebookLine.opacity(isPrimary ? 0.40 : 0.26), lineWidth: 1)
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
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveInk)
                        .padding(5)
                        .background(tone.chipFill)
                        .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1))
                        .clipShape(Circle())
                    Text(commandLabel.uppercased())
                        .font(.caption2.weight(.black))
                        .foregroundColor(tone.textColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(tone.chipFill)
                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
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
                    .stroke(Color.saveNotebookLine.opacity(isPrimary ? 0.38 : 0.22), lineWidth: 1.1)
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
        return colorScheme == .dark ? Color.saveNotebookPage.opacity(0.32) : Color.white.opacity(0.16)
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
                                .stroke(Color.saveNotebookLine.opacity(0.26), lineWidth: 1)
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
                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
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
                    .stroke(Color.saveNotebookLine.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    private var commandSurfaceTint: Color {
        colorScheme == .dark ? Color.saveNotebookPage.opacity(0.30) : Color.white.opacity(0.16)
    }
}
