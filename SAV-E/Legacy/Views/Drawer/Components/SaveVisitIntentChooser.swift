import SwiftUI

/// Want to try / Visited chooser for a confirmed Map Stamp.
///
/// These are Memory Card substates, not new badge cases. Kraft marks the
/// still-open "Want to try" tag. Mint marks Visited, matching the confirmed
/// Map Stamp seal.
struct SaveVisitIntentChooser: View {
    let status: PlaceStatus
    let language: AppLanguage
    var isDisabled: Bool = false
    let onSelect: (PlaceStatus) -> Void

    var body: some View {
        HStack(spacing: 7) {
            intentChip(for: .wantToGo, systemImage: "bookmark")
            intentChip(for: .visited, systemImage: "figure.walk")
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
                Text(intent.visitIntentLabel(language: language))
                    .font(SaveAtlasType.strong(11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
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
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(intent.visitIntentLabel(language: language))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(intent.visitIntentAccessibilityIdentifier())
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
