import Foundation

@MainActor
protocol TripPersisting {
    func fetchTrips(for userId: String) async throws -> [Trip]
    func saveTrip(_ trip: Trip, userId: String) async throws
    func updateTrip(_ trip: Trip) async throws
    func deleteTrip(_ tripId: UUID) async throws
}

extension SupabaseService: TripPersisting {}

@MainActor
final class ReviewDemoTripPersistence: TripPersisting {
    private let fileURL: URL
    private let fileManager: FileManager

    convenience init() {
        self.init(
            fileURL: ReviewDemoStorage.directoryURL
                .appendingPathComponent("trip-packs-v1.json")
        )
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func fetchTrips(for userId: String) async throws -> [Trip] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode([Trip].self, from: data)
    }

    func saveTrip(_ trip: Trip, userId: String) async throws {
        var trips = try await fetchTrips(for: userId)
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[index] = trip
        } else {
            trips.append(trip)
        }
        try write(trips)
    }

    func updateTrip(_ trip: Trip) async throws {
        var trips = try await fetchTrips(for: ReviewDemo.userId)
        if let index = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[index] = trip
        } else {
            trips.append(trip)
        }
        try write(trips)
    }

    func deleteTrip(_ tripId: UUID) async throws {
        let trips = try await fetchTrips(for: ReviewDemo.userId)
            .filter { $0.id != tripId }
        try write(trips)
    }

    private func write(_ trips: [Trip]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(trips)
        try data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
