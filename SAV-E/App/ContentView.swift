import SwiftUI

private enum SaveRootSurface {
    case inbox
    case map
}

struct ContentView: View {
    @StateObject private var mapVM = MapViewModel()
    @StateObject private var drawerVM = AIDrawerViewModel()
    @Binding private var incomingPlaceReceipt: SharedPlaceReceiptDestination?
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenMapTour") private var hasSeenMapTour = false
    @State private var rootSurface: SaveRootSurface
    @State private var drawerDetent: PresentationDetent = .height(88)
    @State private var mapDetailDrawerItem: MapDetailDrawerItem?

    init(incomingPlaceReceipt: Binding<SharedPlaceReceiptDestination?> = .constant(nil)) {
        _incomingPlaceReceipt = incomingPlaceReceipt
        _rootSurface = State(initialValue: incomingPlaceReceipt.wrappedValue == nil ? .map : .inbox)
    }

    var body: some View {
        Group {
            switch rootSurface {
            case .inbox:
                inboxSurface
            case .map:
                mapSurface
            }
        }
        .environment(\.appLanguageSettings, languageSettings)
        .alert(
            languageSettings.localized(english: "Saved on this phone only", traditionalChinese: "只存在這支手機上"),
            isPresented: Binding(
                get: { mapVM.syncFailedPlaceName != nil },
                set: { if !$0 { mapVM.syncFailedPlaceName = nil } }
            )
        ) {
            Button(languageSettings.text(.ok)) { mapVM.syncFailedPlaceName = nil }
        } message: {
            Text(languageSettings.localized(
                english: "\"\(mapVM.syncFailedPlaceName ?? "")\" couldn't sync to your account — check your connection. It stays saved locally.",
                traditionalChinese: "「\(mapVM.syncFailedPlaceName ?? "")」沒能同步到你的帳號——請檢查網路。它仍保存在本機。"
            ))
        }
        .sheet(item: $incomingPlaceReceipt) { destination in
            FriendShareReceiptView(destination: destination) { receipt in
                try await mapVM.saveSharedPlaceReceipt(receipt)
            }
            .environment(\.appLanguageSettings, languageSettings)
        }
        .onChange(of: drawerVM.mapAction) { _, action in
            if let action { mapVM.apply(action) }
        }
        .onChange(of: incomingPlaceReceipt?.id) { _, receiptID in
            mapDetailDrawerItem = nil
            drawerVM.returnToCommands()
            withAnimation(SaveTheme.Motion.standardSpring) {
                rootSurface = receiptID == nil ? .map : .inbox
                drawerDetent = .height(88)
            }
        }
        .onChange(of: mapVM.selectedPlace) { _, place in
            guard let place else { return }
            openPlaceFromInbox(place)
        }
        .onChange(of: mapVM.selectedReviewCandidate) { _, candidate in
            guard let candidate else { return }
            openCandidateFromInbox(candidate)
        }
        .onChange(of: mapVM.selectedMapCandidate) { _, candidate in
            guard let candidate else { return }
            openMapDetail(.unsavedCandidate(candidate))
        }
        .onChange(of: mapVM.selectedSocialPlace) { _, place in
            guard let place else { return }
            openMapDetail(.socialPlace(place))
        }
        .onChange(of: mapVM.places) { _, places in
            drawerVM.places = places
            refreshSelectedMapDetailPlace(from: places)
        }
        .onChange(of: mapVM.mapCandidates) { _, candidates in
            drawerVM.mapCandidates = candidates
        }
        .onReceive(NotificationCenter.default.publisher(for: SaveCollaborativeListNotification.didJoin)) { _ in
            mapVM.reloadCollaborativeLists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveMemoryPreferencesDidChange)) { _ in
            Task { await drawerVM.loadMemoryPreferences() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await mapVM.handleSceneDidBecomeActive() }
        }
        .task {
            drawerVM.places = mapVM.places
            drawerVM.mapCandidates = mapVM.mapCandidates
            await drawerVM.loadMemoryPreferences()
            await mapVM.loadPlaces()
        }
        .fullScreenCover(isPresented: shouldShowMapTour) {
            MapCoachmarkTour {
                hasSeenMapTour = true
            }
            .environment(\.appLanguageSettings, languageSettings)
            .presentationBackground(.clear)
        }
    }

    private var inboxSurface: some View {
        MemoryInboxView(
            places: mapVM.places,
            reviewCandidates: mapVM.reviewCandidates,
            isLoading: mapVM.isLoading,
            onOpenCandidate: openCandidateFromInbox,
            onOpenPlace: openPlaceFromInbox,
            onOpenMap: openMap,
            onAsk: openAsk,
            onCapture: openAsk
        )
    }

    private var mapSurface: some View {
        MapView(viewModel: mapVM)
            .environment(\.appLanguageSettings, languageSettings)
            .sheet(isPresented: .constant(true)) {
                drawerView
            }
    }

    private var drawerView: some View {
        AIDrawerView(
            viewModel: drawerVM,
            drawerDetent: $drawerDetent,
            mapDetailDrawerItem: $mapDetailDrawerItem,
            existingPlacesForImport: mapVM.places,
            reviewCandidates: mapVM.reviewCandidates,
            onSaveGoogleTakeoutImport: { drafts in
                try await mapVM.saveImportedPlaces(drafts)
            },
            onDeletePlace: { place in
                try await mapVM.deletePlace(place)
            },
            onSaveCandidate: { candidate, nameOverride in
                try await mapVM.saveReviewCandidateAsPlace(candidate, nameOverride: nameOverride)
            },
            onRejectCandidate: { candidate in
                try await mapVM.rejectReviewCandidate(candidate)
            },
            onSaveCandidateAsSourceOnly: { candidate in
                try await mapVM.saveReviewCandidateAsSourceOnly(candidate)
            },
            onMarkCandidateWrongBranch: { candidate in
                try await mapVM.markReviewCandidateWrongBranch(candidate)
            },
            onInvestigateCandidateMore: { candidate in
                try await mapVM.investigateReviewCandidateMore(candidate)
            },
            onSaveMapCandidate: { candidate in
                try await mapVM.saveMapCandidateAsPlace(candidate)
            },
            onUpdatePlaceVisibility: { place, visibility in
                try await mapVM.updatePlaceVisibility(place, visibility: visibility)
            },
            onUpdatePlace: { place in
                try await mapVM.updatePlace(place)
            },
            onImportURLAsReviewCandidates: { url in
                try await mapVM.importURLAsReviewCandidates(url)
            },
            onPrepareMapSearch: { query in
                await mapVM.prepareMapCandidatesForDrawerQuery(query)
            },
            onClearMapSearchResults: {
                mapVM.clearMapSearchResults()
            },
            collaborativeLists: mapVM.collaborativeLists,
            onCreateList: { title, note in
                mapVM.createCollaborativeList(title: title, note: note)
            },
            onAddPlaceToList: { place, listID in
                try mapVM.addPlace(place, toListID: listID)
            },
            onShareListURL: { list, role in
                mapVM.shareURL(for: list, role: role)
            },
            onSaveListItem: { item in
                _ = try await mapVM.saveListItemAsPlace(item)
            },
            onPlanList: { list in
                await mapVM.planCollaborativeList(list)
            },
            socialLens: mapVM.socialLens,
            socialPlaces: mapVM.visibleSocialPlaces,
            onSelectSocialLens: { lens in
                mapVM.selectSocialLens(lens)
            },
            onSaveSocialPlace: { place in
                _ = try await mapVM.saveSocialPlaceToMySave(place)
            },
            onFollowReferral: { value in
                try await mapVM.followReferral(value)
            },
            selectedCategories: mapVM.selectedCategories,
            onToggleCategory: { category in
                mapVM.toggleCategory(category)
            },
            onOpenInbox: returnToInbox,
            onDismissMapDetail: {
                mapVM.clearSelectedMapObject()
            }
        )
        .environment(\.appLanguageSettings, languageSettings)
        .presentationDetents([.height(88), .height(104), .height(160), .fraction(0.34), .fraction(0.38), .medium, .large], selection: $drawerDetent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled(true)
        .presentationBackground(.clear)
        .presentationCornerRadius(32)
    }

    /// First-run gate: the guided tour shows once, the first time the user is
    /// actually on the map (this view only renders post-auth). Setting
    /// `hasSeenMapTour` true on dismissal keeps it from ever showing again.
    private var shouldShowMapTour: Binding<Bool> {
        Binding(
            get: { rootSurface == .map && !hasSeenMapTour },
            set: { if !$0 { hasSeenMapTour = true } }
        )
    }

    private func openMap() {
        mapDetailDrawerItem = nil
        drawerVM.returnToCommands()
        withAnimation(SaveTheme.Motion.standardSpring) {
            rootSurface = .map
            drawerDetent = .height(88)
        }
    }

    private func openAsk() {
        mapDetailDrawerItem = nil
        drawerVM.returnToCommands()
        withAnimation(SaveTheme.Motion.standardSpring) {
            rootSurface = .map
            drawerDetent = .medium
        }
    }

    private func openCandidateFromInbox(_ candidate: PlaceReviewCandidate) {
        openMapDetail(.reviewCandidate(candidate))
    }

    private func openPlaceFromInbox(_ place: Place) {
        openMapDetail(.savedPlace(place))
    }

    private func openMapDetail(_ item: MapDetailDrawerItem) {
        drawerVM.returnToCommands()
        mapDetailDrawerItem = item
        withAnimation(SaveTheme.Motion.standardSpring) {
            rootSurface = .map
            drawerDetent = .fraction(0.38)
        }
    }

    private func returnToInbox() {
        mapVM.clearSelectedMapObject()
        mapDetailDrawerItem = nil
        drawerVM.returnToCommands()
        withAnimation(SaveTheme.Motion.standardSpring) {
            rootSurface = .inbox
            drawerDetent = .height(88)
        }
    }

    private func refreshSelectedMapDetailPlace(from places: [Place]) {
        guard case .savedPlace(let selectedPlace) = mapDetailDrawerItem,
              let updatedPlace = places.first(where: { $0.id == selectedPlace.id }),
              updatedPlace != selectedPlace
        else { return }

        mapDetailDrawerItem = .savedPlace(updatedPlace)
    }
}

