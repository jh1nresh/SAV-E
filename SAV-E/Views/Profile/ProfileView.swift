import SwiftUI
import PhotosUI
import UIKit

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showEditProfile = false
    @State private var showLanguageSettings = false
    @State private var draftDisplayName = ""
    @State private var draftAvatarData: Data?
    @State private var localSavedPlaces: [Place] = []
    var savedPlaces: [Place] = []
    var waitingClues: Int = 0
    var onUpdatePlaceVisibility: (Place, PlaceVisibility) async throws -> Void = { _, _ in }

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

                    StatsView(stats: passportStats)

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
                    PassportCountingRulesPanel(stats: passportStats)
                    PassportVisibilityPanel(
                        places: passportPlaces,
                        onUpdate: updatePlaceVisibility
                    )

                    VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
                        Text(languageSettings.text(.passportControls))
                            .font(SaveTheme.Typography.eyebrow)
                            .foregroundColor(.saveCocoa)
                            .padding(.horizontal, SaveTheme.Spacing.xs)

                        SettingsRow(
                            icon: "globe.asia.australia",
                            title: languageSettings.text(.language),
                            detail: languageSettings.language.displayName,
                            color: .saveCocoa
                        ) {
                            SaveHaptics.tap()
                            showLanguageSettings = true
                        }
                        .accessibilityIdentifier("profile.language")

                        NavigationLink {
                            SaveMemoryDebugView()
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

                        SettingsRow(icon: "arrow.right.square", title: languageSettings.text(.signOut), color: .saveError) {
                            SaveHaptics.tap()
                            Task { await viewModel.signOut() }
                        }
                        .accessibilityIdentifier("profile.signOut")
                    }
                    .padding(SaveTheme.Spacing.md)
                    .profileGlassSurface(cornerRadius: 18, tint: .saveCream, fillOpacity: 0.14, strokeOpacity: 0.24, lineWidth: 1.1)
                    .padding(.horizontal)
                }
                .padding(.bottom, SaveTheme.Spacing.xl)
                .profileGlassGroup(spacing: SaveTheme.Spacing.lg)
                .padding(.top, 2)
            }
            .background(ProfileGlassBackground(colorScheme: colorScheme))
            .toolbar(.hidden, for: .navigationBar)
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
    @Environment(\.colorScheme) private var colorScheme
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
                                    .stroke(Color.saveNotebookLine, lineWidth: 2)
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
                                    .stroke(Color.saveNotebookLine, lineWidth: 2)
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
                        .profileGlassSurface(cornerRadius: 14, tint: .saveCream, fillOpacity: 0.12, strokeOpacity: 0.24, lineWidth: 1, isInteractive: true)

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
                .profileGlassSurface(cornerRadius: 20, tint: .saveCream, fillOpacity: 0.14, strokeOpacity: 0.24, lineWidth: 1)
                .padding(.horizontal)

                Spacer()
            }
            .background(ProfileGlassBackground(colorScheme: colorScheme))
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(.clear)
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
    let onClose: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            PassportIconButton(systemName: "xmark", action: onClose)

            VStack(alignment: .leading, spacing: 2) {
                Text(languageSettings.text(.profileTitle))
                    .font(SaveTheme.Typography.cardTitle)
                    .foregroundColor(.saveInk)
                Text(languageSettings.memoWaitingText(waitingClues))
                    .font(SaveTheme.Typography.supporting)
                    .foregroundColor(.saveMutedText)
            }

            Spacer()

            Button(action: onEdit) {
                HStack(spacing: SaveTheme.Spacing.xs) {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.bold))
                    Text(languageSettings.text(.edit))
                        .font(.caption.weight(.bold))
                }
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, SaveTheme.Spacing.md)
                    .frame(height: 38)
                    .profileGlassSurface(cornerRadius: 14, tint: .saveHoney, fillOpacity: 0.34, strokeOpacity: 0.42, lineWidth: 1.1, isInteractive: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.edit")
        }
        .padding(SaveTheme.Spacing.sm)
        .profileGlassSurface(cornerRadius: 22, tint: .saveCream, fillOpacity: 0.16, strokeOpacity: 0.28)
    }
}

