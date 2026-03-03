import SwiftUI

struct CategoryPill: View {
    let category: PlaceCategory
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.iconName)
                .font(.caption2)
            Text(category.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.categoryColor(for: category) : Color.categoryColor(for: category).opacity(0.15))
        .foregroundColor(isSelected ? .white : Color.categoryColor(for: category))
        .cornerRadius(16)
    }
}

#Preview {
    HStack {
        ForEach(PlaceCategory.allCases, id: \.self) { cat in
            CategoryPill(category: cat, isSelected: cat == .food)
        }
    }
    .padding()
}
