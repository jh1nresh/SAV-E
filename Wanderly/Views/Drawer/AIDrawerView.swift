import SwiftUI
import UIKit
import AVFoundation
import Speech

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
    var onConfirmCandidate: (PlaceReviewCandidate) async throws -> Void = { _ in }
    var onRejectCandidate: (PlaceReviewCandidate) async throws -> Void = { _ in }
    var onSaveCandidate: (PlaceReviewCandidate) async throws -> Void = { _ in }
    var onSaveMapCandidate: (SaveMapCandidate) async throws -> Void = { _ in }
    var onUpdatePlaceVisibility: (Place, PlaceVisibility) async throws -> Void = { _, _ in }
    var onImportURLAsReviewCandidates: (URL) async throws -> Int = { _ in 0 }
    var onPrepareMapSearch: (String) async -> [SaveMapCandidate] = { _ in [] }
    var collaborativeLists: [SaveCollaborativeList] = []
    var onCreateList: (String, String?) -> SaveCollaborativeList = { title, note in
        SaveCollaborativeList(title: title, note: note)
    }
    var onAddPlaceToList: (Place, UUID) throws -> Void = { _, _ in }
    var onAddMapCandidateToList: (SaveMapCandidate, UUID) throws -> Void = { _, _ in }
    var onShareListURL: (SaveCollaborativeList, SaveListRole) -> URL? = { _, _ in nil }
    var onSaveListItem: (SaveListItem) async throws -> Void = { _ in }
    var onPlanList: (SaveCollaborativeList) async -> Void = { _ in }
    var socialLens: SaveSocialLens = .forYou
    var socialPlaces: [Place] = []
    var onSelectSocialLens: (SaveSocialLens) -> Void = { _ in }
    var onSaveSocialPlace: (Place) async throws -> Void = { _ in }
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
    @State private var selectedListID: UUID?
    @State private var newListTitle = ""
    @State private var newListNote = ""

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
        .sheet(isPresented: $viewModel.showPlaceList) {
            PlaceListView()
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
                case .idle:             drawerDetent = .height(72)
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
                viewModel.query = "Plan around \(place.name)"
                Task { await viewModel.submit() }
            },
            onConfirmCandidate: { candidate in
                performCandidateAction(candidate, successMessage: "Marked as confirmed. Save it as a Map Stamp when ready.") {
                    try await onConfirmCandidate(candidate)
                }
            },
            onRejectCandidate: { candidate in
                performCandidateAction(candidate, successMessage: "Removed from Review.") {
                    try await onRejectCandidate(candidate)
                    closeMapDetail()
                }
            },
            onSaveCandidate: { candidate in
                performCandidateAction(candidate, successMessage: saveFeedback(for: candidate)) {
                    try await onSaveCandidate(candidate)
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
            onCreateList: createListForPicker,
            onAddPlaceToList: onAddPlaceToList,
            onAddMapCandidateToList: onAddMapCandidateToList
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
                .fill(colorScheme == .dark ? Color.saveNotebookPage.opacity(0.90) : Color.saveNotebookPage.opacity(0.86))
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
        colorScheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.18)
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
            .accessibilityLabel("Clear command")

            Button(action: submitSearchField) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3.weight(.black))
                    .foregroundColor(commandBarTextColor)
            }
            .accessibilityLabel("Ask SAV-E")
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
            if showLists {
                collaborativeListsView
            } else if showSavedCategories {
                savedCategoriesView
            } else if showReviewInbox {
                reviewInboxView
            } else {
                suggestionsView
            }

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
                            aiMessage: response.aiMessage
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
                            viewModel.showSearchResult(result)
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
                        viewModel.query = "Plan around \(place.name)"
                        Task { await viewModel.submit() }
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
                    onConfirm: {
                        performCandidateAction(candidate, successMessage: "Marked as confirmed. Save it as a Map Stamp when ready.") {
                            try await onConfirmCandidate(candidate)
                        }
                    },
                    onReject: {
                        performCandidateAction(candidate, successMessage: "Removed from Review.") {
                            try await onRejectCandidate(candidate)
                            viewModel.returnToCommands()
                            showSavedCategories = false
                            showReviewInbox = true
                            showLists = false
                        }
                    },
                    onSave: {
                        performCandidateAction(candidate, successMessage: saveFeedback(for: candidate)) {
                            try await onSaveCandidate(candidate)
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

                    AddToListPanel(
                        title: "Add this map result to a list",
                        lists: collaborativeLists.filter(\.canEdit),
                        onCreateList: createListForPicker,
                        onAddToList: { listID in
                            do {
                                try onAddMapCandidateToList(candidate, listID)
                                addSpotStatus = "Added \(candidate.title) to list without saving it."
                            } catch {
                                addSpotStatus = error.localizedDescription
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

                    Button(languageSettings.text(.tryAgain)) { Task { await viewModel.submit() } }
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
                .fill(colorScheme == .dark ? Color.saveNotebookPage.opacity(0.92) : Color.saveNotebookPage.opacity(0.86))
                .overlay(navigationHeaderTint)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.13) : Color.saveNotebookLine.opacity(0.18))
                .frame(height: 1)
        }
    }

    private var navigationHeaderTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.10) : Color.white.opacity(0.12)
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
            return "Map Stamps first, unsaved recommendations separate"
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
        if case .idle = viewModel.drawerState, isCollapsed, !showReviewInbox, !showSavedCategories, !showLists { return false }
        return true
    }

    private var hasActiveDrawerContent: Bool {
        switch viewModel.drawerState {
        case .idle:
            return showReviewInbox || showSavedCategories || showLists
        case .loading, .displaying, .saveSearchResults, .placeDetail, .reviewCandidateDetail, .mapCandidateDetail, .error:
            return true
        }
    }

    // MARK: - Idle suggestions

    private var suggestionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                quickActionStrip
                categoryFilterStrip
                socialSignalSection

                if !viewModel.chatHistory.isEmpty {
                    NotebookBandLabel("Recent")
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

                NotebookBandLabel("Try asking")
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

    private let suggestions = [
        "I want boba today",
        "Coffee from my Map Stamps",
        "Plan a day from my Map Stamps",
        "Navigate to the nearest cafe",
        "Show waiting clues",
    ]

    private var quickActionStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotebookBandLabel("Quick actions")
                .padding(.horizontal, 16)

            HStack(spacing: 9) {
                DrawerActionChip(
                    title: "Full list",
                    systemImage: "list.bullet.rectangle",
                    count: viewModel.places.isEmpty ? nil : viewModel.places.count,
                    fill: Color.saveMint.opacity(0.36),
                    action: openFullList
                )

                DrawerActionChip(
                    title: "Saved",
                    systemImage: "square.grid.2x2",
                    count: viewModel.places.isEmpty ? nil : viewModel.places.count,
                    fill: Color.saveSky.opacity(0.28),
                    action: openSavedCategories
                )

                DrawerActionChip(
                    title: "Review",
                    systemImage: "checklist.unchecked",
                    count: reviewCandidates.isEmpty ? nil : reviewCandidates.count,
                    fill: Color.saveHoney.opacity(0.42),
                    action: openReviewInbox
                )

                DrawerActionChip(
                    title: "Lists",
                    systemImage: "person.2.wave.2.fill",
                    count: collaborativeLists.isEmpty ? nil : collaborativeLists.count,
                    fill: Color.savePink.opacity(0.36),
                    action: openCollaborativeLists
                )
            }
            .padding(.horizontal, 16)

            HStack(spacing: 9) {
                DrawerActionChip(
                    title: "Takeout",
                    systemImage: "tray.and.arrow.down",
                    count: nil,
                    fill: Color.saveSky.opacity(0.34),
                    action: { showGoogleTakeoutImport = true }
                )

                DrawerActionChip(
                    title: "Plan",
                    systemImage: "map.fill",
                    count: nil,
                    fill: Color.saveSignal.opacity(0.30),
                    action: {
                        focusAgentPrompt("Plan a day from my Map Stamps")
                    }
                )
            }
            .padding(.horizontal, 16)
        }
    }

    private var categoryFilterStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            NotebookBandLabel("Filters")
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
            NotebookBandLabel("Social map")
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
                            Text(lens.title)
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
                Text(socialSignalEmptyMessage)
                    .font(.caption)
                    .foregroundColor(.saveCocoa.opacity(0.72))
                    .padding(.horizontal, 16)
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

    private var socialSignalEmptyMessage: String {
        switch socialLens {
        case .forYou:
            return "Follow friends or open a referral link. SAV-E will only show real shared places here."
        case .friends:
            return "No friend places yet. Friend signals appear after a real follow or referral handoff."
        case .trending:
            return "Trending stays empty until enough public Map Stamps exist for this area and category."
        }
    }

    private var savedCategoriesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FieldNotebookHeader(memoryCount: viewModel.places.count, clueCount: reviewCandidates.count)

                VStack(alignment: .leading, spacing: 8) {
                    NotebookBandLabel("Saved categories")

                    if viewModel.places.isEmpty {
                        Text("No saved Map Stamps yet. Confirm Review Candidates or save map results to build your categories.")
                            .font(.caption)
                            .foregroundColor(.saveCocoa.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(savedCategorySubtitle)
                            .font(.caption)
                            .foregroundColor(.saveCocoa.opacity(0.72))

                        VStack(spacing: 8) {
                            ForEach(savedCategoryCounts, id: \.category) { bucket in
                                SavedCategoryLensRow(
                                    category: bucket.category,
                                    count: bucket.count,
                                    isSelected: selectedCategories.contains(bucket.category)
                                ) {
                                    onToggleCategory(bucket.category)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .saveNotebookSurface(cornerRadius: 16, fill: .saveNotebookPage, opacity: colorScheme == .dark ? 0.72 : 0.66, strokeOpacity: 0.36, lineWidth: 1)
                .overlay(savedPanelTint)

                HStack(spacing: 9) {
                    Button {
                        Array(selectedCategories).forEach { onToggleCategory($0) }
                    } label: {
                        Label("Clear filters", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption.weight(.black))
                            .foregroundColor(commandBarTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.24))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCategories.isEmpty)
                    .opacity(selectedCategories.isEmpty ? 0.52 : 1)

                    Button {
                        viewModel.showPlaceList = true
                    } label: {
                        Label("Full list", systemImage: "list.bullet.rectangle")
                            .font(.caption.weight(.black))
                            .foregroundColor(commandBarTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.saveHoney.opacity(0.42))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
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

    private var savedCategoryCounts: [(category: PlaceCategory, count: Int)] {
        PlaceCategory.allCases.compactMap { category in
            let count = viewModel.places.filter { $0.category == category }.count
            return count > 0 ? (category, count) : nil
        }
    }

    private var savedCategorySubtitle: String {
        if selectedCategories.isEmpty {
            return "Tap a category to filter the map without leaving the drawer."
        }
        let names = selectedCategories.map(\.displayName).sorted().joined(separator: ", ")
        return "Map filtered to \(names). Tap again to remove."
    }

    private var savedPanelTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.08) : Color.white.opacity(0.18)
    }

    // MARK: - Add Spots

    private var addSpotsHub: some View {
        VStack(alignment: .leading, spacing: 14) {
            FieldNotebookHeader(memoryCount: viewModel.places.count, clueCount: reviewCandidates.count)

            VStack(alignment: .leading, spacing: 9) {
                NotebookBandLabel("Command Console")

                AgentCommandRow(
                    icon: "sparkle.magnifyingglass",
                    title: "Paste your first place",
                    subtitle: "IG, TikTok, Google Maps, Apple Maps, blog, or note",
                    commandLabel: "evidence first",
                    tone: .cocoa,
                    isPrimary: true
                ) {
                    focusSocialInvestigationPrompt()
                }

                HStack(spacing: 9) {
                    AgentCommandCard(
                        icon: "circle.hexagongrid.fill",
                        title: "Review",
                        subtitle: "Turn Review Candidates into Map Stamps",
                        commandLabel: reviewCandidates.isEmpty ? "all clear" : "\(reviewCandidates.count) waiting",
                        tone: .honey
                    ) {
                        openReviewInbox()
                    }

                    AgentCommandCard(
                        icon: "link",
                        title: "Clipboard",
                        subtitle: "Read one copied URL",
                        commandLabel: "metadata",
                        tone: .signal
                    ) {
                        importClipboardURL()
                    }
                }

                HStack(spacing: 9) {
                    AgentCommandCard(
                        icon: "note.text",
                        title: "Notes",
                        subtitle: "Paste a rough list",
                        commandLabel: "review only",
                        tone: .honey
                    ) {
                        focusAgentPrompt("""
                        Turn these notes into reviewable place clues.

                        Extract likely place names, city/address clues, category, evidence, confidence, and what is missing. Do not save anything automatically.

                        Notes:
                        """)
                    }

                    AgentCommandCard(
                        icon: "doc.viewfinder",
                        title: "Media",
                        subtitle: "Screenshot or file evidence",
                        commandLabel: "investigate",
                        tone: .sky
                    ) {
                        focusMediaEvidencePrompt()
                    }
                }

                AgentCommandRow(
                    icon: "location.magnifyingglass",
                    title: "Resolve a fuzzy venue",
                    subtitle: "Find address, city, source links, and whether it is safe to save.",
                    commandLabel: "verifies address",
                    tone: .cocoa
                ) {
                    focusAgentPrompt("""
                    Find the real venue for this place idea and return review clues with evidence.

                    Include official name, address, city, source links, confidence, and whether it is safe to save. Do not save automatically.

                    Place idea:
                    """)
                }

                AgentCommandRow(
                    icon: "map.fill",
                    title: "Plan around Map Stamps",
                    subtitle: "Build a route from the spatial memory canvas.",
                    commandLabel: "uses Map Stamps",
                    tone: .sky
                ) {
                    focusAgentPrompt("""
                    Help me organize my Map Stamps into a practical plan.

                    Use only Map Stamps unless I explicitly ask you to investigate new candidates. Start with:
                    """)
                }
            }

            ReviewCandidatesSection(
                candidates: reviewCandidates,
                limit: 2,
                onSelect: openReviewCandidateDetail
            )

            if let addSpotStatus {
                Text(addSpotStatus)
                    .font(.caption)
                    .foregroundColor(.saveCocoa.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var reviewInboxView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    FieldNotebookHeader(memoryCount: viewModel.places.count, clueCount: reviewCandidates.count)
                    Button(action: {
                        showSavedCategories = false
                        showReviewInbox = false
                        showLists = false
                        withAnimation { drawerDetent = .medium }
                    }) {
                        Label("Commands", systemImage: "terminal")
                            .font(.caption)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.saveSky.opacity(0.54))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

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
                FieldNotebookHeader(memoryCount: viewModel.places.count, clueCount: reviewCandidates.count)

                VStack(alignment: .leading, spacing: 9) {
                    NotebookBandLabel("Create list")
                    TextField("Tokyo cafes, OC weekend, NYC food", text: $newListTitle)
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

                    TextField("Optional note", text: $newListNote)
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
                        Label("Create list", systemImage: "plus")
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
                    Text("Create a list, then add saved Map Stamps or unsaved map results from their detail cards.")
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

    private func focusSocialInvestigationPrompt() {
        showReviewInbox = false
        if let clipboardText = UIPasteboard.general.string,
           let url = firstURL(in: clipboardText) {
            importURLToReviewCandidates(url)
        } else {
            addSpotStatus = "Paste a place link, or share to SAV-E from another app. SAV-E will show evidence before saving anything."
            focusAgentPrompt(socialInvestigationPrompt(for: ""))
        }
    }

    private func socialInvestigationPrompt(for url: String) -> String {
        """
        Investigate this public social/video link and return candidate places with evidence.

        Use public preview metadata, pasted caption text, and reliable cross-checks only. If there is no explicit venue/address, return review candidates with confidence and missing evidence instead of saving.

        Link: \(url)
        """
    }

    private func focusMediaEvidencePrompt() {
        showReviewInbox = false
        addSpotStatus = "Media evidence results stay as review candidates until you choose a place."
        focusAgentPrompt("""
        Investigate this video or screenshot and return candidate places with evidence.

        Use only evidence from the shared media, pasted caption/link, and reliable cross-checks.
        Return likely place candidates, evidence for each candidate, confidence, what is missing, and whether it is safe to save.

        Do not save anything automatically.
        """)
    }

    private func importClipboardURL() {
        showReviewInbox = false
        guard let clipboardText = UIPasteboard.general.string,
              let url = firstURL(in: clipboardText) else {
            addSpotStatus = "Clipboard does not contain a URL yet. Copy a place or social link, then tap Import clipboard again."
            return
        }

        addSpotStatus = "Clipboard link loaded. SAV-E will save possible places to Review first."
        importURLToReviewCandidates(url)
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
        showSavedCategories = false
        showReviewInbox = true
        showLists = false
        searchFocused = false
        withAnimation { drawerDetent = .large }
    }

    private func openSavedCategories() {
        viewModel.returnToCommands()
        showSavedCategories = true
        showReviewInbox = false
        showLists = false
        searchFocused = false
        withAnimation { drawerDetent = .medium }
    }

    private func openFullList() {
        viewModel.returnToCommands()
        showSavedCategories = false
        showReviewInbox = false
        showLists = false
        searchFocused = false
        viewModel.showPlaceList = true
    }

    private func openCollaborativeLists() {
        viewModel.returnToCommands()
        showSavedCategories = false
        showReviewInbox = false
        showLists = true
        searchFocused = false
        withAnimation { drawerDetent = .large }
    }

    private func openReviewCandidateDetail(_ candidate: PlaceReviewCandidate) {
        showSavedCategories = false
        showReviewInbox = false
        showLists = false
        searchFocused = false
        viewModel.showReviewCandidate(candidate)
        withAnimation { drawerDetent = .medium }
    }

    private func submitSearchField() {
        voiceQuery.stop()
        searchFocused = false
        if let url = firstURL(in: viewModel.query) {
            importURLToReviewCandidates(url)
        } else if viewModel.shouldSearchNearbyUnsavedCandidates(for: viewModel.query) {
            searchNearbyUnsavedCandidates(for: viewModel.query)
        } else {
            let submittedQuery = viewModel.query
            Task {
                await viewModel.submit()
                if viewModel.shouldAutoSearchNearbyUnsavedCandidates() {
                    searchNearbyUnsavedCandidates(for: submittedQuery)
                }
            }
        }
    }

    private func searchNearbyUnsavedCandidates(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fallbackQuery = viewModel.shouldSearchNearbyUnsavedCandidates(for: trimmed)
            ? trimmed
            : "search nearby unsaved candidates for \(trimmed)"
        viewModel.query = fallbackQuery
        addSpotStatus = "Looking for nearby unsaved candidates. Your SAV-E results stay separate."
        withAnimation { drawerDetent = .medium }

        Task {
            let candidates = await onPrepareMapSearch(fallbackQuery)
            if candidates.isEmpty {
                viewModel.mapCandidates = []
                addSpotStatus = "No nearby unsaved candidates found yet. Try a more specific place type or city."
            } else {
                viewModel.mapCandidates = candidates
                addSpotStatus = "Found \(candidates.count) nearby unsaved candidates. Save only the ones that look right."
            }
            await viewModel.submit()
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
        viewModel.reset()
        showSavedCategories = false
        showReviewInbox = false
        showLists = false
        searchFocused = false
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
            showSavedCategories = false
            showLists = false
            withAnimation { drawerDetent = .large }
        }
    }
}

private struct DrawerGlassBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        Rectangle()
            .fill(Color.clear)
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
                Color.black.opacity(0.03),
                Color.black.opacity(0.10)
            ]
        }
        return [
            Color.white.opacity(0.02),
            Color.saveCream.opacity(0.05)
        ]
    }

    private var topStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.62)
    }
}

private struct MapDetailDrawerView: View {
    let item: MapDetailDrawerItem
    @Binding var detent: PresentationDetent
    let editableLists: [SaveCollaborativeList]
    let isWorkingReviewCandidateID: UUID?
    let isWorkingMapCandidateID: String?
    let onClose: () -> Void
    let onDeletePlace: (Place) async throws -> Void
    let onPlanAroundPlace: (Place) -> Void
    let onConfirmCandidate: (PlaceReviewCandidate) -> Void
    let onRejectCandidate: (PlaceReviewCandidate) -> Void
    let onSaveCandidate: (PlaceReviewCandidate) -> Void
    let onSaveMapCandidate: (SaveMapCandidate) -> Void
    let onSaveSocialPlace: (Place) -> Void
    let onUpdatePlaceVisibility: (Place, PlaceVisibility) async throws -> Void
    let onCreateList: () -> SaveCollaborativeList
    let onAddPlaceToList: (Place, UUID) throws -> Void
    let onAddMapCandidateToList: (SaveMapCandidate, UUID) throws -> Void
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
            SaveMemoryBadge(state: badgeState, size: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveCocoa.opacity(0.76))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button(action: onClose) {
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
            .accessibilityLabel("Close place detail")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
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
                        }
                    )

                    AddToListPanel(
                        title: "Add this Map Stamp to a list",
                        lists: editableLists,
                        onCreateList: onCreateList,
                        onAddToList: { listID in
                            do {
                                try onAddPlaceToList(place, listID)
                                statusMessage = "Added \(place.name) to list."
                            } catch {
                                statusMessage = error.localizedDescription
                            }
                        }
                    )

                case .reviewCandidate(let candidate):
                    ReviewCandidateDetailCard(
                        candidate: candidate,
                        isWorking: isWorkingReviewCandidateID == candidate.id,
                        onConfirm: { onConfirmCandidate(candidate) },
                        onReject: { onRejectCandidate(candidate) },
                        onSave: { onSaveCandidate(candidate) }
                    )

                case .unsavedCandidate(let candidate):
                    UnsavedMapCandidateCard(
                        candidate: candidate,
                        isWorking: isWorkingMapCandidateID == candidate.id,
                        onSave: { onSaveMapCandidate(candidate) }
                    )

                    AddToListPanel(
                        title: "Add this map result to a list",
                        lists: editableLists,
                        onCreateList: onCreateList,
                        onAddToList: { listID in
                            do {
                                try onAddMapCandidateToList(candidate, listID)
                                statusMessage = "Added \(candidate.title) to list without saving it."
                            } catch {
                                statusMessage = error.localizedDescription
                            }
                        }
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

    private var badgeState: SaveMemoryBadge.State {
        switch item {
        case .savedPlace(let place):
            return .saved(place.category)
        case .reviewCandidate(let candidate):
            return candidate.hasReliableCoordinates ? .ready : .clue
        case .unsavedCandidate:
            return .ready
        case .socialPlace:
            return .ready
        }
    }
}

private struct SelectedPlaceCapsule: View {
    let item: MapDetailDrawerItem
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            shareAction
                .frame(width: 44, height: 44)

            Button(action: onExpand) {
                VStack(spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.black))
                        .foregroundColor(.saveInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)

                    Text(item.subtitle)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.saveCocoa.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                }
                .multilineTextAlignment(.center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.title) details")
            .accessibilityHint("Expands the selected place drawer")

            Button(action: onClose) {
                SelectedPlaceCapsuleIcon(systemImage: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close selected place")
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
        if let url = item.shareURL {
            ShareLink(item: url, subject: Text(item.shareSubject), message: Text(item.shareText)) {
                SelectedPlaceCapsuleIcon(systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share \(item.title)")
        } else {
            ShareLink(item: item.shareText, subject: Text(item.shareSubject)) {
                SelectedPlaceCapsuleIcon(systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share \(item.title)")
        }
    }
}

private struct SelectedPlaceCapsuleIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.saveInk)
            .frame(width: 38, height: 38)
            .background(Color.saveNotebookPage.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(0.44), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension MapDetailDrawerItem {
    var title: String {
        switch self {
        case .savedPlace(let place):
            return place.name
        case .reviewCandidate(let candidate):
            return candidate.name
        case .unsavedCandidate(let candidate):
            return candidate.title
        case .socialPlace(let place):
            return place.name
        }
    }

    var subtitle: String {
        switch self {
        case .savedPlace(let place):
            return "\(place.category.displayName) · Map Stamp"
        case .reviewCandidate(let candidate):
            return candidate.hasReliableCoordinates ? "Review Candidate" : "Source Clue"
        case .unsavedCandidate(let candidate):
            return "\(candidate.category?.displayName ?? "Place") · Unsaved candidate"
        case .socialPlace(let place):
            return "\(place.category.displayName) · \(place.socialSignal?.displayText ?? "Social signal")"
        }
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
}

private struct SocialPlaceRow: View {
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
                    Text(place.category.displayName)
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
                Text("Save")
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.saveHoney.opacity(0.78))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.32), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save \(place.name) to my SAV-E")
        }
        .padding(12)
        .saveNotebookSurface(cornerRadius: 14, fill: .saveNotebookPage, opacity: 0.62, strokeOpacity: 0.34, lineWidth: 1)
    }
}

private struct MapDetailDrawerBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.saveNotebookPage.opacity(0.94) : Color.saveNotebookPage.opacity(0.90))
            .overlay {
                LinearGradient(
                    colors: tintStops,
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.68))
                    .frame(height: 1)
            }
            .ignoresSafeArea()
    }

    private var tintStops: [Color] {
        if colorScheme == .dark {
            return [
                Color.black.opacity(0.02),
                Color.black.opacity(0.08)
            ]
        }
        return [
            Color.saveCream.opacity(0.18),
            Color.saveNotebookPage.opacity(0.12)
        ]
    }
}

