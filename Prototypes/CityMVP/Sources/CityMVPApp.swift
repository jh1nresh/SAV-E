#if SAVVY_CITY_MVP
import SwiftUI
import MapKit

@main
struct CityMVPApp: App {
    @AppStorage(CityMVPStyle.nightPreference) private var night = false
    @StateObject private var language = AppLanguageSettings()
    var body: some Scene {
        WindowGroup {
            ContentView(storageScope: .reviewerDemo)
                .environment(\.appLanguageSettings, language)
                .environmentObject(PrivyAuthService.shared)
                .preferredColorScheme(night ? .dark : .light)
        }
    }
    init() {
        // New app container, no production entitlements, no login or remote saves.
        UserDefaults.standard.set(true, forKey: "hasSeenMapTour")
    }
}

@MainActor
enum CityMVPStorage {
    static func makeMapViewModel() -> MapViewModel {
        let vm = MapViewModel(
            mapCandidateUserIDProvider: { nil },
            pendingImportService: ReviewDemoStorage.pendingImportService,
            saveLocalVaultService: ReviewDemoStorage.localVaultService,
            correctionEventStore: ReviewDemoStorage.correctionEventStore,
            collaborativeListStore: ReviewDemoStorage.collaborativeListStore,
            referralHandoffStore: ReviewDemoStorage.referralHandoffStore,
            usesRemotePersistence: false
        )
        vm.cameraPosition = .camera(CityMVPCameras.world)
        return vm
    }
}

enum CityMVPCameras {
    static var world: MapCamera {
        MapCamera(centerCoordinate: .init(latitude: 25.033968, longitude: 121.564468),
                  distance: 64_000_000, heading: 0, pitch: 0)
    }

    static var taipei: MapCamera {
        MapCamera(centerCoordinate: .init(latitude: 25.033968, longitude: 121.564468),
                  distance: 2_900, heading: 35, pitch: 52)
    }
}
#endif
