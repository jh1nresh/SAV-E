import SwiftUI
import MapKit
import UIKit

struct ClipContentView: View {
    @State private var placeData: SharedPlaceData?
    @State private var tripData: SharedTripData?
    @State private var listData: SharedListData?
    @State private var referralData: SharedReferralProfile?
    @State private var isLoading = true
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let referral = referralData {
                    referralContentView(referral)
                } else if let list = listData {
                    listContentView(list)
                } else if let place = placeData {
                    placeContentView(place)
                } else if let trip = tripData {
                    tripContentView(trip)
                } else {
                    errorView
                }
            }
            .background(ClipDottedBackground())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            handleIncomingURL(activity.webpageURL)
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            if placeData == nil && tripData == nil && listData == nil && referralData == nil {
                isLoading = false
            }
        }
    }

    // MARK: - Place Content

    private func placeContentView(_ place: SharedPlaceData) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Map(position: $cameraPosition) {
                    Marker(place.name, coordinate: place.coordinate)
                        .tint(Color.saveCoral)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 14) {
                    AsyncImage(url: place.photoURLs.first.flatMap(URL.init(string:))) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            Color.savePaper
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundColor(Color.saveCoral)
                        }
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(place.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Color.saveInk)

                        Text(place.category)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 10) {
                        if let ratingText = ratingLine(for: place) {
                            detailRow(icon: "star.fill", title: "Rating", value: ratingText)
                        }
                        if let hours = place.hours, !hours.isEmpty {
                            detailRow(icon: "clock", title: "Hours", value: hours)
                        }
                        if !place.address.isEmpty {
                            detailRow(icon: "mappin.and.ellipse", title: "Address", value: place.address)
                        }
                        detailRow(icon: "link", title: "Source", value: place.sourceLabel)
                    }

                    if let note = place.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(Color.saveCoral)
                            .padding(.top, 2)
                    }
                }
                .padding(16)
                .background(Color.savePaper)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 2)
                )
                .shadow(color: Color.saveNotebookLine.opacity(0.18), radius: 0, x: 4, y: 4)
                .padding(.horizontal)

                Button(action: openInFullApp) {
                    Text("Save / Open in SAV-E")
                        .font(.headline)
                        .foregroundColor(Color.saveInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.saveHoney)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 2)
                        )
                        .shadow(color: Color.saveNotebookLine.opacity(0.18), radius: 0, x: 4, y: 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Trip Content

    private func tripContentView(_ trip: SharedTripData) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Map(position: $cameraPosition) {
                    ForEach(trip.stops) { stop in
                        Marker(stop.name, coordinate: stop.coordinate)
                            .tint(Color.saveCoral)
                    }
                }
                .frame(height: 200)
                .cornerRadius(16)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text(trip.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color.saveInk)

                    Text(summaryLine(for: trip))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(routeSummary(for: trip))
                        .font(.caption)
                        .foregroundColor(Color.saveCoral)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                VStack(spacing: 12) {
                    ForEach(trip.stops) { stop in
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundColor(Color.saveCoral)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(stop.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color.saveInk)
                                    Spacer()
                                    if let time = stop.time {
                                        Text(time)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                if !stop.address.isEmpty {
                                    Text(stop.address)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                if let note = stop.note {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundColor(Color.saveCoral)
                                }
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(Color.savePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 2)
                        )
                        .shadow(color: Color.saveNotebookLine.opacity(0.18), radius: 0, x: 4, y: 4)
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = copySummary(for: trip)
                    } label: {
                        Text("Copy route summary")
                            .font(.headline)
                            .foregroundColor(Color.saveInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.savePaper)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 2)
                            )
                    }

                    Button(action: openInFullApp) {
                        Text("Import / Open in SAV-E")
                            .font(.headline)
                            .foregroundColor(Color.saveInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.saveHoney)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 2)
                            )
                            .shadow(color: Color.saveNotebookLine.opacity(0.18), radius: 0, x: 4, y: 4)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }

    private func listContentView(_ list: SharedListData) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Map(position: $cameraPosition) {
                    ForEach(list.items) { item in
                        Marker(item.title, coordinate: item.coordinate)
                            .tint(item.source == "savedPlace" ? Color.saveCoral : Color.saveHoney)
                    }
                }
                .frame(height: 200)
                .cornerRadius(16)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text(list.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color.saveInk)

                    Text("\(list.items.count) places · \(list.roleLabel)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let note = list.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(Color.saveCoral)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                VStack(spacing: 12) {
                    ForEach(list.items) { item in
                        listItemRow(item)
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 10) {
                    Button(action: openInFullApp) {
                        Text("Open list in SAV-E")
                            .font(.headline)
                            .foregroundColor(Color.saveInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.saveHoney)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 2)
                            )
                            .shadow(color: Color.saveNotebookLine.opacity(0.18), radius: 0, x: 4, y: 4)
                    }

                    Text("Save any place from this list into your own SAV-E after opening the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }

    private func listItemRow(_ item: SharedListItem) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.photoURLs.first.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: item.source == "savedPlace" ? "mappin.circle.fill" : "map")
                    .font(.title3)
                    .foregroundColor(Color.saveCoral)
            }
            .frame(width: 48, height: 48)
            .background(Color.savePaper)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Color.saveInk)
                    Spacer()
                    Text(item.sourceLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let note = item.note {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(Color.saveCoral)
                }
            }
        }
        .padding(12)
        .background(Color.savePaper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .shadow(color: Color.saveNotebookLine.opacity(0.18), radius: 0, x: 4, y: 4)
    }

    private func referralContentView(_ profile: SharedReferralProfile) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Map(position: $cameraPosition) {
                    ForEach(profile.featuredPlaces) { place in
                        Marker(place.name, coordinate: place.coordinate)
                            .tint(Color.saveSky)
                    }
                }
                .frame(height: 220)
                .cornerRadius(18)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text(profile.displayName)
                        .font(.title2.weight(.bold))
                        .foregroundColor(Color.saveInk)
                    Text("@\(profile.handle) invited you to SAV-E")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Open their starter map pack, follow their guide lens, and get your first AI itinerary from their places.")
                        .font(.caption)
                        .foregroundColor(Color.saveCoral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                VStack(spacing: 12) {
                    ForEach(profile.featuredPlaces) { place in
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.fill")
                                .font(.title3)
                                .foregroundColor(Color.saveSky)
                                .frame(width: 42, height: 42)
                                .background(Color.savePaper)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Color.saveInk)
                                Text(place.address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(place.signal)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(Color.saveCoral)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.savePaper)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 2)
                        )
                    }
                }
                .padding(.horizontal)

                Button(action: openInFullApp) {
                    Text("Follow in SAV-E")
                        .font(.headline)
                        .foregroundColor(Color.saveInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.saveHoney)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 2)
                        )
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(Color.saveInk)
            Text("Loading SAV-E link...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(Color.saveCoral)
            Text("Couldn't load this SAV-E link")
                .font(.headline)
                .foregroundColor(Color.saveInk)
            Text("The link may be invalid or expired.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - URL Handling

    private func handleIncomingURL(_ url: URL?) {
        guard let url else { return }
        print("App Clip opened with URL: \(url)")

        if let referral = SharedReferralProfile.from(url: url) {
            referralData = referral
            updateCamera(for: referral.featuredPlaces.map {
                SharedTripData.SharedStop(id: $0.id, name: $0.name, address: $0.address, lat: $0.lat, lng: $0.lng, time: nil, note: $0.signal)
            })
            isLoading = false
            return
        }

        if SharedListPayload.isListLink(url) {
            if let payload = SharedListPayload.from(url: url) {
                listData = payload.list
                placeData = nil
                tripData = nil
                updateCamera(for: payload.list.items.map { SharedTripData.SharedStop(id: $0.id.uuidString, name: $0.title, address: $0.subtitle, lat: $0.latitude, lng: $0.longitude, time: nil, note: $0.note) })
            }
            isLoading = false
            return
        }

        if isPlaceLink(url) {
            if let data = SharedPlaceData.from(url: url) {
                placeData = data
                tripData = nil
                listData = nil
                updateCamera(for: [SharedTripData.SharedStop(id: data.id, name: data.name, address: data.address, lat: data.lat, lng: data.lng, time: nil, note: data.note)])
                isLoading = false
                return
            } else if SharedPlaceData.shortCode(from: url) != nil {
                isLoading = true
                Task {
                    let resolved = await SharedPlaceData.resolveShortCode(from: url)
                    await MainActor.run {
                        if let data = resolved {
                            placeData = data
                            tripData = nil
                            listData = nil
                            updateCamera(for: [SharedTripData.SharedStop(id: data.id, name: data.name, address: data.address, lat: data.lat, lng: data.lng, time: nil, note: data.note)])
                        }
                        isLoading = false
                    }
                }
                return
            }
            isLoading = false
            return
        }

        guard isTripLink(url) else {
            placeData = nil
            tripData = nil
            listData = nil
            referralData = nil
            isLoading = false
            return
        }

        if let data = SharedTripData.from(url: url) {
            tripData = data
            placeData = nil
            listData = nil
            updateCamera(for: data.stops)
        }
        // Invalid URL data → tripData stays nil → errorView shown
        isLoading = false
    }

    private var navigationTitle: String {
        if referralData != nil { return "Referral Preview" }
        if listData != nil { return "List Preview" }
        if placeData != nil { return "Place Preview" }
        return "Trip Preview"
    }

    private func isPlaceLink(_ url: URL) -> Bool {
        if url.scheme == "wanderly", url.host == "p" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app", "sav-e.app", "wanderly.app"].contains(url.host ?? "") else {
            return false
        }
        return url.path.split(separator: "/").first.map(String.init) == "p"
    }

    private func isTripLink(_ url: URL) -> Bool {
        if url.scheme == "wanderly", url.host == "trip" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app", "sav-e.app", "wanderly.app"].contains(url.host ?? "") else {
            return false
        }

        let pathParts = url.path.split(separator: "/")
        if pathParts.first.map(String.init) == "trip", pathParts.count >= 2 {
            return true
        }

        guard url.path == "/trip",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.queryItems?.contains { item in
            item.name == "d" && item.value?.isEmpty == false
        } == true
    }

    private func updateCamera(for stops: [SharedTripData.SharedStop]) {
        let lats = stops.map(\.lat)
        let lngs = stops.map(\.lng)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
            longitudeDelta: max((maxLng - minLng) * 1.5, 0.01)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func summaryLine(for trip: SharedTripData) -> String {
        let countLabel = trip.stops.count == 1 ? "1 place" : "\(trip.stops.count) stops"
        guard !trip.city.isEmpty else { return countLabel }
        return "\(countLabel) in \(trip.city)"
    }

    private func routeSummary(for trip: SharedTripData) -> String {
        trip.stops.map(\.name).joined(separator: " → ")
    }

    private func copySummary(for trip: SharedTripData) -> String {
        let stops = trip.stops.enumerated().map { index, stop in
            let address = stop.address.isEmpty ? "" : " — \(stop.address)"
            return "\(index + 1). \(stop.name)\(address)"
        }.joined(separator: "\n")
        return "\(trip.name)\n\(trip.routeSummary)\n\(stops)"
    }

    private func ratingLine(for place: SharedPlaceData) -> String? {
        guard let rating = place.rating else { return nil }
        if let reviewCount = place.reviewCount {
            return String(format: "%.1f · %d reviews", rating, reviewCount)
        }
        return String(format: "%.1f", rating)
    }

    private func detailRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundColor(Color.saveCoral)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption)
                    .foregroundColor(Color.saveInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func openInFullApp() {
        let url: URL?
        if listData != nil {
            url = currentListAppURL()
        } else if let referralData {
            url = referralData.fullAppURL()
        } else if let placeData {
            url = placeData.toURL(baseURL: "wanderly://p") ?? URL(string: "wanderly://p")
        } else {
            url = tripData?.toURL(baseURL: "wanderly://trip") ?? URL(string: "wanderly://trip")
        }
        guard let url else { return }
        UIApplication.shared.open(url)
    }

    private func currentListAppURL() -> URL? {
        guard let listData,
              let payloadData = try? JSONEncoder().encode(SharedListPayload(list: listData, role: listData.viewerRole)),
              let base64 = payloadData.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return URL(string: "wanderly://list")
        }
        return URL(string: "wanderly://list?d=\(base64)&r=\(listData.viewerRole)")
    }
}

