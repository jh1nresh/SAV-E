import Foundation

/// What the user asked for, separated from how it was phrased.
///
/// `DeterministicTripPlanner` used to parse the raw message itself at three
/// points — day count by regex, place filters by tokenizing, pace by keyword —
/// which made planning fail on wording rather than on substance. Four bugs in
/// one day came from that: "my stamps" searched for a place named *stamps*,
/// "one day" searched for one named *one*, a two-character CJK region was
/// dropped below a Latin length floor, and any phrasing without an explicit
/// day count was refused outright.
///
/// Splitting intent from phrasing lets a smarter extractor (an LLM that knows
/// "somewhere chill with my parents" means a relaxed pace) fill the same struct
/// the deterministic parser fills, without touching selection, routing, or
/// scheduling — the parts that must stay deterministic so a plan can only ever
/// contain places the user actually saved.
struct TripPlanningIntent: Equatable {
    /// Days requested, or `nil` to let the planner size the trip from what is
    /// available. Nil is not a failure: "plan a Taipei trip from my stamps" is
    /// a perfectly clear request.
    var days: Int?

    /// Terms a place must match to be treated as specifically requested,
    /// already stripped of product vocabulary and filler.
    ///
    /// Empty means "no specific ask" — plan from everything nearby. That is
    /// different from a term that matches nothing, which must still refuse
    /// rather than quietly plan somewhere else.
    var searchTerms: [String]

    /// The original request, still needed for pace and meal-window parsing.
    var rawMessage: String

    /// Whether the user named something specific that a place has to match.
    var hasSpecificRequest: Bool { !searchTerms.isEmpty }

    /// Days to actually plan, given how many places are available.
    ///
    /// Sized so a day is neither a single stop nor a forced march, and capped
    /// at a week the way an explicit request is.
    func resolvedDays(availablePlaceCount: Int, maxStopsPerDay: Int) -> Int {
        if let days { return max(1, min(days, Self.maximumDays)) }
        guard availablePlaceCount > 0 else { return 1 }
        let comfortable = max(2, min(maxStopsPerDay, Self.comfortableStopsPerDay))
        let inferred = Int(ceil(Double(availablePlaceCount) / Double(comfortable)))
        return max(1, min(inferred, Self.maximumInferredDays))
    }

    static let maximumDays = 7
    /// An inferred trip stays short: guessing a week from a big vault would be
    /// planning something the user never asked for.
    static let maximumInferredDays = 3
    static let comfortableStopsPerDay = 4
}

/// What a trip-intent extraction is given.
///
/// Privacy: the query plus area labels the user already saved places in —
/// the same city/area granularity `GroundedAnswerContext` uses. No notes,
/// no full addresses, no coordinates.
struct TripIntentParseRequest: Equatable {
    let query: String
    var savedAreaHints: [String] = []
}

/// Clamps a model-produced intent down to something the planner can trust.
///
/// The planner selects only from saved places, so a bad `searchTerms` value
/// cannot inject a place — but it can still make a plan refuse by matching
/// nothing, or bloat scoring with dozens of terms. Both are bounded here.
struct TripIntentJSONValidator {
    static let maxSearchTerms = 6
    static let maxTermLength = 24

    func parse(_ json: String, rawQuery: String) throws -> TripPlanningIntent {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SaveSearchIntentValidationError.malformedJSON
        }

        var days: Int?
        if let raw = object["days"] as? Int {
            days = max(1, min(raw, TripPlanningIntent.maximumDays))
        } else if let raw = object["days"] as? Double {
            days = max(1, min(Int(raw), TripPlanningIntent.maximumDays))
        }

        let rawTerms = (object["searchTerms"] as? [Any])?.compactMap { $0 as? String } ?? []
        let terms = rawTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.count <= Self.maxTermLength }
            .reduce(into: [String]()) { result, term in
                guard !result.contains(term) else { return }
                result.append(term)
            }
            .prefix(Self.maxSearchTerms)

        return TripPlanningIntent(days: days, searchTerms: Array(terms), rawMessage: rawQuery)
    }
}
