#if SAVVY_CITY_MVP
import Foundation

/// A model can select identifiers, not author facts or change saved memory.
nonisolated enum CityMVPGuideSelection {
    struct Request: Codable, Equatable, Sendable {
        let version: Int
        let question: String
        let venues: [Venue]
    }
    struct Venue: Codable, Equatable, Sendable {
        let placeID: UUID
        let name: String
        let category: String
        let sources: [Source]
    }
    struct Source: Codable, Equatable, Sendable {
        let sourceID: String
        let selfDeclaredSender: String
        let reason: String
        let authenticatedSender: Bool
    }
    struct Response: Codable, Equatable, Sendable {
        let choices: [Choice]
    }
    struct Choice: Codable, Equatable, Sendable {
        let placeID: UUID
        let sourceIDs: [String]
    }
    enum ValidationError: Error, Equatable {
        case invalidRequest, invalidSelection, unavailableIdentity, ambiguousIdentity
        case tooLarge, malformedResponse, unselectedChoice
    }
    static let maximumRequestBytes = 24 * 1_024
    static let maximumResponseBytes = 8 * 1_024

    @MainActor
    static func build(question: String, selectedPlaceIDs: [UUID], selectedSourceIDs: [String],
                      places: [Place], records: [CityMVPRecommendationStore.Record]) throws -> Request {
        guard !selectedPlaceIDs.isEmpty, selectedPlaceIDs.count <= 5, selectedSourceIDs.count <= 10,
              Set(selectedPlaceIDs).count == selectedPlaceIDs.count,
              Set(selectedSourceIDs).count == selectedSourceIDs.count else { throw ValidationError.invalidSelection }
        let selectedPlaces = Set(selectedPlaceIDs)
        let placesByID = Dictionary(grouping: places, by: \.id)
        var selected: [UUID: Place] = [:]
        for id in selectedPlaceIDs {
            guard let matches = placesByID[id] else { throw ValidationError.unavailableIdentity }
            guard matches.count == 1 else { throw ValidationError.ambiguousIdentity }
            selected[id] = matches[0]
        }
        var sources: [UUID: [Source]] = [:]
        let recordsByID = Dictionary(grouping: records, by: \.id)
        for id in selectedSourceIDs {
            guard let matches = recordsByID[id] else { throw ValidationError.unavailableIdentity }
            guard matches.count == 1 else { throw ValidationError.ambiguousIdentity }
            let record = matches[0]
            // Even an unselected current place can expose an ambiguous alias.
            let owners = places.filter { $0.savedIDs.contains(record.savedPlaceID) }
            guard !owners.isEmpty else { throw ValidationError.unavailableIdentity }
            guard owners.count == 1 else { throw ValidationError.ambiguousIdentity }
            guard selectedPlaces.contains(owners[0].id) else { throw ValidationError.invalidSelection }
            sources[owners[0].id, default: []].append(Source(sourceID: id,
                selfDeclaredSender: record.senderLabel, reason: record.reason, authenticatedSender: false))
        }
        let venues = selected.values.map { place in
            Venue(placeID: place.id, name: place.name, category: place.category.rawValue,
                  sources: (sources[place.id] ?? []).sorted { $0.sourceID < $1.sourceID })
        }.sorted { $0.placeID.uuidString < $1.placeID.uuidString }
        let request = Request(version: 1, question: question, venues: venues)
        _ = try canonicalData(for: request)
        return request
    }

    /// Compare these bytes against a rebuilt current selection before displaying a response.
    static func canonicalData(for request: Request) throws -> Data {
        try validate(request)
        let ordered = Request(version: request.version, question: request.question,
            venues: request.venues.map { venue in
                Venue(placeID: venue.placeID, name: venue.name, category: venue.category,
                    sources: venue.sources.sorted { $0.sourceID < $1.sourceID })
            }.sorted { $0.placeID.uuidString < $1.placeID.uuidString })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ordered)
        guard data.count <= maximumRequestBytes else { throw ValidationError.tooLarge }
        return data
    }

    static func decodeResponse(_ data: Data, for request: Request) throws -> Response {
        _ = try canonicalData(for: request)
        guard data.count <= maximumResponseBytes else { throw ValidationError.tooLarge }
        try checkJSONStructure(data)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["choices"], let choices = object["choices"] as? [[String: Any]],
              choices.count <= 2,
              choices.allSatisfy({ Set($0.keys) == ["placeID", "sourceIDs"] }) else {
            throw ValidationError.malformedResponse
        }
        guard let result = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ValidationError.malformedResponse
        }
        guard Set(result.choices.map(\.placeID)).count == result.choices.count else {
            throw ValidationError.malformedResponse
        }
        let venues = Dictionary(uniqueKeysWithValues: request.venues.map { ($0.placeID, $0) })
        var usedSources = Set<String>()
        for choice in result.choices {
            guard let venue = venues[choice.placeID] else { throw ValidationError.unselectedChoice }
            guard venue.sources.isEmpty || !choice.sourceIDs.isEmpty else { throw ValidationError.unselectedChoice }
            let allowedSources = Set(venue.sources.map(\.sourceID))
            for id in choice.sourceIDs {
                guard allowedSources.contains(id) else { throw ValidationError.unselectedChoice }
                guard usedSources.insert(id).inserted else { throw ValidationError.malformedResponse }
            }
        }
        return result
    }

    private static func validate(_ request: Request) throws {
        guard request.version == 1, validText(request.question, limit: 1_000, multiline: true),
              !request.venues.isEmpty, request.venues.count <= 5,
              Set(request.venues.map(\.placeID)).count == request.venues.count else {
            throw ValidationError.invalidRequest
        }
        let categories: Set<String> = ["food", "cafe", "bar", "attraction", "stay", "shopping"]
        var sourceIDs = Set<String>()
        for venue in request.venues {
            guard validText(venue.name, limit: 2_048), categories.contains(venue.category),
                  venue.sources.count <= 10 else { throw ValidationError.invalidRequest }
            for source in venue.sources {
                guard source.sourceID.utf8.count == 64,
                      source.sourceID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                      sourceIDs.insert(source.sourceID).inserted,
                      !source.authenticatedSender,
                      validText(source.selfDeclaredSender, limit: 80),
                      validText(source.reason, limit: 1_000, multiline: true) else {
                    throw ValidationError.invalidRequest
                }
            }
        }
        guard sourceIDs.count <= 10 else { throw ValidationError.invalidRequest }
    }

    private static func validText(_ value: String, limit: Int, multiline: Bool = false) -> Bool {
        value.count <= limit && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0) && !(multiline && ($0 == "\n" || $0 == "\t"))
            }
    }

    /// Bound nesting before Foundation parsing and reject duplicate object keys,
    /// including escaped spellings. Strings are data, never parsed as instructions.
    private static func checkJSONStructure(_ data: Data) throws {
        let bytes = Array(data)
        var stack: [Set<String>?] = []
        var index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 123, 91: // object / array
                stack.append(bytes[index] == 123 ? Set<String>() : nil)
                guard stack.count <= 6 else { throw ValidationError.malformedResponse }
            case 125, 93:
                guard !stack.isEmpty else { throw ValidationError.malformedResponse }
                stack.removeLast()
            case 34:
                let start = index
                index += 1
                while index < bytes.count && bytes[index] != 34 {
                    if bytes[index] == 92 { index += 1 }
                    index += 1
                }
                guard index < bytes.count else { throw ValidationError.malformedResponse }
                var next = index + 1
                while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
                if next < bytes.count && bytes[next] == 58 {
                    guard !stack.isEmpty, var keys = stack[stack.count - 1],
                          let key = try? JSONDecoder().decode(String.self, from: Data(bytes[start...index])),
                          keys.insert(key).inserted else { throw ValidationError.malformedResponse }
                    stack[stack.count - 1] = keys
                }
            default: break
            }
            index += 1
        }
        guard stack.isEmpty else { throw ValidationError.malformedResponse }
    }
}
#endif
