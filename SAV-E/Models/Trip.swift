import Foundation

struct Trip: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var city: String
    var startDate: Date?
    var endDate: Date?
    var places: [TripStop]
    var isOptimized: Bool
    var createdAt: Date

    var dateRangeText: String {
        guard let start = startDate, let end = endDate else { return "No dates set" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    func matchesHomeStoryCity(_ city: String) -> Bool {
        let needle = city.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }

        let haystack = "\(name) \(self.city)".folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        if haystack.contains(needle) { return true }
        if needle.contains("taipei") && (haystack.contains("台北") || haystack.contains("臺北")) {
            return true
        }
        if needle.contains("tokyo") && haystack.contains("東京") {
            return true
        }
        if needle.contains("los angeles")
            && (haystack.contains("los angeles")
                || haystack.contains("orange county")
                || haystack.contains(" la ")) {
            return true
        }
        return false
    }
}

struct TripStop: Identifiable, Codable, Hashable {
    let id: UUID
    var placeId: UUID
    var placeName: String
    var day: Int
    var orderIndex: Int
    var startTime: String?
    var duration: Int? // minutes
    var note: String?
}

// MARK: - Mock Data

extension Trip {
    static let mock = Trip(
        id: UUID(),
        name: "Tokyo Adventure",
        city: "Tokyo",
        startDate: Date(),
        endDate: Date().addingTimeInterval(86400 * 5),
        places: TripStop.mockList,
        isOptimized: false,
        createdAt: Date()
    )

    static let mockList: [Trip] = [
        .mock,
        Trip(
            id: UUID(),
            name: "SF Food Tour",
            city: "San Francisco",
            startDate: Date().addingTimeInterval(86400 * 14),
            endDate: Date().addingTimeInterval(86400 * 16),
            places: [],
            isOptimized: true,
            createdAt: Date().addingTimeInterval(-86400 * 3)
        ),
    ]
}

extension TripStop {
    static let mockList: [TripStop] = [
        TripStop(id: UUID(), placeId: UUID(), placeName: "Tsukiji Outer Market", day: 1, orderIndex: 0, startTime: "9:00 AM", duration: 120, note: "Get there early"),
        TripStop(id: UUID(), placeId: UUID(), placeName: "teamLab Borderless", day: 1, orderIndex: 1, startTime: "1:00 PM", duration: 180),
        TripStop(id: UUID(), placeId: UUID(), placeName: "Shibuya Crossing", day: 2, orderIndex: 0, startTime: "10:00 AM", duration: 60),
    ]
}
