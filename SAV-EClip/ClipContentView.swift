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
    @State private var lastIncomingURL: URL?
    @State private var loadErrorMessage: String?
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
            .toolbar {
                if tripData != nil || placeReceipt != nil {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            Image("SavvyLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .accessibilityHidden(true)
                            Text("Savvy")
                                .font(ClipAtlasType.strong(18, relativeTo: .headline))
                                .foregroundStyle(ClipAtlasPalette.forest)
                        }
                    }
                }
            }
            .toolbarBackground(ClipAtlasPalette.canvas, for: .navigationBar)
            .toolbarBackground(tripData != nil || placeReceipt != nil ? .visible : .automatic, for: .navigationBar)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            handleIncomingURL(activity.webpageURL)
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .task {
#if DEBUG
            if activeIncomingURLRequestID == nil,
               let rawURL = ProcessInfo.processInfo.environment["_XCAppClipURL"],
               let localInvocationURL = URL(string: rawURL) {
                handleIncomingURL(localInvocationURL)
                return
            }
#endif
            try? await Task.sleep(for: .seconds(1))
            if activeIncomingURLRequestID == nil,
               placeReceipt == nil && tripData == nil && listData == nil && referralData == nil && mySavesData == nil {
                loadErrorMessage = "Open a Savvy shared place, trip, or list link to preview it here."
                isLoading = false
            }
        }
        .onDisappear {
            incomingURLTask?.cancel()
            incomingURLTask = nil
            activeIncomingURLRequestID = nil
        }
    }

    // MARK: - My Savvy Content

    private func mySavesContentView(_ payload: SharedMySavesData) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("My Savvy")
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
                    Text("Open in Savvy")
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
            Text("Text Savvy a place link to start building your private map.")
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
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    Map(position: $cameraPosition) {
                        Annotation("", coordinate: place.coordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(ClipAtlasPalette.paper, ClipAtlasPalette.forest)
                                .shadow(color: ClipAtlasPalette.ink.opacity(0.16), radius: 3, y: 2)
                                .accessibilityLabel("Shared place, \(place.name)")
                        }
                    }
                    .frame(height: 210)
                    .overlay(alignment: .topTrailing) {
                        ClipSharedPostageStamp()
                            .padding(14)
                    }
                    .accessibilityIdentifier("clip.place.map")

                    ClipAirmailDivider()

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("PLACE POSTCARD")
                                    .font(ClipAtlasType.strong(10, relativeTo: .caption))
                                    .tracking(0.8)
                                    .foregroundStyle(ClipAtlasPalette.coral)

                                Text(place.name)
                                    .font(ClipAtlasType.strong(25, relativeTo: .title2))
                                    .foregroundStyle(ClipAtlasPalette.forest)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 4)
                            ClipPostmark(kind: "PLACE")
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(ClipAtlasPalette.forest)
                                .frame(width: 46, height: 46)
                                .background(ClipAtlasPalette.kraft.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("DELIVERED FOR REVIEW")
                                    .font(ClipAtlasType.strong(10, relativeTo: .caption))
                                    .tracking(0.55)
                                    .foregroundStyle(ClipAtlasPalette.muted)
                                Text(receipt.verifiedSenderLabel.map { "Shared by \($0)" } ?? "Ready for your review")
                                    .font(ClipAtlasType.strong(16, relativeTo: .headline))
                                    .foregroundStyle(ClipAtlasPalette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        HStack(spacing: 8) {
                            ClipAtlasChip(text: place.category, systemImage: "fork.knife")
                            if let ratingText = ratingLine(for: place) {
                                ClipAtlasChip(text: ratingText, systemImage: "star.fill")
                            }
                        }

                        VStack(spacing: 0) {
                            if let note = place.note, !note.isEmpty {
                                postcardLine(title: "A NOTE FOR YOU", value: note, icon: "quote.opening")
                            }
                            if let hours = place.hours, !hours.isEmpty {
                                postcardLine(title: "WHEN", value: hours, icon: "clock")
                            }
                            if !place.address.isEmpty {
                                postcardLine(title: "WHERE", value: place.address, icon: "mappin.and.ellipse")
                            }
                            postcardLine(title: "FOUND ON", value: place.sourceLabel, icon: "link")
                        }
                    }
                    .padding(18)
                }
                .background {
                    ClipScallopedRectangle(depth: 3, pitch: 11)
                        .fill(ClipAtlasPalette.paper)
                }
                .clipShape(ClipScallopedRectangle(depth: 3, pitch: 11))
                .overlay {
                    ClipScallopedRectangle(depth: 3, pitch: 11)
                        .stroke(
                            ClipAtlasPalette.coral.opacity(0.68),
                            style: StrokeStyle(lineWidth: 1.1, dash: [3, 3])
                        )
                }
                .shadow(color: ClipAtlasPalette.ink.opacity(0.07), radius: 8, y: 4)

                Text("A read-only preview. Review it in Savvy before adding it to your map.")
                    .font(ClipAtlasType.body(11, relativeTo: .caption))
                    .foregroundStyle(ClipAtlasPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .background(ClipAtlasPalette.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button(action: openInFullApp) {
                    Label("Save to my Savvy", systemImage: "plus.circle.fill")
                        .font(ClipAtlasType.strong(16, relativeTo: .headline))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background {
                            ClipScallopedRectangle(depth: 2.5, pitch: 10)
                                .fill(ClipAtlasPalette.coral)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clip.place.open")

                if let mapsURL = place.appleMapsURL {
                    Link(destination: mapsURL) {
                        Label("Open in Maps", systemImage: "map")
                            .font(ClipAtlasType.body(14, relativeTo: .subheadline))
                            .foregroundStyle(ClipAtlasPalette.forest)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("clip.place.maps")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(ClipAtlasPalette.paper)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(ClipAtlasPalette.line.opacity(0.42))
                    .frame(height: 1)
            }
        }
        .accessibilityIdentifier("clip.place.preview")
    }

    // MARK: - Trip Content

    private func tripContentView(_ trip: SharedTripData) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 0) {
                    Map(position: $cameraPosition) {
                        ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                            Annotation("", coordinate: stop.coordinate) {
                                Text("\(index + 1)")
                                    .font(ClipAtlasType.strong(13, relativeTo: .caption))
                                    .foregroundStyle(ClipAtlasPalette.paper)
                                    .padding(9)
                                    .background(ClipAtlasPalette.forest, in: Circle())
                                    .overlay { Circle().stroke(ClipAtlasPalette.paper, lineWidth: 2) }
                                    .accessibilityLabel("Shared trip stop \(index + 1), \(stop.name)")
                            }
                        }
                    }
                    .frame(height: 210)
                    .overlay(alignment: .topTrailing) {
                        ClipSharedPostageStamp()
                            .padding(14)
                    }
                    .accessibilityIdentifier("clip.trip.map")

                    ClipAirmailDivider()

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("TRIP POSTCARD")
                                    .font(ClipAtlasType.strong(10, relativeTo: .caption))
                                    .tracking(0.8)
                                    .foregroundStyle(ClipAtlasPalette.coral)

                                Text(trip.name)
                                    .font(ClipAtlasType.strong(25, relativeTo: .title2))
                                    .foregroundStyle(ClipAtlasPalette.forest)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 4)
                            ClipPostmark(kind: "TRIP")
                        }

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(ClipAtlasPalette.forest)
                                .frame(width: 46, height: 46)
                                .background(ClipAtlasPalette.kraft.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 3) {
                                Text("TO YOUR TRAVEL CREW")
                                    .font(ClipAtlasType.strong(10, relativeTo: .caption))
                                    .tracking(0.55)
                                    .foregroundStyle(ClipAtlasPalette.muted)
                                Text(trip.city.isEmpty ? "Destination pending" : trip.city)
                                    .font(ClipAtlasType.strong(17, relativeTo: .headline))
                                    .foregroundStyle(ClipAtlasPalette.ink)
                                Text(summaryLine(for: trip))
                                    .font(ClipAtlasType.body(12, relativeTo: .caption))
                                    .foregroundStyle(ClipAtlasPalette.muted)
                            }
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text("ROUTE")
                                .font(ClipAtlasType.strong(10, relativeTo: .caption))
                                .tracking(0.75)
                                .foregroundStyle(ClipAtlasPalette.muted)
                                .padding(.bottom, 4)

                            ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                                if index > 0 {
                                    Rectangle()
                                        .fill(ClipAtlasPalette.line.opacity(0.30))
                                        .frame(height: 1)
                                        .padding(.leading, 52)
                                }
                                tripStopRow(stop, index: index)
                            }
                        }
                    }
                    .padding(18)
                }
                .background {
                    ClipScallopedRectangle(depth: 3, pitch: 11)
                        .fill(ClipAtlasPalette.paper)
                }
                .clipShape(ClipScallopedRectangle(depth: 3, pitch: 11))
                .overlay {
                    ClipScallopedRectangle(depth: 3, pitch: 11)
                        .stroke(
                            ClipAtlasPalette.coral.opacity(0.68),
                            style: StrokeStyle(lineWidth: 1.1, dash: [3, 3])
                        )
                }
                .shadow(color: ClipAtlasPalette.ink.opacity(0.07), radius: 8, y: 4)

                Text("A read-only preview. Nothing is added until you open Savvy.")
                    .font(ClipAtlasType.body(11, relativeTo: .caption))
                    .foregroundStyle(ClipAtlasPalette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .background(ClipAtlasPalette.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button(action: openInFullApp) {
                    Label("Open in Savvy", systemImage: "arrow.up.right")
                        .font(ClipAtlasType.strong(16, relativeTo: .headline))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background {
                            ClipScallopedRectangle(depth: 2.5, pitch: 10)
                                .fill(ClipAtlasPalette.coral)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clip.trip.open")

                Button {
                    UIPasteboard.general.string = copySummary(for: trip)
                } label: {
                    Label("Copy route summary", systemImage: "doc.on.doc")
                        .font(ClipAtlasType.body(14, relativeTo: .subheadline))
                        .foregroundStyle(ClipAtlasPalette.forest)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clip.trip.copy")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(ClipAtlasPalette.paper)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(ClipAtlasPalette.line.opacity(0.42))
                    .frame(height: 1)
            }
        }
        .accessibilityIdentifier("clip.trip.preview")
    }

    private func tripStopRow(_ stop: SharedTripData.SharedStop, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(ClipAtlasType.strong(13, relativeTo: .caption))
                .foregroundStyle(ClipAtlasPalette.forest)
                .frame(width: 36, height: 36)
                .background {
                    ClipScallopedRectangle(depth: 2, pitch: 8)
                        .fill(ClipAtlasPalette.mint.opacity(0.82))
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(stop.name)
                    .font(ClipAtlasType.strong(16, relativeTo: .headline))
                    .foregroundStyle(ClipAtlasPalette.ink)
                if let time = stop.time, !time.isEmpty {
                    Text(time)
                        .font(ClipAtlasType.body(13, relativeTo: .caption))
                        .foregroundStyle(ClipAtlasPalette.forest)
                }
                if !stop.address.isEmpty {
                    Text(stop.address)
                        .font(ClipAtlasType.body(13, relativeTo: .caption))
                        .foregroundStyle(ClipAtlasPalette.muted)
                }
                if let note = stop.note, !note.isEmpty {
                    Text(note)
                        .font(ClipAtlasType.body(13, relativeTo: .caption))
                        .foregroundStyle(ClipAtlasPalette.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private func listContentView(_ list: SharedListData) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Map(position: $cameraPosition) {
                    ForEach(list.items) { item in
                        Marker(item.title, coordinate: item.coordinate)
                            .tint(item.source == "savedPlace" ? ClipAtlasPalette.forest : ClipAtlasPalette.coral)
                    }
                }
                .frame(height: 176)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Label("Shared list", systemImage: "rectangle.stack.fill")
                        .font(ClipAtlasType.strong(12))
                        .foregroundStyle(ClipAtlasPalette.forest)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(ClipAtlasPalette.paper.opacity(0.94), in: Capsule())
                        .overlay { Capsule().stroke(ClipAtlasPalette.line.opacity(0.38), lineWidth: 1) }
                        .padding(12)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("SHARED LIST PREVIEW")
                        .font(ClipAtlasType.strong(11))
                        .tracking(0.8)
                        .foregroundStyle(ClipAtlasPalette.coral)
                    Text(list.title)
                        .font(ClipAtlasType.display(27, relativeTo: .title))
                        .foregroundStyle(ClipAtlasPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        ClipAtlasChip(
                            text: list.items.count == 1 ? "1 place" : "\(list.items.count) places",
                            systemImage: "mappin.and.ellipse"
                        )
                        ClipAtlasChip(text: list.roleLabel, systemImage: "person.2")
                    }

                    if let note = list.note, !note.isEmpty {
                        Text(note)
                            .font(ClipAtlasType.body(14))
                            .foregroundStyle(ClipAtlasPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background {
                    ClipScallopedRectangle(depth: 3, pitch: 11)
                        .fill(ClipAtlasPalette.paper)
                }
                .overlay {
                    ClipScallopedRectangle(depth: 3, pitch: 11)
                        .stroke(ClipAtlasPalette.sky, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                }

                VStack(spacing: 12) {
                    ForEach(list.items) { item in
                        listItemRow(item)
                    }
                }

                VStack(spacing: 10) {
                    Button(action: openInFullApp) {
                        Label("Open list in Savvy", systemImage: "arrow.up.right.square")
                            .font(ClipAtlasType.strong(16))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(ClipAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)

                    Text("Save any place from this list into your own Savvy after opening the app.")
                        .font(ClipAtlasType.body(12))
                        .foregroundStyle(ClipAtlasPalette.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .accessibilityIdentifier("clip.list.preview")
    }

    private func listItemRow(_ item: SharedListItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: item.photoURLs.first.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: item.source == "savedPlace" ? "mappin.circle.fill" : "map")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(ClipAtlasPalette.forest)
            }
            .frame(width: 48, height: 48)
            .background(
                item.source == "savedPlace"
                    ? ClipAtlasPalette.mint.opacity(0.7)
                    : ClipAtlasPalette.sky.opacity(0.7),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(ClipAtlasType.strong(16))
                    .foregroundStyle(ClipAtlasPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(ClipAtlasType.body(12))
                        .foregroundStyle(ClipAtlasPalette.muted)
                }
                if let note = item.note {
                    Text(note)
                        .font(ClipAtlasType.body(12))
                        .foregroundStyle(ClipAtlasPalette.muted)
                }
            }
            Spacer(minLength: 4)
            Text(item.sourceLabel)
                .font(ClipAtlasType.strong(10))
                .foregroundStyle(item.source == "savedPlace" ? ClipAtlasPalette.forest : ClipAtlasPalette.coral)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(ClipAtlasPalette.paper, in: Capsule())
                .overlay { Capsule().stroke(ClipAtlasPalette.line.opacity(0.32), lineWidth: 1) }
        }
        .padding(12)
        .background(ClipAtlasPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(ClipAtlasPalette.line.opacity(0.34), lineWidth: 1) }
        .shadow(color: ClipAtlasPalette.ink.opacity(0.05), radius: 4, y: 2)
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
                    Text("@\(profile.handle) invited you to Savvy")
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
                    Text("Follow in Savvy")
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
        VStack(spacing: 18) {
            Spacer(minLength: 24)

            VStack(spacing: 16) {
                Text("OPENING SHARED MEMORY")
                    .font(ClipAtlasType.strong(11))
                    .tracking(0.9)
                    .foregroundStyle(ClipAtlasPalette.coral)

                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 29, weight: .bold))
                        .foregroundStyle(ClipAtlasPalette.forest)
                        .frame(width: 70, height: 70)
                        .background(ClipAtlasPalette.sky.opacity(0.72), in: Circle())
                        .overlay {
                            Circle().stroke(
                                ClipAtlasPalette.forest.opacity(0.36),
                                style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                            )
                        }
                    ProgressView()
                        .tint(ClipAtlasPalette.forest)
                        .padding(7)
                        .background(ClipAtlasPalette.paper, in: Circle())
                        .offset(x: 3, y: 3)
                }

                VStack(spacing: 6) {
                    Text("Getting the link ready")
                        .font(ClipAtlasType.display(25, relativeTo: .title2))
                        .foregroundStyle(ClipAtlasPalette.forest)
                    Text("Checking the shared place, trip, or list before showing it.")
                        .font(ClipAtlasType.body(14))
                        .foregroundStyle(ClipAtlasPalette.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 26)
            .background {
                ClipScallopedRectangle(depth: 3, pitch: 11)
                    .fill(ClipAtlasPalette.paper)
            }
            .overlay {
                ClipScallopedRectangle(depth: 3, pitch: 11)
                    .stroke(
                        ClipAtlasPalette.sky,
                        style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                    )
            }
            .shadow(color: ClipAtlasPalette.ink.opacity(0.06), radius: 6, y: 2)

            Text("Nothing is added to your Savvy until you choose to open the app.")
                .font(ClipAtlasType.body(12))
                .foregroundStyle(ClipAtlasPalette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clip.loading")
    }

    private var errorView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)

            VStack(spacing: 14) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(ClipAtlasPalette.coral)
                    .frame(width: 64, height: 64)
                    .background(ClipAtlasPalette.coral.opacity(0.14), in: Circle())

                Text("This link needs attention")
                    .font(ClipAtlasType.display(25, relativeTo: .title2))
                    .foregroundStyle(ClipAtlasPalette.forest)

                Text(loadErrorMessage ?? "The shared Savvy link may be invalid or expired.")
                    .font(ClipAtlasType.body(14))
                    .foregroundStyle(ClipAtlasPalette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let lastIncomingURL {
                    Button {
                        handleIncomingURL(lastIncomingURL)
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(ClipAtlasType.strong(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(ClipAtlasPalette.coral, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("clip.error.retry")
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .background(ClipAtlasPalette.paper)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ClipAtlasPalette.line.opacity(0.42), lineWidth: 1)
            }
            .shadow(color: ClipAtlasPalette.ink.opacity(0.06), radius: 6, y: 2)

            Spacer(minLength: 24)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clip.error")
    }

    // MARK: - URL Handling

    private func handleIncomingURL(_ url: URL?) {
        guard let url else { return }
        incomingURLTask?.cancel()
        incomingURLTask = nil
        lastIncomingURL = url
        loadErrorMessage = nil
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
                SharedTripData.SharedStop(id: $0.id, name: $0.name, address: $0.address, lat: $0.lat, lng: $0.lng, time: nil, note: $0.signal, day: nil, order: nil)
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
                updateCamera(for: payload.list.items.map { SharedTripData.SharedStop(id: $0.id.uuidString, name: $0.title, address: $0.subtitle, lat: $0.latitude, lng: $0.longitude, time: nil, note: $0.note, day: nil, order: nil) })
                isLoading = false
                return
            }
            guard SharedListPayload.shareCode(from: url) != nil else {
                loadErrorMessage = "This shared list link is not valid."
                isLoading = false
                return
            }
            isLoading = true
            incomingURLTask = Task { @MainActor in
                do {
                    let payload = try await SharedListPayload.resolve(from: url)
                    guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                    listData = payload.list
                    mySavesData = nil
                    mySavesSourceURL = nil
                    placeReceipt = nil
                    tripData = nil
                    referralData = nil
                    updateCamera(for: payload.list.items.map { SharedTripData.SharedStop(id: $0.id.uuidString, name: $0.title, address: $0.subtitle, lat: $0.latitude, lng: $0.longitude, time: nil, note: $0.note, day: nil, order: nil) })
                    isLoading = false
                    incomingURLTask = nil
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                    loadErrorMessage = (error as? LocalizedError)?.errorDescription
                        ?? "Savvy could not open this shared list."
                    isLoading = false
                    incomingURLTask = nil
                }
            }
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
                updateCamera(for: [SharedTripData.SharedStop(id: data.id, name: data.name, address: data.address, lat: data.lat, lng: data.lng, time: nil, note: data.note, day: nil, order: nil)])
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
                        updateCamera(for: [SharedTripData.SharedStop(id: data.id, name: data.name, address: data.address, lat: data.lat, lng: data.lng, time: nil, note: data.note, day: nil, order: nil)])
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
                        switch error {
                        case .missingOrExpired:
                            loadErrorMessage = "This shared place link is no longer available."
                        case .networkUnavailable:
                            loadErrorMessage = "Savvy could not reach this shared place. Check your connection and try again."
                        case .serverUnavailable:
                            loadErrorMessage = "This shared place is temporarily unavailable. Try again in a moment."
                        case .malformedOrUnconfigured, .invalidResponse:
                            loadErrorMessage = "Savvy could not read this shared place link."
                        }
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
            loadErrorMessage = "This link does not contain a Savvy place, trip, or list."
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
        } else {
            loadErrorMessage = "This shared trip link is invalid or incomplete."
        }
        // Invalid URL data → tripData stays nil → errorView shown
        isLoading = false
    }

    private var navigationTitle: String {
        if mySavesData != nil { return "My Savvy" }
        if referralData != nil { return "Referral Preview" }
        if listData != nil { return "List Preview" }
        if placeReceipt != nil { return "Savvy" }
        return "Trip Preview"
    }

    private func isPlaceLink(_ url: URL) -> Bool {
        if SAVEProductionConfig.supportsCustomURLScheme(url), url.host == "p" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app"].contains(url.host ?? "") else {
            return false
        }
        return url.path.split(separator: "/").first.map(String.init) == "p"
    }

    private func isTripLink(_ url: URL) -> Bool {
        if SAVEProductionConfig.supportsCustomURLScheme(url), url.host == "trip" {
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
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16)
                .foregroundStyle(ClipAtlasPalette.coral)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(ClipAtlasType.strong(10))
                    .tracking(0.45)
                    .textCase(.uppercase)
                    .foregroundStyle(ClipAtlasPalette.muted)
                Text(value)
                    .font(ClipAtlasType.body(13))
                    .foregroundStyle(ClipAtlasPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func postcardLine(title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ClipAtlasPalette.coral)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ClipAtlasType.strong(9, relativeTo: .caption2))
                    .tracking(0.65)
                    .foregroundStyle(ClipAtlasPalette.muted)
                Text(value)
                    .font(ClipAtlasType.body(13, relativeTo: .caption))
                    .foregroundStyle(ClipAtlasPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ClipAtlasPalette.line.opacity(0.30))
                .frame(height: 1)
                .padding(.leading, 28)
        }
        .accessibilityElement(children: .combine)
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
            url = placeReceipt.fullAppURL ?? URL(string: "savvy://p")
        } else {
            url = tripData?.toURL(baseURL: "savvy://trip") ?? URL(string: "savvy://trip")
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
        if let lastIncomingURL,
           let code = SharedListPayload.shareCode(from: lastIncomingURL) {
            return URL(string: "savvy://list?c=\(code)")
        }
        guard let listData,
              let payloadData = try? JSONEncoder().encode(SharedListPayload(list: listData, role: listData.viewerRole)),
              let base64 = payloadData.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return URL(string: "savvy://list")
        }
        return URL(string: "savvy://list?d=\(base64)&r=\(listData.viewerRole)")
    }
}

// MARK: - Demo Data

extension SharedTripData {
    static let demo = SharedTripData(
        name: "SF Food Tour",
        city: "San Francisco",
        stops: [
            SharedStop(id: UUID().uuidString, name: "Tartine Bakery", address: "600 Guerrero St, SF", lat: 37.7614, lng: -122.4241, time: "9:00 AM", note: "Must try the morning bun", day: 1, order: 0),
            SharedStop(id: UUID().uuidString, name: "Dolores Park", address: "Dolores St, SF", lat: 37.7596, lng: -122.4269, time: "10:30 AM", note: nil, day: 1, order: 1),
            SharedStop(id: UUID().uuidString, name: "Bi-Rite Creamery", address: "3692 18th St, SF", lat: 37.7618, lng: -122.4256, time: "12:00 PM", note: "Salted caramel ice cream", day: 1, order: 2),
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
        ClipAtlasPalette.canvas
    }
}

private enum ClipAtlasPalette {
    static let canvas = Color(hex: "FDF8F3")
    static let paper = Color(hex: "FFFDF7")
    static let forest = Color(hex: "0E4A33")
    static let ink = Color(hex: "2E2117")
    static let muted = Color(hex: "62594F")
    static let coral = Color(hex: "F26B4A")
    static let mint = Color(hex: "D6E8C4")
    static let sky = Color(hex: "B5E3F5")
    static let kraft = Color(hex: "F0CFA1")
    static let line = Color(hex: "A68F78")
}

private enum ClipAtlasType {
    static func display(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        rounded(size, weight: .semibold, relativeTo: style)
    }

    static func strong(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        rounded(size, weight: .bold, relativeTo: style)
    }

    static func body(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body
    ) -> Font {
        rounded(size, weight: .medium, relativeTo: style)
    }

    private static func rounded(
        _ size: CGFloat,
        weight: UIFont.Weight,
        relativeTo style: Font.TextStyle
    ) -> Font {
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = systemFont.fontDescriptor.withDesign(.rounded)
            ?? systemFont.fontDescriptor
        let roundedFont = UIFont(descriptor: descriptor, size: size)
        let scaledFont = UIFontMetrics(forTextStyle: style.uiTextStyle)
            .scaledFont(for: roundedFont)
        return Font(scaledFont)
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        if self == .largeTitle { return .largeTitle }
        if self == .title { return .title1 }
        if self == .title2 { return .title2 }
        if self == .title3 { return .title3 }
        if self == .headline { return .headline }
        if self == .subheadline { return .subheadline }
        if self == .callout { return .callout }
        if self == .footnote { return .footnote }
        if self == .caption { return .caption1 }
        if self == .caption2 { return .caption2 }
        return .body
    }
}

private struct ClipSharedPostageStamp: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 17, weight: .semibold))
            Text("SHARED")
                .font(ClipAtlasType.strong(9, relativeTo: .caption2))
                .tracking(0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(.white)
        .frame(width: 62, height: 72)
        .background {
            ClipScallopedRectangle(depth: 2.5, pitch: 8)
                .fill(ClipAtlasPalette.coral.opacity(0.96))
        }
        .overlay {
            ClipScallopedRectangle(depth: 2.5, pitch: 8)
                .stroke(ClipAtlasPalette.paper.opacity(0.86), lineWidth: 1)
                .padding(4)
        }
        .shadow(color: ClipAtlasPalette.ink.opacity(0.08), radius: 4, y: 2)
        .dynamicTypeSize(.large)
        .accessibilityHidden(true)
    }
}

private struct ClipPostmark: View {
    let kind: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(ClipAtlasPalette.line.opacity(0.72), lineWidth: 1)
                .frame(width: 52, height: 52)

            VStack(spacing: 0) {
                Text("SAVVY")
                Text(kind)
            }
            .font(ClipAtlasType.strong(8, relativeTo: .caption2))
            .tracking(0.6)
            .foregroundStyle(ClipAtlasPalette.line)
        }
        .overlay(alignment: .trailing) {
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(ClipAtlasPalette.line.opacity(0.58))
                        .frame(width: 26, height: 1)
                }
            }
            .offset(x: 22)
        }
        .frame(width: 72, height: 56)
        .dynamicTypeSize(.large)
        .accessibilityHidden(true)
    }
}

