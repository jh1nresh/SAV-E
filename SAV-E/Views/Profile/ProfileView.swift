import SwiftUI
import PhotosUI
import UIKit

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showEditProfile = false
    @State private var showLanguageSettings = false
    @State private var showGoogleTakeoutImport = false
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
    var onSaveGoogleTakeoutImport: ([ImportedPlaceDraft]) async throws -> GoogleTakeoutSaveSummary = { _ in
        GoogleTakeoutSaveSummary(saved: 0, skippedDuplicates: 0, reviewDrafts: 0)
    }
    var onCreateList: (String, String?) -> Void = { _, _ in }
    var onShareListURL: (SaveCollaborativeList, SaveListRole) -> URL? = { _, _ in nil }
    var onOpenListOnMap: (SaveCollaborativeList) -> Void = { _ in }
    var onFollowReferral: (String) async throws -> Void = { _ in }
    var onRefreshFollowedFriends: () async -> Void = {}
    var onSearchFollowedFriends: (String) async -> Void = { _ in }
    var onLoadMoreFollowedFriends: () async -> Void = {}
    var onUnfollowFriend: (SaveFollowedFriend) async throws -> Void = { _ in }

    private var passportStats: PassportStats {
        PassportStats(profile: viewModel.profile, savedPlaces: passportPlaces, waitingClues: waitingClues)
    }

    private var passportPlaces: [Place] {
        localSavedPlaces
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SaveTheme.Spacing.lg) {
                    PassportTopBar(
                        waitingClues: waitingClues,
                        allowsEditing: !PrivyAuthService.shared.isReviewerDemo,
                        onClose: { dismiss() },
                        onEdit: {
                            SaveHaptics.tap()
                            draftDisplayName = viewModel.profile.displayName
                            draftAvatarData = nil
                            showEditProfile = true
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, SaveTheme.Spacing.lg)

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

                    PassportStampSection(profile: viewModel.profile, stats: passportStats)
                        .accessibilityIdentifier("profile.stampLedger")

                    VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
                        Text(languageSettings.text(.passportControls))
                            .font(SaveTheme.Typography.eyebrow)
                            .foregroundColor(.saveCocoa)
                            .padding(.horizontal, SaveTheme.Spacing.xs)

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
                                detail: languageSettings.localized(english: "Inspect and control what SAV-E remembers", traditionalChinese: "查看並控制 SAV-E 記住的內容"),
                                color: .saveCocoa
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded { SaveHaptics.tap() })
                        .accessibilityIdentifier("profile.memoryPreferences")

                        NavigationLink {
                            PassportConnectionsView(
                                collaborativeLists: collaborativeLists,
                                followedFriends: followedFriends,
                                isLoadingFollowedFriends: isLoadingFollowedFriends,
                                hasMoreFollowedFriends: hasMoreFollowedFriends,
                                onCreateList: onCreateList,
                                onShareListURL: onShareListURL,
                                onOpenListOnMap: onOpenListOnMap,
                                onFollowReferral: onFollowReferral,
                                onRefreshFollowedFriends: onRefreshFollowedFriends,
                                onSearchFollowedFriends: onSearchFollowedFriends,
                                onLoadMoreFollowedFriends: onLoadMoreFollowedFriends,
                                onUnfollowFriend: onUnfollowFriend
                            )
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
                        .simultaneousGesture(TapGesture().onEnded { SaveHaptics.tap() })
                        .accessibilityIdentifier("profile.connections")

                        SettingsRow(
                            icon: "shippingbox.and.arrow.backward.fill",
                            title: languageSettings.localized(
                                english: "Import Google Takeout",
                                traditionalChinese: "匯入 Google Takeout"
                            ),
                            detail: languageSettings.localized(
                                english: "Deliver historical place exports to SAV-E",
                                traditionalChinese: "把歷史地點匯出檔送進 SAV-E"
                            ),
                            color: SaveAtlasPalette.kraft,
                            accessibilityIdentifier: "profile.importGoogleTakeout"
                        ) {
                            SaveHaptics.tap()
                            showGoogleTakeoutImport = true
                        }

                        SettingsRow(
                            icon: "arrow.right.square",
                            title: languageSettings.text(.signOut),
                            color: .saveError,
                            accessibilityIdentifier: "profile.signOut"
                        ) {
                            SaveHaptics.tap()
                            Task { await viewModel.signOut() }
                        }
                    }
                    .padding(.horizontal, SaveTheme.Spacing.md)
                    .padding(.top, SaveTheme.Spacing.lg)
                    .padding(.bottom, SaveTheme.Spacing.xl)
                    .background {
                        SavePostcardScallopedRectangle(depth: 4, pitch: 12)
                            .fill(SaveAtlasPalette.kraft.opacity(0.24))
                    }
                    .overlay {
                        SavePostcardScallopedRectangle(depth: 4, pitch: 12)
                            .stroke(
                                SaveAtlasPalette.kraft.opacity(0.72),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                            )
                    }
                    .padding(.horizontal)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("profile.controlPocket")

                    SavePetCompanionCard(profile: viewModel.profile)
                        .padding(.horizontal)

                    PassportCountingRulesPanel(stats: passportStats)

                    PassportVisibilityPanel(
                        places: passportPlaces,
                        onUpdate: updatePlaceVisibility
                    )
                }
                .padding(.bottom, SaveTheme.Spacing.xl)
                .padding(.top, 2)
            }
            .background(SaveDottedBackground().ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("profile.root")
        }
        .task {
            localSavedPlaces = savedPlaces
            await viewModel.loadProfile()
        }
        .onChange(of: savedPlaces) { _, places in
            localSavedPlaces = places
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
        .sheet(isPresented: $showLanguageSettings) {
            LanguageSettingsSheet()
        }
        .sheet(isPresented: $showGoogleTakeoutImport) {
            GoogleTakeoutImportView(
                existingPlaces: passportPlaces,
                onSave: onSaveGoogleTakeoutImport
            )
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

    private func updatePlaceVisibility(_ place: Place, visibility: PlaceVisibility) async throws {
        try await onUpdatePlaceVisibility(place, visibility)
        if let index = localSavedPlaces.firstIndex(where: { $0.id == place.id }) {
            localSavedPlaces[index].visibility = visibility
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
    let onOpenListOnMap: (SaveCollaborativeList) -> Void
    let onFollowReferral: (String) async throws -> Void
    let onRefreshFollowedFriends: () async -> Void
    let onSearchFollowedFriends: (String) async -> Void
    let onLoadMoreFollowedFriends: () async -> Void
    let onUnfollowFriend: (SaveFollowedFriend) async throws -> Void

    @State private var selectedSection: Section = .friends
    @State private var referralValue = ""
    @State private var friendQuery = ""
    @State private var listTitle = ""
    @State private var listNote = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

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
            postcardPocket(
                eyebrow: languageSettings.localized(english: "FOLLOW A FRIEND", traditionalChinese: "追蹤朋友"),
                title: languageSettings.localized(english: "Paste their SAV-E link", traditionalChinese: "貼上對方的 SAV-E 連結")
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

                if let viewerURL = onShareListURL(list, .viewer) {
                    ShareLink(item: viewerURL) {
                        Label(
                            languageSettings.localized(english: "Share", traditionalChinese: "分享"),
                            systemImage: "square.and.arrow.up"
                        )
                        .frame(maxWidth: .infinity)
                    }
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
        let honeyColor = Color.saveHoney
        let notebookLineColor = Color.saveNotebookLine

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
                            .background(Color.saveNotebookPage)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
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
                            .foregroundColor(.saveInk)
                            .padding(.horizontal, SaveTheme.Spacing.md)
                            .frame(height: 38)
                            .background(Color.saveHoney)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
                            )
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
                .saveNotebookPage(cornerRadius: 20)
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
                        .saveNotebookSurface(cornerRadius: 14)

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
                .saveNotebookSurface(cornerRadius: 20)
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

// MARK: - Passport

private struct PassportTopBar: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let waitingClues: Int
    let allowsEditing: Bool
    let onClose: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            PassportIconButton(systemName: "xmark", action: onClose)
                .accessibilityIdentifier("profile.close")

            VStack(alignment: .leading, spacing: 2) {
                Text("SAV-E · \(languageSettings.text(.profileTitle).uppercased())")
                    .font(SaveAtlasType.strong(12))
                    .tracking(1.2)
                    .foregroundStyle(SaveAtlasPalette.forest)
                Text(languageSettings.memoWaitingText(waitingClues))
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }

            Spacer()

            if allowsEditing {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .frame(width: 38, height: 38)
                        .background(SaveAtlasPalette.honey, in: SavePostcardSealShape())
                        .overlay {
                            SavePostcardSealShape()
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
                .frame(width: 38, height: 38)
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
        HStack(spacing: 0) {
            PassportNotebookSpine(color: SaveAtlasPalette.kraft)

            VStack(alignment: .leading, spacing: SaveTheme.Spacing.md) {
                HStack {
                    Text("SAV-E MEMORY PASSPORT")
                        .font(SaveAtlasType.strong(10))
                        .tracking(1.15)
                        .foregroundStyle(SaveAtlasPalette.mint)

                    Spacer()

                    SavePostcardPostmark()
                        .scaleEffect(0.76)
                        .frame(width: 52, height: 34)
                        .colorInvert()
                        .opacity(0.70)
                }

                HStack(alignment: .top, spacing: SaveTheme.Spacing.md) {
                    ProfileAvatarView(avatarURLString: profile.avatarUrl, size: 78)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "book.closed")
                                // Intentional one-off badge glyph size; no token maps cleanly.
                                .font(.system(size: 18, weight: .black))
                                .foregroundStyle(SaveAtlasPalette.forest)
                                .frame(width: 28, height: 28)
                                .background(SaveAtlasPalette.mint)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.saveNotebookLine.opacity(0.35), lineWidth: 1))
                                .offset(x: 6, y: 6)
                        }

                    VStack(alignment: .leading, spacing: SaveTheme.Spacing.xs) {
                        Text(languageSettings.text(.profileTitle))
                            .font(SaveAtlasType.strong(11))
                            .tracking(0.75)
                            .foregroundStyle(SaveAtlasPalette.honey)
                        Text(profile.displayName)
                            .font(SaveAtlasType.strong(28, relativeTo: .title2))
                            .foregroundStyle(SaveAtlasPalette.paper)
                            .lineLimit(2)
                        Text(profile.email ?? languageSettings.text(.localMemoHelper))
                            .font(SaveAtlasType.body(13))
                            .foregroundStyle(SaveAtlasPalette.paper.opacity(0.70))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                HStack(alignment: .bottom, spacing: SaveTheme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(languageSettings.text(.memberSince).uppercased())
                            .font(SaveAtlasType.strong(9))
                            .tracking(0.8)
                        Text(profile.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(SaveAtlasType.editorial(16))
                    }
                    .foregroundStyle(SaveAtlasPalette.paper.opacity(0.88))

                    Spacer()

                    Text(visitedBadgeText)
                        .font(SaveAtlasType.strong(9))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 38)
                        .background(SaveAtlasPalette.mint, in: SavePostcardSealShape())
                }
            }
            .padding(SaveTheme.Spacing.lg)
        }
        .background(SaveAtlasPalette.forest)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(SaveAtlasPalette.kraft.opacity(0.72), lineWidth: 1.5)
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.12), radius: 8, y: 4)
    }

    private var visitedBadgeText: String {
        switch languageSettings.language {
        case .english: return "VISITED IS SELF-MARKED"
        case .traditionalChinese: return "去過由你自己標記"
        }
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
                .background(Color.saveHoney)
                .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1.2))
                .clipShape(Circle())
                .offset(x: 2, y: 2)
        }
        .frame(width: 92, height: 92)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 2))
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
        .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1.6))
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

