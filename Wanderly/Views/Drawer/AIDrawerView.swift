import SwiftUI
import UIKit

struct AIDrawerView: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
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
    var onImportURLAsReviewCandidates: (URL) async throws -> Int = { _ in 0 }
    @FocusState private var searchFocused: Bool
    @State private var showGoogleTakeoutImport = false
    @State private var addSpotStatus: String?
    @State private var candidateActionInFlight: UUID?
    @State private var showReviewInbox = false
    @State private var isImportingURL = false

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if showsContentArea {
                Divider().opacity(0.35)
                contentArea
            }
        }
        .background(SaveDottedBackground())
        .sheet(isPresented: $viewModel.showPlaceList) {
            PlaceListView()
        }
        .sheet(isPresented: $showGoogleTakeoutImport) {
            GoogleTakeoutImportView(
                existingPlaces: existingPlacesForImport,
                onSave: onSaveGoogleTakeoutImport
            )
        }
        .onChange(of: viewModel.drawerState) { _, state in
            withAnimation(.spring(duration: 0.3)) {
                switch state {
                case .idle:             drawerDetent = .height(72)
                case .loading:          drawerDetent = .medium
                case .error:            drawerDetent = .medium
                case .placeDetail:      drawerDetent = .medium
                case .reviewCandidateDetail: drawerDetent = .medium
                case .displaying(let r):
                    drawerDetent = r.componentType == .tripItinerary ? .large : .medium
                }
            }
        }
        .onChange(of: drawerDetent) { _, detent in
            guard case .idle = viewModel.drawerState else { return }
            if detent != .height(72) {
                searchFocused = true
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: isLoading ? "hourglass" : "sparkles")
                .foregroundColor(.saveInk)
                .font(.caption.weight(.black))
                .frame(width: 28, height: 28)
                .background(Color.saveCream)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .symbolEffect(.pulse, isActive: isLoading)

            TextField(languageSettings.text(.askPlaceholder), text: $viewModel.query)
                .font(.subheadline)
                .foregroundColor(.saveInk)
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
                    Image(systemName: "xmark.circle.fill").foregroundColor(.saveCocoa.opacity(0.72))
                }
            } else if !viewModel.query.isEmpty {
                Button(action: {
                    viewModel.returnToCommands()
                    showReviewInbox = false
                    searchFocused = true
                    withAnimation { drawerDetent = .medium }
                }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.saveCocoa.opacity(0.72))
                }
            } else if !reviewCandidates.isEmpty {
                Button(action: openReviewInbox) {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist.unchecked")
                        Text("\(reviewCandidates.count)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.saveHoney)
                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1.4))
                    .clipShape(Capsule())
                }
                .accessibilityLabel(languageSettings.text(.openReviewCandidates))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(Color.saveNotebookPage)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(height: 72)
        .background(Color.saveNotebookPage)
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

        case .placeDetail(let place):
            PlaceBottomSheet(place: place) {
                try await onDeletePlace(place)
                viewModel.removePlace(place)
                withAnimation(.spring(duration: 0.3)) {
                    drawerDetent = .height(72)
                }
            }

        case .reviewCandidateDetail(let candidate):
            ScrollView {
                ReviewCandidateCard(
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
        .background(Color.saveNotebookPage.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.saveNotebookLine)
                .frame(height: 2)
        }
    }

    private var showsNavigationHeader: Bool {
        switch viewModel.drawerState {
        case .idle:
            return false
        case .loading, .displaying, .placeDetail, .reviewCandidateDetail, .error:
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
        case .placeDetail(let place):
            return place.name
        case .reviewCandidateDetail(let candidate):
            return candidate.name
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
        case .placeDetail:
            return languageSettings.text(.placeDetailSubtitle)
        case .reviewCandidateDetail(let candidate):
            return candidate.hasReliableCoordinates ? "Map-ready Review Candidate" : "Needs address confirmation"
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

    // MARK: - Idle suggestions

    private var suggestionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        DrawerActionChip(
                            title: "Memories",
                            systemImage: "list.bullet",
                            count: nil,
                            fill: Color.saveMint.opacity(0.74),
                            action: { viewModel.showPlaceList = true }
                        )

                        DrawerActionChip(
                            title: "Import",
                            systemImage: "tray.and.arrow.down",
                            count: nil,
                            fill: Color.saveSky.opacity(0.64),
                            action: { showGoogleTakeoutImport = true }
                        )

                        DrawerActionChip(
                            title: "Review",
                            systemImage: "circle.hexagongrid.fill",
                            count: reviewCandidates.isEmpty ? nil : reviewCandidates.count,
                            fill: Color.saveHoney.opacity(0.84),
                            action: openReviewInbox
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .padding(.top, 14)

                addSpotsHub

                if !viewModel.chatHistory.isEmpty {
                    NotebookBandLabel("Recent")
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    ForEach(viewModel.chatHistory.prefix(5)) { entry in
                        Button(action: {
                            viewModel.query = entry.query
                            Task { await viewModel.submit() }
                        }) {
                            DrawerSuggestionRow(icon: "clock.arrow.circlepath", text: entry.query)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }

                NotebookBandLabel("Try asking")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                ForEach(suggestions, id: \.self) { suggestion in
                    Button(action: {
                        viewModel.query = suggestion
                        Task { await viewModel.submit() }
                    }) {
                        DrawerSuggestionRow(icon: "arrow.up.left", text: suggestion)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private let suggestions = [
        "Show my food spots on the map",
        "Navigate to the nearest cafe",
        "Plan a day from my Map Stamps",
        "What haven't I visited yet?",
    ]

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
                actionInFlight: candidateActionInFlight,
                onConfirm: { candidate in
                    performCandidateAction(candidate, successMessage: "Place confirmed. Save it when the address is ready.") {
                        try await onConfirmCandidate(candidate)
                    }
                },
                onReject: { candidate in
                    performCandidateAction(candidate, successMessage: "Review Candidate cleared.") {
                        try await onRejectCandidate(candidate)
                    }
                },
                onSave: { candidate in
                    performCandidateAction(candidate, successMessage: saveFeedback(for: candidate)) {
                        try await onSaveCandidate(candidate)
                    }
                }
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
                    actionInFlight: candidateActionInFlight,
                    onConfirm: { candidate in
                        performCandidateAction(candidate, successMessage: "Place confirmed. Save it when the address is ready.") {
                            try await onConfirmCandidate(candidate)
                        }
                    },
                    onReject: { candidate in
                        performCandidateAction(candidate, successMessage: "Review Candidate cleared.") {
                            try await onRejectCandidate(candidate)
                        }
                    },
                    onSave: { candidate in
                        performCandidateAction(candidate, successMessage: saveFeedback(for: candidate)) {
                            try await onSaveCandidate(candidate)
                        }
                    }
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

    private func submitSearchField() {
        if let url = firstURL(in: viewModel.query) {
            importURLToReviewCandidates(url)
        } else {
            Task { await viewModel.submit() }
        }
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
    var actionInFlight: UUID?
    var onConfirm: (PlaceReviewCandidate) -> Void
    var onReject: (PlaceReviewCandidate) -> Void
    var onSave: (PlaceReviewCandidate) -> Void

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
                    ReviewCandidateCard(
                        candidate: candidate,
                        isWorking: actionInFlight == candidate.id,
                        onConfirm: { onConfirm(candidate) },
                        onReject: { onReject(candidate) },
                        onSave: { onSave(candidate) }
                    )
                }
            }
        }
    }

    private var displayedCandidates: [PlaceReviewCandidate] {
        guard let limit else { return candidates }
        return Array(candidates.prefix(limit))
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

private struct ReviewCandidateCard: View {
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
                        Text(candidate.hasReliableCoordinates ? "MAP READY" : "POSSIBLE PLACE FOUND")
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
                            StampChip(text: candidate.hasReliableCoordinates ? "maybe · map ready" : "maybe · 1 clue missing", color: .saveHoney)
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
            }
            .padding(12)
        }
        .saveNotebookPage(cornerRadius: 16)
        .opacity(isWorking ? 0.65 : 1)
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
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .fontWeight(.black)
                .foregroundColor(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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
