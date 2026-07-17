#if DEBUG
import CoreLocation
import SwiftUI

enum SaveSmokeHarness {
    static let launchArgument = "-SAVEUISmokeHarness"

    static var isLaunchEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument) ||
            ProcessInfo.processInfo.environment["SAVE_UI_SMOKE_HARNESS"] == "1"
    }

    static func isSmokeURL(_ url: URL) -> Bool {
        url.scheme == "wanderly" && url.host == "smoke"
    }
}

struct SaveSmokeHarnessView: View {
    @State private var rows: [SmokeHarnessRow] = []
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Smoke harness ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("smoke-harness-root")

                Button {
                    Task { await runSmokeHarness() }
                } label: {
                    Label(isRunning ? "Running smoke harness" : "Run smoke harness", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
                .accessibilityIdentifier("smoke-run-button")

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: row.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(row.passed ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(.headline)
                                Text(row.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(row.accessibilityIdentifier)
                                    .font(.caption2)
                                    .foregroundStyle(row.passed ? .green : .red)
                                    .accessibilityIdentifier(row.accessibilityIdentifier)
                            }
                        }
                        .accessibilityIdentifier(row.accessibilityIdentifier)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("SAV-E Smoke Harness")
            .accessibilityIdentifier("smoke-harness-root")
            .task {
                if rows.isEmpty {
                    await runSmokeHarness()
                }
            }
        }
    }

    @MainActor
    private func runSmokeHarness() async {
        isRunning = true
        rows = []
        let runner = SaveSmokeHarnessRunner()
        rows = await runner.runAll()
        isRunning = false
    }
}

private struct SmokeHarnessRow: Identifiable {
    let id: String
    let title: String
    let detail: String
    let passed: Bool

    var accessibilityIdentifier: String {
        "smoke-\(id)-\(passed ? "pass" : "fail")"
    }
}

@MainActor
private struct SaveSmokeHarnessRunner {
    func runAll() async -> [SmokeHarnessRow] {
        var rows: [SmokeHarnessRow] = []
        rows.append(await authPath())
        rows.append(locationPath())
        rows.append(nearbyRecommendationPath())
        rows.append(shareLinkPath())
        rows.append(reviewConfirmSavePath())
        return rows
    }

