import SwiftUI

struct PlaceCard: View {
    let place: Place

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            memoryEgg

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(place.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.saveInk)
                        .lineLimit(1)

                    Spacer()

                    sourceBadge
                }

                Text(place.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let rating = place.googleRating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.saveHoney)
                            Text(String(format: "%.1f", rating))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let priceRange = place.priceRange {
                        Text(priceRange)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(statusLabel)
                        .font(.system(size: 10))
                        .fontWeight(.semibold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(place.status == .visited ? Color.saveMint : Color.saveHoney.opacity(0.42))
                        .foregroundColor(.saveCocoa)
                        .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .saveNotebookPage(cornerRadius: 16)
    }

    private var memoryEgg: some View {
        VStack(spacing: 4) {
            SaveEggBadge(state: .hatched(place.category), size: 44)
            Text("HATCHED")
                .font(.system(size: 7, weight: .black))
                .foregroundColor(.saveCocoa)
        }
        .frame(width: 54)
    }

    private var sourceBadge: some View {
        HStack(spacing: 4) {
            PlatformIcon(platform: place.sourcePlatform, size: 12)
            Text(sourceLabel)
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

    private var statusLabel: String {
        place.status == .visited ? "Visited" : "Hatched"
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
