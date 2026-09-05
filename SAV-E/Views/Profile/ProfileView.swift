import SwiftUI
import PhotosUI
import UIKit

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showEditProfile = false
    @State private var showLanguageSettings = false
    @State private var showTutorial = false
    @State private var showProPaywall = false
    @State private var showDeleteAccountConfirmation = false
    @State private var draftDisplayName = ""
    @State private var draftAvatarData: Data?
    @State private var localSavedPlaces: [Place] = []
    var savedPlaces: [Place] = []
    var waitingClues: Int = 0
    var collaborativeLists: [SaveCollaborativeList] = []
    var followedFriends: [SaveFollowedFriend] = []
    var isLoadingFollowedFriends = false
    var hasMoreFollowedFriends = false
    var onUpdatePlaceVisibility: (Place, PlaceVisibility) async throws -> Void = { _, _ in }
    var onCreateList: (String, String?) -> Void = { _, _ in }
    var onShareListURL: (SaveCollaborativeList, SaveListRole) -> URL? = { _, _ in nil }
    var onShareListLink: (SaveCollaborativeList, SaveListRole) async -> URL? = { list, role in
        list.shareURL(role: role)
    }
    var onLoadMyReferralURL: () async -> URL? = { nil }
    var onOpenListOnMap: (SaveCollaborativeList) -> Void = { _ in }
    var currentUserID: String?
    var onRefreshLists: () async -> Void = {}
    var onLoadListMembers: (SaveCollaborativeList) async -> [SaveListMemberInfo] = { _ in [] }
    var onRemoveListMember: (SaveListMemberInfo, SaveCollaborativeList) async throws -> Void = { _, _ in }
    var onLoadListShareCodes: (SaveCollaborativeList) async -> [SaveListShareCodeInfo] = { _ in [] }
    var onRevokeListShareCode: (SaveListShareCodeInfo, SaveCollaborativeList) async throws -> Void = { _, _ in }
    var onFollowReferral: (String) async throws -> Void = { _ in }
    var onRefreshFollowedFriends: () async -> Void = {}
    var onSearchFollowedFriends: (String) async -> Void = { _ in }
    var onLoadMoreFollowedFriends: () async -> Void = {}
    var onUnfollowFriend: (SaveFollowedFriend) async throws -> Void = { _ in }
    var onReviewAll: () -> Void = {}
    var onUpdatePlace: (Place) async throws -> Void = { _ in }
    var isRootTab = false
    @State private var opensConnections = false
    @State private var shareFocusPlace: Place?
    @State private var hasSharedInvite = SavePassportInviteShareStore.shared.hasSharedInvite
    @State private var fieldStreak = SavePassportFieldStreakStore.shared.currentStreak
    @State private var hasFieldActionToday = SavePassportFieldStreakStore.shared.hasFieldActionToday
    @State private var visitFocusPlace: Place?
    @State private var isUpdatingVisit = false
    @State private var visitError: String?
    @State private var inviteURLAvailable = false
    private var passportStats: PassportStats {
        PassportStats(profile: viewModel.profile, savedPlaces: passportPlaces, waitingClues: waitingClues)
    }

    private var passportPlaces: [Place] {
        localSavedPlaces
    }

    private var todayMissions: [SavePassportTodayMission] {
        guard isRootTab else { return [] }
        return SavePassportTodayCatalog.missions(
            waitingClues: waitingClues,
            savedPlaces: passportPlaces,
            followedFriends: followedFriends,
            hasSharedInvite: hasSharedInvite,
            inviteURLAvailable: inviteURLAvailable
        )
    }

    private var passportContent: some View {
            ScrollView {
                ScrollViewReader { proxy in
                VStack(spacing: SaveTheme.Spacing.lg) {
                    PassportTopBar(
                        waitingClues: waitingClues,
                        allowsEditing: !PrivyAuthService.shared.isReviewerDemo,
                        showsCloseButton: !isRootTab,
                        onClose: { dismiss() },
                        onEdit: {
                            SaveHaptics.tap()
                            draftDisplayName = viewModel.profile.displayName
                            draftAvatarData = nil
                            showEditProfile = true
                        }
                    )
                    .padding(.horizontal)
                    .padding(
                        .top,
                        isRootTab
                            ? AtlasMetrics.statusBarHeight + SaveTheme.Spacing.sm
                            : SaveTheme.Spacing.lg
                    )

                    PassportHero(
                        profile: viewModel.profile
                    )
                    .padding(.horizontal)
                    .accessibilityIdentifier("profile.cover")

                    if let errorMessage = viewModel.errorMessage {
                        HStack(spacing: SaveTheme.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(errorMessage)
                                .lineLimit(2)
                            Spacer()
                        }
                        .font(SaveTheme.Typography.supporting)
                        .foregroundColor(.saveError)
                        .padding(SaveTheme.Spacing.md)
                        .background(Color.saveError.opacity(0.08))
                        .cornerRadius(SaveTheme.Spacing.md)
                        .padding(.horizontal)
                    }

                    PassportStampSection(stats: passportStats)
                        .accessibilityIdentifier("profile.stampLedger")

                    if !todayMissions.isEmpty {
                        PassportTodayOnSavvyStrip(missions: todayMissions) { missionID in
                            handleTodayMission(missionID, scrollProxy: proxy)
                        }
                    }

                    DisclosureGroup(languageSettings.localized(english: "Field activity", traditionalChinese: "探索紀錄")) {
                        PassportFieldStreakStrip(streak: fieldStreak, hasActionToday: hasFieldActionToday)
                            .accessibilityIdentifier("profile.fieldStreak")
                    }
                    .font(SaveAtlasType.body(14))
                    .tint(SaveAtlasPalette.forest)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("profile.activityDisclosure")

                    VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
                        DisclosureGroup {
                            SettingsRow(
                                icon: "globe.asia.australia",
                                title: languageSettings.text(.language),
                                detail: languageSettings.language.displayName,
                                color: .saveCocoa,
                                accessibilityIdentifier: "profile.language"
                            ) {
                                SaveHaptics.tap()
                                showLanguageSettings = true
                            }

                            if SAVEProAccessPolicy.shouldOfferProFromPassport(
                                hasConfirmedMapStamp: !passportPlaces.isEmpty
                            ) {
                                SettingsRow(
                                    icon: "sparkles",
                                    title: languageSettings.localized(
                                        english: "Savvy Pro",
                                        traditionalChinese: "Savvy Pro"
                                    ),
                                    detail: languageSettings.localized(
                                        english: "Core place memory stays free",
                                        traditionalChinese: "核心地點記憶維持免費"
                                    ),
                                    color: SaveAtlasPalette.lavender,
                                    accessibilityIdentifier: "profile.pro"
                                ) {
                                    SaveHaptics.tap()
                                    showProPaywall = true
                                }
                            }
                        } label: {
                            Text(languageSettings.text(.passportControls))
                                .font(SaveTheme.Typography.eyebrow)
                                .foregroundColor(.saveCocoa)
                        }
                        .padding(.horizontal, SaveTheme.Spacing.xs)
                        .accessibilityIdentifier("profile.controlsDisclosure")

                        SettingsRow(
                            icon: "book.pages",
                            title: languageSettings.localized(english: "How to use Savvy", traditionalChinese: "Savvy 使用教學"),
                            detail: languageSettings.localized(english: "Try a clue, review it, then make a Map Stamp", traditionalChinese: "從線索、確認到地圖章，跟著做一次"),
                            color: SaveAtlasPalette.forest,
                            accessibilityIdentifier: "profile.tutorial"
                        ) {
                            showTutorial = true
                        }

                        NavigationLink {
                            SaveMemoryDebugView(
                                localVaultService: PrivyAuthService.shared.isReviewerDemo
                                    ? ReviewDemoStorage.localVaultService
                                    : .shared
                            )
                        } label: {
                            SettingsRow(
                                icon: "brain.head.profile",
                                title: languageSettings.localized(english: "Memory & Preferences", traditionalChinese: "記憶與偏好"),
                                detail: languageSettings.localized(english: "Inspect and control what Savvy remembers", traditionalChinese: "查看並控制 Savvy 記住的內容"),
                                color: .saveCocoa
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { SaveHaptics.tap() })
                        .accessibilityIdentifier("profile.memoryPreferences")

                        Button {
                            SaveHaptics.tap()
                            opensConnections = true
                        } label: {
                            SettingsRow(
                                icon: "person.2.fill",
                                title: languageSettings.localized(english: "Friends & Lists", traditionalChinese: "朋友與清單"),
                                detail: languageSettings.localized(
                                    english: "Manage people and shared place collections",
                                    traditionalChinese: "管理朋友與共享地點清單"
                                ),
                                color: SaveAtlasPalette.mint
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.connections")

                        SettingsRow(
                            icon: "arrow.right.square",
                            title: languageSettings.text(.signOut),
                            color: .saveError,
                            accessibilityIdentifier: "profile.signOut"
                        ) {
                            SaveHaptics.tap()
                            Task { await viewModel.signOut() }
                        }

                        if !PrivyAuthService.shared.isReviewerDemo {
                            SettingsRow(
                                icon: "trash.fill",
                                title: languageSettings.localized(
                                    english: "Delete Account",
                                    traditionalChinese: "刪除帳號"
                                ),
                                detail: languageSettings.localized(
                                    english: "Permanently delete your account and saved data",
                                    traditionalChinese: "永久刪除帳號與已儲存資料"
                                ),
                                color: .saveError,
                                accessibilityIdentifier: "profile.deleteAccount"
                            ) {
                                SaveHaptics.tap()
                                showDeleteAccountConfirmation = true
                            }
                            .disabled(viewModel.isDeletingAccount)
                        }
                    }
                    .padding(.horizontal, SaveTheme.Spacing.md)
                    .padding(.top, SaveTheme.Spacing.lg)
                    .padding(.bottom, SaveTheme.Spacing.xl)
                    .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(SaveAtlasPalette.line.opacity(0.3)) }
                    .padding(.horizontal)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("profile.controlPocket")

                    PassportCountingRulesPanel(stats: passportStats)

                    PassportVisibilityPanel(
                        places: visibilityPlaces,
                        onUpdate: updatePlaceVisibility
                    )
                    .id("profile.sharingPrivacy")
                }
                .padding(
                    .bottom,
                    isRootTab
                        ? AtlasMetrics.height - 786 + 14
                        : SaveTheme.Spacing.xl
                )
                .padding(.top, 2)
                }
            }
            .background(SaveAtlasPalette.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("profile.root")
            .navigationDestination(isPresented: $opensConnections) {
                connectionsDestination
            }
    }

    var body: some View {
        Group {
            if isRootTab {
                passportContent
            } else {
                NavigationStack { passportContent }
            }
        }
        .task {
            localSavedPlaces = savedPlaces
            refreshFieldStreak()
            hasSharedInvite = SavePassportInviteShareStore.shared.hasSharedInvite
            inviteURLAvailable = await onLoadMyReferralURL() != nil
            await viewModel.loadProfile()
        }
        .onChange(of: savedPlaces) { _, places in
            localSavedPlaces = places
            refreshFieldStreak()
        }
        .onChange(of: opensConnections) { _, isOpen in
            guard !isOpen else { return }
            hasSharedInvite = SavePassportInviteShareStore.shared.hasSharedInvite
        }
        .sheet(item: $shareFocusPlace) { place in
            shareMissionSheet(place)
        }
        .sheet(item: $visitFocusPlace) { place in
            visitMissionSheet(place)
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet(
                displayName: $draftDisplayName,
                avatarURLString: viewModel.profile.avatarUrl,
                selectedAvatarData: $draftAvatarData,
                isSaving: viewModel.isSaving,
                errorMessage: viewModel.errorMessage,
                onCancel: { showEditProfile = false },
                onSave: {
                    let saved = await viewModel.updateProfile(displayName: draftDisplayName, avatarData: draftAvatarData)
                    if saved { showEditProfile = false }
                }
            )
        }
        .fullScreenCover(isPresented: $showTutorial) {
            OnboardingView(isReplay: true) { _ in
                showTutorial = false
            }
        }
        .sheet(isPresented: $showLanguageSettings) {
            LanguageSettingsSheet()
        }
        .sheet(isPresented: $showProPaywall) {
            SaveProPaywallView(trigger: .passport)
        }
        .confirmationDialog(
            languageSettings.localized(
                english: "Permanently delete your account?",
                traditionalChinese: "要永久刪除帳號嗎？"
            ),
            isPresented: $showDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                languageSettings.localized(english: "Delete Account", traditionalChinese: "刪除帳號"),
                role: .destructive
            ) {
                Task { _ = await viewModel.deleteAccount() }
            }
            Button(languageSettings.localized(english: "Cancel", traditionalChinese: "取消"), role: .cancel) {}
        } message: {
            Text(languageSettings.localized(
                english: "This deletes your Savvy account and saved places. This cannot be undone.",
                traditionalChinese: "這會刪除你的 Savvy 帳號與已儲存地點，而且無法復原。"
            ))
        }
    }

    private var localMemoryTitle: String {
        switch languageSettings.language {
        case .english: return "Raw local memory"
        case .traditionalChinese: return "原始本機記憶"
        }
    }

    private var localMemoryDetail: String {
        switch languageSettings.language {
        case .english: return "Captured clue inbox"
        case .traditionalChinese: return "已捕捉線索的收件匣"
        }
    }

    private var visibilityPlaces: [Place] {
        guard let focused = shareFocusPlace else { return passportPlaces }
        return [focused] + passportPlaces.filter { $0.id != focused.id }
    }

    private var connectionsDestination: PassportConnectionsView {
        PassportConnectionsView(
            collaborativeLists: collaborativeLists,
            followedFriends: followedFriends,
            isLoadingFollowedFriends: isLoadingFollowedFriends,
            hasMoreFollowedFriends: hasMoreFollowedFriends,
            onCreateList: onCreateList,
            onShareListURL: onShareListURL,
            onShareListLink: onShareListLink,
            onLoadMyReferralURL: onLoadMyReferralURL,
            onOpenListOnMap: onOpenListOnMap,
            currentUserID: currentUserID,
            onRefreshLists: onRefreshLists,
            onLoadListMembers: onLoadListMembers,
            onRemoveListMember: onRemoveListMember,
            onLoadListShareCodes: onLoadListShareCodes,
            onRevokeListShareCode: onRevokeListShareCode,
            onFollowReferral: onFollowReferral,
            onRefreshFollowedFriends: onRefreshFollowedFriends,
            onSearchFollowedFriends: onSearchFollowedFriends,
            onLoadMoreFollowedFriends: onLoadMoreFollowedFriends,
            onUnfollowFriend: onUnfollowFriend,
            onSharedInvite: markInviteShared
        )
    }

    private func handleTodayMission(
        _ missionID: SavePassportTodayMissionID,
        scrollProxy: ScrollViewProxy
    ) {
        switch missionID {
        case .confirmWaitingClue:
            onReviewAll()
        case .markVisitedStamp:
            visitError = nil
            visitFocusPlace = SavePassportTodayCatalog.firstVisitEligiblePlace(in: passportPlaces)
            withAnimation(SaveTheme.Motion.standardSpring) {
                scrollProxy.scrollTo("profile.stampLedger", anchor: .center)
            }
        case .shareRecommendation:
            shareFocusPlace = SavePassportTodayCatalog.firstShareEligiblePlace(in: passportPlaces)
            withAnimation(SaveTheme.Motion.standardSpring) {
                scrollProxy.scrollTo("profile.sharingPrivacy", anchor: .center)
            }
        case .inviteOrFollowFriend:
            opensConnections = true
        }
    }

    private func markInviteShared() {
        SavePassportInviteShareStore.shared.markShared()
        hasSharedInvite = true
    }

    private func refreshFieldStreak() {
        fieldStreak = SavePassportFieldStreakStore.shared.currentStreak
        hasFieldActionToday = SavePassportFieldStreakStore.shared.hasFieldActionToday
    }

    private func visitMissionSheet(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.md) {
            HStack(spacing: SaveTheme.Spacing.md) {
                PassportIconButton(systemName: "xmark") {
                    SaveHaptics.tap()
                    visitFocusPlace = nil
                }
                .accessibilityLabel(languageSettings.localized(english: "Close", traditionalChinese: "關閉"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(languageSettings.localized(
                        english: "MARK VISITED",
                        traditionalChinese: "標記去過"
                    ))
                    .font(SaveAtlasType.strong(11))
                    .tracking(0.9)
                    .foregroundStyle(SaveAtlasPalette.forest)
                    Text(place.name)
                        .font(SaveAtlasType.body(13))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .lineLimit(2)
                }
            }

            Text(languageSettings.localized(
                english: "Count a real field day by marking one Map Stamp visited.",
                traditionalChinese: "把一個地圖章標成去過，就算進真實的野外連續天。"
            ))
            .font(SaveAtlasType.body(13))
            .foregroundStyle(SaveAtlasPalette.ink)

            Button {
                SaveHaptics.tap()
                isUpdatingVisit = true
                visitError = nil
                Task {
                    defer { isUpdatingVisit = false }
                    var updated = place
                    updated.status = .visited
                    do {
                        try await onUpdatePlace(updated)
                        SavePassportFieldStreakStore.shared.recordFieldAction()
                        refreshFieldStreak()
                        if let index = localSavedPlaces.firstIndex(where: { $0.id == place.id }) {
                            localSavedPlaces[index].status = .visited
                        }
                        visitFocusPlace = nil
                    } catch {
                        visitError = languageSettings.localized(
                            english: "Couldn’t update this place. Please try again.",
                            traditionalChinese: "暫時無法更新這個地點，請再試一次。"
                        )
                    }
                }
            } label: {
                Text(languageSettings.localized(english: "Mark visited", traditionalChinese: "標記去過"))
                    .font(SaveAtlasType.strong(15))
                    .foregroundStyle(SaveAtlasPalette.paper)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(SaveAtlasPalette.coral, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingVisit)
            .accessibilityIdentifier("profile.today.markVisitedConfirm")
            if isUpdatingVisit { ProgressView() }
            if let visitError {
                Text(visitError)
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .accessibilityIdentifier("profile.today.visitError")
            }

            Spacer(minLength: 0)
        }
        .padding(SaveTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SaveDottedBackground().ignoresSafeArea())
        .presentationDetents([.medium])
    }


    private func shareMissionSheet(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.md) {
            HStack(spacing: SaveTheme.Spacing.md) {
                PassportIconButton(systemName: "xmark") {
                    SaveHaptics.tap()
                    shareFocusPlace = nil
                }
                .accessibilityLabel(languageSettings.localized(english: "Close", traditionalChinese: "關閉"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(languageSettings.localized(
                        english: "SHARING & PRIVACY",
                        traditionalChinese: "分享與隱私"
                    ))
                    .font(SaveAtlasType.strong(11))
                    .tracking(0.9)
                    .foregroundStyle(SaveAtlasPalette.forest)
                    Text(languageSettings.localized(
                        english: "Share one Map Stamp",
                        traditionalChinese: "分享一個地圖章推薦"
                    ))
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                }
            }

            PassportVisibilityRow(place: place, onUpdate: updatePlaceVisibility)
            Spacer(minLength: 0)
        }
        .padding(SaveTheme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SaveDottedBackground().ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func updatePlaceVisibility(_ place: Place, visibility: PlaceVisibility) async throws {
        try await onUpdatePlaceVisibility(place, visibility)
        if let index = localSavedPlaces.firstIndex(where: { $0.id == place.id }) {
            localSavedPlaces[index].visibility = visibility
        }
        if shareFocusPlace?.id == place.id {
            shareFocusPlace?.visibility = visibility
        }
    }
}

// MARK: - Passport Connections

private struct PassportConnectionsView: View {
    private enum Section: String, CaseIterable {
        case friends
        case lists
    }

    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.dismiss) private var dismiss

    let collaborativeLists: [SaveCollaborativeList]
    let followedFriends: [SaveFollowedFriend]
    let isLoadingFollowedFriends: Bool
    let hasMoreFollowedFriends: Bool
    let onCreateList: (String, String?) -> Void
    let onShareListURL: (SaveCollaborativeList, SaveListRole) -> URL?
    let onShareListLink: (SaveCollaborativeList, SaveListRole) async -> URL?
    let onLoadMyReferralURL: () async -> URL?
    let onOpenListOnMap: (SaveCollaborativeList) -> Void
    let currentUserID: String?
    let onRefreshLists: () async -> Void
    let onLoadListMembers: (SaveCollaborativeList) async -> [SaveListMemberInfo]
    let onRemoveListMember: (SaveListMemberInfo, SaveCollaborativeList) async throws -> Void
    let onLoadListShareCodes: (SaveCollaborativeList) async -> [SaveListShareCodeInfo]
    let onRevokeListShareCode: (SaveListShareCodeInfo, SaveCollaborativeList) async throws -> Void
    let onFollowReferral: (String) async throws -> Void
    let onRefreshFollowedFriends: () async -> Void
    let onSearchFollowedFriends: (String) async -> Void
    let onLoadMoreFollowedFriends: () async -> Void
    let onUnfollowFriend: (SaveFollowedFriend) async throws -> Void
    var onSharedInvite: () -> Void = {}

    @State private var selectedSection: Section = .friends
    @State private var referralValue = ""
    @State private var friendQuery = ""
    @State private var listTitle = ""
    @State private var listNote = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var myInviteURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: SaveTheme.Spacing.lg) {
                topBar
                sectionPicker

                if selectedSection == .friends {
                    friendsSection
                } else {
                    listsSection
                }
            }
            .padding(.horizontal)
            .padding(.bottom, SaveTheme.Spacing.xl)
        }
        .background(SaveDottedBackground().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard followedFriends.isEmpty else { return }
            await onRefreshFollowedFriends()
        }
        .task {
            guard myInviteURL == nil else { return }
            myInviteURL = await onLoadMyReferralURL()
        }
        // Poll-on-open: server membership/role changes (someone joined, a code
        // was revoked, you were removed) land when the lists section shows.
        .task {
            await onRefreshLists()
        }
        .onChange(of: selectedSection) { _, newSection in
            guard newSection == .lists else { return }
            Task { await onRefreshLists() }
        }
        .accessibilityIdentifier("profile.connections.root")
    }

    private var topBar: some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            PassportIconButton(systemName: "chevron.left") {
                SaveHaptics.tap()
                dismiss()
            }
            .accessibilityLabel(languageSettings.localized(english: "Back to Passport", traditionalChinese: "返回護照"))
            .accessibilityIdentifier("profile.connections.back")

            VStack(alignment: .leading, spacing: 2) {
                Text(languageSettings.localized(english: "PASSPORT CONNECTIONS", traditionalChinese: "護照連線"))
                    .font(SaveAtlasType.strong(11))
                    .tracking(1.1)
                    .foregroundStyle(SaveAtlasPalette.forest)
                Text(languageSettings.localized(
                    english: "People and shared place collections",
                    traditionalChinese: "朋友與共享地點清單"
                ))
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
            }

            Spacer()

            SavePostcardPostmark()
                .scaleEffect(0.68)
                .frame(width: 48, height: 34)
                .opacity(0.66)
        }
        .padding(.top, SaveTheme.Spacing.lg)
    }

    private var sectionPicker: some View {
        HStack(spacing: SaveTheme.Spacing.xs) {
            sectionButton(
                .friends,
                title: languageSettings.localized(english: "Friends", traditionalChinese: "朋友"),
                count: followedFriends.count
            )
            sectionButton(
                .lists,
                title: languageSettings.localized(english: "Lists", traditionalChinese: "清單"),
                count: collaborativeLists.count
            )
        }
        .padding(5)
        .background(SaveAtlasPalette.paper.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.45), lineWidth: 1)
        }
    }

    private func sectionButton(_ section: Section, title: String, count: Int) -> some View {
        Button {
            SaveHaptics.tap()
            selectedSection = section
            errorMessage = nil
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)")
                    .font(SaveAtlasType.strong(11))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(SaveAtlasPalette.paper.opacity(0.72), in: Capsule())
            }
            .font(SaveAtlasType.strong(13))
            .foregroundStyle(SaveAtlasPalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                selectedSection == section ? SaveAtlasPalette.mint.opacity(0.72) : .clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.connections.\(section.rawValue)")
    }

    private var friendsSection: some View {
        VStack(spacing: SaveTheme.Spacing.md) {
            // Hidden while nil (API unconfigured or the referral fetch failed)
            // so there is never a dead share button.
            if let myInviteURL {
                ShareLink(item: myInviteURL) {
                    HStack(spacing: SaveTheme.Spacing.md) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(SaveAtlasPalette.forest)
                            .frame(width: 44, height: 44)
                            .background(SaveAtlasPalette.honey.opacity(0.55), in: SavePostcardSealShape())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(languageSettings.localized(english: "My invite link", traditionalChinese: "我的邀請連結"))
                                .font(SaveAtlasType.strong(15))
                                .foregroundStyle(SaveAtlasPalette.ink)
                            Text(languageSettings.localized(
                                english: "Friends who open it follow you",
                                traditionalChinese: "朋友打開後就會追蹤你"
                            ))
                            .font(SaveAtlasType.body(12))
                            .foregroundStyle(SaveAtlasPalette.muted)
                        }

                        Spacer()

                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(SaveAtlasPalette.forest)
                    }
                    .padding(SaveTheme.Spacing.md)
                    .background(SaveAtlasPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(SaveAtlasPalette.honey.opacity(0.78), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    onSharedInvite()
                })
                .accessibilityIdentifier("profile.connections.myInvite")
            }

            postcardPocket(
                eyebrow: languageSettings.localized(english: "FOLLOW A FRIEND", traditionalChinese: "追蹤朋友"),
                title: languageSettings.localized(english: "Paste their Savvy link", traditionalChinese: "貼上對方的 Savvy 連結")
            ) {
                TextField(
                    languageSettings.localized(english: "Referral link or code", traditionalChinese: "邀請連結或代碼"),
                    text: $referralValue
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(SaveTheme.Spacing.md)
                .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SaveAtlasPalette.line.opacity(0.50), lineWidth: 1)
                }
                .accessibilityIdentifier("profile.connections.referral")

                Button {
                    followFriend()
                } label: {
                    Label(
                        languageSettings.localized(english: "Follow", traditionalChinese: "追蹤"),
                        systemImage: "person.badge.plus"
                    )
                    .font(SaveAtlasType.strong(13))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(SaveAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isWorking || referralValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("profile.connections.follow")
            }

            VStack(spacing: SaveTheme.Spacing.sm) {
                HStack(spacing: SaveTheme.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SaveAtlasPalette.muted)
                    TextField(
                        languageSettings.localized(english: "Search friends", traditionalChinese: "搜尋朋友"),
                        text: $friendQuery
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        Task { await onSearchFollowedFriends(friendQuery) }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(SaveAtlasPalette.forest)
                    }
                    .accessibilityLabel(languageSettings.localized(english: "Search", traditionalChinese: "搜尋"))
                }
                .padding(SaveTheme.Spacing.md)
                .background(SaveAtlasPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(SaveAtlasPalette.line.opacity(0.45), lineWidth: 1)
                }

                if isLoadingFollowedFriends && followedFriends.isEmpty {
                    ProgressView()
                        .tint(SaveAtlasPalette.forest)
                        .padding(.vertical, SaveTheme.Spacing.xl)
                } else if followedFriends.isEmpty {
                    emptyTicket(
                        title: languageSettings.localized(english: "No friends here yet", traditionalChinese: "還沒有朋友"),
                        detail: languageSettings.localized(
                            english: "A friend link keeps this list intentional — it never changes your map automatically.",
                            traditionalChinese: "貼上朋友連結即可追蹤；朋友內容不會自動改動你的地圖。"
                        )
                    )
                } else {
                    ForEach(followedFriends) { friend in
                        friendTicket(friend)
                    }
                }

                if hasMoreFollowedFriends {
                    Button {
                        Task { await onLoadMoreFollowedFriends() }
                    } label: {
                        Text(languageSettings.localized(english: "Load more", traditionalChinese: "載入更多"))
                            .font(SaveAtlasType.strong(13))
                            .foregroundStyle(SaveAtlasPalette.forest)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingFollowedFriends)
                }
            }

            inlineError
        }
    }

    private var listsSection: some View {
        VStack(spacing: SaveTheme.Spacing.md) {
            postcardPocket(
                eyebrow: languageSettings.localized(english: "NEW SHARED LIST", traditionalChinese: "新增共享清單"),
                title: languageSettings.localized(english: "Collect places with people", traditionalChinese: "和朋友一起整理地點")
            ) {
                TextField(
                    languageSettings.localized(english: "List name", traditionalChinese: "清單名稱"),
                    text: $listTitle
                )
                .padding(SaveTheme.Spacing.md)
                .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                TextField(
                    languageSettings.localized(english: "Optional note", traditionalChinese: "備註（可選）"),
                    text: $listNote,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .padding(SaveTheme.Spacing.md)
                .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    let title = listTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return }
                    onCreateList(title, listNote)
                    listTitle = ""
                    listNote = ""
                    SaveHaptics.stamp()
                } label: {
                    Label(
                        languageSettings.localized(english: "Create list", traditionalChinese: "建立清單"),
                        systemImage: "plus"
                    )
                    .font(SaveAtlasType.strong(13))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(SaveAtlasPalette.honey, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(listTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("profile.connections.createList")
            }

            if collaborativeLists.isEmpty {
                emptyTicket(
                    title: languageSettings.localized(english: "No shared lists yet", traditionalChinese: "還沒有共享清單"),
                    detail: languageSettings.localized(
                        english: "Create one here, then add confirmed Map Stamps from their postcard.",
                        traditionalChinese: "在這裡建立，再從地圖章明信片加入已確認地點。"
                    )
                )
            } else {
                ForEach(collaborativeLists) { list in
                    listTicket(list)
                }
            }

            inlineError
        }
    }

    private func postcardPocket<Content: View>(
        eyebrow: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.md) {
            Text(eyebrow)
                .font(SaveAtlasType.strong(10))
                .tracking(1.05)
                .foregroundStyle(SaveAtlasPalette.coral)
            Text(title)
                .font(SaveAtlasType.display(22))
                .foregroundStyle(SaveAtlasPalette.forest)
            content()
        }
        .padding(SaveTheme.Spacing.lg)
        .background {
            SavePostcardScallopedRectangle(depth: 4, pitch: 12)
                .fill(SaveAtlasPalette.kraft.opacity(0.28))
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 4, pitch: 12)
                .stroke(SaveAtlasPalette.kraft.opacity(0.70), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private func friendTicket(_ friend: SaveFollowedFriend) -> some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(width: 48, height: 48)
                .background(SaveAtlasPalette.mint.opacity(0.62), in: SavePostcardSealShape())

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName)
                    .font(SaveAtlasType.strong(15))
                    .foregroundStyle(SaveAtlasPalette.ink)
                if let handle = friend.handleLabel {
                    Text(handle)
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }
            }

            Spacer()

            Button {
                Task { await unfollow(friend) }
            } label: {
                Image(systemName: "person.crop.circle.badge.minus")
                    .foregroundStyle(SaveAtlasPalette.coral)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageSettings.localized(english: "Unfollow", traditionalChinese: "取消追蹤"))
        }
        .padding(SaveTheme.Spacing.md)
        .background(SaveAtlasPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SaveAtlasPalette.mint.opacity(0.72), lineWidth: 1)
        }
    }

    private func listTicket(_ list: SaveCollaborativeList) -> some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(list.title)
                        .font(SaveAtlasType.strong(16))
                        .foregroundStyle(SaveAtlasPalette.forest)
                    Text("\(list.placeCountLabel) · \(list.ownerDisplayName)")
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }
                Spacer()
                Text(list.viewerRole.displayName.uppercased())
                    .font(SaveAtlasType.strong(9))
                    .tracking(0.7)
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(SaveAtlasPalette.mint.opacity(0.62), in: Capsule())
            }

            if let note = list.note, !note.isEmpty {
                Text(note)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .lineLimit(3)
            }

            HStack(spacing: SaveTheme.Spacing.sm) {
                Button {
                    onOpenListOnMap(list)
                } label: {
                    Label(
                        languageSettings.localized(english: "Show on Map", traditionalChinese: "在地圖顯示"),
                        systemImage: "map"
                    )
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("profile.connections.openList")

                ListShareLinkControl(
                    list: list,
                    legacyURL: onShareListURL(list, .viewer),
                    resolve: onShareListLink
                )

                // Members/share-code management only exists server-side, so
                // local-only lists get no dead Manage entry.
                if list.serverBacked {
                    NavigationLink {
                        ListManageView(
                            list: list,
                            currentUserID: currentUserID,
                            onLoadMembers: onLoadListMembers,
                            onRemoveMember: onRemoveListMember,
                            onLoadShareCodes: onLoadListShareCodes,
                            onRevokeShareCode: onRevokeListShareCode
                        )
                    } label: {
                        Label(
                            languageSettings.localized(english: "Manage", traditionalChinese: "管理"),
                            systemImage: "person.2.badge.gearshape"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .simultaneousGesture(TapGesture().onEnded { SaveHaptics.tap() })
                    .accessibilityIdentifier("profile.connections.manageList")
                }
            }
            .font(SaveAtlasType.strong(12))
            .foregroundStyle(SaveAtlasPalette.ink)
            .buttonStyle(.bordered)
            .tint(SaveAtlasPalette.kraft)
        }
        .padding(SaveTheme.Spacing.md)
        .background {
            SavePostcardScallopedRectangle(depth: 3, pitch: 11)
                .fill(SaveAtlasPalette.mint.opacity(0.18))
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 3, pitch: 11)
                .stroke(SaveAtlasPalette.mint.opacity(0.76), lineWidth: 1)
        }
    }

    private func emptyTicket(title: String, detail: String) -> some View {
        VStack(spacing: SaveTheme.Spacing.sm) {
            Image(systemName: "envelope.open")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(SaveAtlasPalette.kraft)
            Text(title)
                .font(SaveAtlasType.strong(15))
                .foregroundStyle(SaveAtlasPalette.forest)
            Text(detail)
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(SaveTheme.Spacing.lg)
        .background(SaveAtlasPalette.paper.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    @ViewBuilder
    private var inlineError: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(SaveAtlasType.body(12))
                .foregroundStyle(Color.saveError)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SaveTheme.Spacing.md)
                .background(Color.saveError.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func followFriend() {
        let value = referralValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await onFollowReferral(value)
                referralValue = ""
                SaveHaptics.stamp()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func unfollow(_ friend: SaveFollowedFriend) async {
        errorMessage = nil
        do {
            try await onUnfollowFriend(friend)
            SaveHaptics.tap()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Share button for a list ticket. Shows the legacy base64 viewer link
/// immediately (never a dead button) and swaps in the server short-code URL
/// once `resolve` returns it.
private struct ListShareLinkControl: View {
    @Environment(\.appLanguageSettings) private var languageSettings

    let list: SaveCollaborativeList
    let legacyURL: URL?
    let resolve: (SaveCollaborativeList, SaveListRole) async -> URL?

    @State private var resolvedURL: URL?

    var body: some View {
        if let url = resolvedURL ?? legacyURL ?? list.shareURL(role: .viewer) {
            ShareLink(item: url) {
                Label(
                    languageSettings.localized(english: "Share", traditionalChinese: "分享"),
                    systemImage: "square.and.arrow.up"
                )
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("profile.connections.shareList")
            .task(id: list.id) {
                guard resolvedURL == nil else { return }
                resolvedURL = await resolve(list, .viewer)
            }
        }
    }
}

// MARK: - List Management

/// Member + share-code management for one server-backed collaborative list.
/// Owners remove members and revoke share codes; everyone else can only
/// leave the list. All mutations round-trip through the Savvy backend.
private struct ListManageView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.dismiss) private var dismiss

    let list: SaveCollaborativeList
    let currentUserID: String?
    let onLoadMembers: (SaveCollaborativeList) async -> [SaveListMemberInfo]
    let onRemoveMember: (SaveListMemberInfo, SaveCollaborativeList) async throws -> Void
    let onLoadShareCodes: (SaveCollaborativeList) async -> [SaveListShareCodeInfo]
    let onRevokeShareCode: (SaveListShareCodeInfo, SaveCollaborativeList) async throws -> Void

    @State private var members: [SaveListMemberInfo] = []
    @State private var shareCodes: [SaveListShareCodeInfo] = []
    @State private var isLoadingMembers = true
    @State private var isLoadingShareCodes = true
    @State private var memberPendingRemoval: SaveListMemberInfo?
    @State private var codePendingRevoke: SaveListShareCodeInfo?
    @State private var isLeaveConfirmationPresented = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var isOwner: Bool {
        list.viewerRole == .owner
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SaveTheme.Spacing.lg) {
                topBar
                membersSection

                if isOwner {
                    shareCodesSection
                } else {
                    leaveButton
                }

                inlineError
            }
            .padding(.horizontal)
            .padding(.bottom, SaveTheme.Spacing.xl)
        }
        .background(SaveDottedBackground().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            members = await onLoadMembers(list)
            isLoadingMembers = false
        }
        .task {
            guard isOwner else {
                isLoadingShareCodes = false
                return
            }
            shareCodes = await onLoadShareCodes(list)
            isLoadingShareCodes = false
        }
        .confirmationDialog(
            languageSettings.localized(english: "Remove this member?", traditionalChinese: "要移除這位成員嗎？"),
            isPresented: Binding(
                get: { memberPendingRemoval != nil },
                set: { if !$0 { memberPendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: memberPendingRemoval
        ) { member in
            Button(
                languageSettings.localized(english: "Remove \(member.displayName)", traditionalChinese: "移除 \(member.displayName)"),
                role: .destructive
            ) {
                Task { await remove(member) }
            }
        } message: { member in
            Text(languageSettings.localized(
                english: "\(member.displayName) loses access to \"\(list.title)\". Their own saved places stay untouched.",
                traditionalChinese: "\(member.displayName) 將失去「\(list.title)」的存取權；對方自己收藏的地點不受影響。"
            ))
        }
        .confirmationDialog(
            languageSettings.localized(english: "Revoke this share code?", traditionalChinese: "要撤銷這個分享碼嗎？"),
            isPresented: Binding(
                get: { codePendingRevoke != nil },
                set: { if !$0 { codePendingRevoke = nil } }
            ),
            titleVisibility: .visible,
            presenting: codePendingRevoke
        ) { code in
            Button(
                languageSettings.localized(english: "Revoke code", traditionalChinese: "撤銷分享碼"),
                role: .destructive
            ) {
                Task { await revoke(code) }
            }
        } message: { _ in
            Text(languageSettings.localized(
                english: "The link stops working for new joiners. People already in the list keep access.",
                traditionalChinese: "連結將無法再加入新成員；已加入的成員仍保有存取權。"
            ))
        }
        .confirmationDialog(
            languageSettings.localized(english: "Leave this list?", traditionalChinese: "要退出這個清單嗎？"),
            isPresented: $isLeaveConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                languageSettings.localized(english: "Leave list", traditionalChinese: "退出清單"),
                role: .destructive
            ) {
                Task { await leave() }
            }
        } message: {
            Text(languageSettings.localized(
                english: "\"\(list.title)\" disappears from your passport. Rejoin any time with a fresh share link.",
                traditionalChinese: "「\(list.title)」會從你的護照移除；之後可用新的分享連結再加入。"
            ))
        }
        .accessibilityIdentifier("profile.connections.manageList.root")
    }

    private var topBar: some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            PassportIconButton(systemName: "chevron.left") {
                SaveHaptics.tap()
                dismiss()
            }
            .accessibilityLabel(languageSettings.localized(english: "Back to connections", traditionalChinese: "返回連線"))
            .accessibilityIdentifier("profile.connections.manageList.back")

            VStack(alignment: .leading, spacing: 2) {
                Text(languageSettings.localized(english: "MANAGE LIST", traditionalChinese: "管理清單"))
                    .font(SaveAtlasType.strong(11))
                    .tracking(1.1)
                    .foregroundStyle(SaveAtlasPalette.forest)
                Text(list.title)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .lineLimit(1)
            }

            Spacer()

            Text(list.viewerRole.displayName.uppercased())
                .font(SaveAtlasType.strong(9))
                .tracking(0.7)
                .foregroundStyle(SaveAtlasPalette.forest)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(SaveAtlasPalette.mint.opacity(0.62), in: Capsule())
        }
        .padding(.top, SaveTheme.Spacing.lg)
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
            Text(languageSettings.localized(english: "MEMBERS", traditionalChinese: "成員"))
                .font(SaveAtlasType.strong(10))
                .tracking(1.05)
                .foregroundStyle(SaveAtlasPalette.coral)

            if isLoadingMembers {
                ProgressView()
                    .tint(SaveAtlasPalette.forest)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SaveTheme.Spacing.lg)
            } else if members.isEmpty {
                Text(languageSettings.localized(
                    english: "Couldn't load members. Check your connection and reopen this page.",
                    traditionalChinese: "無法載入成員，請確認網路後再重開此頁。"
                ))
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SaveTheme.Spacing.md)
            } else {
                ForEach(members) { member in
                    memberRow(member)
                }
            }
        }
    }

    private func memberRow(_ member: SaveListMemberInfo) -> some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(width: 42, height: 42)
                .background(SaveAtlasPalette.mint.opacity(0.62), in: SavePostcardSealShape())

            VStack(alignment: .leading, spacing: 3) {
                Text(isSelf(member)
                    ? languageSettings.localized(english: "\(member.displayName) (You)", traditionalChinese: "\(member.displayName)（你）")
                    : member.displayName)
                    .font(SaveAtlasType.strong(14))
                    .foregroundStyle(SaveAtlasPalette.ink)
                if let joinedAt = member.joinedAt {
                    Text(languageSettings.localized(
                        english: "Joined \(joinedAt.formatted(date: .abbreviated, time: .omitted))",
                        traditionalChinese: "加入於 \(joinedAt.formatted(date: .abbreviated, time: .omitted))"
                    ))
                    .font(SaveAtlasType.body(11))
                    .foregroundStyle(SaveAtlasPalette.muted)
                }
            }

            Spacer()

            Text(member.role.displayName.uppercased())
                .font(SaveAtlasType.strong(9))
                .tracking(0.7)
                .foregroundStyle(SaveAtlasPalette.forest)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(SaveAtlasPalette.honey.opacity(0.55), in: Capsule())

            // The backend rejects owner self-removal (409), so the minus only
            // renders for other members.
            if isOwner, !isSelf(member) {
                Button {
                    SaveHaptics.tap()
                    memberPendingRemoval = member
                } label: {
                    Image(systemName: "person.crop.circle.badge.minus")
                        .foregroundStyle(SaveAtlasPalette.coral)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .accessibilityLabel(languageSettings.localized(english: "Remove member", traditionalChinese: "移除成員"))
                .accessibilityIdentifier("profile.connections.removeMember")
            }
        }
        .padding(SaveTheme.Spacing.md)
        .background(SaveAtlasPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SaveAtlasPalette.mint.opacity(0.72), lineWidth: 1)
        }
    }

    private var shareCodesSection: some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
            Text(languageSettings.localized(english: "SHARE CODES", traditionalChinese: "分享碼"))
                .font(SaveAtlasType.strong(10))
                .tracking(1.05)
                .foregroundStyle(SaveAtlasPalette.coral)

            if isLoadingShareCodes {
                ProgressView()
                    .tint(SaveAtlasPalette.forest)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SaveTheme.Spacing.lg)
            } else if shareCodes.isEmpty {
                Text(languageSettings.localized(
                    english: "No active share codes. Tap Share on the list to mint one.",
                    traditionalChinese: "目前沒有分享碼；在清單上點「分享」即可產生。"
                ))
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SaveTheme.Spacing.md)
            } else {
                ForEach(shareCodes) { code in
                    shareCodeRow(code)
                }
            }
        }
    }

    private func shareCodeRow(_ code: SaveListShareCodeInfo) -> some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            Image(systemName: "link")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(width: 42, height: 42)
                .background(SaveAtlasPalette.honey.opacity(0.55), in: SavePostcardSealShape())

            VStack(alignment: .leading, spacing: 3) {
                Text(code.code)
                    .font(SaveAtlasType.strong(13))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .lineLimit(1)
                Text(expiryLabel(for: code))
                    .font(SaveAtlasType.body(11))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }

            Spacer()

            Text(code.role.displayName.uppercased())
                .font(SaveAtlasType.strong(9))
                .tracking(0.7)
                .foregroundStyle(SaveAtlasPalette.forest)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(SaveAtlasPalette.mint.opacity(0.62), in: Capsule())

            Button {
                SaveHaptics.tap()
                codePendingRevoke = code
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(SaveAtlasPalette.coral)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityLabel(languageSettings.localized(english: "Revoke share code", traditionalChinese: "撤銷分享碼"))
            .accessibilityIdentifier("profile.connections.revokeCode")
        }
        .padding(SaveTheme.Spacing.md)
        .background(SaveAtlasPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SaveAtlasPalette.honey.opacity(0.72), lineWidth: 1)
        }
    }

    private var leaveButton: some View {
        Button {
            SaveHaptics.tap()
            isLeaveConfirmationPresented = true
        } label: {
            Label(
                languageSettings.localized(english: "Leave list", traditionalChinese: "退出清單"),
                systemImage: "rectangle.portrait.and.arrow.right"
            )
            .font(SaveAtlasType.strong(13))
            .foregroundStyle(Color.saveError)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.saveError.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.saveError.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking || currentUserID == nil)
        .accessibilityIdentifier("profile.connections.leaveList")
    }

    @ViewBuilder
    private var inlineError: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(SaveAtlasType.body(12))
                .foregroundStyle(Color.saveError)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SaveTheme.Spacing.md)
                .background(Color.saveError.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func isSelf(_ member: SaveListMemberInfo) -> Bool {
        guard let currentUserID else { return false }
        return member.userID == currentUserID
    }

    private func expiryLabel(for code: SaveListShareCodeInfo) -> String {
        guard let expiresAt = code.expiresAt else {
            return languageSettings.localized(english: "Never expires", traditionalChinese: "永不過期")
        }
        let formatted = expiresAt.formatted(date: .abbreviated, time: .shortened)
        return languageSettings.localized(english: "Expires \(formatted)", traditionalChinese: "到期：\(formatted)")
    }

    private func remove(_ member: SaveListMemberInfo) async {
        isWorking = true
        errorMessage = nil
        do {
            try await onRemoveMember(member, list)
            members.removeAll { $0.userID == member.userID }
            SaveHaptics.tap()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func revoke(_ code: SaveListShareCodeInfo) async {
        isWorking = true
        errorMessage = nil
        do {
            try await onRevokeShareCode(code, list)
            shareCodes = await onLoadShareCodes(list)
            SaveHaptics.tap()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func leave() async {
        guard let currentUserID else { return }
        isWorking = true
        errorMessage = nil
        let selfMember = members.first { $0.userID == currentUserID }
            ?? SaveListMemberInfo(userID: currentUserID, role: list.viewerRole, displayName: "You")
        do {
            try await onRemoveMember(selfMember, list)
            SaveHaptics.stamp()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}

// MARK: - Edit Profile

private struct EditProfileSheet: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Binding var displayName: String
    let avatarURLString: String?
    @Binding var selectedAvatarData: Data?
    let isSaving: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () async -> Void
    @FocusState private var isNameFocused: Bool
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoError: String?

    var body: some View {
        let uploadPhotoTitle = languageSettings.localized(english: "Upload photo", traditionalChinese: "上傳照片")
        let inkColor = Color.saveInk
        let horizontalPadding = SaveTheme.Spacing.md
        let honeyColor = SaveAtlasPalette.kraft
        let notebookLineColor = SaveAtlasPalette.line

        return NavigationStack {
            VStack(spacing: SaveTheme.Spacing.lg) {
                HStack(spacing: SaveTheme.Spacing.md) {
                    Button(action: {
                        SaveHaptics.tap()
                        onCancel()
                    }) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.saveInk)
                            .frame(width: 38, height: 38)
                            .background(SaveAtlasPalette.paper)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(SaveAtlasPalette.line, lineWidth: 1.4)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(isSaving)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(languageSettings.text(.editPassport))
                            .font(SaveTheme.Typography.entryTitle)
                            .foregroundColor(.saveInk)
                        Text(languageSettings.text(.editPassportDescription))
                            .font(SaveTheme.Typography.supporting)
                            .foregroundColor(.saveMutedText)
                    }

                    Spacer()

                    Button {
                        SaveHaptics.stamp()
                        Task { await onSave() }
                    } label: {
                        Text(isSaving ? languageSettings.text(.saving) : languageSettings.text(.save))
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, SaveTheme.Spacing.md)
                            .frame(height: 38)
                            .background(SaveAtlasPalette.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("profile.editSave")
                }
                .padding(.horizontal)
                .padding(.top, SaveTheme.Spacing.lg)

                VStack(spacing: SaveTheme.Spacing.sm) {
                    EditableProfileAvatar(
                        avatarURLString: avatarURLString,
                        selectedAvatarData: selectedAvatarData
                    )

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(uploadPhotoTitle, systemImage: "camera.fill")
                            .font(.caption.weight(.bold))
                            .foregroundColor(inkColor)
                            .padding(.horizontal, horizontalPadding)
                            .frame(height: 36)
                            .background(honeyColor.opacity(0.42))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(notebookLineColor, lineWidth: 1.4)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)

                    if let photoError {
                        Text(photoError)
                            .font(SaveTheme.Typography.supporting)
                            .foregroundColor(.saveError)
                    }
                }
                .padding(SaveTheme.Spacing.lg)
                .saveAtlasPaper(radius: 20)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
                    Text(languageSettings.text(.passportName))
                        .font(SaveTheme.Typography.eyebrow)
                        .foregroundColor(.saveCocoa)

                    TextField(languageSettings.text(.name), text: $displayName)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.saveInk)
                        .textInputAutocapitalization(.words)
                        .focused($isNameFocused)
                        .padding(SaveTheme.Spacing.md)
                        .saveAtlasPaper(radius: 14)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(SaveTheme.Typography.supporting)
                            .foregroundColor(.saveError)
                    } else {
                        Text(languageSettings.text(.accountManagedByLogin))
                            .font(SaveTheme.Typography.supporting)
                            .foregroundColor(.saveMutedText)
                    }
                }
                .padding(SaveTheme.Spacing.lg)
                .saveAtlasPaper(radius: 20)
                .padding(.horizontal)

                Spacer()
            }
            .background(SaveDottedBackground().ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            isNameFocused = true
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await loadSelectedPhoto(item) }
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = languageSettings.localized(english: "Couldn’t load that photo.", traditionalChinese: "無法載入這張照片。")
                return
            }
            selectedAvatarData = data
            photoError = nil
        } catch {
            photoError = error.localizedDescription
        }
    }
}

