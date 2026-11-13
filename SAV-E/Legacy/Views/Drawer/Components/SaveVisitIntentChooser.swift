import SwiftUI

/// Want to try / Visited chooser for a confirmed Map Stamp.
///
/// These are Memory Card substates, not new badge cases. Kraft marks the
/// still-open "Want to try" tag. Mint marks Visited, matching the confirmed
/// Map Stamp seal.
struct SaveVisitIntentChooser: View {
#if SAVVY_CITY_MVP
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
#endif
    let status: PlaceStatus
    let language: AppLanguage
    var isDisabled: Bool = false
    let onSelect: (PlaceStatus) -> Void

    var body: some View {
        Group {
#if SAVVY_CITY_MVP
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    intentChip(for: .wantToGo, systemImage: "bookmark")
                    intentChip(for: .visited, systemImage: "figure.walk")
                }
            } else {
                HStack(spacing: 7) {
                    intentChip(for: .wantToGo, systemImage: "bookmark")
                    intentChip(for: .visited, systemImage: "figure.walk")
                }
            }
#else
        HStack(spacing: 7) {
            intentChip(for: .wantToGo, systemImage: "bookmark")
            intentChip(for: .visited, systemImage: "figure.walk")
        }
#endif
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer.saved.visitIntent")
    }

    private func intentChip(for intent: PlaceStatus, systemImage: String) -> some View {
        let isSelected = status == intent
        return Button {
            guard !isDisabled, status != intent else { return }
            SaveHaptics.tap()
            onSelect(intent)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                Text(intentLabel(intent))
#if SAVVY_CITY_MVP
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
#else
                    .font(SaveAtlasType.strong(11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
#endif
            }
#if SAVVY_CITY_MVP
            .foregroundStyle(isSelected ? CityMVPFormStyle.canvas : CityMVPFormStyle.ink)
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(isSelected ? CityMVPFormStyle.ink : CityMVPFormStyle.card, in: Capsule())
            .contentShape(Capsule())
#else
            .foregroundStyle(foreground(isSelected: isSelected, intent: intent))
            .padding(.horizontal, 9)
            .frame(minHeight: 32)
            .background(fill(isSelected: isSelected, intent: intent), in: Capsule())
            .overlay {
                Capsule().stroke(
                    stroke(isSelected: isSelected, intent: intent),
                    style: StrokeStyle(
                        lineWidth: isSelected ? 1.4 : 1.1,
                        dash: intent == .wantToGo && isSelected ? [4, 3] : []
                    )
                )
            }
#endif
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(intentLabel(intent))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(intent.visitIntentAccessibilityIdentifier())
    }

    private func intentLabel(_ intent: PlaceStatus) -> String {
#if SAVVY_CITY_MVP
        if intent == .wantToGo {
            return language.localized(english: "Want to go", traditionalChinese: "想去")
        }
#endif
        return intent.visitIntentLabel(language: language)
    }

    private func fill(isSelected: Bool, intent: PlaceStatus) -> Color {
        guard isSelected else { return SaveAtlasPalette.paper }
        switch intent {
        case .wantToGo:
            return SaveAtlasPalette.kraft.opacity(0.62)
        case .visited:
            return SaveAtlasPalette.mint
        }
    }

    private func stroke(isSelected: Bool, intent: PlaceStatus) -> Color {
        guard isSelected else { return SaveAtlasPalette.line.opacity(0.46) }
        switch intent {
        case .wantToGo:
            return SaveAtlasPalette.kraft
        case .visited:
            return SaveAtlasPalette.forest.opacity(0.46)
        }
    }

    private func foreground(isSelected: Bool, intent: PlaceStatus) -> Color {
        if isSelected && intent == .visited {
            return SaveAtlasPalette.forest
        }
        return SaveAtlasPalette.ink
    }
}
