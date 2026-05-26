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
                        icon: "map.fill",
                        title: "No Plans Yet",
                        subtitle: "Ask SAV-E to turn confirmed Map Stamps into a practical day plan.",
                        actionTitle: "Create Plan",
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
                    .background(SaveDottedBackground())
                }
            }
            .navigationTitle("Plans")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showNewTrip = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(.saveCocoa)
                    }
                }
            }
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip, viewModel: viewModel)
            }
            .alert("New Plan", isPresented: $showNewTrip) {
                TextField("Plan Name", text: $newTripName)
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
            Text(trip.isOptimized ? "ROUTE READY" : "PLAN DRAFT")
                .font(.caption2.weight(.black))
                .foregroundColor(.saveInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(trip.isOptimized ? Color.saveMint : Color.saveHoney.opacity(0.56))
                .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                .clipShape(Capsule())

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name)
                        .font(.headline)
                        .foregroundColor(.saveInk)

                    Text(trip.city)
                        .font(.subheadline)
                        .foregroundColor(.saveMutedText)
                }

                Spacer()

                if trip.isOptimized {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.saveSignal)
                        .font(.title3)
                }
            }

            HStack(spacing: 16) {
                Label(trip.dateRangeText, systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.saveMutedText)

                Label("\(trip.places.count) Map Stamp stops", systemImage: "mappin")
                    .font(.caption)
                    .foregroundColor(.saveMutedText)
            }
        }
        .padding(16)
        .saveNotebookPage(cornerRadius: 18)
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
                .foregroundColor(.saveMutedText)
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
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.vertical, 10)
                    .background(Color.saveHoney)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.6)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