// MARK: - Today on Savvy


// MARK: - Field streak

private struct PassportFieldStreakStrip: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let streak: Int
    let hasActionToday: Bool

    var body: some View {
        HStack(alignment: .center, spacing: SaveTheme.Spacing.md) {
            SavePostcardPerforatedMedallion(
                systemName: "flame.fill",
                tint: hasActionToday ? SaveAtlasPalette.coral : SaveAtlasPalette.kraft,
                edge: SaveAtlasPalette.forest
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(languageSettings.localized(
                    english: "FIELD STREAK",
                    traditionalChinese: "野外連續"
                ))
                .font(SaveAtlasType.strong(11))
                .tracking(0.7)
                .foregroundStyle(SaveAtlasPalette.forest)

                Text(streakTitle)
                    .font(SaveAtlasType.strong(18))
                    .foregroundStyle(SaveAtlasPalette.ink)

                Text(streakDetail)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            SavePostcardScallopedRectangle(depth: 4, pitch: 12)
                .fill(SaveAtlasPalette.paper)
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 4, pitch: 12)
                .stroke(
                    SaveAtlasPalette.kraft.opacity(0.82),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.07), radius: 6, y: 3)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(streakTitle + ". " + streakDetail)
    }

    private var streakTitle: String {
        if streak <= 0 {
            return languageSettings.localized(
                english: "No field day yet",
                traditionalChinese: "還沒有野外日"
            )
        }
        return languageSettings.localized(
            english: "\(streak)-day field streak",
            traditionalChinese: "連續 \(streak) 個野外日"
        )
    }

    private var streakDetail: String {
        if hasActionToday {
            return languageSettings.localized(
                english: "Today already counts: confirm, save, or mark Visited.",
                traditionalChinese: "今天已記入：確認線索、存章、或標記去過。"
            )
        }
        return languageSettings.localized(
            english: "Confirm a clue, save a Map Stamp, or mark Visited to count today.",
            traditionalChinese: "確認線索、存下地圖章、或標記去過，今天才算。"
        )
    }
}