private struct SavedMapDetailDrawerContent: View {
    let place: Place
    let onPlanAroundPlace: () -> Void
    let onDeletePlace: () async throws -> Void
    let onUpdateVisibility: (PlaceVisibility) async throws -> Void
    @Environment(\.openURL) private var openURL
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaceBusinessPhotoCarousel(imageURLs: place.businessPhotoURLStrings)

            FlowLayout(spacing: 8) {
                CategoryPill(category: place.category, isSelected: true)
                if let rating = place.googleRating ?? place.rating {
                    MapDetailChip(icon: "star.fill", text: String(format: "%.1f", rating))
                }
                if let priceRange = place.priceRange {
                    MapDetailChip(icon: "tag.fill", text: priceRange)
                }
                ForEach(place.verificationChips(sourceLabel: place.sourceConfirmationLabel), id: \.text) { chip in
                    MapDetailChip(icon: chip.icon, text: chip.text)
                }
            }

            PlaceBasicInfoPanel(place: place)
            PlaceInsightSummaryPanel(place: place, fallbackSummary: memorySummary)
            PlaceVisibilityControl(
                visibility: place.effectiveVisibility,
                onChange: onUpdateVisibility
            )

            HStack(spacing: 8) {
                Button {
                    NavigationService.navigate(to: place.coordinate, name: place.name)
                } label: {
                    PlaceDetailActionLabel(title: "Maps", systemImage: "map.fill", fill: .saveHoney.opacity(0.78))
                }

                ShareLink(item: place.saveShareURL ?? place.appleMapsURL ?? URL(string: "https://sav-e-app.vercel.app")!, subject: Text(place.shareSubject), message: Text(place.shareText)) {
                    PlaceDetailActionLabel(title: "Share", systemImage: "square.and.arrow.up", fill: Color.saveMint.opacity(0.32))
                }

                if let sourceURL = place.primarySourceURL {
                    Button {
                        openURL(sourceURL)
                    } label: {
                        PlaceDetailActionLabel(title: "Source", systemImage: "link", fill: Color.saveSky.opacity(0.20))
                    }
                } else {
                    Button(action: onPlanAroundPlace) {
                        PlaceDetailActionLabel(title: "Plan", systemImage: "sparkles", fill: Color.saveNotebookPage.opacity(0.42))
                    }
                }
            }

