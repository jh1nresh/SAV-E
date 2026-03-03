import SwiftUI

struct StatsView: View {
    let profile: UserProfile

    var body: some View {
        HStack(spacing: 0) {
            StatItem(value: "\(profile.savedCount)", label: "Saved", color: .wanderlyTerracotta)
            Divider().frame(height: 40)
            StatItem(value: "\(profile.visitedCount)", label: "Visited", color: .wanderlySage)
            Divider().frame(height: 40)
            StatItem(value: "\(profile.citiesCount)", label: "Cities", color: .wanderlyAmber)
        }
        .padding(.vertical, 16)
        .wanderlyCard()
        .padding(.horizontal)
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    StatsView(profile: .mock)
        .padding()
        .background(Color.wanderlyCream)
}