private struct PassportTodayOnSavvyStrip: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let missions: [SavePassportTodayMission]
    let onSelect: (SavePassportTodayMissionID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(languageSettings.localized(english: "Your quests", traditionalChinese: "你的探索任務"))
                    .font(SaveAtlasType.strong(17))
                    .foregroundStyle(SaveAtlasPalette.forest)
                Spacer()
                Text(languageSettings.localized(english: "\(missions.count) next steps", traditionalChinese: "\(missions.count) 件可以做的事"))
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
            VStack(spacing: 0) {
                ForEach(missions) { mission in
                    PassportTodayMissionRow(mission: mission) {
                        SaveHaptics.tap()
                        onSelect(mission.id)
                    }
                    if mission.id != missions.last?.id {
                        Rectangle()
                            .fill(SaveAtlasPalette.line.opacity(0.2))
                            .frame(height: 1)
                            .padding(.leading, 62)
                            .padding(.trailing, 16)
                    }
                }
            }
            .saveAtlasPaper(radius: 18)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.today")
    }
}

private struct PassportTodayMissionRow: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let mission: SavePassportTodayMission
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SaveTheme.Spacing.md) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .frame(width: 36, height: 40)
                    .background(medallionTint.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SaveAtlasType.strong(15))
                        .foregroundStyle(SaveAtlasPalette.forest)
                    Text(detail)
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(rowAccessibilityIdentifier)
    }

    private var rowAccessibilityIdentifier: String {
        switch mission.id {
        case .confirmWaitingClue:
            return "profile.today.confirmWaitingClue"
        case .markVisitedStamp:
            return "profile.today.markVisitedStamp"
        case .shareRecommendation:
            return "profile.today.shareRecommendation"
        case .inviteOrFollowFriend:
            return "profile.today.inviteFriend"
        }
    }

    private var title: String {
        switch mission.id {
        case .confirmWaitingClue:
            return languageSettings.localized(
                english: "Confirm a waiting clue",
                traditionalChinese: "確認一個待審線索"
            )
        case .markVisitedStamp:
            return languageSettings.localized(
                english: "Mark one Map Stamp visited",
                traditionalChinese: "把一個地圖章標成去過"
            )
        case .shareRecommendation:
            return languageSettings.localized(
                english: "Share one Map Stamp",
                traditionalChinese: "分享一個地圖章推薦"
            )
        case .inviteOrFollowFriend:
            return languageSettings.localized(
                english: "Invite or follow a friend",
                traditionalChinese: "邀請或追蹤朋友"
            )
        }
    }

    private var detail: String {
        switch mission.id {
        case .confirmWaitingClue:
            return languageSettings.localized(
                english: "Choose which places belong in your memory",
                traditionalChinese: "看看哪些地點值得留下"
            )
        case .markVisitedStamp:
            return languageSettings.localized(
                english: "Keep a memory of somewhere you’ve been",
                traditionalChinese: "把走過的地方留在記憶裡"
            )
        case .shareRecommendation:
            return languageSettings.localized(
                english: "Let friends discover a place you recommend",
                traditionalChinese: "讓朋友發現你推薦的好地方"
            )
        case .inviteOrFollowFriend:
            return languageSettings.localized(
                english: "Find inspiration in a friend’s places",
                traditionalChinese: "從朋友的地點找些新靈感"
            )
        }
    }

    private var iconName: String {
        switch mission.id {
        case .confirmWaitingClue:
            return "circle.hexagongrid"
        case .markVisitedStamp:
            return "figure.walk"
        case .shareRecommendation:
            return "square.and.arrow.up"
        case .inviteOrFollowFriend:
            return "person.badge.plus"
        }
    }

    private var medallionTint: Color {
        switch mission.id {
        case .confirmWaitingClue:
            return SaveAtlasPalette.coral
        case .markVisitedStamp:
            return SaveAtlasPalette.mint
        case .shareRecommendation:
            return SaveAtlasPalette.mint
        case .inviteOrFollowFriend:
            return SaveAtlasPalette.kraft
        }
    }
}

