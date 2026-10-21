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
            .background(ClipDottedBackground().ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image("SavvyLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .accessibilityHidden(true)
                        ClipDisplayTitle(text: "Savvy", pointSize: 28, relativeTo: .headline)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Savvy")
                }
            }
            .toolbarBackground(ClipJournalPalette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
                loadErrorMessage = ClipCopy.text(
                    "Open a Savvy shared place or list link to preview it here.",
                    "打開 Savvy 分享的地點或清單連結即可預覽。"
                )
                isLoading = false
            }
        }
        .onDisappear {
            incomingURLTask?.cancel()
            incomingURLTask = nil
            activeIncomingURLRequestID = nil
        }
    }

    // MARK: - Place Content

    private func placeContentView(_ receipt: SharedPlaceReceipt) -> some View {
        let place = receipt.payload
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    ClipGooglePhotoCard(photo: place.journalGooglePhoto)

                    Map(position: $cameraPosition) {
                        Annotation("", coordinate: place.coordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, ClipJournalPalette.coral)
                                .accessibilityLabel(ClipCopy.text("Shared place, \(place.name)", "分享的地點，\(place.name)"))
                        }
                    }
                    .frame(height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: ClipJournalPalette.cardRadius, style: .continuous))
                    .accessibilityIdentifier("clip.place.map")

                    ClipDisplayTitle(text: place.name, pointSize: 30, relativeTo: .title2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        receipt.verifiedSenderLabel.map {
                            ClipCopy.text("Shared by \($0)", "由 \($0) 分享")
                        } ?? ClipCopy.text("Ready for your review", "先確認，再加入你的地圖")
                    )
                    .font(ClipJournalType.body(15))
                    .foregroundStyle(ClipJournalPalette.ink)

                    HStack(spacing: 8) {
                        ClipJournalChip(text: place.category, systemImage: "fork.knife")
                        if let ratingText = ratingLine(for: place) {
                            ClipJournalChip(text: ratingText, systemImage: "star.fill")
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if let note = place.note, !note.isEmpty {
                            journalLine(
                                title: ClipCopy.text("A note for you", "給你的備註"),
                                value: note
                            )
                        }
                        if let hours = place.hours, !hours.isEmpty {
                            journalLine(title: ClipCopy.text("Hours", "時間"), value: hours)
                        }
                        if !place.address.isEmpty {
                            journalLine(title: ClipCopy.text("Address", "地址"), value: place.address)
                        }
                        journalLine(
                            title: ClipCopy.text("Found on", "來源"),
                            value: place.sourceLabel
                        )
                    }
                }
                .padding(ClipJournalLayout.cardPadding)
                .clipJournalPaper()

                Text(ClipCopy.text(
                    "A read-only preview. Review it in Savvy before adding it to your map.",
                    "這是唯讀預覽。加入地圖前，請先在 Savvy 確認。"
                ))
                .font(ClipJournalType.body(12, relativeTo: .caption))
                .foregroundStyle(ClipJournalPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                ClipJournalPrimaryButton(
                    title: ClipCopy.text("Save to my Savvy", "存到我的 Savvy"),
                    systemImage: "plus"
                ) {
                    openInFullApp()
                }
                .accessibilityIdentifier("clip.place.open")

                if let mapsURL = place.appleMapsURL {
                    Link(destination: mapsURL) {
                        Text(ClipCopy.text("Open in Maps", "在地圖開啟"))
                            .font(ClipJournalType.body(15, relativeTo: .subheadline))
                            .foregroundStyle(ClipJournalPalette.forest)
                            .frame(maxWidth: .infinity, minHeight: ClipJournalLayout.minTap)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("clip.place.maps")
                }
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(ClipJournalPalette.paper)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(ClipJournalPalette.stroke)
                    .frame(height: ClipJournalPalette.strokeWidth)
            }
        }
        .accessibilityIdentifier("clip.place.preview")
    }

    // MARK: - List Content

    private func listContentView(_ list: SharedListData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Map(position: $cameraPosition) {
                    ForEach(list.items) { item in
                        Marker(item.title, coordinate: item.coordinate)
                            .tint(item.source == "savedPlace" ? ClipJournalPalette.forest : ClipJournalPalette.coral)
                    }
                }
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: ClipJournalPalette.cardRadius, style: .continuous))
                .accessibilityIdentifier("clip.list.map")

                VStack(alignment: .leading, spacing: 10) {
                    Text(ClipCopy.text("Shared list", "分享的清單"))
                        .font(ClipJournalType.strong(12, relativeTo: .caption))
                        .foregroundStyle(ClipJournalPalette.coral)
                    ClipDisplayTitle(text: list.title, pointSize: 28, relativeTo: .title)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        ClipJournalChip(
                            text: list.items.count == 1
                                ? ClipCopy.text("1 place", "1 個地點")
                                : ClipCopy.text("\(list.items.count) places", "\(list.items.count) 個地點"),
                            systemImage: "mappin.and.ellipse"
                        )
                        ClipJournalChip(text: list.roleLabel, systemImage: "person.2")
                    }

                    if let note = list.note, !note.isEmpty {
                        Text(note)
                            .font(ClipJournalType.body(14))
                            .foregroundStyle(ClipJournalPalette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ClipJournalLayout.cardPadding)
                .clipJournalPaper()

                VStack(spacing: 12) {
                    ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                        listItemRow(item, index: index)
                    }
                }

                ClipJournalPrimaryButton(
                    title: ClipCopy.text("Open list in Savvy", "在 Savvy 開啟清單"),
                    systemImage: "arrow.up.right"
                ) {
                    openInFullApp()
                }
                .accessibilityIdentifier("clip.list.open")

                Text(ClipCopy.text(
                    "Save any place from this list into your own Savvy after opening the app.",
                    "打開 App 後，就能把清單裡的地點存進你的 Savvy。"
                ))
                .font(ClipJournalType.body(12, relativeTo: .caption))
                .foregroundStyle(ClipJournalPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.top, 12)
        }
        .accessibilityIdentifier("clip.list.preview")
    }

    private func listItemRow(_ item: SharedListItem, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(ClipJournalType.strong(13, relativeTo: .caption))
                .foregroundStyle(ClipJournalPalette.ink)
                .frame(width: 32, height: 32)
                .background(ClipJournalPalette.washGreen, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(ClipJournalType.strong(16))
                    .foregroundStyle(ClipJournalPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(ClipJournalType.body(12, relativeTo: .caption))
                        .foregroundStyle(ClipJournalPalette.muted)
                }
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(ClipJournalType.body(12, relativeTo: .caption))
                        .foregroundStyle(ClipJournalPalette.muted)
                }
            }
            Spacer(minLength: 4)
            Text(item.sourceLabel)
                .font(ClipJournalType.strong(10, relativeTo: .caption2))
                .foregroundStyle(item.source == "savedPlace" ? ClipJournalPalette.forest : ClipJournalPalette.coral)
        }
        .padding(12)
        .clipJournalPaper()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clip.list.item.\(index)")
    }

    // MARK: - Trip Content

    private func tripContentView(_ trip: SharedTripData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Map(position: $cameraPosition) {
                    ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                        Annotation("", coordinate: stop.coordinate) {
                            Text("\(index + 1)")
                                .font(ClipJournalType.strong(13, relativeTo: .caption))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(ClipJournalPalette.coral, in: Circle())
                                .accessibilityLabel(ClipCopy.text(
                                    "Shared trip stop \(index + 1), \(stop.name)",
                                    "行程第 \(index + 1) 站，\(stop.name)"
                                ))
                        }
                    }
                }
                .frame(height: 148)
                .clipShape(RoundedRectangle(cornerRadius: ClipJournalPalette.cardRadius, style: .continuous))
                .accessibilityIdentifier("clip.trip.map")

                VStack(alignment: .leading, spacing: 10) {
                    Text(ClipCopy.text("Shared trip", "分享的行程"))
                        .font(ClipJournalType.strong(12, relativeTo: .caption))
                        .foregroundStyle(ClipJournalPalette.coral)
                    ClipDisplayTitle(text: trip.name, pointSize: 28, relativeTo: .title2)
                    Text(trip.city.isEmpty ? summaryLine(for: trip) : "\(trip.city) · \(summaryLine(for: trip))")
                        .font(ClipJournalType.body(14))
                        .foregroundStyle(ClipJournalPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ClipJournalLayout.cardPadding)
                .clipJournalPaper()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                        if index > 0 {
                            Rectangle()
                                .fill(ClipJournalPalette.stroke)
                                .frame(height: ClipJournalPalette.strokeWidth)
                                .padding(.leading, 44)
                        }
                        tripStopRow(stop, index: index)
                    }
                }
                .padding(ClipJournalLayout.cardPadding)
                .clipJournalPaper()
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                ClipJournalPrimaryButton(
                    title: ClipCopy.text("Open in Savvy", "在 Savvy 開啟"),
                    systemImage: "arrow.up.right"
                ) {
                    openInFullApp()
                }
                .accessibilityIdentifier("clip.trip.open")

                Button {
                    UIPasteboard.general.string = copySummary(for: trip)
                } label: {
                    Text(ClipCopy.text("Copy route summary", "複製路線摘要"))
                        .font(ClipJournalType.body(15, relativeTo: .subheadline))
                        .foregroundStyle(ClipJournalPalette.forest)
                        .frame(maxWidth: .infinity, minHeight: ClipJournalLayout.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("clip.trip.copy")
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(ClipJournalPalette.paper)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(ClipJournalPalette.stroke)
                    .frame(height: ClipJournalPalette.strokeWidth)
            }
        }
        .accessibilityIdentifier("clip.trip.preview")
    }

    private func tripStopRow(_ stop: SharedTripData.SharedStop, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index + 1)")
                .font(ClipJournalType.strong(13, relativeTo: .caption))
                .foregroundStyle(ClipJournalPalette.ink)
                .frame(width: 32, height: 32)
                .background(ClipJournalPalette.washGreen, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(ClipJournalType.strong(16))
                    .foregroundStyle(ClipJournalPalette.ink)
                if let time = stop.time, !time.isEmpty {
                    Text(time)
                        .font(ClipJournalType.body(13, relativeTo: .caption))
                        .foregroundStyle(ClipJournalPalette.forest)
                }
                if !stop.address.isEmpty {
                    Text(stop.address)
                        .font(ClipJournalType.body(13, relativeTo: .caption))
                        .foregroundStyle(ClipJournalPalette.muted)
                }
                if let note = stop.note, !note.isEmpty {
                    Text(note)
                        .font(ClipJournalType.body(13, relativeTo: .caption))
                        .foregroundStyle(ClipJournalPalette.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - My Savvy / Referral

    private func mySavesContentView(_ payload: SharedMySavesData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    ClipDisplayTitle(
                        text: ClipCopy.text("My Savvy", "我的 Savvy"),
                        pointSize: 30,
                        relativeTo: .title
                    )
                    HStack(spacing: 8) {
                        statPill(value: payload.counts.places, label: ClipCopy.text("places", "地點"))
                        statPill(value: payload.counts.visits, label: ClipCopy.text("visits", "造訪"))
                        statPill(value: payload.counts.reviews, label: ClipCopy.text("reviews", "評論"))
                    }
                }
                .padding(ClipJournalLayout.cardPadding)
                .clipJournalPaper()

                if payload.places.isEmpty {
                    Text(ClipCopy.text("No saved places yet", "還沒有收藏的地點"))
                        .font(ClipJournalType.body(15))
                        .foregroundStyle(ClipJournalPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ClipJournalLayout.cardPadding)
                        .clipJournalPaper()
                } else {
                    ForEach(Array(payload.places.enumerated()), id: \.element.id) { index, place in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name)
                                .font(ClipJournalType.strong(16))
                                .foregroundStyle(ClipJournalPalette.ink)
                            if let area = place.area, !area.isEmpty {
                                Text(area)
                                    .font(ClipJournalType.body(12, relativeTo: .caption))
                                    .foregroundStyle(ClipJournalPalette.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .clipJournalPaper()
                        .accessibilityLabel(ClipCopy.text("Saved place \(index + 1), \(place.name)", "收藏地點 \(index + 1)，\(place.name)"))
                    }
                }

                ClipJournalPrimaryButton(
                    title: ClipCopy.text("Open in Savvy", "在 Savvy 開啟"),
                    systemImage: "arrow.up.right",
                    action: openInFullApp
                )
                .padding(.bottom, 32)
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.top, 16)
        }
    }

    private func statPill(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(ClipJournalType.strong(17))
                .foregroundStyle(ClipJournalPalette.ink)
            Text(label)
                .font(ClipJournalType.regular(11, relativeTo: .caption2))
                .foregroundStyle(ClipJournalPalette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: ClipJournalLayout.minTap)
        .background(ClipJournalPalette.kraft.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func referralContentView(_ profile: SharedReferralProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ClipDisplayTitle(text: profile.displayName, pointSize: 28, relativeTo: .title2)
                    Text(ClipCopy.text(
                        "@\(profile.handle) invited you to Savvy",
                        "@\(profile.handle) 邀請你加入 Savvy"
                    ))
                    .font(ClipJournalType.body(15))
                    .foregroundStyle(ClipJournalPalette.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(ClipJournalLayout.cardPadding)
                .clipJournalPaper()

                ClipJournalPrimaryButton(
                    title: ClipCopy.text("Open in Savvy", "在 Savvy 開啟"),
                    systemImage: "arrow.up.right",
                    action: openInFullApp
                )
                .padding(.bottom, 32)
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.top, 16)
        }
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(ClipJournalPalette.coral)
            Text(ClipCopy.text("Getting the link ready", "正在準備連結"))
                .font(ClipJournalType.strong(18, relativeTo: .title3))
                .foregroundStyle(ClipJournalPalette.ink)
            Text(ClipCopy.text(
                "Checking the shared place or list before showing it.",
                "正在確認分享的地點或清單。"
            ))
            .font(ClipJournalType.body(14))
            .foregroundStyle(ClipJournalPalette.muted)
            .multilineTextAlignment(.center)
        }
        .padding(24)
        .clipJournalPaper()
        .padding(.horizontal, ClipJournalLayout.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("clip.loading")
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Text(ClipCopy.text("This link needs attention", "這個連結需要再確認"))
                .font(ClipJournalType.strong(20, relativeTo: .title3))
                .foregroundStyle(ClipJournalPalette.forest)
                .multilineTextAlignment(.center)
            Text(
                loadErrorMessage
                    ?? ClipCopy.text(
                        "The shared Savvy link may be invalid or expired.",
                        "這個 Savvy 分享連結可能無效或已過期。"
                    )
            )
            .font(ClipJournalType.body(14))
            .foregroundStyle(ClipJournalPalette.muted)
            .multilineTextAlignment(.center)

            if let lastIncomingURL {
                ClipJournalPrimaryButton(
                    title: ClipCopy.text("Try again", "再試一次"),
                    systemImage: "arrow.clockwise"
                ) {
                    handleIncomingURL(lastIncomingURL)
                }
                .accessibilityIdentifier("clip.error.retry")
            }
        }
        .padding(24)
        .clipJournalPaper()
        .padding(.horizontal, ClipJournalLayout.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                loadErrorMessage = ClipCopy.text(
                    "This shared list link is not valid.",
                    "這個分享清單連結無效。"
                )
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
                        ?? ClipCopy.text(
                            "Savvy could not open this shared list.",
                            "Savvy 無法打開這個分享清單。"
                        )
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
                            loadErrorMessage = ClipCopy.text(
                                "This shared place link is no longer available.",
                                "這個分享地點連結已無法使用。"
                            )
                        case .networkUnavailable:
                            loadErrorMessage = ClipCopy.text(
                                "Savvy could not reach this shared place. Check your connection and try again.",
                                "Savvy 無法連上這個分享地點。請檢查網路後再試。"
                            )
                        case .serverUnavailable:
                            loadErrorMessage = ClipCopy.text(
                                "This shared place is temporarily unavailable. Try again in a moment.",
                                "這個分享地點暫時無法使用。請稍後再試。"
                            )
                        case .malformedOrUnconfigured, .invalidResponse:
                            loadErrorMessage = ClipCopy.text(
                                "Savvy could not read this shared place link.",
                                "Savvy 無法讀取這個分享地點連結。"
                            )
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
            loadErrorMessage = ClipCopy.text(
                "This link does not contain a Savvy place, trip, or list.",
                "這個連結不是 Savvy 地點、行程或清單。"
            )
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
            loadErrorMessage = ClipCopy.text(
                "This shared trip link is invalid or incomplete.",
                "這個分享行程連結無效或不完整。"
            )
        }
        isLoading = false
    }

    private var navigationTitle: String {
        if mySavesData != nil { return ClipCopy.text("My Savvy", "我的 Savvy") }
        if referralData != nil { return ClipCopy.text("Invite", "邀請") }
        if listData != nil { return ClipCopy.text("List", "清單") }
        if placeReceipt != nil { return "Savvy" }
        if tripData != nil { return ClipCopy.text("Trip", "行程") }
        return "Savvy"
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
        let countLabel = trip.stops.count == 1
            ? ClipCopy.text("1 place", "1 個地點")
            : ClipCopy.text("\(trip.stops.count) stops", "\(trip.stops.count) 站")
        guard !trip.city.isEmpty else { return countLabel }
        return "\(countLabel) · \(trip.city)"
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
            return String(format: "%.1f · %d", rating, reviewCount)
        }
        return String(format: "%.1f", rating)
    }

    private func journalLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(ClipJournalType.strong(11, relativeTo: .caption))
                .foregroundStyle(ClipJournalPalette.muted)
            Text(value)
                .font(ClipJournalType.body(14))
                .foregroundStyle(ClipJournalPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
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