private struct ClipAirmailDivider: View {
    var body: some View {
        Rectangle()
            .fill(ClipAtlasPalette.coral)
            .frame(height: 5)
            .overlay {
                HStack(spacing: 7) {
                    ForEach(0..<18, id: \.self) { index in
                        Capsule()
                            .fill(index.isMultiple(of: 2) ? ClipAtlasPalette.paper : ClipAtlasPalette.sky)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

private struct ClipAtlasChip: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(ClipAtlasType.strong(11))
            .foregroundStyle(ClipAtlasPalette.forest)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(ClipAtlasPalette.sky.opacity(0.44), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(ClipAtlasPalette.line.opacity(0.32), lineWidth: 1)
            }
    }
}

private struct ClipScallopedRectangle: Shape {
    var depth: CGFloat = 4
    var pitch: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = pitch / 2
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY + depth))

        var x = rect.minX + radius
        while x < rect.maxX - radius {
            path.addQuadCurve(
                to: CGPoint(x: x + pitch, y: rect.minY + depth),
                control: CGPoint(x: x + radius, y: rect.minY - depth)
            )
            x += pitch
        }

        path.addLine(to: CGPoint(x: rect.maxX - depth, y: rect.minY + radius))
        var y = rect.minY + radius
        while y < rect.maxY - radius {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - depth, y: y + pitch),
                control: CGPoint(x: rect.maxX + depth, y: y + radius)
            )
            y += pitch
        }

        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY - depth))
        x = rect.maxX - radius
        while x > rect.minX + radius {
            path.addQuadCurve(
                to: CGPoint(x: x - pitch, y: rect.maxY - depth),
                control: CGPoint(x: x - radius, y: rect.maxY + depth)
            )
            x -= pitch
        }

        path.addLine(to: CGPoint(x: rect.minX + depth, y: rect.maxY - radius))
        y = rect.maxY - radius
        while y > rect.minY + radius {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + depth, y: y - pitch),
                control: CGPoint(x: rect.minX - depth, y: y - radius)
            )
            y -= pitch
        }

        path.closeSubpath()
        return path
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