            Menu {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
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
        }
        .confirmationDialog(
            "Delete \(place.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Place", role: .destructive) {
                Task { await deletePlace() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the Map Stamp from SAV-E.")
        }
    }

    private var memorySummary: String {
        place.memorySummary
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
            PlaceInsightSummaryPanel(place: place, fallbackSummary: "This is a social map result. Save it to make it part of your own SAV-E memory.")

            Button(action: onSave) {
                Label("Save to my SAV-E", systemImage: "plus.circle.fill")
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
                    Label("Create list and add", systemImage: "plus")
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
                    Button("New list") {
                        let list = onCreateList()
                        onAddToList(list.id)
                    }
                } label: {
                    Label("Choose list", systemImage: "list.bullet.rectangle")
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
                Label("Plan", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
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
                    Label("Viewer", systemImage: "square.and.arrow.up")
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
                    Label("Editor", systemImage: "person.badge.plus")
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
                Text("Open a place or map result, then add it to this list.")
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
                                .accessibilityLabel("Already saved")
                        } else {
                            Button(action: { onSaveItem(item) }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.saveInk)
                            }
                            .accessibilityLabel("Save to my SAV-E")
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

private struct FieldNotebookHeader: View {
    var memoryCount: Int
    var clueCount: Int

    private var statusText: String {
        if clueCount > 0 {
            return "\(clueCount) clues waiting to save"
        }
        if memoryCount > 0 {
            return "Ready to investigate the next save"
        }
        return "Waiting for the first place clue"
    }

    var body: some View {
        HStack(spacing: 0) {
            NotebookSpine(color: .saveNotebookSpine)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    MemoMascotMark(size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SAV-E Memo Book")
                            .font(.title3)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(statusText)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.saveCocoa.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Text("MEMO")
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.saveSky.opacity(0.58))
                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1.2))
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    FieldNotebookStat(title: "MEMORIES", value: "\(memoryCount)", color: .saveCocoa)
                    FieldNotebookStat(title: "CLUES", value: "\(clueCount)", color: .saveHoney)
                    FieldNotebookStat(title: "HELPER", value: "MEMO", color: .saveSky)
                }
            }
            .padding(14)
        }
        .saveNotebookPage(cornerRadius: 18)
    }
}

