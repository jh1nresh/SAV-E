import CoreLocation
import Foundation

/// One day of stops routed by a real routing engine: possibly reordered, with
/// travel legs between consecutive stops. Planning never depends on this —
/// every caller must keep the deterministic order as its fallback.
struct TripRouteDayPlan: Equatable {
    let orderedPlaces: [Place]
    let legs: [TripTravelLeg]
}

enum TripRouteServiceError: Error, Equatable {
    case apiKeyMissing
    case unsupportedMode
    case invalidResponse
    case apiError(Int)
}

protocol TripRouteServiceProtocol {
    /// Optimizes the visit order of one day's places and returns leg travel
    /// times. Throws when routing is unavailable; the caller keeps the
    /// deterministic order in that case.
    func optimizedDay(
        _ places: [Place],
        mode: SaveAIResponse.TransportMode
    ) async throws -> TripRouteDayPlan

    func fixedOrderDay(_ places: [Place], mode: SaveAIResponse.TransportMode) async throws -> TripRouteDayPlan
}

extension TripRouteServiceProtocol {
    func fixedOrderDay(_ places: [Place], mode: SaveAIResponse.TransportMode) async throws -> TripRouteDayPlan {
        let result = try await optimizedDay(places, mode: mode)
        guard result.orderedPlaces.map(\.id) == places.map(\.id) else {
            throw TripRouteServiceError.invalidResponse
        }
        return result
    }
}

/// Google Routes API (`computeRoutes`) client. First and last stops stay
/// fixed; intermediates are reordered via `optimizeWaypointOrder`. Transit is
/// rejected up front — the API does not optimize transit waypoints.
final class GoogleTripRouteService: TripRouteServiceProtocol {
    private let apiKey: String?
    private let session: URLSession
    private let bundleIdentifier: String?

    init(
        apiKey: String? = nil,
        session: URLSession? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.apiKey = Self.normalizedAPIKey(
            apiKey
                ?? ProcessInfo.processInfo.environment["GOOGLE_DIRECTIONS_API_KEY"]
                ?? ProcessInfo.processInfo.environment["GOOGLE_PLACES_API_KEY"]
                ?? SAVEProductionConfig.keyFromPlist("GOOGLE_PLACES_API_KEY")
        )
        self.bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 5
            self.session = URLSession(configuration: configuration)
        }
    }

    func optimizedDay(
        _ places: [Place],
        mode: SaveAIResponse.TransportMode
    ) async throws -> TripRouteDayPlan {
        try await routeDay(places, mode: mode, optimizeOrder: true)
    }

    func fixedOrderDay(_ places: [Place], mode: SaveAIResponse.TransportMode) async throws -> TripRouteDayPlan {
        try await routeDay(places, mode: mode, optimizeOrder: false)
    }

    private func routeDay(
        _ places: [Place], mode: SaveAIResponse.TransportMode, optimizeOrder: Bool
    ) async throws -> TripRouteDayPlan {
        guard places.count >= 2 else {
            return TripRouteDayPlan(orderedPlaces: places, legs: [])
        }
        guard mode != .transit else { throw TripRouteServiceError.unsupportedMode }
        guard let apiKey else { throw TripRouteServiceError.apiKeyMissing }

        let intermediates = Array(places.dropFirst().dropLast())
        var body: [String: Any] = [
            "origin": Self.waypoint(places[0]),
            "destination": Self.waypoint(places[places.count - 1]),
            "travelMode": mode == .driving ? "DRIVE" : "WALK",
        ]
        if !intermediates.isEmpty {
            body["intermediates"] = intermediates.map(Self.waypoint)
            if optimizeOrder { body["optimizeWaypointOrder"] = true }
        }
        if mode == .driving {
            body["routingPreference"] = "TRAFFIC_AWARE"
        }

        var request = URLRequest(url: URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "routes.optimizedIntermediateWaypointIndex,routes.legs.duration,routes.legs.distanceMeters",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            request.setValue(bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw TripRouteServiceError.apiError(http.statusCode)
        }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let route = (json?["routes"] as? [[String: Any]])?.first else {
            throw TripRouteServiceError.invalidResponse
        }

        let orderedPlaces = Self.reordered(
            places: places,
            intermediates: intermediates,
            optimizedIndices: optimizeOrder ? route["optimizedIntermediateWaypointIndex"] as? [Int] : nil
        )
        let legs = Self.legs(
            from: route["legs"] as? [[String: Any]] ?? [],
            orderedPlaces: orderedPlaces,
            mode: mode
        )
        return TripRouteDayPlan(orderedPlaces: orderedPlaces, legs: legs)
    }

    // MARK: - Helpers

    private static func waypoint(_ place: Place) -> [String: Any] {
        [
            "location": [
                "latLng": [
                    "latitude": place.latitude,
                    "longitude": place.longitude,
                ],
            ],
        ]
    }

    private static func reordered(
        places: [Place],
        intermediates: [Place],
        optimizedIndices: [Int]?
    ) -> [Place] {
        guard let optimizedIndices,
              optimizedIndices.count == intermediates.count,
              Set(optimizedIndices) == Set(intermediates.indices) else {
            return places
        }
        return [places[0]] + optimizedIndices.map { intermediates[$0] } + [places[places.count - 1]]
    }

    private static func legs(
        from rawLegs: [[String: Any]],
        orderedPlaces: [Place],
        mode: SaveAIResponse.TransportMode
    ) -> [TripTravelLeg] {
        guard rawLegs.count == orderedPlaces.count - 1 else { return [] }
        return rawLegs.enumerated().compactMap { index, raw in
            guard let seconds = durationSeconds(raw["duration"]) else { return nil }
            return TripTravelLeg(
                fromPlaceId: orderedPlaces[index].id.uuidString,
                toPlaceId: orderedPlaces[index + 1].id.uuidString,
                durationMinutes: max(1, Int((Double(seconds) / 60).rounded())),
                distanceMeters: raw["distanceMeters"] as? Int ?? 0,
                mode: mode
            )
        }
    }

    /// Routes API encodes durations as `"1234s"`.
    private static func durationSeconds(_ value: Any?) -> Int? {
        guard let string = value as? String, string.hasSuffix("s") else { return nil }
        return Int(string.dropLast())
    }

    private static func normalizedAPIKey(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        let placeholders: Set<String> = [
            "YOUR_KEY_HERE",
            "REPLACE_ME",
            "GOOGLE_PLACES_API_KEY",
            "GOOGLE_DIRECTIONS_API_KEY",
        ]
        return placeholders.contains(trimmed.uppercased()) ? nil : trimmed
    }
}
