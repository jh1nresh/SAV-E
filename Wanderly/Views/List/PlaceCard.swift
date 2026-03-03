import SwiftUI

struct PlaceCard: View {
    let place: Place

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: place.category.iconName)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.categoryColor(for: place.category))
                .cornerRadius(12)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(place.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.wanderlyCharcoal)
                        .lineLimit(1)

                    Spacer()

                    PlatformIcon(platform: place.sourcePlatform, size: 14)
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
                                .foregroundColor(.orange)
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

                    Text(place.status.displayName)
                        .font(.system(size: 10))
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(place.status == .visited ? Color.wanderlySage.opacity(0.3) : Color.wanderlyTerracotta.opacity(0.15))
                        .foregroundColor(place.status == .visited ? Color.wanderlySage : Color.wanderlyTerracotta)
                        .cornerRadius(6)
                }
            }
        }
        .padding(12)
        .wanderlyCard()
    }
}

#Preview {
    VStack {
        PlaceCard(place: .mock)
        PlaceCard(place: Place.mockList[1])
    }
    .padding()
    .background(Color.wanderlyCream)
}