    private func authPath() async -> SmokeHarnessRow {
        let authService = PrivyAuthService.shared
        let timeout = Date().addingTimeInterval(3)
        while authService.authState == .unknown && Date() < timeout {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let stateDescription: String
        switch authService.authState {
        case .authenticated:
            stateDescription = "authenticated route reachable"
        case .unauthenticated:
            stateDescription = "unauthenticated route reachable"
        case .unknown:
            stateDescription = "auth state stayed unknown"
        }
        return SmokeHarnessRow(
            id: "auth",
            title: "Auth",
            detail: stateDescription,
            passed: authService.authState != .unknown
        )
    }

    private func locationPath() -> SmokeHarnessRow {
        let service = SaveLocationIntentRecommendationService()
        let query = "推薦我附近咖啡"
        let needsLocation = service.requiresCurrentLocation(for: query)
        let response = service.recommendationSearchResponse(
            for: query,
            places: [sampleCafe],
            currentLocation: CLLocation(latitude: 33.6846, longitude: -117.8265)
        )
        let passed = needsLocation && (response?.fromYourSave.results.contains { $0.title == sampleCafe.name } == true)
        return SmokeHarnessRow(
            id: "location",
            title: "Location",
            detail: passed ? "nearby intent used mock current location" : "nearby intent did not produce location-aware result",
            passed: passed
        )
    }

    private func nearbyRecommendationPath() -> SmokeHarnessRow {
        let service = SaveLocationIntentRecommendationService()
        let currentLocation = CLLocation(latitude: 33.6846, longitude: -117.8265)
        let cafe = service.recommendationSearchResponse(
            for: "推薦我附近咖啡",
            places: [sampleCafe, sampleRestaurant],
            currentLocation: currentLocation
        )
        let restaurant = service.recommendationSearchResponse(
            for: "推薦我附近餐廳",
            places: [sampleCafe, sampleRestaurant],
            currentLocation: currentLocation
        )
        let cafePassed = cafe?.fromYourSave.results.first?.title == sampleCafe.name
        let restaurantPassed = restaurant?.fromYourSave.results.first?.title == sampleRestaurant.name
        return SmokeHarnessRow(
            id: "nearby",
            title: "Nearby Restaurant / Cafe",
            detail: "cafe=\(cafe?.fromYourSave.results.first?.title ?? "none"), restaurant=\(restaurant?.fromYourSave.results.first?.title ?? "none")",
            passed: cafePassed && restaurantPassed
        )
    }

    private func shareLinkPath() -> SmokeHarnessRow {
        let service = SocialLinkReviewCandidateService(googlePlacesService: EmptyGooglePlacesService())
        let instagramCandidates = service.reviewCandidatesOrSourceOnly(
            fromEvidenceText: """
            Food reel on Instagram: "Dinner at Smoke Test Noodle Bar
            123 Test Street, Irvine, CA"
            """,
            sourceURL: "https://www.instagram.com/reel/SMOKE123/"
        )
        let mapsCandidates = GoogleMapsListPlaceExtractor.extractCandidates(
            sourceURL: "https://maps.google.com",
            title: "Dinner ideas - Google Maps",
            text: nil,
            metadataTitle: "Dinner ideas - Google Maps",
            metadataDescription: "Smoke Test Cafe · 100 Test Loop, Irvine, CA",
            htmlText: """
            <html><head><title>Dinner ideas - Google Maps</title></head><body>
            <a href="https://www.google.com/maps/place/Smoke+Test+Cafe/@33.6846,-117.8265,17z">Smoke Test Cafe</a>
            </body></html>
            """
        )
        let passed = instagramCandidates.contains { $0.candidateName.localizedCaseInsensitiveContains("Smoke Test Noodle Bar") } &&
            mapsCandidates.contains { $0.name.localizedCaseInsensitiveContains("Smoke Test Cafe") }
        return SmokeHarnessRow(
            id: "share",
            title: "Share IG / Maps Link",
            detail: "ig=\(instagramCandidates.first?.candidateName ?? "none"), maps=\(mapsCandidates.first?.name ?? "none")",
            passed: passed
        )
    }

    private func reviewConfirmSavePath() -> SmokeHarnessRow {
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("save-ui-smoke-\(UUID().uuidString).json")
            let vault = SaveLocalVaultService(overrideVaultURL: url)
            let candidate = PendingReviewCandidate(
                candidateName: "Smoke Test Noodle Bar",
                address: "123 Test Street, Irvine, CA",
                category: "food",
                latitude: 33.6846,
                longitude: -117.8265,
                sourceURL: "https://www.instagram.com/reel/SMOKE123/",
                sourceText: "Smoke harness review candidate",
                evidence: ["Smoke harness candidate"],
                confidence: 0.82,
                missingInfo: [],
                savedAt: Date(),
                reviewState: "map_match_ready"
            )
            _ = try vault.saveReviewCandidate(candidate)
            let draft = SavePlaceDraft(
                title: candidate.candidateName,
                address: candidate.address,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                category: .food,
                sourceURL: candidate.sourceURL,
                sourcePlatform: .instagram,
                evidence: candidate.evidence,
                externalRating: nil,
                externalReviewCount: nil
            )
            let place = try SaveSearchController().makeSavedPlace(from: draft)
            _ = try vault.saveConfirmedPlace(place)
            let confirmed = try vault.confirmedPlaces()
            let passed = confirmed.contains { $0.name == "Smoke Test Noodle Bar" }
            return SmokeHarnessRow(
                id: "review",
                title: "Review Confirm / Save",
                detail: "confirmed=\(confirmed.first?.name ?? "none")",
                passed: passed
            )
        } catch {
            return SmokeHarnessRow(
                id: "review",
                title: "Review Confirm / Save",
                detail: error.localizedDescription,
                passed: false
            )
        }
    }

    private var sampleCafe: Place {
        Place(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Smoke Test Cafe",
            address: "100 Test Loop, Irvine, CA",
            latitude: 33.6847,
            longitude: -117.8264,
            googlePlaceId: nil,
            category: .cafe,
            status: .wantToGo,
            rating: nil,
            note: "coffee latte pastry",
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }

    private var sampleRestaurant: Place {
        Place(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Smoke Test Noodle Bar",
            address: "123 Test Street, Irvine, CA",
            latitude: 33.6848,
            longitude: -117.8266,
            googlePlaceId: nil,
            category: .food,
            status: .wantToGo,
            rating: nil,
            note: "noodles dinner",
            sourceUrl: nil,
            sourcePlatform: .other,
            sourceImageUrl: nil,
            extractedDishes: nil,
            priceRange: nil,
            recommender: nil,
            googleRating: nil,
            googlePriceLevel: nil,
            openingHours: nil,
            createdAt: Date()
        )
    }
}

private struct EmptyGooglePlacesService: GooglePlacesServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        []
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        throw GooglePlacesError.noResults
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        nil
    }
}
#endif
