import SwiftUI

struct PlaceCard: View {
    let place: Place
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            memoryBadge

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(place.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.saveInk)
                        .lineLimit(1)

                    Spacer()

                    memoryStatusBadge
                }

                Text(place.address)
                    .font(.caption)
                    .foregroundColor(.saveMutedText)
                    .lineLimit(1)

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
        .padding(12)
        .saveNotebookPage(cornerRadius: 16)
    }

    private var memoryBadge: some View {
        VStack(spacing: 4) {
            SaveMemoryBadge(state: .saved(place.category), size: 44)
            Text("SAVED")
                .font(.system(size: 7, weight: .black))
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
        if let url = normalizedSourceURL {
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

    private var normalizedSourceURL: URL? {
        guard let raw = place.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }

        if let url = URL(string: raw), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(raw)")
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
