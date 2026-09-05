import SwiftUI

struct SaveIntentFilterPill: View {
    let intent: SaveMapDrawerIntent
    let language: AppLanguage
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: intent.systemImage)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(SaveAtlasPalette.ink)
                .frame(width: 21, height: 21)
                .background(isSelected ? SaveAtlasPalette.canvas : SaveAtlasPalette.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(SaveAtlasPalette.line.opacity(0.6), lineWidth: 1.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(intent.chipLabel(language: language))
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .frame(height: 34)
        .foregroundStyle(isSelected && intent == .visited ? SaveAtlasPalette.forest : SaveAtlasPalette.ink)
        .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    stroke,
                    style: StrokeStyle(
                        lineWidth: isSelected ? 1.4 : 1.2,
                        dash: intent == .wantToGo && isSelected ? [4, 3] : []
                    )
                )
        )
        .accessibilityLabel(intent.chipLabel(language: language))
        .accessibilityValue(isSelected
            ? language.localized(english: "Selected", traditionalChinese: "已選取")
            : language.localized(english: "Not selected", traditionalChinese: "未選取"))
        .accessibilityIdentifier(intent.accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var fill: Color {
        guard isSelected else { return SaveAtlasPalette.paper }
        switch intent {
        case .wantToGo, .nearby:
            return SaveAtlasPalette.kraft.opacity(0.62)
        case .visited:
            return SaveAtlasPalette.mint
        }
    }

    private var stroke: Color {
        isSelected ? SaveAtlasPalette.line.opacity(0.7) : SaveAtlasPalette.line.opacity(0.5)
    }
}
