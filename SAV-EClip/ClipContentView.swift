import SwiftUI
import MapKit
import UIKit

struct ClipContentView: View {
    @State private var placeReceipt: SharedPlaceReceipt?
    @State private var tripData: SharedTripData?
    @State private var listData: SharedListData?
    @State private var referralData: SharedReferralProfile?
    @State private var mySavesData: SharedMySavesData?
    @State private var mySavesSourceURL: URL?
    @State private var isLoading = true
    @State private var incomingURLTask: Task<Void, Never>?
    @State private var activeIncomingURLRequestID: UUID?
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if let mySaves = mySavesData {
                    mySavesContentView(mySaves)
                } else if let referral = referralData {
                    referralContentView(referral)
                } else if let list = listData {
                    listContentView(list)
                } else if let receipt = placeReceipt {
                    placeContentView(receipt)
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
            if activeIncomingURLRequestID == nil,
               placeReceipt == nil && tripData == nil && listData == nil && referralData == nil && mySavesData == nil {
                isLoading = false
            }
        }
        .onDisappear {
            incomingURLTask?.cancel()
            incomingURLTask = nil
            activeIncomingURLRequestID = nil
        }
    }

    // MARK: - My SAV-E Content

    private func mySavesContentView(_ payload: SharedMySavesData) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("My SAV-E")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(Color.saveInk)

                    Text("Your texted places, verified visits, and receipt-gated reviews.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        statPill(value: payload.counts.places, label: "places")
                        statPill(value: payload.counts.visits, label: "visits")
                        statPill(value: payload.counts.reviews, label: "reviews")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.savePaper)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 2)
                )
                .shadow(color: Color.saveNotebookLine.opacity(0.18), radius: 0, x: 4, y: 4)
                .padding(.horizontal)

                if payload.places.isEmpty {
                    emptyMySavesSection
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeading("Saved places")
                        ForEach(Array(payload.places.enumerated()), id: \.element.id) { index, place in
                            mySavedPlaceRow(place, index: index)
                        }
                    }
                    .padding(.horizontal)
                }

                if !payload.visits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeading("Verified visits")
                        ForEach(payload.visits) { visit in
                            myVisitRow(visit)
                        }
                    }
                    .padding(.horizontal)
                }

                if !payload.reviews.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeading("Reviews")
                        ForEach(payload.reviews) { review in
                            myReviewRow(review)
                        }
                    }
                    .padding(.horizontal)
                }

                Button(action: openInFullApp) {
                    Text("Open in SAV-E")
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
            .padding(.top, 16)
        }
    }

    private func statPill(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundColor(Color.saveInk)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.saveCream)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.5)
        )
    }

    private var emptyMySavesSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundColor(Color.saveCoral)
            Text("No saved places yet")
                .font(.headline)
                .foregroundColor(Color.saveInk)
            Text("Text SAV-E a place link to start building your private map.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color.savePaper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .padding(.horizontal)
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundColor(Color.saveInk)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mySavedPlaceRow(_ place: SharedMySavesData.SavedPlace, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index + 1).")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(Color.saveInk)
                    .frame(width: 34, height: 34)
                    .background(Color.saveCream)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color.saveInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let area = place.area, !area.isEmpty {
                        Text(area)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let category = place.category, !category.isEmpty {
                        Text(category)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(Color.saveCoral)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if let mapURL = place.mapURL {
                    Button {
                        UIApplication.shared.open(mapURL)
                    } label: {
                        Label("Map", systemImage: "map")
                    }
                    .buttonStyle(MySavesActionButtonStyle())
                }
                if let sourceURL = place.safeSourceURL {
                    Button {
                        UIApplication.shared.open(sourceURL)
                    } label: {
                        Label("Source", systemImage: "link")
                    }
                    .buttonStyle(MySavesActionButtonStyle())
                }
            }
        }
        .padding(14)
        .background(Color.savePaper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .shadow(color: Color.saveNotebookLine.opacity(0.16), radius: 0, x: 3, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Saved place \(index + 1), \(place.name)")
    }

    private func myVisitRow(_ visit: SharedMySavesData.VerifiedVisit) -> some View {
        compactMySavesRow(
            icon: "checkmark.seal.fill",
            title: visit.merchant,
            subtitle: [visit.total, visit.visitDate].compactMap { $0 }.joined(separator: " · "),
            accent: Color.saveMint
        )
    }

    private func myReviewRow(_ review: SharedMySavesData.StoredReview) -> some View {
        let rating = review.rating.map { "\($0)★" }
        let subtitle = [rating, review.text].compactMap { $0 }.joined(separator: " · ")
        return compactMySavesRow(
            icon: "star.fill",
            title: review.merchant,
            subtitle: subtitle,
            accent: Color.saveHoney
        )
    }

    private func compactMySavesRow(icon: String, title: String, subtitle: String, accent: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(Color.saveInk)
                .frame(width: 34, height: 34)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color.saveInk)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.savePaper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
    }

    // MARK: - Place Content

    private func placeContentView(_ receipt: SharedPlaceReceipt) -> some View {
        let place = receipt.payload
        return ScrollView {
            VStack(spacing: 18) {
                Map(position: $cameraPosition) {
                    Marker(place.name, coordinate: place.coordinate)
                        .tint(Color.saveCoral)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        if let sender = receipt.verifiedSenderLabel {
                            Label("Shared by \(sender)", systemImage: "person.crop.circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Color.saveCoral)
                        } else {
                            Label("Shared place", systemImage: "square.and.arrow.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)
                        }

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

                VStack(spacing: 12) {
                    Button(action: openInFullApp) {
                        Text("Save to my SAV-E")
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

                    if let mapsURL = place.appleMapsURL {
                        Link(destination: mapsURL) {
                            Label("Open in Maps", systemImage: "map")
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
                    }
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
        incomingURLTask?.cancel()
        incomingURLTask = nil
        let requestID = UUID()
        activeIncomingURLRequestID = requestID

        if let referral = SharedReferralProfile.from(url: url) {
            referralData = referral
            mySavesData = nil
            mySavesSourceURL = nil
            placeReceipt = nil
            tripData = nil
            listData = nil
            updateCamera(for: referral.featuredPlaces.map {
                SharedTripData.SharedStop(id: $0.id, name: $0.name, address: $0.address, lat: $0.lat, lng: $0.lng, time: nil, note: $0.signal)
            })
            isLoading = false
            return
        }

        if SharedListPayload.isListLink(url) {
            if let payload = SharedListPayload.from(url: url) {
                listData = payload.list
                mySavesData = nil
                mySavesSourceURL = nil
                placeReceipt = nil
                tripData = nil
                referralData = nil
                updateCamera(for: payload.list.items.map { SharedTripData.SharedStop(id: $0.id.uuidString, name: $0.title, address: $0.subtitle, lat: $0.latitude, lng: $0.longitude, time: nil, note: $0.note) })
            }
            isLoading = false
            return
        }

        if SharedMySavesData.isMySavesLink(url) {
            isLoading = true
            incomingURLTask = Task { @MainActor in
                let resolved = await SharedMySavesData.resolve(from: url)
                guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                mySavesData = resolved
                mySavesSourceURL = url
                placeReceipt = nil
                tripData = nil
                listData = nil
                referralData = nil
                isLoading = false
                incomingURLTask = nil
            }
            return
        }

        if isPlaceLink(url) {
            guard url.absoluteString.utf8.count <= ShareRoutePayloadLimits.pendingPlaceURLMaxBytes else {
                isLoading = false
                return
            }
            persistPendingFriendShare(url)
            placeReceipt = nil
            mySavesData = nil
            mySavesSourceURL = nil
            tripData = nil
            listData = nil
            referralData = nil
            if let data = SharedPlaceData.from(url: url) {
                placeReceipt = .embedded(data)
                updateCamera(for: [SharedTripData.SharedStop(id: data.id, name: data.name, address: data.address, lat: data.lat, lng: data.lng, time: nil, note: data.note)])
                isLoading = false
                return
            } else if SharedPlaceData.shortCode(from: url) != nil {
                isLoading = true
                incomingURLTask = Task { @MainActor in
                    do {
                        let receipt = try await SharedPlaceReceipt.resolve(from: url)
                        guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                        let data = receipt.payload
                        placeReceipt = receipt
                        mySavesData = nil
                        mySavesSourceURL = nil
                        tripData = nil
                        listData = nil
                        referralData = nil
                        updateCamera(for: [SharedTripData.SharedStop(id: data.id, name: data.name, address: data.address, lat: data.lat, lng: data.lng, time: nil, note: data.note)])
                        isLoading = false
                        if let code = receipt.code {
                            guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                            await SharedPlaceReceipt.recordPublicEvent(
                                code: code,
                                eventType: "friend_share_receipt_opened"
                            )
                        }
                        guard activeIncomingURLRequestID == requestID else { return }
                        incomingURLTask = nil
                    } catch is CancellationError {
                        return
                    } catch let error as SharedPlaceReceiptError {
                        guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                        if let code = SharedPlaceData.shortCode(from: url) {
                            await SharedPlaceReceipt.recordPublicEvent(
                                code: code,
                                eventType: "friend_share_open_failed",
                                reasonCode: error.eventFailureReason
                            )
                        }
                        guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                        isLoading = false
                        incomingURLTask = nil
                    } catch {
                        guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                        if let code = SharedPlaceData.shortCode(from: url) {
                            await SharedPlaceReceipt.recordPublicEvent(
                                code: code,
                                eventType: "friend_share_open_failed",
                                reasonCode: "unknown"
                            )
                        }
                        guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                        isLoading = false
                        incomingURLTask = nil
                    }
                }
                return
            }
            isLoading = false
            return
        }

        guard isTripLink(url) else {
            placeReceipt = nil
            tripData = nil
            listData = nil
            referralData = nil
            mySavesData = nil
            mySavesSourceURL = nil
            isLoading = false
            return
        }

        if let data = SharedTripData.from(url: url) {
            tripData = data
            placeReceipt = nil
            listData = nil
            referralData = nil
            mySavesData = nil
            mySavesSourceURL = nil
            updateCamera(for: data.stops)
        }
        // Invalid URL data → tripData stays nil → errorView shown
        isLoading = false
    }

    private var navigationTitle: String {
        if mySavesData != nil { return "My SAV-E" }
        if referralData != nil { return "Referral Preview" }
        if listData != nil { return "List Preview" }
        if placeReceipt != nil { return "Place Preview" }
        return "Trip Preview"
    }

    private func isPlaceLink(_ url: URL) -> Bool {
        if url.scheme == "wanderly", url.host == "p" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app"].contains(url.host ?? "") else {
            return false
        }
        return url.path.split(separator: "/").first.map(String.init) == "p"
    }

    private func isTripLink(_ url: URL) -> Bool {
        if url.scheme == "wanderly", url.host == "trip" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app"].contains(url.host ?? "") else {
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
        if mySavesData != nil {
            url = mySavesSourceURL
        } else if listData != nil {
            url = currentListAppURL()
        } else if let referralData {
            url = referralData.fullAppURL()
        } else if let placeReceipt {
            url = placeReceipt.fullAppURL ?? URL(string: "wanderly://p")
        } else {
            url = tripData?.toURL(baseURL: "wanderly://trip") ?? URL(string: "wanderly://trip")
        }
        guard let url else { return }
        if placeReceipt != nil {
            persistPendingFriendShare(url)
        }
        UIApplication.shared.open(url) { opened in
            guard !opened,
                  let appStoreURL = URL(string: "https://apps.apple.com/app/id6769216556")
            else { return }
            UIApplication.shared.open(appStoreURL)
        }
    }

    private func persistPendingFriendShare(_ url: URL) {
        guard url.absoluteString.utf8.count <= ShareRoutePayloadLimits.pendingPlaceURLMaxBytes else { return }
        UserDefaults(suiteName: "group.com.wanderly.app")?
            .set(url.absoluteString, forKey: "pendingFriendShareURL")
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

private struct MySavesActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .foregroundColor(Color.saveInk)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(configuration.isPressed ? Color.saveHoney.opacity(0.65) : Color.saveCream)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.5)
            )
    }
}
