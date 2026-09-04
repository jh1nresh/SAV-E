import SwiftUI

struct SaveFilteredStampRow: View {
    let place: Place
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: place.category.iconName)
                .font(.caption.weight(.bold))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(width: 36, height: 36)
                .background(SaveAtlasPalette.mint.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(SaveAtlasPalette.line.opacity(0.28), lineWidth: 1)
                }

            Text(place.name)
                .font(SaveAtlasType.strong(15))
                .foregroundStyle(SaveAtlasPalette.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(statusChip.chipLabel(language: language))
                .font(SaveAtlasType.strong(11))
                .foregroundStyle(place.status == .visited ? SaveAtlasPalette.forest : SaveAtlasPalette.ink)
                .padding(.horizontal, 8)
                .frame(minHeight: 26)
                .background(
                    place.status == .visited
                        ? SaveAtlasPalette.mint
                        : SaveAtlasPalette.kraft.opacity(0.62),
                    in: Capsule()
                )
                .overlay {
                    Capsule().stroke(
                        SaveAtlasPalette.line.opacity(0.4),
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: place.status == .wantToGo ? [4, 3] : []
                        )
                    )
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .saveAtlasPaper(radius: 14)
        .accessibilityLabel("\(place.name), \(statusChip.chipLabel(language: language))")
    }

    private var statusChip: SaveMapDrawerIntent {
        place.status == .visited ? .visited : .wantToGo
    }
}
