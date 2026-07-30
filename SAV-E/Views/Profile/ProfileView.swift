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
    var onUpdatePlaceVisibility: (Place, PlaceVisibility) async throws -> Void = { _, _ in }
    var onSaveGoogleTakeoutImport: ([ImportedPlaceDraft]) async throws -> GoogleTakeoutSaveSummary = { _ in
        GoogleTakeoutSaveSummary(saved: 0, skippedDuplicates: 0, reviewDrafts: 0)
    }

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
