#if SAVVY_CITY_MVP
import SwiftUI
import MapKit

#if !SAVVY_MAIN_APP
@main
struct CityMVPApp: App {
    private static let verificationDayBootstrap: Void = {
        guard CityDistrictTrace.enabled,
              ProcessInfo.processInfo.arguments.contains("--verify-start-day") else { return }
        // Seed once, rather than forcing an argument-domain value that would
        // override subsequent writes from the real lighting control.
        UserDefaults.standard.set(false, forKey: CityMVPStyle.nightPreference)
        CityDistrictTrace.write("verification-startup\tday-once")
    }()
    @AppStorage(CityMVPStyle.nightPreference) private var night = false
    @StateObject private var language = AppLanguageSettings()
    private static var inspectsPinStateLayout: Bool {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--inspect-citylab") && arguments.contains("--inspect-state-pin-layout")
            && UUID(uuidString: ProcessInfo.processInfo.environment["CITY_PIN_LAYOUT_TEST_ID"] ?? "") != nil
#else
        return false
#endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if targetEnvironment(simulator)
                if Self.inspectsPinStateLayout {
                    CityNativePinStateProbe().environment(\.appLanguageSettings, language)
                } else {
                    CityMVPOrdinaryRoot(language: language)
                        .preferredColorScheme(night ? .dark : .light)
                }
#else
                CityMVPOrdinaryRoot(language: language)
                        .preferredColorScheme(night ? .dark : .light)
#endif
            }

        }
    }

    init() {
        _ = Self.verificationDayBootstrap
        CityMVPLatencyObservation.startIfRequested()
        // New app container, no production entitlements, no login or remote saves.
        UserDefaults.standard.set(true, forKey: "hasSeenMapTour")
    }
}


/// Ordinary routes own private draft/source stores; layout inspection cannot create them.
private struct CityMVPOrdinaryRoot: View {
    let language: AppLanguageSettings
    @StateObject private var captureDraft = CityMVPCaptureDraftStore(storageID: Self.draftStorageID)
    @StateObject private var recommendations = CityMVPRecommendationStore(storageID: Self.draftStorageID)
    private static var draftStorageID: String? {
        // This entire entry point is prototype-only. Its generated Debug
        // configuration defines SAVVY_CITY_MVP rather than DEBUG.
        ProcessInfo.processInfo.environment["SAVE_UI_TEST_STORAGE_ID"]
    }

    var body: some View {
        Group { ordinaryContent }
            .alert(language.localized(english: "Capture draft", traditionalChinese: "線索草稿"),
                   isPresented: Binding(get: { captureDraft.failure != nil },
                                        set: { if !$0 { captureDraft.dismissFailure() } })) {
                Button(language.localized(english: "OK", traditionalChinese: "知道了")) { captureDraft.dismissFailure() }
            } message: {
                Text(captureDraft.failure?.message(english: language.language != .traditionalChinese) ?? "")
            }
    }
    @ViewBuilder
    private var ordinaryContent: some View {
        if CityDistrictTrace.enabled,
           ProcessInfo.processInfo.arguments.contains("--verify-uikit-buildings-probe") {
            CityUIKitBuildingsProbe()
        } else if CitySceneView.usesOpaqueReveal,
           ProcessInfo.processInfo.arguments.contains("--verify-native-ground-owner"),
           ProcessInfo.processInfo.arguments.contains("--verify-solid-reveal-preview") {
            CitySolidRevealPreview()
        } else if ProcessInfo.processInfo.arguments.contains("--verify-native-overlay-probe") {
            CityNativeOverlayProbe()
        } else {
            // An unfinished editor draft is not an onboarding share.
            // The shared onboarding binding may import automatically.
            ContentView(pendingOnboardingClue: .constant(""), storageScope: .reviewerDemo)
                .environment(\.appLanguageSettings, language)
                .environmentObject(PrivyAuthService.shared)
                .environmentObject(captureDraft)
                .environmentObject(recommendations)
        }
    }

}

#endif

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
        // Match the pitch MapKit settles on at this overview. A higher request
        // can trigger a second camera adjustment after the destination arrives.
        MapCamera(centerCoordinate: CityDistrictCamera.coordinate(x: -15, z: -175),
                  distance: CityDistrictCamera.overviewDistance, heading: 20, pitch: 35)
    }
}
#endif