// MARK: - Demo Data

extension SharedTripData {
    static let demo = SharedTripData(
        name: "SF Food Tour",
        city: "San Francisco",
        stops: [
            SharedStop(id: UUID().uuidString, name: "Tartine Bakery", address: "600 Guerrero St, SF", lat: 37.7614, lng: -122.4241, time: "9:00 AM", note: "Must try the morning bun"),
            SharedStop(id: UUID().uuidString, name: "Dolores Park", address: "Dolores St, SF", lat: 37.7596, lng: -122.4269, time: "10:30 AM", note: nil),
            SharedStop(id: UUID().uuidString, name: "Bi-Rite Creamery", address: "3692 18th St, SF", lat: 37.7618, lng: -122.4256, time: "12:00 PM", note: "Salted caramel ice cream"),
        ]
    )
}

// MARK: - Hex Color (standalone for App Clip target)

extension Color {
    static let saveCream = Color(hex: "FFF7E8")
    static let saveHoney = Color(hex: "FFE24A")
    static let saveCoral = Color(hex: "FF8A65")
    static let saveSky = Color(hex: "7EDAEF")
    static let saveMint = Color(hex: "B8F5C8")
    static let savePink = Color(hex: "FFD7E8")
    static let saveInk = Color(hex: "111111")
    static let savePaper = Color(hex: "FFF0D6")
    static let saveNotebookLine = Color(hex: "111111")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

private struct ClipDottedBackground: View {
    var body: some View {
        Color.saveCream
            .overlay {
                Canvas { context, size in
                    let spacing: CGFloat = 18
                    for x in stride(from: CGFloat(8), through: size.width, by: spacing) {
                        for y in stride(from: CGFloat(8), through: size.height, by: spacing) {
                            let rect = CGRect(x: x, y: y, width: 2, height: 2)
                            context.fill(Path(ellipseIn: rect), with: .color(Color.saveNotebookLine.opacity(0.08)))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
    }
}