private struct NotebookSpine: View {
    var color: Color

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
        .background(color.opacity(0.86))
    }
}

private struct FieldNotebookStat: View {
    var title: String
    var value: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.black))
                .foregroundColor(.saveCocoa.opacity(0.74))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(.caption.monospacedDigit().weight(.black))
                .foregroundColor(.saveInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.saveNotebookPage.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.1)
        )
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(color.opacity(0.72))
                .frame(width: 28, height: 4)
                .clipShape(Capsule())
                .padding(.leading, 9)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

private struct ReviewCandidatesSection: View {
    var candidates: [PlaceReviewCandidate]
    var limit: Int? = 4
    var onSelect: (PlaceReviewCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NotebookBandLabel("Review")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(candidates.count)")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(candidates.isEmpty ? Color.saveNotebookPage : Color.saveMint)
                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1.2))
                    .clipShape(Capsule())
            }

            if candidates.isEmpty {
                ReviewCandidatesEmptyState()
            } else {
                ForEach(displayedCandidates) { candidate in
                    Button(action: { onSelect(candidate) }) {
                        ReviewCandidatePlaceRow(candidate: candidate)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var displayedCandidates: [PlaceReviewCandidate] {
        guard let limit else { return candidates }
        return Array(candidates.prefix(limit))
    }
}

private struct ReviewCandidatePlaceRow: View {
    var candidate: PlaceReviewCandidate

    private var inferredCategory: PlaceCategory {
        PlaceCategory.inferred(from: "\(candidate.name) \(candidate.address)")
    }

    private var addressText: String {
        if !candidate.address.isEmpty { return candidate.address }
        if let city = candidate.city, !city.isEmpty { return city }
        return "Needs address confirmation"
    }

    private var statusText: String {
        candidate.hasReliableCoordinates ? "Ready to review" : "Needs info"
    }

    private var statusIcon: String {
        candidate.hasReliableCoordinates ? "checkmark.seal.fill" : "questionmark.folder.fill"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                SaveMemoryBadge(state: candidate.hasReliableCoordinates ? .ready : .clue, size: 44)
                Text(candidate.hasReliableCoordinates ? "PLACE" : "CLUE")
                    .font(.system(size: 7, weight: .black))
                    .foregroundColor(.saveCocoa)
            }
            .frame(width: 54)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(candidate.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.saveInk)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    statusBadge
                }

                Text(addressText)
                    .font(.caption)
                    .foregroundColor(.saveMutedText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(inferredCategory.displayName, systemImage: inferredCategory.iconName)
                        .font(.caption2)
                        .foregroundColor(.saveMutedText)
                        .lineLimit(1)

                    if let confidence = candidate.confidence {
                        Text("\(Int(confidence * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.saveMutedText)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.saveCocoa.opacity(0.48))
                }
            }
        }
        .padding(12)
        .saveNotebookPage(cornerRadius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.name), \(statusText)")
        .accessibilityHint("Open review details before saving")
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption2.weight(.black))
            Text(statusText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(.saveCocoa)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.saveNotebookPage)
        .overlay(
            Capsule()
                .stroke(Color.saveNotebookLine.opacity(0.28), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

private struct ReviewCandidatesEmptyState: View {
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
                Text("No clues waiting")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.saveInk)

                Text("Share a post, screenshot, or map link for SAV-E to investigate. Uncertain places wait here as Review Candidates until you save them as Map Stamps.")
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
    var candidate: PlaceReviewCandidate
    var isWorking: Bool
    var onConfirm: () -> Void
    var onReject: () -> Void
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            NotebookSpine(color: candidate.hasReliableCoordinates ? .saveSignal : .saveNotebookSpine)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 11) {
                    SaveMemoryBadge(state: candidate.hasReliableCoordinates ? .ready : .clue, size: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.hasReliableCoordinates ? "REVIEW CANDIDATE" : "SOURCE CLUE")
                            .font(.caption2.weight(.black))
                            .foregroundColor(.saveCocoa)
                            .lineLimit(1)

                        Text(candidate.name)
                            .font(.headline)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)
                            .lineLimit(2)

                        Text(candidate.address.isEmpty ? "Needs address confirmation" : candidate.address)
                            .font(.caption)
                            .foregroundColor(.saveCocoa.opacity(0.74))
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            if let confidence = candidate.confidence {
                                StampChip(text: "\(Int(confidence * 100))% confidence", color: .saveCocoa)
                            }
                            StampChip(text: candidate.hasReliableCoordinates ? "map ready" : "1 clue missing", color: .saveHoney)
                        }
                    }

                    Spacer(minLength: 0)
                }

                Text(candidate.hasReliableCoordinates
                     ? "I found enough map evidence. Save it as a Map Stamp when this looks right."
                     : "I found the likely place, but I still need the exact address before saving it as a map pin.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveCocoa.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                if !candidate.hasReliableCoordinates {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("Needs Google Places refinement or a map link before this can be saved.")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.saveCocoa)
                }

                HStack(spacing: 8) {
                    CandidateActionButton(
                        title: "Confirm",
                        systemImage: "checkmark.seal",
                        fill: Color.saveSky.opacity(0.54),
                        disabled: isWorking,
                        action: onConfirm
                    )
                    CandidateActionButton(
                        title: candidate.hasReliableCoordinates ? "Save" : "Find + Save",
                        systemImage: "seal",
                        fill: .saveHoney,
                        disabled: isWorking,
                        action: onSave
                    )
                    CandidateActionButton(
                        title: "Not this",
                        systemImage: "xmark",
                        fill: .saveNotebookPage,
                        foreground: .saveSignal,
                        disabled: isWorking,
                        action: onReject
                    )
                }

                reviewCandidateShareLink
            }
            .padding(12)
        }
        .saveNotebookPage(cornerRadius: 16)
        .opacity(isWorking ? 0.65 : 1)
    }

    @ViewBuilder
    private var reviewCandidateShareLink: some View {
        if let url = candidate.saveShareURL {
            ShareLink(item: url, subject: Text(candidate.shareSubject), message: Text(candidate.shareText)) {
                reviewCandidateShareLabel
            }
        } else {
            ShareLink(item: candidate.shareText, subject: Text(candidate.shareSubject)) {
                reviewCandidateShareLabel
            }
        }
    }

    private var reviewCandidateShareLabel: some View {
        Label("Share candidate", systemImage: "square.and.arrow.up")
            .font(.caption.weight(.black))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color.saveNotebookPage)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct UnsavedMapCandidateCard: View {
    var candidate: SaveMapCandidate
    var isWorking: Bool
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            NotebookSpine(color: .saveSignal)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 11) {
                    SaveMemoryBadge(state: .ready, size: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("UNSAVED CANDIDATE")
                            .font(.caption2.weight(.black))
                            .foregroundColor(.saveCocoa)
                            .lineLimit(1)

                        Text(candidate.title)
                            .font(.headline)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)
                            .lineLimit(2)

                        Text(candidate.subtitle)
                            .font(.caption)
                            .foregroundColor(.saveCocoa.opacity(0.74))
                            .lineLimit(3)

                        HStack(spacing: 6) {
                            StampChip(text: candidate.category?.displayName ?? "Place", color: .saveHoney)
                            StampChip(text: "not saved", color: .saveSky)
                        }
                    }

                    Spacer(minLength: 0)
                }

                Text("This is a map result, not one of your SAV-E memories yet. Save it only after it looks like the place you want.")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveCocoa.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                UnsavedMapCandidateVisualPreview(candidate: candidate)

                UnsavedMapCandidateBasicInfo(candidate: candidate)
                UnsavedMapCandidateSummaryPanel(candidate: candidate)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2.weight(.bold))
                        Text("Source")
                            .font(.caption2.weight(.black))
                        Spacer()
                    }
                    .foregroundColor(.saveCocoa)

                    Text("Found from map search. It is not a Map Stamp or memory until you save it.")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.saveCocoa.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)

                    EvidenceLinkList(evidence: sourceEvidence, maxItems: 4)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.saveSky.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.saveNotebookLine, style: StrokeStyle(lineWidth: 1, dash: [4]))
                        )
                )

                HStack(spacing: 8) {
                    CandidateActionButton(
                        title: isWorking ? "Saving" : "Save",
                        systemImage: "bookmark.badge.plus",
                        fill: .saveHoney,
                        disabled: isWorking,
                        action: onSave
                    )

                    ShareLink(item: candidate.saveShareURL ?? URL(string: "https://sav-e-app.vercel.app")!, subject: Text(candidate.shareSubject), message: Text(candidate.shareText)) {
                        CandidateActionLabel(
                            title: "Share",
                            systemImage: "square.and.arrow.up",
                            fill: .saveNotebookPage
                        )
                    }

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
            }
            .padding(12)
        }
        .saveNotebookPage(cornerRadius: 16)
        .opacity(isWorking ? 0.65 : 1)
    }

    private var sourceEvidence: [String] {
        let fallback = [
            "Found in map search",
            "Unsaved until you tap Save",
            "Source: Apple Maps"
        ]
        let cleaned = candidate.evidence.compactMap(cleanMapEvidenceLine)
        return cleaned.isEmpty ? fallback : cleaned
    }

    private func cleanMapEvidenceLine(_ line: String) -> String? {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.localizedCaseInsensitiveCompare("Apple Maps POI") == .orderedSame {
            return "Selected from Apple Maps"
        }
        if value.localizedCaseInsensitiveCompare("Apple Maps result") == .orderedSame {
            return "Found in Apple Maps nearby search"
        }
        if value.localizedCaseInsensitiveContains("POI:") ||
            value.localizedCaseInsensitiveContains("MKPOICategory") {
            return nil
        }
        return value
    }

}

