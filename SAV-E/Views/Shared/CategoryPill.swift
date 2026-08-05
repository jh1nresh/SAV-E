import SwiftUI

struct CategoryPill: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let category: PlaceCategory
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.iconName)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.saveInk)
                .frame(width: 21, height: 21)
                .background(isSelected ? SaveAtlasPalette.canvas : SaveAtlasPalette.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(SaveAtlasPalette.line.opacity(0.6), lineWidth: 1.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(category.displayName(language: languageSettings.language))
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .frame(height: 34)
        // Spec P2 follow-up: kraft selected state on Atlas paper — this pill
        // renders inside the Atlas ask drawer's FILTERS strip.
        .background(isSelected ? SaveAtlasPalette.kraft.opacity(0.62) : SaveAtlasPalette.paper)
        .foregroundColor(.saveInk)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(isSelected ? 0.7 : 0.5), lineWidth: isSelected ? 1.4 : 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel(category.displayName(language: languageSettings.language))
        .accessibilityValue(isSelected ? selectedAccessibilityValue : notSelectedAccessibilityValue)
    }

    private var selectedAccessibilityValue: String {
        languageSettings.localized(english: "Selected", traditionalChinese: "已選取")
    }

    private var notSelectedAccessibilityValue: String {
        languageSettings.localized(english: "Not selected", traditionalChinese: "未選取")
    }
}

#Preview {
    HStack {
        ForEach(PlaceCategory.allCases, id: \.self) { cat in
            CategoryPill(category: cat, isSelected: cat == .food)
        }
    }
    .padding()
    .environment(\.appLanguageSettings, AppLanguageSettings())
}