// MARK: - Passport

private struct PassportTopBar: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let waitingClues: Int
    let allowsEditing: Bool
    let showsCloseButton: Bool
    let onClose: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            if showsCloseButton {
                PassportIconButton(systemName: "xmark", action: onClose)
                    .accessibilityIdentifier("profile.close")
            }

            Image("SavvyLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("Savvy")
                .accessibilityIdentifier("profile.brandLogo")

            VStack(alignment: .leading, spacing: 2) {
                Text(languageSettings.text(.profileTitle))
                    .font(SaveAtlasType.strong(20))
                    .tracking(0)
                    .foregroundStyle(SaveAtlasPalette.forest)
                Text(languageSettings.localized(english: "Your personal atlas", traditionalChinese: "你的私人地點圖鑑"))
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }

            Spacer()

            if allowsEditing {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .frame(width: 44, height: 44)
                        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(SaveAtlasPalette.kraft.opacity(0.68), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageSettings.text(.edit))
                .accessibilityIdentifier("profile.edit")
            }
        }
        .padding(.vertical, SaveTheme.Spacing.xs)
    }
}

private struct PassportIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(SaveAtlasPalette.ink)
                .frame(width: 44, height: 44)
                .background(SaveAtlasPalette.paper.opacity(0.90), in: Circle())
                .overlay {
                    Circle().stroke(SaveAtlasPalette.line.opacity(0.40), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct PassportHero: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let profile: UserProfile

    var body: some View {
        HStack(spacing: 16) {
            ProfileAvatarView(avatarURLString: profile.avatarUrl, size: 48)
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.displayName)
                    .font(SaveAtlasType.strong(22, relativeTo: .title2))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .fixedSize(horizontal: false, vertical: true)
                Text(profile.email ?? languageSettings.text(.localMemoHelper))
                    .font(SaveAtlasType.body(13))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .lineLimit(1)
                Text("\(languageSettings.text(.memberSince)) · \(profile.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(SaveAtlasPalette.forest)
                .frame(width: 5)
                .padding(.vertical, 20)
        }
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(SaveAtlasPalette.line.opacity(0.35)) }
    }
}

