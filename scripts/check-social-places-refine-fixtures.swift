import Foundation
import CoreLocation

private final class StubGooglePlacesService: GooglePlacesServiceProtocol {
    func searchPlace(query: String, near: CLLocationCoordinate2D?) async throws -> [GooglePlaceMatch] {
        if query.contains("Known Cafe") {
            return [
                GooglePlaceMatch(
                    id: "stub-wrong",
                    name: "Wrong Tea House",
                    address: "999 Wrong Road",
                    latitude: 25.0,
                    longitude: 121.0,
                    rating: 4.8,
                    priceLevel: 2
                ),
                GooglePlaceMatch(
                    id: "stub-known-cafe",
                    name: "Known Cafe",
                    address: "123 Known Street",
                    latitude: 24.2,
                    longitude: 120.7,
                    rating: 4.6,
                    priceLevel: 2
                )
            ]
        }
        if query.contains("蜜柑") {
            return [
                GooglePlaceMatch(
                    id: "stub-mikan",
                    name: "蜜柑 關西風壽喜燒",
                    address: "台中市西區中興街125號2樓",
                    latitude: 24.149,
                    longitude: 120.663,
                    rating: 4.5,
                    priceLevel: 3
                )
            ]
        }
        return []
    }

    func getPlaceDetails(placeId: String) async throws -> GooglePlaceDetails {
        throw GooglePlacesError.noResults
    }

    func photoURL(reference: String, maxWidth: Int) -> URL? {
        nil
    }
}

@main
struct SocialPlacesRefineFixtureCheck {
    static func main() async {
        let service = SocialLinkReviewCandidateService(googlePlacesService: StubGooglePlacesService())
        let candidates = service.reviewCandidates(
            fromEvidenceText: """
            勤美附近新開的棉花糖壽喜燒
            @mikantaichung
            台中 西區 壽喜燒
            """,
            sourceURL: "https://www.instagram.com/p/DX_cUWNmNxH/"
        )
        guard let candidate = candidates.first else {
            fail("expected handle review candidate")
        }

        let refined = await service.refineCandidate(candidate)
        expect(refined.candidateName == "蜜柑 關西風壽喜燒", "expected refined name")
        expect(refined.address == "台中市西區中興街125號2樓", "expected refined address")
        expect(refined.latitude == 24.149, "expected refined latitude")
        expect(refined.longitude == 120.663, "expected refined longitude")
        expect(refined.confidence >= 0.74, "expected likely confidence")
        expect(refined.missingInfo.contains("Evidence tier: likely"), "expected likely tier")
        expect(refined.missingInfo.contains("Google Places refined; user must confirm before saving"), "expected user confirmation guard")
        expect(refined.evidence.contains("Google Places refined match: 蜜柑 關西風壽喜燒"), "expected Places evidence")

        let addressed = PendingReviewCandidate(
            candidateName: "Known Cafe",
            address: "123 Known Street",
            category: "cafe",
            sourceURL: "https://example.com/known-cafe",
            sourceText: "Known Cafe at 123 Known Street",
            evidence: ["Evidence tier: likely"],
            confidence: 0.6,
            missingInfo: [],
            savedAt: Date()
        )
        let addressedRefined = await service.refineCandidate(addressed)
        expect(addressedRefined.candidateName == "Known Cafe", "expected addressed candidate to skip unrelated first match")
        expect(addressedRefined.address == "123 Known Street", "expected addressed candidate to keep matching address")
        expect(addressedRefined.latitude == 24.2, "expected addressed candidate to use acceptable match latitude")
        expect(addressedRefined.longitude == 120.7, "expected addressed candidate to use acceptable match longitude")

        let persistedReviewCandidate = PlaceReviewCandidate(
            id: UUID(),
            captureId: nil,
            name: "Wagyu Tenderloin Sukiyaki",
            address: "",
            city: nil,
            latitude: nil,
            longitude: nil,
            evidence: [
                "Source URL: https://www.instagram.com/reel/example/",
                "Caption area clue: KYOTO",
                "Recovered address evidence: 先斗町, 京都",
                "Suggested public search: Wagyu Tenderloin Sukiyaki Kyoto"
            ],
            confidence: 0.58,
            missingInfo: ["Verified address", "Verified coordinates"],
            status: "review",
            createdAt: Date()
        )
        expect(
            persistedReviewCandidate.refinementQuery.contains("先斗町, 京都"),
            "persisted review candidate exact-place query should keep recovered address evidence"
        )
        expect(
            persistedReviewCandidate.refinementQuery.contains("KYOTO"),
            "persisted review candidate exact-place query should keep caption area clue"
        )

        print("Validated social Places refine fixtures.")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
