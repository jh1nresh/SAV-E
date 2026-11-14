#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW && SAVVY_CITY_MVP && targetEnvironment(simulator)
import Foundation
import MapKit
import SwiftUI

/// Simulator-only, isolated synthetic data. This never establishes an authenticated account.
@MainActor
final class LivePlanningReviewFixture {
    nonisolated static func hasLaunchIntent(arguments: [String]) -> Bool {
        arguments.contains("--uitest-live-review-rail")
    }

    nonisolated static func requestedNamespace(arguments: [String], environment: [String: String]) -> UUID? {
        let allowedTestFlags: Set<String> = ["--uitest-live-review-rail", "--uitest-review-demo-offline",
            "--uitest-location-denied", "--uitest-force-dark", "--uitest-force-light"]
        guard hasLaunchIntent(arguments: arguments), arguments.contains("--uitest-review-demo-offline"),
              !arguments.contains(where: { $0.hasPrefix("--uitest-") && !allowedTestFlags.contains($0) }),
              let raw = environment["SAVE_UI_TEST_STORAGE_ID"], raw.count == 36 else { return nil }
        return UUID(uuidString: raw)
    }

    nonisolated static var isRequested: Bool {
        requestedNamespace(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment) != nil
    }

    nonisolated static func canConstruct(currentUserID: String?, isAuthenticated: Bool) -> Bool {
        currentUserID == nil && !isAuthenticated
    }

    /// Offline test startup deliberately does not restore stored credentials.
    /// This checks active process state, not absence of an account on disk.
    static var hasNoActiveIdentity: Bool {
        let auth = PrivyAuthService.shared
        if case .authenticated = auth.authState { return false }
        return canConstruct(currentUserID: auth.currentUserId, isAuthenticated: false)
    }

    static let shared: LivePlanningReviewFixture = {
        // The wrapper checks these before referencing shared. Keep the factory fail-closed as well.
        precondition(isRequested && hasNoActiveIdentity)
        let namespace = requestedNamespace(arguments: ProcessInfo.processInfo.arguments,
                                           environment: ProcessInfo.processInfo.environment)!
        return LivePlanningReviewFixture(namespace: namespace, directoryURL: ReviewDemoStorage.directoryURL,
            defaults: ReviewDemoStorage.defaults, isCurrent: {
                hasNoActiveIdentity && requestedNamespace(arguments: ProcessInfo.processInfo.arguments,
                    environment: ProcessInfo.processInfo.environment) == namespace
            })
    }()

    nonisolated static let captureText = "1. Harbor Oven Pizza\nLos Angeles\n2. Fixture Tea House\nLos Angeles"
    let namespace: UUID
    let directoryURL: URL
    let defaults: UserDefaults
    let ownerSubject: String
    let sessionGeneration = 0
    let mapViewModel: MapViewModel
    let dependencies: LivePlanningDependencies
    let initializationError: String?
    private let current: @MainActor () -> Bool
    var isCurrent: Bool { initializationError == nil && current() }