private struct EditableProfileAvatar: View {
    let avatarURLString: String?
    let selectedAvatarData: Data?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let selectedAvatarData, let image = UIImage(data: selectedAvatarData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProfileAvatarView(avatarURLString: avatarURLString, size: 92)
            }

            Image(systemName: "camera.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(.saveInk)
                .frame(width: 28, height: 28)
                .background(SaveAtlasPalette.kraft)
                .overlay(Circle().stroke(SaveAtlasPalette.line, lineWidth: 1.2))
                .clipShape(Circle())
                .offset(x: 2, y: 2)
        }
        .frame(width: 92, height: 92)
        .clipShape(Circle())
        .overlay(Circle().stroke(SaveAtlasPalette.line, lineWidth: 2))
    }
}

private struct ProfileAvatarView: View {
    let avatarURLString: String?
    var size: CGFloat

    var body: some View {
        Group {
            if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL {
                CachedAsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        MemoMascotMark(size: size)
                    }
                }
            } else {
                MemoMascotMark(size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(SaveAtlasPalette.line, lineWidth: 1.6))
    }

    private var remoteURL: URL? {
        guard let avatarURLString,
              let url = URL(string: avatarURLString),
              url.isFileURL == false
        else { return nil }
        return url
    }

    private var localImage: UIImage? {
        guard let avatarURLString,
              let url = URL(string: avatarURLString),
              url.isFileURL
        else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

private struct PassportBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(SaveTheme.Typography.stamp)
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, SaveTheme.Spacing.sm)
            .padding(.vertical, SaveTheme.Spacing.xs)
            .background(color.opacity(0.38))
            .clipShape(Capsule())
    }
}

