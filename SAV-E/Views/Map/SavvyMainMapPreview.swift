#if DEBUG && SAVVY_MAIN_APP && SAVVY_CITY_MVP
import SwiftUI

/// Synthetic UI evidence only. This route is impossible on a physical iPhone
/// and requires an explicit offline test flag plus a valid unique namespace.
struct SavvyMainMapPreview: View {
    static var isRequested: Bool {
#if targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--uitest-main-map")
            && ReviewDemo.isOfflineUITestMode
            && UUID(uuidString: ProcessInfo.processInfo.environment["SAVE_UI_TEST_STORAGE_ID"] ?? "") != nil
#else
        false
#endif
    }
    @AppStorage(CityMVPStyle.nightPreference) private var night = false
    @StateObject private var draft: CityMVPCaptureDraftStore
    @StateObject private var recommendations: CityMVPRecommendationStore

    init() {
        precondition(Self.isRequested)
        let storageID = ProcessInfo.processInfo.environment["SAVE_UI_TEST_STORAGE_ID"]!
        _draft = StateObject(wrappedValue: CityMVPCaptureDraftStore(storageID: storageID))
        _recommendations = StateObject(wrappedValue: CityMVPRecommendationStore(storageID: storageID))
        let fixture = Place(id: UUID(uuidString: "AFE03D53-2026-4113-8101-000000000001")!,
            name: "Taipei 101", address: "UI fixture · Xinyi, Taipei", latitude: 25.033968,
            longitude: 121.564468, category: .attraction, status: .wantToGo,
            sourceUrl: "https://www.openstreetmap.org/?mlat=25.033968&mlon=121.564468#map=18/25.033968/121.564468",
            sourcePlatform: .other, createdAt: Date(timeIntervalSince1970: 0))
        // The valid UUID namespace above is distinct from real and ordinary
        // review-demo stores. Fixture persistence failure remains a UI failure.
        try? ReviewDemoStorage.localVaultService.saveConfirmedPlace(fixture)
    }

    var body: some View {
        ContentView(storageScope: .reviewerDemo)
            .environmentObject(PrivyAuthService.shared)
            .environmentObject(draft)
            .environmentObject(recommendations)
            .preferredColorScheme(night ? .dark : .light)
    }
}
#endif