private struct PassportIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SaveIconTile(
                systemName: systemName,
                size: 36,
                iconSize: 15,
                fill: Color.saveCream.opacity(0.16),
                foreground: .saveCocoa,
                strokeOpacity: 0.48,
                cornerRadius: 10
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PassportHero: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let profile: UserProfile

    var body: some View {
        HStack(spacing: 0) {
            PassportNotebookSpine(color: .saveNotebookSpine)

            VStack(alignment: .leading, spacing: SaveTheme.Spacing.md) {
                HStack(alignment: .top, spacing: SaveTheme.Spacing.md) {
                    ProfileAvatarView(avatarURLString: profile.avatarUrl, size: 78)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "book.closed")
                                // Intentional one-off badge glyph size; no token maps cleanly.
                                .font(.system(size: 18, weight: .black))
                                .foregroundColor(.saveInk)
                                .frame(width: 28, height: 28)
                                .profileGlassCapsule(tint: .saveCream, fillOpacity: 0.12, strokeOpacity: 0.34, lineWidth: 1)
                                .clipShape(Circle())
                                .offset(x: 6, y: 6)
                        }

                    VStack(alignment: .leading, spacing: SaveTheme.Spacing.xs) {
                        Text(languageSettings.text(.profileTitle))
                            .font(SaveTheme.Typography.eyebrow)
                            .foregroundColor(.saveCocoa)
                        Text(profile.displayName)
                            // Intentional large display name; .title2 is the hero size, no token.
                            .font(.title2.weight(.bold))
                            .foregroundColor(.saveInk)
                            .lineLimit(2)
                        Text(profile.email ?? languageSettings.text(.localMemoHelper))
                            .font(SaveTheme.Typography.supporting)
                            .foregroundColor(.saveMutedText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: SaveTheme.Spacing.sm) {
                    PassportBadge(text: languageSettings.text(.memoHelper), color: .saveHoney)
                    PassportBadge(text: visitedBadgeText, color: .saveSignal)
                    Spacer()
                }
            }
            .padding(SaveTheme.Spacing.lg)
        }
        .profileGlassSurface(cornerRadius: 22, tint: .saveCream, fillOpacity: 0.18, strokeOpacity: 0.32, lineWidth: 1.2)
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
        .shadow(color: Color.saveCocoa.opacity(0.12), radius: 8, x: 0, y: 4)
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
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.lg) {
            HStack {
                Text(languageSettings.text(.passportStamps))
                    .font(SaveTheme.Typography.cardTitle)
                    .foregroundColor(.saveInk)
                Spacer()
                Text(languageSettings.text(.memoBook))
                    .font(SaveTheme.Typography.stamp)
                    .foregroundColor(.saveCocoa)
                    .padding(.horizontal, SaveTheme.Spacing.sm)
                    .padding(.vertical, SaveTheme.Spacing.xs)
                    .background(Color.saveHoney.opacity(0.18))
                    .clipShape(Capsule())
            }

            PassportStampRow(
                icon: "rectangle.stack",
                title: languageSettings.text(.memoryCards),
                value: languageSettings.savedCountText(stats.savedCount),
                detail: mapStampDetail
            )
            PassportStampRow(
                icon: "figure.walk",
                title: languageSettings.text(.visited),
                value: languageSettings.visitedCountText(stats.visitedCount),
                detail: visitedDetail
            )
            PassportStampRow(
                icon: "building.2",
                title: languageSettings.text(.cities),
                value: languageSettings.cityCountText(stats.citiesCount),
                detail: citiesDetail
            )
            if !stats.cityNames.isEmpty {
                PassportCityStrip(cityNames: stats.cityNames)
            }
            PassportStampRow(
                icon: "circle.hexagongrid",
                title: languageSettings.text(.waitingClues),
                value: languageSettings.waitingPlaceText(stats.waitingClues),
                detail: waitingClueDetail
            )
            PassportStampRow(icon: "calendar", title: languageSettings.text(.memberSince), value: profile.createdAt.formatted(date: .abbreviated, time: .omitted))
        }
        .padding(SaveTheme.Spacing.lg)
        .profileGlassSurface(cornerRadius: 18, tint: .saveCream, fillOpacity: 0.16, strokeOpacity: 0.28)
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
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            SaveIconTile(
                systemName: icon,
                size: 32,
                iconSize: 13,
                fill: Color.saveHoney.opacity(0.16),
                foreground: .saveCocoa,
                strokeOpacity: 0.48,
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SaveTheme.Typography.rowTitle)
                    .foregroundColor(.saveInk)
                Text(value)
                    .font(SaveTheme.Typography.supporting)
                    .foregroundColor(.saveMutedText)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.saveCocoa.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
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
    }
}