private struct UnsavedMapCandidateBasicInfo: View {
    var candidate: SaveMapCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption.weight(.black))
                Text("Basic info")
                    .font(.caption.weight(.black))
                Spacer()
            }
            .foregroundColor(.saveCocoa)

            VStack(spacing: 7) {
                UnsavedMapCandidateInfoRow(icon: "star", title: "Rating", value: ratingText)
                if let reviewText {
                    UnsavedMapCandidateInfoRow(icon: "text.bubble", title: "Reviews", value: reviewText)
                }
                if let hoursText {
                    UnsavedMapCandidateInfoRow(icon: "clock", title: "Hours", value: hoursText)
                }
                if let distanceText = candidate.distanceLabel {
                    UnsavedMapCandidateInfoRow(icon: "location", title: "Distance", value: distanceText)
                }
                UnsavedMapCandidateInfoRow(icon: candidate.category?.outlineIconName ?? "mappin", title: "Category", value: candidate.category?.displayName ?? "Place")
                UnsavedMapCandidateInfoRow(icon: "mappin", title: "Address", value: candidate.subtitle)
                UnsavedMapCandidateInfoRow(icon: "map", title: "Source", value: "Map search")
            }
        }
        .padding(10)
        .background(Color.saveSky.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.56), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var ratingText: String {
        guard let rating = candidate.rating else { return "No rating yet" }
        return String(format: "%.1f", rating)
    }

    private var reviewText: String? {
        candidate.reviewCount.map { "\($0) reviews" }
    }

    private var hoursText: String? {
        candidate.evidence.compactMap { evidence -> String? in
            guard let range = evidence.range(of: "Hours:", options: [.caseInsensitive]) else { return nil }
            let value = evidence[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }.first
    }
}