    /// Explicit dependencies let native tests use their own temporary namespace; no singleton is reset.
    init(namespace: UUID, directoryURL: URL, defaults: UserDefaults, isCurrent: @escaping @MainActor () -> Bool) {
        self.namespace = namespace; self.directoryURL = directoryURL; self.defaults = defaults
        let owner = "ui-review:\(namespace.uuidString.lowercased())"
        self.ownerSubject = owner
        self.current = isCurrent
        let vault = SaveLocalVaultService(overrideVaultURL: directoryURL.appendingPathComponent("save-memory-records.json"))
        let pending = PendingPlaceImportService(overrideContainerURL: directoryURL)
        let correction = SavePlaceCorrectionEventStore(overrideURL: directoryURL.appendingPathComponent("save-place-correction-events.json"))
        let google = LiveReviewDeniedGoogle()
        let unavailableService = SupabaseService(apiBaseURL: nil)
        let analysis = SocialLinkReviewCandidateService(googlePlacesService: google,
            publicSourceSearchService: LiveReviewDeniedPublicSearch(), captionVenueExtractor: nil,
            socialSemanticAnalyzer: LiveReviewDeniedSemanticAnalysis())
        var seedFailure: String?
        do {
            let existing = try vault.reviewCandidates()
            if !existing.contains(where: { $0.name == "Earlier fixture clue" }) {
                _ = try vault.saveReviewCandidate(PendingReviewCandidate(candidateName: "Earlier fixture clue", address: "",
                    category: "other", sourceURL: nil, sourceText: nil, evidence: ["Synthetic older clue"],
                    confidence: 0, missingInfo: ["Exact place", "User confirmation"],
                    savedAt: Date(timeIntervalSince1970: 1), isSourceOnly: true))
            }
        } catch { seedFailure = "The isolated review fixture could not be prepared." }
        self.initializationError = seedFailure
        self.mapViewModel = MapViewModel(supabaseService: unavailableService, mapCandidateUserIDProvider: { nil },
            pendingImportService: pending, mapCandidateDistanceLocationProvider: { nil }, googlePlacesService: google,
            socialLinkReviewCandidateService: analysis, saveLocalVaultService: vault, correctionEventStore: correction,
            correctionLearningEnabled: false, mapCandidateSearchService: LiveReviewMapResults(),
            collaborativeListStore: SaveCollaborativeListStore(defaults: defaults),
            referralHandoffStore: SaveReferralHandoffStore(defaults: defaults), relatedPlaceSourcesService: unavailableService,
            entitlementResolvedProvider: { false }, usesRemotePersistence: false)
        let denied = LiveReviewDeniedBackend()
        self.dependencies = LivePlanningDependencies(
            outing: LiveOutingModel(ownerSubject: owner, sessionGeneration: 0, backend: denied, sessionIsCurrent: isCurrent),
            plan: LiveRoutePlan(ownerSubject: owner, sessionGeneration: 0,
                makeDirections: { _ in LiveReviewDeniedDirections() }, sessionIsCurrent: isCurrent),
            discovery: LivePublicDiscoveryModel(backend: denied, sessionIsCurrent: isCurrent), sessionIsCurrent: isCurrent)
    }
}

/// SaveApp selects this before its ordinary auth/handoff modifiers. No auth gate method is invoked.
@MainActor
struct LivePlanningReviewFixtureRoot: View {
    @ObservedObject private var auth = PrivyAuthService.shared

    var body: some View {
        Group {
            if LivePlanningReviewFixture.isRequested && LivePlanningReviewFixture.hasNoActiveIdentity {
                let fixture = LivePlanningReviewFixture.shared
                if fixture.isCurrent { LivePlanningReviewFixtureContent(fixture: fixture) }
                else { unavailable }
            } else { unavailable }
        }
    }

    private var unavailable: some View {
        Text("Synthetic review fixture unavailable. Use the exact isolated offline test flags.")
            .padding().accessibilityIdentifier("live.fixture.unavailable")
    }
}

@MainActor
private struct LivePlanningReviewFixtureContent: View {
    let fixture: LivePlanningReviewFixture
    @StateObject private var draft: CityMVPCaptureDraftStore
    @StateObject private var recommendations: CityMVPRecommendationStore
    private let language: AppLanguageSettings
    private let dark: Bool

    init(fixture: LivePlanningReviewFixture) {
        self.fixture = fixture
        let id = fixture.namespace.uuidString
        _draft = StateObject(wrappedValue: CityMVPCaptureDraftStore(documentsDirectory: fixture.directoryURL,
            storageID: id, isCurrentSession: { fixture.isCurrent }))
        _recommendations = StateObject(wrappedValue: CityMVPRecommendationStore(documentsDirectory: fixture.directoryURL,
            storageID: id, isCurrentSession: { fixture.isCurrent }))
        let language = AppLanguageSettings(userDefaults: fixture.defaults, preferredLanguages: { ["en"] })
        language.preference = .english
        self.language = language
        self.dark = ProcessInfo.processInfo.arguments.contains("--uitest-force-dark")
    }