private struct PassportStampSection: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let stats: PassportStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(languageSettings.localized(english: "Your place memory", traditionalChinese: "你的地點記憶"))
                .font(SaveAtlasType.strong(17))
                .foregroundStyle(SaveAtlasPalette.forest)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 1) {
                stat(stats.savedCount, title: languageSettings.localized(english: "Map Stamps", traditionalChinese: "地圖章"), symbol: "mappin", tint: SaveAtlasPalette.mint)
                stat(stats.visitedCount, title: languageSettings.text(.visited), symbol: "figure.walk", tint: SaveAtlasPalette.mint)
                stat(stats.citiesCount, title: languageSettings.text(.cities), symbol: "building.2", tint: SaveAtlasPalette.kraft)
                stat(stats.waitingClues, title: languageSettings.text(.waitingClues), symbol: "tray", tint: SaveAtlasPalette.sky)
            }
            .background(SaveAtlasPalette.line.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Text(languageSettings.localized(english: "Visited places are marked by you.", traditionalChinese: "去過的地點由你自己標記。"))
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
            if !stats.cityNames.isEmpty {
                DisclosureGroup(languageSettings.text(.cities)) {
                    PassportCityStrip(cityNames: stats.cityNames)
                }
                .font(SaveAtlasType.body(14))
                .tint(SaveAtlasPalette.forest)
            }
        }
        .padding(.horizontal, 16)
    }

    private func stat(_ count: Int, title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(SaveAtlasPalette.forest)
                    .padding(5)
                    .background(tint.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                Text(title).foregroundStyle(SaveAtlasPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(SaveAtlasType.body(14))
            Spacer(minLength: 4)
            Text(count.formatted())
                .font(SaveAtlasType.strong(22, relativeTo: .title2))
                .foregroundStyle(SaveAtlasPalette.forest)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(SaveAtlasPalette.paper)
        .accessibilityElement(children: .combine)
    }
}

private struct PassportCityStrip: View {
    let cityNames: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SaveTheme.Spacing.xs) {
                ForEach(cityNames.prefix(8), id: \.self) { city in
                    Text(city)
                        .font(SaveTheme.Typography.stamp)
                        .foregroundColor(.saveInk)
                        .lineLimit(1)
                        .padding(.horizontal, SaveTheme.Spacing.sm)
                        .padding(.vertical, SaveTheme.Spacing.xs)
                        .background(SaveAtlasPalette.kraft.opacity(0.2))
                        .overlay(Capsule().stroke(SaveAtlasPalette.line.opacity(0.62), lineWidth: 1))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, 1)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
}

private struct PassportCountingRulesPanel: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let stats: PassportStats

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SavePostcardPostmark()
                .scaleEffect(0.82)
                .frame(width: 66, height: 56)

            VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
                Text(title.uppercased())
                    .font(SaveAtlasType.strong(10))
                    .tracking(0.9)
                    .foregroundStyle(SaveAtlasPalette.forest)
                Text(cityRule)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
                Text(visitedRule)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(SaveAtlasPalette.paper.opacity(0.74))
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    SaveAtlasPalette.line.opacity(0.48),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
        }
        .padding(.horizontal)
    }

    private var title: String {
        switch languageSettings.language {
        case .english: return "How Passport counts stamps"
        case .traditionalChinese: return "護照印章怎麼計算"
        }
    }

    private var cityRule: String {
        switch languageSettings.language {
        case .english: return "Cities come from the city or area in saved place addresses."
        case .traditionalChinese: return "城市會從已存地點地址裡的城市或區域整理出來。"
        }
    }

    private var visitedRule: String {
        switch languageSettings.language {
        case .english: return "Visited counts places you marked visited in Savvy."
        case .traditionalChinese: return "去過數量只計算你自己標記為去過的地點。"
        }
    }
}

