#if SAVVY_CITY_MVP
import Foundation

/// A place confirmation is durable even if its separate copied-source write
/// fails. Retrying a source has no place-saving capability.
@MainActor
enum CityMVPFriendConfirmation {
    struct Outcome {
        let savedPlace: Place
        let recommendationKept: Bool
    }

    static func confirm(place: Place, snapshot: CityMVPFriendExchange.Snapshot,
                        venueID: UUID, recommendations: CityMVPRecommendationStore,
                        save: (Place) async throws -> Place) async throws -> Outcome {
        let actual = try await save(place)
        do {
            try recommendations.remember(snapshot: snapshot, venueID: venueID, savedPlaceID: actual.id)
            return Outcome(savedPlace: actual, recommendationKept: true)
        } catch {
            return Outcome(savedPlace: actual, recommendationKept: false)
        }
    }

    static func retryRecommendation(snapshot: CityMVPFriendExchange.Snapshot, venueID: UUID,
                                    savedPlaceID: UUID, recommendations: CityMVPRecommendationStore) throws {
        try recommendations.remember(snapshot: snapshot, venueID: venueID, savedPlaceID: savedPlaceID)
    }
}
#endif
