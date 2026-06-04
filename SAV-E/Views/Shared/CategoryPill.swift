import SwiftUI

struct CategoryPill: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let category: PlaceCategory
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category.iconName)
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.saveInk)
                .frame(width: 21, height: 21)
                .background(isSelected ? Color.saveMint : Color.saveNotebookPage)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 1.1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(category.displayName(language: languageSettings.language))
                .font(.caption2.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .frame(height: 34)
        .background(isSelected ? Color.saveHoney : Color.saveNotebookPage.opacity(0.86))
        .foregroundColor(.saveInk)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: isSelected ? 1.8 : 1.2)
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
    .environmentObject(AppLanguageSettings())
}