private struct PassportVisibilityPanel: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let places: [Place]
    let onUpdate: (Place, PlaceVisibility) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
            HStack(spacing: SaveTheme.Spacing.sm) {
                SavePostcardPerforatedMedallion(
                    systemName: "person.2.wave.2.fill",
                    tint: SaveAtlasPalette.mint,
                    edge: SaveAtlasPalette.forest
                )
                Text(languageSettings.localized(
                    english: "SHARING & PRIVACY",
                    traditionalChinese: "分享與隱私"
                ))
                    .font(SaveAtlasType.strong(11))
                    .tracking(0.9)
                    .foregroundStyle(SaveAtlasPalette.forest)
                Spacer()
            }

            if places.isEmpty {
                Text(languageSettings.localized(
                    english: "Save places first, then choose which memories stay private or become shareable links.",
                    traditionalChinese: "先保存地點，再選哪些記憶保持私密、哪些可以用公開連結分享。"
                ))
                    .font(SaveTheme.Typography.supporting)
                    .foregroundColor(.saveCocoa.opacity(0.72))
            } else {
                Text(languageSettings.localized(
                    english: "Choose who can see each saved place.",
                    traditionalChinese: "選擇每個已存地點誰看得到。"
                ))
                    .font(SaveTheme.Typography.supporting)
                    .foregroundColor(.saveCocoa.opacity(0.72))

                VStack(spacing: SaveTheme.Spacing.sm) {
                    ForEach(places.prefix(4)) { place in
                        PassportVisibilityRow(place: place, onUpdate: onUpdate)
                    }
                }
            }
        }
        .padding(18)
        .background {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .fill(SaveAtlasPalette.paper)
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .stroke(
                    SaveAtlasPalette.mint.opacity(0.90),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
        }
        .padding(.horizontal)
    }
}

