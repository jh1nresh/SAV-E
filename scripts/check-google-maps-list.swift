// Host verifier: compile with SocialPlaceEvidence.swift and
// GoogleMapsListPlaceExtractor.swift; no simulator or account is required.
import Foundation

@main
struct GoogleMapsListCheck {
    static let id = "fixture-list-public-123"
    static let url = "https://www.google.com/maps/@/data=!3m1!4b1!4m2!11m1!2s\(id)?g_st=share"

    static func payload(count: Int = 32, total: Int? = nil, transform: ((inout [Any]) -> Void)? = nil) throws -> Data {
        var rows: [Any] = (0..<count).map { i in
            [NSNull(), [NSNull(), NSNull(), "untrusted display text", NSNull(), "\(i + 1) Test Street",
                        [NSNull(), NSNull(), 25.0 + Double(i) / 1_000, 121.0 + Double(i) / 1_000],
                        ["provider", "\(i)"]], i < 2 ? "Same name cafe" : "Cafe \(i)", "private note"] as [Any]
        }
        transform?(&rows)
        let list: [Any] = [[id], 4, NSNull(), ["PRIVATE OWNER"], "Test saved list", "private description",
                           NSNull(), NSNull(), rows, NSNull(), NSNull(), NSNull(), total ?? rows.count]
        return Data(")]}'\n".utf8) + (try JSONSerialization.data(withJSONObject: [list, ""]))
    }

    static func expect(_ value: Bool, _ message: String) {
        guard value else { fatalError(message) }
    }

    static func main() async throws {
        expect(GoogleMapsPublicListLoader.listID(in: url) == id, "expanded share URL")
        expect(GoogleMapsPublicListLoader.listID(in: "https://www.google.com/maps/placelists/list/\(id)") == id, "canonical list URL")
        for bad in ["https://www.google.com.evil.test/maps/placelists/list/\(id)",
                    "https://evil.test/maps/@/data=!11m1!2s\(id)",
                    "https://user:password@www.google.com/maps/placelists/list/\(id)",
                    "http://www.google.com/maps/placelists/list/\(id)",
                    "https://www.google.com:9999/maps/placelists/list/\(id)",
                    "https://www.google.com/maps/place/Cafe/@25,121"] {
            expect(GoogleMapsPublicListLoader.listID(in: bad) == nil, "Reject non-list or spoofed URL")
        }
        expect(GoogleMapsPublicListLoader.requestURL(for: "x!2shttps://evil.test") == nil, "Reject ID query injection")
        let full = GoogleMapsPublicListLoader.parse(try payload(), expectedListID: id)
        expect(full.candidates.count == 32 && full.notice == nil, "Do not truncate at 30")
        expect(full.candidates[0].name == full.candidates[1].name, "Keep same-name branches")
        expect(full.candidates[1].address == "2 Test Street" && full.candidates[1].latitude == 25.001, "Keep row identity together")
        expect(!String(describing: full).contains("PRIVATE OWNER") && !String(describing: full).contains("private note"), "Exclude owner and notes")
        let duplicate = GoogleMapsPublicListLoader.parse(try payload(count: 2, transform: { rows in rows.append(rows[0]) }), expectedListID: id)
        expect(duplicate.candidates.count == 2 && duplicate.notice == nil, "Deduplicate provider identity, not name")
        let partial = GoogleMapsPublicListLoader.parse(try payload(total: 501), expectedListID: id)
        expect(partial.candidates.isEmpty && partial.notice?.contains("32 of 501") == true, "Never claim partial list is complete")
        let badCoordinate = GoogleMapsPublicListLoader.parse(try payload(count: 1, transform: { rows in
            var row = rows[0] as! [Any]; var place = row[1] as! [Any]
            place[5] = [NSNull(), NSNull(), true, 121]; row[1] = place; rows[0] = row
        }), expectedListID: id)
        expect(badCoordinate.candidates.isEmpty && badCoordinate.notice != nil, "Reject boolean coordinates")
        for latitude in [91.0, -91.0] {
            let invalid = GoogleMapsPublicListLoader.parse(try payload(count: 1, transform: { rows in
                var row = rows[0] as! [Any]; var place = row[1] as! [Any]
                place[5] = [NSNull(), NSNull(), latitude, 121]; row[1] = place; rows[0] = row
            }), expectedListID: id)
            expect(invalid.candidates.isEmpty, "Reject out-of-range coordinates")
        }
        for bad in [Data("<html>Sign in</html>".utf8), Data("[]".utf8), Data(repeating: 0, count: 4_000_001)] {
            expect(GoogleMapsPublicListLoader.parse(bad, expectedListID: id).candidates.isEmpty, "Private/malformed/oversized responses cannot create places")
        }
        expect(GoogleMapsPublicListLoader.parse(try payload(), expectedListID: "other-list-123").candidates.isEmpty, "Reject wrong list response")
        expect(GoogleMapsPublicListLoader.parse(try payload(count: 0), expectedListID: id).notice?.contains("no readable places") == true, "Empty is explicit")
        let responseData = try payload()
        let loaded = await GoogleMapsPublicListLoader.load(sourceURL: url) { request in
            expect(request.host == "www.google.com" && request.path == "/maps/preview/entitylist/getlist", "Fixed public endpoint")
            return responseData
        }
        expect(loaded?.candidates.count == 32, "Bounded loader is reachable")
        let nonList = await GoogleMapsPublicListLoader.load(sourceURL: "https://example.com") { _ in
            fatalError("Non-list must not request a list")
        }
        expect(nonList == nil, "Unrelated paths remain unchanged")
        let failure = await GoogleMapsPublicListLoader.load(sourceURL: url) { _ in throw URLError(.timedOut) }
        expect(failure?.candidates.isEmpty == true && failure?.notice != nil, "Network failure preserves source")
        let html = "<a href=\"/maps/place/Alpha/@25.01,121.01\">Alpha</a><a href=\"/maps/place/Beta/@25.02,121.02\">Beta</a>"
        let legacy = GoogleMapsListPlaceExtractor.extractCandidates(sourceURL: url, title: nil, text: nil,
            metadataTitle: nil, metadataDescription: nil, htmlText: html)
        expect(legacy.count == 2 && legacy[0].latitude == 25.01 && legacy[1].latitude == 25.02, "Never borrow adjacent entry coordinates")
        print("PASS: Google Maps list URL, payload, completeness, identity, privacy, failure and legacy-link checks")
        if let liveURL = CommandLine.arguments.dropFirst().first {
            let result = await GoogleMapsPublicListLoader.load(sourceURL: liveURL)
            expect(result?.notice == nil && result?.candidates.isEmpty == false, "Live list must be fully readable")
            print("LIVE PASS: \(result!.candidates.count) complete review candidates; title: \(result!.title)")
        }
    }
}