    var body: some View {
        ContentView(storageScope: .livePlanningReviewFixture)
            .environmentObject(PrivyAuthService.shared)
            .environmentObject(draft).environmentObject(recommendations)
            .environment(\.appLanguageSettings, language).environment(\.locale, Locale(identifier: "en"))
            .preferredColorScheme(dark ? .dark : .light)
    }
}

private struct LiveReviewDeniedGoogle: GooglePlacesServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] { throw URLError(.notConnectedToInternet) }
    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails { throw URLError(.notConnectedToInternet) }
    func photoURL(reference: String, maxWidth: Int) -> URL? { nil }
}

private struct LiveReviewDeniedPublicSearch: PublicSourceSearchServiceProtocol {
    func search(query: String) async throws -> [PublicSourceSearchResult] { throw URLError(.notConnectedToInternet) }
}

private struct LiveReviewDeniedSemanticAnalysis: SocialSemanticAnalyzing {
    func analyze(caption: String, ocrText: String?) async -> SocialSemanticResult {
        SocialSemanticResult(status: "analysis_pending", venues: [], reason: "Synthetic fixture excludes remote analysis")
    }
}

private struct LiveReviewMapResults: MapCandidateSearchServiceProtocol {
    func searchCandidates(near coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan,
                          excluding savedPlaces: [Place], categories: Set<PlaceCategory>) async -> [SaveMapCandidate] { [] }
    func searchCandidates(matching query: String, near coordinate: CLLocationCoordinate2D?,
                          span: MKCoordinateSpan?, excluding savedPlaces: [Place]) async -> [SaveMapCandidate] {
        guard query.contains("Harbor Oven Pizza") else { return [] }
        return [SaveMapCandidate(id: "review-map-result-fixture", title: "Harbor Oven Pizza — corrected branch",
            subtitle: "1 Fixture Road, Los Angeles", latitude: 33.741, longitude: -118.281,
            category: .food, evidence: ["Synthetic map-search result"])]
    }
}

@MainActor
private final class LiveReviewDeniedBackend: LiveOutingBackend, LivePublicDiscoveryBackend {
    var isConfigured: Bool { false }
    func fetchCollaborativeListRows() async throws -> [SaveCollaborativeListServerRow] { throw URLError(.notConnectedToInternet) }
    func fetchListMembers(listID: UUID) async throws -> [SaveListMemberRow] { throw URLError(.notConnectedToInternet) }
    func fetchSharedPosts(mine: Bool, filter: SharedPostFilter, cursor: String?) async throws -> SharedPlacePostsPage { throw URLError(.notConnectedToInternet) }
    func createCollaborativeListRow(id: UUID, title: String, note: String?) async throws { throw URLError(.notConnectedToInternet) }
    func joinCollaborativeList(code: String) async throws -> SaveCollaborativeListServerRow { throw URLError(.notConnectedToInternet) }
    func createListShareCode(listID: UUID, role: SaveListRole) async throws -> (code: String, url: URL) { throw URLError(.notConnectedToInternet) }
    func addCollaborativeListItem(listID: UUID, payload: SaveListItem) async throws { throw URLError(.notConnectedToInternet) }
    func fetchPublicDiscovery(viewport: LivePublicDiscoveryViewport, cursor: String?) async throws -> LivePublicDiscoveryPage { throw URLError(.notConnectedToInternet) }
}

@MainActor
private final class LiveReviewDeniedDirections: LiveWalkingDirections {
    func route() async throws -> MKRoute { throw MKError(.directionsNotFound) }
    func cancel() {}
}
#endif
