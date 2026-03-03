import SwiftUI

struct TripPlannerView: View {
    @StateObject private var viewModel = TripViewModel()
    @State private var showNewTrip = false
    @State private var newTripName = ""
    @State private var newTripCity = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.trips.isEmpty {
                    EmptyStateView(
                        icon: "airplane",
                        title: "No Trips Yet",
                        subtitle: "Plan your next adventure by creating a trip and adding saved places.",
                        actionTitle: "Create Trip",
                        action: { showNewTrip = true }
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.trips) { trip in
                                NavigationLink(value: trip) {
                                    TripCard(trip: trip)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .background(Color.wanderlyCream)
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showNewTrip = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(.wanderlyTerracotta)
                    }
                }
            }
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip, viewModel: viewModel)
            }
            .alert("New Trip", isPresented: $showNewTrip) {
                TextField("Trip Name", text: $newTripName)
                TextField("City", text: $newTripCity)
                Button("Create") {
                    Task {
                        await viewModel.createTrip(name: newTripName, city: newTripCity)
                        newTripName = ""
                        newTripCity = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    newTripName = ""
                    newTripCity = ""
                }
            }
        }
        .task {
            await viewModel.loadTrips()
        }
    }
}

// MARK: - Trip Card

struct TripCard: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name)
                        .font(.headline)
                        .foregroundColor(.wanderlyCharcoal)

                    Text(trip.city)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if trip.isOptimized {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.wanderlySage)
                        .font(.title3)
                }
            }

            HStack(spacing: 16) {
                Label(trip.dateRangeText, systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("\(trip.places.count) stops", systemImage: "mappin")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .wanderlyCard()
    }
}

// MARK: - Trip Detail View

struct TripDetailView: View {
    let trip: Trip
    @ObservedObject var viewModel: TripViewModel

    var body: some View {
        List {
            Section {
                HStack {
                    Label(trip.dateRangeText, systemImage: "calendar")
                    Spacer()
                    Label("\(trip.places.count) stops", systemImage: "mappin")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Section("Timeline") {
                ForEach(trip.places) { stop in
                    TripTimelineCard(stop: stop)
                }
                .onMove { from, to in
                    viewModel.reorderStops(trip: trip, from: from, to: to)
                }
            }

            Section {
                Button(action: {
                    Task { await viewModel.optimizeRoute(for: trip) }
                }) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text(viewModel.isOptimizing ? "Optimizing..." : "Optimize Route")
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .background(Color.wanderlyTerracotta)
                    .cornerRadius(16)
                }
                .disabled(viewModel.isOptimizing)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(trip.name)
        .toolbar {
            EditButton()
        }
    }
}

#Preview {
    TripPlannerView()
}
