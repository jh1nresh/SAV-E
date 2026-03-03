import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Avatar & Name
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 72))
                            .foregroundColor(.wanderlySage)

                        Text(viewModel.profile.displayName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.wanderlyCharcoal)

                        if let email = viewModel.profile.email {
                            Text(email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if viewModel.profile.isPremium {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.caption)
                                Text("Premium")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.wanderlyAmber)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.wanderlyAmber.opacity(0.15))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.top, 16)

                    // Stats
                    StatsView(profile: viewModel.profile)

                    // World map placeholder
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your World Map")
                            .font(.headline)
                            .foregroundColor(.wanderlyCharcoal)

                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.wanderlySage.opacity(0.15))
                            .frame(height: 180)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "globe.americas.fill")
                                        .font(.largeTitle)
                                        .foregroundColor(.wanderlySage)
                                    Text("\(viewModel.profile.citiesCount) cities explored")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                    .padding(.horizontal)

                    // Collections
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Collections")
                            .font(.headline)
                            .foregroundColor(.wanderlyCharcoal)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(viewModel.profile.collections) { collection in
                                    CollectionCard(collection: collection)
                                }

                                // Add collection
                                Button(action: {}) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "plus")
                                            .font(.title2)
                                            .foregroundColor(.wanderlyTerracotta)
                                        Text("New")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(width: 100, height: 100)
                                    .background(Color.wanderlyTerracotta.opacity(0.08))
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.wanderlyTerracotta.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6]))
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Settings section
                    VStack(spacing: 0) {
                        SettingsRow(icon: "crown", title: "Upgrade to Premium", color: .wanderlyAmber)
                        SettingsRow(icon: "bell", title: "Notifications", color: .wanderlyTerracotta)
                        SettingsRow(icon: "questionmark.circle", title: "Help & Feedback", color: .wanderlySage)
                        SettingsRow(icon: "arrow.right.square", title: "Sign Out", color: .red) {
                            Task { await viewModel.signOut() }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 32)
            }
            .background(Color.wanderlyCream)
            .navigationTitle("Profile")
        }
        .task {
            await viewModel.loadProfile()
        }
    }
}

// MARK: - Collection Card

struct CollectionCard: View {
    let collection: PlaceCollection

    var body: some View {
        VStack(spacing: 8) {
            Text(collection.emoji)
                .font(.largeTitle)
            Text(collection.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.wanderlyCharcoal)
            Text("\(collection.placeIds.count) places")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 100, height: 100)
        .wanderlyCard()
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    var action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
                    .frame(width: 24)

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.wanderlyCharcoal)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
        }
    }
}

#Preview {
    ProfileView()
}