private struct UnsavedMapCandidateSummaryPanel: View {
    var candidate: SaveMapCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.caption.weight(.black))
                Text("Quick take")
                    .font(.caption.weight(.black))
                Spacer()
            }
            .foregroundColor(.saveCocoa)

            VStack(alignment: .leading, spacing: 7) {
                UnsavedMapCandidateSummaryLine(icon: candidate.category?.outlineIconName ?? "mappin", text: candidateSummary)
                if let distanceSummary {
                    UnsavedMapCandidateSummaryLine(icon: "location", text: distanceSummary)
                }
                if let reviewSummary {
                    UnsavedMapCandidateSummaryLine(icon: "star", text: reviewSummary)
                }
                if let practicalInfo {
                    UnsavedMapCandidateSummaryLine(icon: "mappin", text: practicalInfo)
                }
                UnsavedMapCandidateSummaryLine(icon: "bookmark", text: saveReminder)
            }
        }
        .padding(10)
        .background(Color.saveNotebookPage.opacity(0.62))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.56), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var candidateSummary: String {
        let category = candidate.category?.displayName.lowercased() ?? "place"
        if let searchQuery {
            return "\(candidate.title) matches your \(searchQuery) search as an unsaved \(category)."
        }
        if !candidate.shareAreaLabel.isEmpty {
            return "\(candidate.title) is an unsaved \(category) in \(candidate.shareAreaLabel)."
        }
        return "\(candidate.title) is an unsaved \(category) selected from the map."
    }

    private var distanceSummary: String? {
        candidate.distanceLabel.map { "About \($0) from your search area." }
    }

    private var practicalInfo: String? {
        let address = candidate.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address != "Nearby unsaved place", address != "Selected on map" else {
            return nil
        }
        return address
    }

    private var reviewSummary: String? {
        var parts: [String] = []
        if let rating = candidate.rating {
            parts.append(String(format: "%.1f", rating))
        }
        if let reviewCount = candidate.reviewCount {
            parts.append("\(reviewCount) reviews")
        }
        return parts.isEmpty ? nil : "Public rating \(parts.joined(separator: " · "))."
    }

    private var saveReminder: String {
        "Save only after the photo, address, and map pin match the place you want."
    }

    private var searchQuery: String? {
        candidate.evidence.compactMap { line -> String? in
            guard let range = line.range(of: "Search:", options: [.caseInsensitive]) else {
                return nil
            }
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }.first
    }
}

private struct UnsavedMapCandidateSummaryLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            UnsavedMapCandidateRowIcon(icon: icon, fill: Color.saveNotebookPage.opacity(0.72))
                .padding(.top, 1)

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct UnsavedMapCandidateInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            UnsavedMapCandidateRowIcon(icon: icon, fill: Color.saveCream.opacity(0.74))
                .padding(.top, 1)

            Text(title)
                .font(.caption2.weight(.black))
                .foregroundColor(.saveCocoa)
                .frame(width: 58, alignment: .leading)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct UnsavedMapCandidateRowIcon: View {
    let icon: String
    var fill: Color

    var body: some View {
        Image(systemName: icon)
            .font(.caption2.weight(.bold))
            .foregroundColor(.saveCocoa)
            .frame(width: 22, height: 22)
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(0.54), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct UnsavedMapCandidateVisualPreview: View {
    var candidate: SaveMapCandidate

    var body: some View {
        PlaceBusinessPhotoCarousel(imageURLs: candidate.businessPhotoURLStrings)
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
        .accessibilityLabel("Open SAV-E Passport")
    }
}

private struct DrawerActionChip: View {
    @Environment(\.colorScheme) private var colorScheme
    var title: String
    var systemImage: String
    var count: Int?
    var fill: Color = Color.saveHoney.opacity(0.84)
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .frame(width: 16)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                if let count {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.saveMint)
                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(colorScheme == .dark ? .white : .saveInk)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(fill)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(0.34), lineWidth: 1.1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct SavedCategoryLensRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let category: PlaceCategory
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: category.iconName)
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)
                    .frame(width: 34, height: 34)
                    .background(Color.saveStampColor(for: category).opacity(isSelected ? 0.82 : 0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(primaryText)
                    Text(isSelected ? "Showing on map" : "Tap to filter map")
                        .font(.caption2)
                        .foregroundColor(secondaryText)
                }

                Spacer()

                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundColor(primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.24))
                    .clipShape(Capsule())

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(isSelected ? primaryText : secondaryText.opacity(0.68))
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(isSelected ? Color.saveHoney.opacity(0.26) : Color.white.opacity(0.10))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(isSelected ? 0.36 : 0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .saveInk
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.68) : Color.saveCocoa.opacity(0.70)
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
    var onFollowUp: () -> Void
    var onNewQuestion: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onFollowUp) {
                Label("Follow up", systemImage: "text.bubble")
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
                Label("New", systemImage: "plus.bubble")
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
                    .background(isPrimary ? Color.saveHoney : tone.color.opacity(0.42))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.4)
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
                    .fill(isPrimary ? Color.saveHoney.opacity(0.72) : Color.saveNotebookPage.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 2)
                    )
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
}

private struct AgentCommandCard: View {
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
                        .background(tone.color.opacity(0.42))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 1.2)
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
                    .fill(Color.saveNotebookPage.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 2)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