private struct PassportNotebookSpine: View {
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
        .padding(.top, SaveTheme.Spacing.lg)
        .background(color.opacity(0.42))
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
    let profile: UserProfile
    let stats: PassportStats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageSettings.text(.passportStamps).uppercased())
                        .font(SaveAtlasType.strong(11))
                        .tracking(1)
                        .foregroundStyle(SaveAtlasPalette.forest)
                    Text(languageSettings.text(.memoBook))
                        .font(SaveAtlasType.editorial(18))
                        .foregroundStyle(SaveAtlasPalette.ink)
                }

                Spacer()

                SavePostcardPostmark()
                    .scaleEffect(0.78)
                    .frame(width: 58, height: 48)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)

            PassportStampRow(
                icon: "rectangle.stack",
                tint: SaveAtlasPalette.sky,
                title: languageSettings.text(.memoryCards),
                value: languageSettings.savedCountText(stats.savedCount),
                detail: mapStampDetail
            )
            PassportStampRow(
                icon: "figure.walk",
                tint: SaveAtlasPalette.mint,
                title: languageSettings.text(.visited),
                value: languageSettings.visitedCountText(stats.visitedCount),
                detail: visitedDetail
            )
            PassportStampRow(
                icon: "building.2",
                tint: SaveAtlasPalette.honey,
                title: languageSettings.text(.cities),
                value: languageSettings.cityCountText(stats.citiesCount),
                detail: citiesDetail
            )
            if !stats.cityNames.isEmpty {
                PassportCityStrip(cityNames: stats.cityNames)
            }
            PassportStampRow(
                icon: "circle.hexagongrid",
                tint: SaveAtlasPalette.coral.opacity(0.58),
                title: languageSettings.text(.waitingClues),
                value: languageSettings.waitingPlaceText(stats.waitingClues),
                detail: waitingClueDetail
            )

            HStack {
                Text(languageSettings.localized(
                    english: "Issued to \(profile.displayName)",
                    traditionalChinese: "發給 \(profile.displayName)"
                ))
                    .font(SaveAtlasType.editorial(15))
                    .foregroundStyle(SaveAtlasPalette.muted)
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(SaveAtlasPalette.forest)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(SaveAtlasPalette.mint.opacity(0.22))
        }
        .background {
            SavePostcardScallopedRectangle(depth: 4, pitch: 12)
                .fill(SaveAtlasPalette.paper)
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 4, pitch: 12)
                .stroke(
                    SaveAtlasPalette.sky.opacity(0.82),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.07), radius: 6, y: 3)
        .padding(.horizontal)
    }

    private var mapStampDetail: String {
        switch languageSettings.language {
        case .english: return "Saved places in your SAV-E map."
        case .traditionalChinese: return "你存進 SAV-E 地圖的地點。"
        }
    }

    private var visitedDetail: String {
        switch languageSettings.language {
        case .english: return "Places you marked visited in SAV-E."
        case .traditionalChinese: return "你自己標記為去過的地點。"
        }
    }

    private var citiesDetail: String {
        switch languageSettings.language {
        case .english: return stats.usesSavedPlaces ? "City-level stamps parsed from saved place addresses." : "Appears after SAV-E has saved place addresses."
        case .traditionalChinese: return stats.usesSavedPlaces ? "從已存地點地址整理出的城市級地區。" : "存下帶地址的地點後就會出現。"
        }
    }

    private var waitingClueDetail: String {
        switch languageSettings.language {
        case .english: return "Source clues that still need a confirmed place."
        case .traditionalChinese: return "還需要你確認成具體地點的來源線索。"
        }
    }
}

