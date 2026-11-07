import Foundation
import MapKit
import CoreLocation

// Read-only diagnostic. Only this public fixture is submitted to Apple.
// This does not replace the iOS production acceptance test.
let address = "中国北京市朝阳区望京东园四区4号楼"

@MainActor
func report(_ phase: String, _ marks: [CLPlacemark], error: Error? = nil) {
    let failure = error as NSError?
    print("phase=\(phase) count=\(marks.count) error=\(failure.map { "\($0.domain)/\($0.code)" } ?? "none")")
    for mark in marks {
        let lat = mark.location?.coordinate.latitude ?? .nan
        let lon = mark.location?.coordinate.longitude ?? .nan
        print("iso=\(mark.isoCountryCode ?? "nil") admin=\(mark.administrativeArea ?? "nil") city=\(mark.locality ?? "nil") lat=\(lat) lon=\(lon)")
    }
    fflush(stdout)
}

Task { @MainActor in
    let geocoder = CLGeocoder()
    do {
        let marks = try await geocoder.geocodeAddressString(address, in: nil, preferredLocale: Locale(identifier: "en_US"))
        report("CL-exact-address", marks)
    } catch { report("CL-exact-address", [], error: error) }
    if #available(macOS 26.0, *) {
        if let request = MKGeocodingRequest(addressString: address) {
            request.preferredLocale = Locale(identifier: "en_US")
            do { report("structured-exact-address", try await request.mapItems.map(\.placemark)) }
            catch { report("structured-exact-address", [], error: error) }
        }
    }
    for (phase, query) in [("local-search-exact-address", address), ("local-search-public-POI", "高德地图总部 北京")] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        do { report(phase, try await MKLocalSearch(request: request).start().mapItems.map(\.placemark)) }
        catch { report(phase, [], error: error) }
    }
    exit(0)
}
RunLoop.main.run()