private struct PassportCountingRulesPanel: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let stats: PassportStats

    var body: some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
            HStack(spacing: SaveTheme.Spacing.sm) {
                Image(systemName: "seal")
                    .font(SaveTheme.Typography.sectionLabel)
                    .foregroundColor(.saveCocoa)
                Text(title)
                    .font(SaveTheme.Typography.sectionLabel)
                    .foregroundColor(.saveCocoa)
                Spacer()
            }

            VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
                PassportRuleLine(icon: "building.2", text: cityRule)
                PassportRuleLine(icon: "figure.walk", text: visitedRule)
            }
        }
        .padding(SaveTheme.Spacing.md)
        .profileGlassSurface(cornerRadius: 16, tint: .saveCream, fillOpacity: 0.14, strokeOpacity: 0.24, lineWidth: 1)
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
                Image(systemName: "person.2.wave.2.fill")
                    .font(SaveTheme.Typography.sectionLabel)
                    .foregroundColor(.saveCocoa)
                Text(languageSettings.localized(english: "Sharing controls", traditionalChinese: "分享設定"))
                    .font(SaveTheme.Typography.sectionLabel)
                    .foregroundColor(.saveCocoa)
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
        .padding(SaveTheme.Spacing.md)
        .profileGlassSurface(cornerRadius: 16, tint: .saveCream, fillOpacity: 0.14, strokeOpacity: 0.24, lineWidth: 1)
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
                .profileGlassCapsule(tint: .saveCream, fillOpacity: 0.14, strokeOpacity: 0.24, isInteractive: true)
            }
            .disabled(isUpdating)
            .accessibilityIdentifier("profile.visibility.\(place.id)")
        }
        .padding(SaveTheme.Spacing.sm)
        .profileGlassSurface(cornerRadius: 12, tint: .saveCream, fillOpacity: 0.10, strokeOpacity: 0.18, lineWidth: 1)
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
    var action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: SaveTheme.Spacing.md) {
                SaveIconTile(
                    systemName: icon,
                    size: 32,
                    iconSize: 13,
                    fill: color.opacity(0.16),
                    foreground: .saveCocoa,
                    strokeOpacity: 0.48,
                    cornerRadius: 10
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SaveTheme.Typography.rowTitle)
                        .foregroundColor(.saveInk)

                    if let detail {
                        Text(detail)
                            .font(SaveTheme.Typography.supporting)
                            .foregroundColor(.saveMutedText)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.saveMutedText)
            }
            .padding(.vertical, SaveTheme.Spacing.md)
            .padding(.horizontal, SaveTheme.Spacing.sm)
            .profileGlassSurface(cornerRadius: 14, tint: color, fillOpacity: 0.10, strokeOpacity: 0.18, lineWidth: 1, isInteractive: true)
        }
        .buttonStyle(.plain)
    }
}

private struct LanguageSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.colorScheme) private var colorScheme

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
                                    .stroke(Color.saveNotebookLine, lineWidth: 2)
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
            .background(ProfileGlassBackground(colorScheme: colorScheme))
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationBackground(.clear)
    }
}

struct ProfileGlassBackground: View {
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
                Color.black.opacity(0.035)
            ]
        }
        return [
            Color.white.opacity(0.01),
            Color.saveCream.opacity(0.025)
        ]
    }

    private var baseTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.04) : Color.white.opacity(0.03)
    }

    private var materialOpacity: Double {
        0.24
    }

    private var topStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.24)
    }
}

extension View {
    @ViewBuilder
    func profileGlassGroup(spacing: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func profileGlassSurface(
        cornerRadius: CGFloat,
        tint: Color = .saveCream,
        fillOpacity: Double = 0.14,
        strokeOpacity: Double = 0.26,
        lineWidth: CGFloat = 1,
        isInteractive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(tint.opacity(fillOpacity))
                .glassEffect(
                    .regular
                        .tint(tint.opacity(0.18))
                        .interactive(isInteractive),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(strokeOpacity), lineWidth: lineWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(tint.opacity(fillOpacity), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(strokeOpacity), lineWidth: lineWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func profileGlassCapsule(
        tint: Color = .saveCream,
        fillOpacity: Double = 0.14,
        strokeOpacity: Double = 0.26,
        lineWidth: CGFloat = 1,
        isInteractive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(tint.opacity(fillOpacity))
                .glassEffect(
                    .regular
                        .tint(tint.opacity(0.18))
                        .interactive(isInteractive),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(strokeOpacity), lineWidth: lineWidth))
                .clipShape(Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .background(tint.opacity(fillOpacity), in: Capsule())
                .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(strokeOpacity), lineWidth: lineWidth))
                .clipShape(Capsule())
        }
    }
}

#Preview {
    ProfileView()
        .environment(\.appLanguageSettings, AppLanguageSettings())
}