private struct PassportStampRow: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            SavePostcardPerforatedMedallion(
                systemName: icon,
                tint: tint,
                edge: SaveAtlasPalette.forest
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SaveAtlasType.strong(15))
                    .foregroundStyle(SaveAtlasPalette.forest)
                if let detail {
                    Text(detail)
                        .font(SaveAtlasType.body(11))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Text(value)
                .font(SaveAtlasType.editorial(18))
                .foregroundStyle(SaveAtlasPalette.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SaveAtlasPalette.line.opacity(0.22))
                .frame(height: 1)
                .padding(.leading, 82)
        }
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
                        .background(Color.saveHoney.opacity(0.18))
                        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.62), lineWidth: 1))
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
        case .english: return "Visited counts places you marked visited in SAV-E."
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
                    english: "SHARING RECEIPT",
                    traditionalChinese: "分享收據"
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
                .background(Color.saveNotebookPage.opacity(0.76))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.35), lineWidth: 1))
            }
            .disabled(isUpdating)
            .accessibilityIdentifier("profile.visibility.\(place.id)")
        }
        .padding(.vertical, SaveTheme.Spacing.sm)
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

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: SaveTheme.Spacing.md) {
                SavePostcardPerforatedMedallion(
                    systemName: icon,
                    tint: color.opacity(0.30),
                    edge: color
                )

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
                    .foregroundColor(.saveMutedText)
            }
            .padding(.vertical, SaveTheme.Spacing.sm)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SaveAtlasPalette.kraft.opacity(0.32))
                    .frame(height: 1)
                    .padding(.leading, 62)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
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
                            .background(Color.saveNotebookPage)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
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
                                ? Color.saveHoney.opacity(0.22)
                                : Color.saveCream.opacity(0.08)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.saveNotebookLine.opacity(0.24), lineWidth: 1)
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