private struct FriendShareReceiptView: View {
    private enum LoadState {
        case loading
        case loaded(SharedPlaceReceipt)
        case failed(SharedPlaceReceiptError)
    }

    private enum SaveState {
        case idle
        case saving
        case saved
        case alreadySaved
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.appLanguageSettings) private var languageSettings
    let destination: SharedPlaceReceiptDestination
    let onSave: (SharedPlaceReceipt) async throws -> SharedPlaceSaveOutcome
    @State private var loadState: LoadState = .loading
    @State private var saveState: SaveState = .idle
    @State private var saveErrorMessage: String?
    @State private var retryCount = 0
    @State private var activeLoadID: UUID?
    @State private var activeSaveID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading:
                    loadingView
                case .loaded(let receipt):
                    receiptView(receipt)
                case .failed(let error):
                    errorView(error)
                }
            }
            .navigationTitle(localized("Shared place", "好友分享"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized("Done", "完成")) { dismiss() }
                }
            }
        }
        .task(id: "\(destination.id):\(retryCount)") {
            await loadReceipt()
        }
        .onDisappear {
            activeLoadID = nil
            activeSaveID = nil
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(localized("Verifying this share receipt…", "正在驗證這張分享收據…"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: SharedPlaceReceiptError) -> some View {
        ContentUnavailableView {
            Label(localized("Could not open this place", "無法打開這個地點"), systemImage: "link.badge.plus")
        } description: {
            Text(localized(error.errorDescription ?? "The link is unavailable.", errorMessage(error)))
        } actions: {
            if case .shortLink = destination {
                Button(localized("Try Again", "再試一次")) {
                    retryCount += 1
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func receiptView(_ receipt: SharedPlaceReceipt) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    if let sender = receipt.verifiedSenderLabel {
                        Label(localized("Shared by \(sender)", "由 \(sender) 分享"), systemImage: "person.crop.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.saveCoral)
                            .accessibilityIdentifier("friendShareReceipt.sender")
                    } else {
                        Label(localized("Shared place", "分享的地點"), systemImage: "square.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(receipt.payload.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Color.saveInk)

                    if !receipt.payload.address.isEmpty {
                        Text(receipt.payload.address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(receipt.payload.category)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.saveHoney.opacity(0.35), in: Capsule())
                }

                if let note = receipt.payload.note, !note.isEmpty {
                    receiptSection(
                        title: receipt.verifiedSenderLabel == nil
                            ? localized("Shared note", "分享備註")
                            : localized("Why they shared it", "為什麼推薦這裡"),
                        value: note,
                        icon: "quote.bubble"
                    )
                }

                receiptSection(
                    title: localized("Original source", "原始來源"),
                    value: receipt.payload.sourceLabel,
                    icon: "link"
                )

                if let sourceURL = receipt.payload.safeSourceURL {
                    Link(destination: sourceURL) {
                        Label(localized("Open original source", "打開原始來源"), systemImage: "arrow.up.right.square")
                    }
                    .font(.subheadline.weight(.semibold))
                }

                if receipt.verifiedSenderLabel != nil {
                    Label(
                        localized("Share record verified by SAV-E. Saving stays private.", "分享紀錄已由 SAV-E 驗證；儲存後仍是私人記憶。"),
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await save(receipt) }
                    } label: {
                        Label(saveButtonTitle, systemImage: saveButtonIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.saveCoral)
                    .controlSize(.large)
                    .disabled(saveState != .idle)
                    .accessibilityIdentifier("friendShareReceipt.save")

                    if let saveErrorMessage {
                        Text(saveErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("friendShareReceipt.saveError")
                    }

                    if let mapsURL = receipt.payload.appleMapsURL {
                        Button {
                            openURL(mapsURL)
                        } label: {
                            Label(localized("Open in Maps", "在地圖中打開"), systemImage: "map")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .accessibilityIdentifier("friendShareReceipt.openMaps")
                    }
                }
            }
            .padding(24)
        }
        .background(Color.saveCream.ignoresSafeArea())
    }

    private func receiptSection(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(Color.saveInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.savePaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var saveButtonTitle: String {
        switch saveState {
        case .idle: return localized("Save to my SAV-E", "存到我的 SAV-E")
        case .saving: return localized("Saving…", "儲存中…")
        case .saved: return localized("Saved privately", "已私人儲存")
        case .alreadySaved: return localized("Already saved", "已經存過")
        }
    }

    private var saveButtonIcon: String {
        switch saveState {
        case .idle: return "bookmark"
        case .saving: return "hourglass"
        case .saved: return "checkmark.circle.fill"
        case .alreadySaved: return "checkmark.circle"
        }
    }

    @MainActor
    private func loadReceipt() async {
        let loadID = UUID()
        let expectedDestination = destination
        activeLoadID = loadID
        activeSaveID = nil
        saveState = .idle
        saveErrorMessage = nil
        switch expectedDestination {
        case .embedded(let payload):
            guard activeLoadID == loadID else { return }
            loadState = .loaded(.embedded(payload))
        case .malformed:
            guard activeLoadID == loadID else { return }
            loadState = .failed(.malformedLink)
        case .shortLink(let url):
            loadState = .loading
            do {
                let receipt = try await SharedPlaceReceipt.resolve(from: url)
                guard !Task.isCancelled, activeLoadID == loadID else { return }
                loadState = .loaded(receipt)
                if let code = receipt.code {
                    guard !Task.isCancelled, activeLoadID == loadID else { return }
                    try? await SupabaseService.shared.recordFriendShareEvent(
                        code: code,
                        event: .receiptOpened,
                        failureReason: nil
                    )
                }
            } catch is CancellationError {
                return
            } catch let error as SharedPlaceReceiptError {
                guard !Task.isCancelled, activeLoadID == loadID else { return }
                loadState = .failed(error)
                if let code = SharedPlaceData.shortCode(from: url) {
                    guard !Task.isCancelled, activeLoadID == loadID else { return }
                    try? await SupabaseService.shared.recordFriendShareEvent(
                        code: code,
                        event: .openFailed,
                        failureReason: error.eventFailureReason
                    )
                }
            } catch {
                guard !Task.isCancelled, activeLoadID == loadID else { return }
                loadState = .failed(.invalidResponse)
                if let code = SharedPlaceData.shortCode(from: url) {
                    guard !Task.isCancelled, activeLoadID == loadID else { return }
                    try? await SupabaseService.shared.recordFriendShareEvent(
                        code: code,
                        event: .openFailed,
                        failureReason: .unknown
                    )
                }
            }
        }
    }

    @MainActor
    private func save(_ receipt: SharedPlaceReceipt) async {
        guard saveState == .idle,
              case .loaded(let currentReceipt) = loadState,
              currentReceipt.id == receipt.id
        else { return }
        let saveID = UUID()
        activeSaveID = saveID
        saveState = .saving
        saveErrorMessage = nil
        do {
            let outcome = try await onSave(receipt)
            guard !Task.isCancelled,
                  activeSaveID == saveID,
                  case .loaded(let currentReceipt) = loadState,
                  currentReceipt.id == receipt.id
            else { return }
            saveState = outcome.isDuplicate ? .alreadySaved : .saved
        } catch {
            guard !Task.isCancelled,
                  activeSaveID == saveID,
                  case .loaded(let currentReceipt) = loadState,
                  currentReceipt.id == receipt.id
            else { return }
            saveState = .idle
            saveErrorMessage = localized(
                "Couldn't save this verified share. It may have expired; refresh the receipt and try again.",
                "無法儲存這張已驗證的分享。連結可能已過期；請重新載入收據後再試。"
            )
        }
    }

    private func localized(_ english: String, _ traditionalChinese: String) -> String {
        languageSettings.localized(english: english, traditionalChinese: traditionalChinese)
    }

    private func errorMessage(_ error: SharedPlaceReceiptError) -> String {
        switch error {
        case .malformedLink: return "這個分享連結格式不正確。"
        case .missingAPIConfiguration: return "SAV-E 尚未設定好這個分享服務。"
        case .networkUnavailable: return "請檢查網路後再試一次。"
        case .missingOrExpired: return "這個分享連結不存在或已過期。"
        case .serverUnavailable: return "分享收據暫時無法使用。"
        case .invalidResponse: return "SAV-E 無法驗證這張分享收據。"
        }
    }
}

#Preview {
    ContentView()
        .environment(\.appLanguageSettings, AppLanguageSettings())
}
