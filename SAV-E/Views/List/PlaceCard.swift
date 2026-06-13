import SwiftUI

struct PlaceCard: View {
    let place: Place
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            memoryBadge

            VStack(alignment: .leading, spacing: SaveTheme.Spacing.xs) {
                HStack(alignment: .top) {
                    Text(place.name)
                        .font(SaveTheme.Typography.rowTitle)
                        .foregroundColor(.saveInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    memoryStatusBadge
                }

                Text(place.address)
                    .font(.caption)
                    .foregroundColor(.saveMutedText)
                    .lineLimit(1)

                if let signal = place.socialSignal {
                    friendSignalBadge(signal)
                }

                HStack(spacing: 8) {
                    if let rating = place.googleRating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.saveHoney)
                            Text(String(format: "%.1f", rating))
                                .font(.caption2)
                                .foregroundColor(.saveMutedText)
                        }
                    }

                    if let priceRange = place.priceRange {
                        Text(priceRange)
                            .font(.caption2)
                            .foregroundColor(.saveMutedText)
                    }

                    Spacer()

                    sourceBadge
                }
            }
        }
        .padding(SaveTheme.Spacing.md)
        .saveNotebookPage(cornerRadius: 16)
    }

    private var memoryBadge: some View {
        VStack(spacing: 4) {
            SaveMemoryBadge(state: .saved(place.category), size: 44)
            Text(place.status == .visited ? "TRIED" : "STAMP")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundColor(.saveCocoa)
        }
        .frame(width: 54)
    }

    private var memoryStatusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: place.status == .visited ? "seal.fill" : "checkmark.seal.fill")
                .font(.caption2.weight(.black))
            Text(place.status.memoryCardLabel)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.saveNotebookPage)
        .overlay(
            Capsule()
                .stroke(Color.saveNotebookLine.opacity(0.28), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var sourceLabel: String {
        place.sourcePlatform == .other ? "Memory" : "\(place.sourcePlatform.displayName) memory"
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let url = place.primarySourceURL {
            Button {
                openURL(url)
            } label: {
                sourceBadgeLabel(isLinked: true)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open source")
        } else {
            sourceBadgeLabel(isLinked: false)
        }
    }

    private func sourceBadgeLabel(isLinked: Bool) -> some View {
        HStack(spacing: 3) {
            if isLinked {
                Image(systemName: "link")
                    .font(.system(size: 9, weight: .black))
            }
            Text(sourceLabel.uppercased())
                .font(.system(size: 10))
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.saveHoney.opacity(0.42))
        .foregroundColor(.saveCocoa)
        .cornerRadius(8)
    }

    private func friendSignalBadge(_ signal: PlaceSocialSignal) -> some View {
        HStack(spacing: 5) {
            Image(systemName: signal.kind.pinSystemImage)
                .font(.system(size: 10, weight: .black))
            Text(signal.displayText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(.saveCocoa)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.saveSky.opacity(signal.kind == .trending ? 0.18 : 0.28))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.25), lineWidth: 1))
    }

}

#Preview {
    VStack {
        PlaceCard(place: .mock)
        PlaceCard(place: Place.mockList[1])
    }
    .padding()
    .background(SaveDottedBackground())
}
