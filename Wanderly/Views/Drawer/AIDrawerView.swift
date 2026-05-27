import SwiftUI
import UIKit
import AVFoundation
import Speech

struct AIDrawerView: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: AIDrawerViewModel
    @Binding var drawerDetent: PresentationDetent
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
    var onImportURLAsReviewCandidates: (URL) async throws -> Int = { _ in 0 }
    var onPrepareMapSearch: (String) async -> [SaveMapCandidate] = { _ in [] }
    var selectedCategories: Set<PlaceCategory> = []
    var onToggleCategory: (PlaceCategory) -> Void = { _ in }
    var onOpenPassport: () -> Void = {}
    @FocusState private var searchFocused: Bool
    @StateObject private var voiceQuery = VoiceQueryController()
    @State private var showGoogleTakeoutImport = false
    @State private var addSpotStatus: String?
    @State private var candidateActionInFlight: UUID?
    @State private var mapCandidateActionInFlight: String?
    @State private var showReviewInbox = false
    @State private var isImportingURL = false
    @State private var showProfile = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if showsContentArea {
                Divider().opacity(colorScheme == .dark ? 0.18 : 0.28)
                contentArea
            }
        }
        .background {
            DrawerGlassBackground(colorScheme: colorScheme)
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
            ProfileView(waitingClues: reviewCandidates.count)
        }
        .onChange(of: viewModel.drawerState) { _, state in
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
        .background(commandBarFill)
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
        colorScheme == .dark ? Color.black.opacity(0.34) : Color.white.opacity(0.44)
    }

    private var commandIconFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.48)
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
                showReviewInbox = false
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
                reviewCount: reviewCandidates.count,
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
            if showReviewInbox {
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
                        .background(Color.saveNotebookPage)
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
                PlaceBottomSheet(place: place) {
                    try await onDeletePlace(place)
                    viewModel.removePlace(place)
                    withAnimation(.spring(duration: 0.3)) {
                        drawerDetent = .height(72)
                    }
                } onPlanAround: {
                    viewModel.query = "Plan around \(place.name)"
                    Task { await viewModel.submit() }
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
                            showReviewInbox = true
                        }
                    },
                    onSave: {
                        performCandidateAction(candidate, successMessage: saveFeedback(for: candidate)) {
                            try await onSaveCandidate(candidate)
                            viewModel.returnToCommands()
                            showReviewInbox = false
                        }
                    }
                )
                .padding(14)
            }

        case .mapCandidateDetail(let candidate):
            ScrollView {
                UnsavedMapCandidateCard(
                    candidate: candidate,
                    isWorking: mapCandidateActionInFlight == candidate.id,
                    onSave: {
                        performMapCandidateAction(candidate) {
                            try await onSaveMapCandidate(candidate)
                            viewModel.returnToCommands()
                            showReviewInbox = false
                        }
                    }
                )
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
                showReviewInbox = false
                searchFocused = false
                withAnimation { drawerDetent = .medium }
            }) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .frame(width: 32, height: 32)
                    .background(Color.saveNotebookPage)
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
                showReviewInbox = false
                searchFocused = false
                withAnimation { drawerDetent = .height(72) }
            }) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.saveCocoa.opacity(0.72))
                    .frame(width: 30, height: 30)
                    .background(Color.saveNotebookPage)
                    .overlay(
                        Circle()
                            .stroke(Color.saveNotebookLine, lineWidth: 2)
                    )
                    .clipShape(Circle())
            }
            .accessibilityLabel(languageSettings.text(.closeDrawerContent))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(navigationHeaderTint)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.13) : Color.saveNotebookLine.opacity(0.18))
                .frame(height: 1)
        }
    }

    private var navigationHeaderTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.26) : Color.saveCream.opacity(0.18)
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

    private var showsContentArea: Bool {
        if case .idle = viewModel.drawerState, drawerDetent == .height(72), !showReviewInbox { return false }
        return true
    }

    private var hasActiveDrawerContent: Bool {
        switch viewModel.drawerState {
        case .idle:
            return showReviewInbox
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
                    title: "Saved",
                    systemImage: "list.bullet",
                    count: viewModel.places.isEmpty ? nil : viewModel.places.count,
                    fill: Color.saveMint.opacity(0.74),
                    action: { viewModel.showPlaceList = true }
                )

                DrawerActionChip(
                    title: "Review",
                    systemImage: "checklist.unchecked",
                    count: reviewCandidates.isEmpty ? nil : reviewCandidates.count,
                    fill: Color.saveHoney.opacity(0.84),
                    action: openReviewInbox
                )
            }
            .padding(.horizontal, 16)

            HStack(spacing: 9) {
                DrawerActionChip(
                    title: "Import",
                    systemImage: "tray.and.arrow.down",
                    count: nil,
                    fill: Color.saveSky.opacity(0.64),
                    action: { showGoogleTakeoutImport = true }
                )

                DrawerActionChip(
                    title: "Plan",
                    systemImage: "map.fill",
                    count: nil,
                    fill: Color.saveSignal.opacity(0.56),
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
                        showReviewInbox = false
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

    private func focusAgentPrompt(_ prompt: String) {
        showReviewInbox = false
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
        showReviewInbox = true
        searchFocused = false
        withAnimation { drawerDetent = .large }
    }

    private func openReviewCandidateDetail(_ candidate: PlaceReviewCandidate) {
        showReviewInbox = false
        searchFocused = false
        viewModel.showReviewCandidate(candidate)
        withAnimation { drawerDetent = .medium }
    }

    private func submitSearchField() {
        voiceQuery.stop()
        searchFocused = false
        if let url = firstURL(in: viewModel.query) {
            importURLToReviewCandidates(url)
        } else {
            Task { await viewModel.submit() }
        }
    }

    private func searchNearbyUnsavedCandidates(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.query = trimmed
        addSpotStatus = "Looking for nearby unsaved candidates. Your SAV-E results stay separate."
        withAnimation { drawerDetent = .medium }

        Task {
            let candidates = await onPrepareMapSearch(trimmed)
            if candidates.isEmpty {
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
        showReviewInbox = false
        searchFocused = false
        withAnimation { drawerDetent = .height(72) }
    }

    private func importURLToReviewCandidates(_ url: URL) {
        guard !isImportingURL else { return }
        showReviewInbox = false
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
}

private struct DrawerGlassBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
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
                Color.black.opacity(0.20),
                Color.black.opacity(0.32)
            ]
        }
        return [
            Color.white.opacity(0.16),
            Color.saveCream.opacity(0.26)
        ]
    }

    private var topStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.58)
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

                if !candidate.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.caption2.weight(.bold))
                            Text("Evidence receipt")
                                .font(.caption2.weight(.black))
                            Spacer()
                        }
                        .foregroundColor(.saveCocoa)

                        EvidenceLinkList(evidence: candidate.evidence, maxItems: 3)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.saveHoney.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.saveNotebookLine, style: StrokeStyle(lineWidth: 1, dash: [4]))
                            )
                    )
                }

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

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2.weight(.bold))
                        Text("Map clue")
                            .font(.caption2.weight(.black))
                        Spacer()
                    }
                    .foregroundColor(.saveCocoa)

                    Text("Map clue means this came from a map search result. It is not a Map Stamp or memory until you save it.")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.saveCocoa.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)

                    EvidenceLinkList(evidence: mapClueEvidence, maxItems: 4)
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

                    ShareLink(item: candidate.saveShareURL ?? candidate.appleMapsURL ?? URL(string: "https://wanderly.app")!, subject: Text(candidate.shareSubject), message: Text(candidate.shareText)) {
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

    private var mapClueEvidence: [String] {
        let fallback = [
            "Visible map result; not a SAV-E memory",
            "State: unsaved candidate",
            "Source: Maps result"
        ]
        return candidate.evidence.isEmpty ? fallback : candidate.evidence
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
                UnsavedMapCandidateInfoRow(icon: "star.fill", title: "Rating", value: ratingText)
                if let reviewText {
                    UnsavedMapCandidateInfoRow(icon: "text.bubble.fill", title: "Reviews", value: reviewText)
                }
                UnsavedMapCandidateInfoRow(icon: candidate.category?.iconName ?? "mappin.and.ellipse", title: "Category", value: candidate.category?.displayName ?? "Place")
                UnsavedMapCandidateInfoRow(icon: "mappin.and.ellipse", title: "Address", value: candidate.subtitle)
                UnsavedMapCandidateInfoRow(icon: "map.fill", title: "Source", value: "Map clue")
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
}

private struct UnsavedMapCandidateInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 16)
                .padding(.top, 2)

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

