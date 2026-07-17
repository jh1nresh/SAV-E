import SwiftUI

struct SavePetCompanionCard: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let profile: UserProfile

    var body: some View {
        if let preset = profile.petPreset {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accentColor(for: preset))
                    .frame(width: 10)

                VStack(alignment: .leading, spacing: SaveTheme.Spacing.md) {
                    HStack(spacing: SaveTheme.Spacing.md) {
                        SavePetAvatar(
                            preset: preset,
                            stage: profile.petStage,
                            size: 82
                        )

                        VStack(alignment: .leading, spacing: SaveTheme.Spacing.xs) {
                            Text(languageSettings.localized(
                                english: "Your SAV-E companion",
                                traditionalChinese: "你的 SAV-E 夥伴"
                            ))
                            .font(SaveTheme.Typography.eyebrow)
                            .foregroundColor(.saveCocoa)

                            Text(profile.petName ?? presetTitle(preset))
                                .font(.title3.weight(.bold))
                                .foregroundColor(.saveInk)
                                .lineLimit(1)

                            HStack(spacing: SaveTheme.Spacing.sm) {
                                Label(stageTitle(profile.petStage), systemImage: "arrow.up.right.circle.fill")
                                    .font(SaveTheme.Typography.supporting)
                                    .foregroundColor(.saveMutedText)
                                    .lineLimit(1)

                                Text("\(profile.petXP) XP")
                                    .font(SaveTheme.Typography.stamp)
                                    .foregroundColor(.saveInk)
                                    .padding(.horizontal, SaveTheme.Spacing.sm)
                                    .frame(height: 28)
                                    .background(Color.saveHoney.opacity(0.58))
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ProgressView(value: profile.petStage.progress(xp: profile.petXP))
                        .tint(accentColor(for: preset))

                    Text(progressText)
                        .font(SaveTheme.Typography.supporting)
                        .foregroundColor(.saveMutedText)
                }
                .padding(SaveTheme.Spacing.lg)
            }
            .saveNotebookPage(cornerRadius: 22)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile.petCompanion")
        }
    }

    private var progressText: String {
        guard let nextThreshold = profile.petStage.nextThreshold else {
            return languageSettings.localized(
                english: "Guardian stage reached",
                traditionalChinese: "已成長為守護夥伴"
            )
        }
        let remaining = max(nextThreshold - profile.petXP, 0)
        return languageSettings.localized(
            english: "\(remaining) XP until the next stage",
            traditionalChinese: "再 \(remaining) XP 進入下一階段"
        )
    }

    private func stageTitle(_ stage: SavePetStage) -> String {
        switch stage {
        case .hatchling:
            return languageSettings.localized(english: "Hatchling", traditionalChinese: "幼生期")
        case .companion:
            return languageSettings.localized(english: "Companion", traditionalChinese: "夥伴期")
        case .guardian:
            return languageSettings.localized(english: "Guardian", traditionalChinese: "守護期")
        }
    }

    private func presetTitle(_ preset: SavePetPreset) -> String {
        switch preset {
        case .sprout: return languageSettings.localized(english: "Sprout", traditionalChinese: "芽芽")
        case .spark: return languageSettings.localized(english: "Spark", traditionalChinese: "火花")
        case .cloud: return languageSettings.localized(english: "Cloud", traditionalChinese: "雲朵")
        }
    }

    private func accentColor(for preset: SavePetPreset) -> Color {
        switch preset {
        case .sprout: return .saveLeaf
        case .spark: return .saveHoney
        case .cloud: return .saveSky
        }
    }
}
