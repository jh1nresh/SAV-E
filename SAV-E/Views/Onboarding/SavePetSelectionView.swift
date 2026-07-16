import SwiftUI

struct SavePetSelectionView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var store: SavePetCompanionStore
    @State private var selectedPreset: SavePetPreset = .sprout
    @State private var petName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SaveTheme.Spacing.xl) {
                VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
                    SavePetAvatar(
                        preset: selectedPreset,
                        stage: .hatchling,
                        size: 96
                    )
                    .animation(SaveTheme.Motion.standardSpring, value: selectedPreset)
                    Text(languageSettings.localized(
                        english: "Choose your SAV-E companion",
                        traditionalChinese: "選一隻 SAV-E 夥伴"
                    ))
                    .font(.largeTitle.weight(.bold))
                    .foregroundColor(.saveInk)

                    Text(languageSettings.localized(
                        english: "Verified link analyses help your companion grow.",
                        traditionalChinese: "每次成功分析連結，都會陪牠一起成長。"
                    ))
                    .font(.body)
                    .foregroundColor(.saveMutedText)
                }

                VStack(spacing: SaveTheme.Spacing.md) {
                    ForEach(SavePetPreset.allCases) { preset in
                        Button {
                            SaveHaptics.select()
                            selectedPreset = preset
                            petName = defaultName(for: preset)
                        } label: {
                            SavePetPresetRow(
                                preset: preset,
                                title: title(for: preset),
                                detail: detail(for: preset),
                                isSelected: selectedPreset == preset
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pet.preset.\(preset.rawValue)")
                    }
                }

                VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
                    Text(languageSettings.localized(english: "Name", traditionalChinese: "名字"))
                        .font(SaveTheme.Typography.eyebrow)
                        .foregroundColor(.saveCocoa)
                    TextField(
                        languageSettings.localized(english: "Companion name", traditionalChinese: "夥伴名字"),
                        text: $petName
                    )
                    .textInputAutocapitalization(.words)
                    .font(.title3.weight(.bold))
                    .padding(SaveTheme.Spacing.md)
                    .saveNotebookSurface(cornerRadius: 14)
                    .accessibilityIdentifier("pet.name")

                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(SaveTheme.Typography.supporting)
                            .foregroundColor(.saveError)
                    }
                }

                Button {
                    SaveHaptics.stamp()
                    Task { _ = await store.select(preset: selectedPreset, name: petName) }
                } label: {
                    HStack(spacing: SaveTheme.Spacing.sm) {
                        if store.isSaving {
                            ProgressView()
                                .tint(.saveInk)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        Text(languageSettings.localized(
                            english: store.isSaving ? "Saving…" : "Choose companion",
                            traditionalChinese: store.isSaving ? "儲存中…" : "選擇這位夥伴"
                        ))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SaveBrandPrimaryButtonStyle(fill: .saveHoney))
                .disabled(store.isSaving || petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("pet.confirm")
            }
            .padding(SaveTheme.Spacing.xl)
        }
        .background(SaveDottedBackground().ignoresSafeArea())
        .onAppear {
            if petName.isEmpty {
                petName = defaultName(for: selectedPreset)
            }
        }
    }

    private func title(for preset: SavePetPreset) -> String {
        switch preset {
        case .sprout: return languageSettings.localized(english: "Sprout", traditionalChinese: "芽芽")
        case .spark: return languageSettings.localized(english: "Spark", traditionalChinese: "火花")
        case .cloud: return languageSettings.localized(english: "Cloud", traditionalChinese: "雲朵")
        }
    }

    private func defaultName(for preset: SavePetPreset) -> String {
        title(for: preset)
    }

    private func detail(for preset: SavePetPreset) -> String {
        switch preset {
        case .sprout:
            return languageSettings.localized(english: "Warm and curious", traditionalChinese: "溫暖又好奇")
        case .spark:
            return languageSettings.localized(english: "Bold and energetic", traditionalChinese: "勇敢又有活力")
        case .cloud:
            return languageSettings.localized(english: "Calm and thoughtful", traditionalChinese: "平靜又細心")
        }
    }
}

private struct SavePetPresetRow: View {
    let preset: SavePetPreset
    let title: String
    let detail: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: SaveTheme.Spacing.md) {
            SavePetAvatar(
                preset: preset,
                stage: .hatchling,
                size: 64,
                animates: isSelected
            )

            VStack(alignment: .leading, spacing: SaveTheme.Spacing.xs) {
                Text(title)
                    .font(SaveTheme.Typography.cardTitle)
                    .foregroundColor(.saveInk)
                Text(detail)
                    .font(SaveTheme.Typography.supporting)
                    .foregroundColor(.saveMutedText)
            }

            Spacer()
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(isSelected ? .saveCocoa : .saveDisabled)
        }
        .padding(SaveTheme.Spacing.md)
        .background(isSelected ? accentColor.opacity(0.42) : Color.saveNotebookPage.opacity(0.76))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var accentColor: Color {
        switch preset {
        case .sprout: return .saveLeaf
        case .spark: return .saveHoney
        case .cloud: return .saveSky
        }
    }
}