private struct UnsavedMapCandidateVisualPreview: View {
    var candidate: SaveMapCandidate

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let photoURL = candidate.photoURL.flatMap(URL.init(string:)) {
                    AsyncImage(url: photoURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            fallbackVisual
                        case .empty:
                            ProgressView()
                                .tint(.saveInk)
                        @unknown default:
                            fallbackVisual
                        }
                    }
                } else {
                    fallbackVisual
                }
            }
            .frame(height: 138)
            .frame(maxWidth: .infinity)
            .clipped()

            HStack(spacing: 6) {
                Image(systemName: candidate.photoURL == nil ? "photo" : "camera.fill")
                    .font(.caption2.weight(.black))
                Text(candidate.photoURL == nil ? "No business photo available" : "Business photo")
                    .font(.caption2.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundColor(.saveInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.saveNotebookPage.opacity(0.9))
            .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
            .clipShape(Capsule())
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.2)
        )
    }

    private var fallbackVisual: some View {
        Rectangle()
            .fill(Color.saveNotebookPage)
            .overlay {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.saveCocoa.opacity(0.66))
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
    var reviewCount: Int
    var fill: Color
    var stroke: Color
    var foreground: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3.weight(.black))
                    .foregroundColor(foreground)

                if reviewCount > 0 {
                    Text("\(reviewCount)")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.saveInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.saveHoney)
                        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.7), lineWidth: 1))
                        .clipShape(Capsule())
                        .frame(maxWidth: 24)
                        .offset(x: 12, y: -12)
                }
            }
            .frame(width: 30, height: 30)
            .background(fill)
            .overlay(Circle().stroke(stroke, lineWidth: 1))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open SAV-E Passport")
        .accessibilityValue(reviewCount > 0 ? "\(reviewCount) waiting clues" : "No waiting clues")
    }
}

private struct DrawerActionChip: View {
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
            .foregroundColor(.saveInk)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .background(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct DrawerSuggestionRow: View {
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
                .foregroundColor(.saveInk)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.black))
                .foregroundColor(.saveCocoa.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.saveNotebookPage.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.1)
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
