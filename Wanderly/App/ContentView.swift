import SwiftUI

struct ContentView: View {
    @StateObject private var mapVM = MapViewModel()
    @StateObject private var drawerVM = AIDrawerViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var drawerDetent: PresentationDetent = .height(72)

    var body: some View {
        MapView(viewModel: mapVM)
            .sheet(isPresented: .constant(true)) {
                AIDrawerView(
                    viewModel: drawerVM,
                    drawerDetent: $drawerDetent,
                    existingPlacesForImport: mapVM.places,
                    onSaveGoogleTakeoutImport: { drafts in
                        try await mapVM.saveImportedPlaces(drafts)
                    }
                )
                    .presentationDetents([.height(72), .medium, .large], selection: $drawerDetent)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .interactiveDismissDisabled(true)
                    .presentationBackground(Color.wanderlyCream)
            }
            .onChange(of: drawerVM.mapAction) { _, action in
                if let action { mapVM.apply(action) }
            }
            .onChange(of: mapVM.selectedPlace) { _, place in
                if let place { drawerVM.showPlace(place) }
            }
            .onChange(of: mapVM.places) { _, places in
                drawerVM.places = places
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await mapVM.loadPlaces() }
            }
            .task {
                drawerVM.places = mapVM.places
            }
    }
}

#Preview {
    ContentView()
}