private struct PassportVisibilityRow: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let place: Place
    let onUpdate: (Place, PlaceVisibility) async throws -> Void
    @State private var selectedVisibility: PlaceVisibility
    @State private var isUpdating = false
    @State private var errorMessage: String?

    init(place: Place, onUpdate: @escaping (Place, PlaceVisibility) async throws -> Void) {
        self.place = place
        self.onUpdate = onUpdate
        _selectedVisibility = State(initialValue: place.effectiveVisibility)
    }

    var body: some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            SaveMemoryBadge(state: .saved(place.category), size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(SaveTheme.Typography.stamp)
                    .foregroundColor(.saveInk)
                    .lineLimit(1)
                Text(errorMessage ?? selectedVisibility.detailText(language: languageSettings.language))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(errorMessage == nil ? .saveCocoa.opacity(0.72) : .saveError)
                    .lineLimit(1)
            }

            Spacer()

            SavePlaceShareButton(content: .place(place)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .frame(width: 36, height: 36)
                    .background(SaveAtlasPalette.sky.opacity(0.72), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(SaveAtlasPalette.forest.opacity(0.20), lineWidth: 1)
                    }
            }
            .accessibilityLabel(languageSettings.localized(
                english: "Share \(place.name)",
                traditionalChinese: "分享 \(place.name)"
            ))
            .accessibilityIdentifier("profile.share.\(place.id)")

            Menu {
                ForEach(PlaceVisibility.allCases, id: \.self) { visibility in
                    Button {
                        Task { await update(visibility) }
                    } label: {
                        Label(visibility.displayName(language: languageSettings.language), systemImage: visibility.systemImage)
                    }
                }
            } label: {
                HStack(spacing: SaveTheme.Spacing.xs) {
                    if isUpdating {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: selectedVisibility.systemImage)
                    }
                    Text(selectedVisibility.displayName(language: languageSettings.language))
                }
                .font(SaveTheme.Typography.stamp)
                .foregroundColor(.saveInk)
                .padding(.horizontal, SaveTheme.Spacing.sm)
                .padding(.vertical, SaveTheme.Spacing.xs)
                .background(SaveAtlasPalette.paper.opacity(0.76))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(SaveAtlasPalette.line.opacity(0.35), lineWidth: 1))
            }
            .disabled(isUpdating)
            .accessibilityIdentifier("profile.visibility.\(place.id)")
        }
        .padding(.vertical, SaveTheme.Spacing.sm)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SaveAtlasPalette.line.opacity(0.22))
                .frame(height: 1)
        }
        .onChange(of: place.effectiveVisibility) { _, visibility in
            selectedVisibility = visibility
        }
    }

    private func update(_ visibility: PlaceVisibility) async {
        guard visibility != selectedVisibility else { return }
        SaveHaptics.select()
        let previous = selectedVisibility
        withAnimation(SaveTheme.Motion.standardSpring) {
            selectedVisibility = visibility
        }
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }

        do {
            try await onUpdate(place, visibility)
        } catch {
            withAnimation(SaveTheme.Motion.standardSpring) {
                selectedVisibility = previous
            }
            errorMessage = error.localizedDescription
        }
    }
}

private struct PassportRuleLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: SaveTheme.Spacing.md) {
            SaveIconTile(
                systemName: icon,
                size: 32,
                iconSize: 13,
                fill: Color.saveCocoa.opacity(0.16),
                foreground: .saveCocoa,
                strokeOpacity: 0.48,
                cornerRadius: 10
            )

            Text(text)
                .font(SaveTheme.Typography.supporting)
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    let color: Color
    var accessibilityIdentifier: String? = nil
    var action: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let action {
            Button(action: action) {
                rowContent
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(accessibilityIdentifier ?? "")
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(width: 36, height: 40)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SaveAtlasType.strong(15))
                    .foregroundStyle(SaveAtlasPalette.forest)

                if let detail {
                    Text(detail)
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(SaveAtlasPalette.muted)
        }
        .padding(.vertical, SaveTheme.Spacing.sm)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SaveAtlasPalette.kraft.opacity(0.32))
                .frame(height: 1)
                .padding(.leading, 62)
        }
    }
}

private struct LanguageSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SaveTheme.Spacing.lg) {
                HStack(spacing: SaveTheme.Spacing.md) {
                    Button(action: {
                        SaveHaptics.tap()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.saveInk)
                            .frame(width: 38, height: 38)
                            .background(SaveAtlasPalette.paper)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(SaveAtlasPalette.line, lineWidth: 1.4)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: SaveTheme.Spacing.xs) {
                        Text(languageSettings.text(.chooseLanguage))
                            .font(SaveTheme.Typography.entryTitle)
                            .foregroundColor(.saveInk)
                        Text(languageSettings.text(.languageDescription))
                            .font(SaveTheme.Typography.supporting)
                            .foregroundColor(.saveMutedText)
                    }
                }
                .padding(.top, SaveTheme.Spacing.lg)

                VStack(spacing: SaveTheme.Spacing.sm) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            SaveHaptics.select()
                            withAnimation(SaveTheme.Motion.standardSpring) {
                                languageSettings.language = language
                            }
                        } label: {
                            HStack(spacing: SaveTheme.Spacing.md) {
                                Text(language.displayName)
                                    .font(.headline.weight(.bold))
                                    .foregroundColor(.saveInk)

                                Spacer()

                                if languageSettings.language == language {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3.weight(.bold))
                                        .foregroundColor(.saveSuccess)
                                }
                            }
                            .padding(SaveTheme.Spacing.md)
                            .background(
                                languageSettings.language == language
                                ? SaveAtlasPalette.kraft.opacity(0.25)
                                : SaveAtlasPalette.canvas.opacity(0.5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(SaveAtlasPalette.line.opacity(0.24), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.languageOption.\(language.id)")
                    }
                }

                Spacer()
            }
            .padding(.horizontal, SaveTheme.Spacing.lg)
            .background(SaveDottedBackground().ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    ProfileView()
        .environment(\.appLanguageSettings, AppLanguageSettings())
}
