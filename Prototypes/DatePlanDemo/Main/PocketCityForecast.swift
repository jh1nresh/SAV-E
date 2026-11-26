#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Foundation

actor PocketCityForecast {
    static let shared = PocketCityForecast()

    // Only a coarse viewport grid cell goes to the provider.
    struct Area: Hashable {
        let latitudeTenths: Int
        let longitudeTenths: Int

        init?(latitude: Double, longitude: Double) {
            guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
            latitudeTenths = Int((latitude * 10).rounded())
            longitudeTenths = Int((longitude * 10).rounded())
        }
    }

    struct Reading: Identifiable {
        let time: Date
        let celsius: Double?
        let symbol: String

        var id: Date { time }
        var isNight: Bool { symbol.hasSuffix("_night") }
    }

    struct Result {
        let readings: [Reading]
        var refreshAfter: Date
        let usableUntil: Date

        func current(at now: Date) -> Reading? {
            guard now < usableUntil else { return nil }
            return readings.last { $0.time <= now }
        }

        func upcoming(at now: Date) -> [Reading] {
            guard now < usableUntil else { return [] }
            let cutoff = now.addingTimeInterval(6 * 3_600)
            return readings.filter { $0.time > now && $0.time <= cutoff }
        }
    }

    private struct Response: Decodable {
        struct Properties: Decodable { let timeseries: [Period] }
        struct Period: Decodable { let time: Date; let data: Conditions }
        struct Conditions: Decodable {
            struct Instant: Decodable {
                struct Details: Decodable { let air_temperature: Double? }
                let details: Details
            }
            let instant: Instant?
            let next_1_hours: Interval?
            let next_6_hours: Interval?

            func reading(at time: Date, hourlyOnly: Bool) -> Reading? {
                let interval = next_1_hours ?? (hourlyOnly ? nil : next_6_hours)
                guard let symbol = interval?.summary.symbol_code else { return nil }
                return Reading(time: time, celsius: instant?.details.air_temperature, symbol: symbol)
            }
        }
        struct Interval: Decodable { let summary: Summary }
        struct Summary: Decodable { let symbol_code: String }
        let properties: Properties
    }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }()
    private var cache: [Area: Result] = [:]

    static func weather(for symbol: String) -> PocketCityPresentation.Weather? {
        let symbol = symbol.components(separatedBy: "_")[0]
        if symbol.contains("snow") || symbol.contains("sleet") { return .cloudy }
        if symbol.contains("thunder") { return .rain }
        if symbol.hasPrefix("lightrain") { return .drizzle }
        if symbol.contains("rain") { return .rain }
        if ["cloudy", "partlycloudy", "fog"].contains(symbol) { return .cloudy }
        if ["clearsky", "fair"].contains(symbol) { return .day }
        return nil
    }

    func forecast(for area: Area) async throws -> Result {
        let now = Date()
        if let entry = cache[area], entry.refreshAfter > now { return entry }
        let lat = Double(area.latitudeTenths) / 10
        let lon = Double(area.longitudeTenths) / 10
        let url = URL(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=\(lat)&lon=\(lon)")!
        var request = URLRequest(url: url)
        request.setValue("SavvyPocketCity/1.0 (https://github.com/jh1nresh/SAV-E)", forHTTPHeaderField: "User-Agent")
        var result: Result
        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let readings = try Self.decodeReadings(body, at: now)
            guard let current = readings.first else { throw URLError(.cannotDecodeContentData) }
            let dateFormat = DateFormatter()
            dateFormat.locale = Locale(identifier: "en_US_POSIX")
            dateFormat.timeZone = TimeZone(secondsFromGMT: 0)
            dateFormat.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let expires = http.value(forHTTPHeaderField: "Expires").flatMap(dateFormat.date(from:))
            result = Result(readings: readings, refreshAfter: max(now.addingTimeInterval(600), expires ?? now.addingTimeInterval(1800)),
                            usableUntil: current.time.addingTimeInterval(7200))
            result.refreshAfter = min(result.refreshAfter, result.usableUntil)
        } catch {
            try Task.checkCancellation()
            let retry = now.addingTimeInterval(600)
            if let previous = cache[area], previous.usableUntil > now {
                result = Result(readings: previous.readings, refreshAfter: min(previous.usableUntil, retry),
                                usableUntil: previous.usableUntil)
            } else {
                result = Result(readings: [], refreshAfter: retry, usableUntil: now)
            }
        }
        try Task.checkCancellation()
        if cache.count >= 32, cache[area] == nil, let oldest = cache.min(by: { $0.value.refreshAfter < $1.value.refreshAfter }) {
            cache.removeValue(forKey: oldest.key)
        }
        cache[area] = result
        return result
    }

    static func decodeReadings(_ body: Data, at now: Date) throws -> [Reading] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let periods = try decoder.decode(Response.self, from: body).properties.timeseries
        guard let period = periods.last(where: { $0.time <= now && now.timeIntervalSince($0.time) < 3_600 }),
              let current = period.data.reading(at: period.time, hourlyOnly: false),
              weather(for: current.symbol) != nil else { return [] }

        // Keep enough hours to advance the card through the result's cache lifetime.
        let upcoming = periods.lazy
            .filter { $0.time > now && $0.time <= now.addingTimeInterval(8 * 3_600) }
            .compactMap { $0.data.reading(at: $0.time, hourlyOnly: true) }
        return [current] + upcoming
    }
}
#endif
