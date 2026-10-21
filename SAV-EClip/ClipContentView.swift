import SwiftUI
import MapKit
import StoreKit
import UIKit

enum ClipPreviewFailure: String {
    case expired
    case offline
    case server
    case malformed
    case empty

    var titleKey: String.LocalizationValue {
        switch self {
        case .expired: return "clip.error.expired.title"
        case .offline: return "clip.error.offline.title"
        case .server: return "clip.error.server.title"
        case .malformed: return "clip.error.malformed.title"
        case .empty: return "clip.empty.title"
        }
    }

    var bodyKey: String.LocalizationValue {
        switch self {
        case .expired: return "clip.error.expired.body"
        case .offline: return "clip.error.offline.body"
        case .server: return "clip.error.server.body"
        case .malformed: return "clip.error.malformed.body"
        case .empty: return "clip.empty.body"
        }
    }

    var sticker: ClipStickerKind {
        switch self {
        case .expired, .malformed: return .lantern
        case .server: return .coffee
        case .offline, .empty: return .place
    }
    }

    var badge: String {
        switch self {
        case .expired: return "✕"
        case .offline: return "!"
        case .server: return "…"
        case .malformed: return "?"
        case .empty: return ""
        }
    }

    var showsRetry: Bool {
        self == .offline || self == .server
    }
}

struct ClipContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var failure: ClipPreviewFailure?
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
    @State private var presentsAppClipOverlay = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if isLoading {
                    stateScreen(
                        title: ClipCopy.string("clip.loading.title"),
                        bodyText: ClipCopy.string("clip.loading.body"),
                        sticker: .place,
                        badge: "",
                        showProgress: true,
                        retry: nil
                    )
                    .accessibilityIdentifier("clip.loading")
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
                    let reason = failure ?? .empty
                    stateScreen(
                        title: ClipCopy.string(reason.titleKey),
                        bodyText: ClipCopy.string(reason.bodyKey),
                        sticker: reason.sticker,
                        badge: reason.badge,
                        showProgress: false,
                        retry: reason.showsRetry ? lastIncomingURL : nil
                    )
                    .accessibilityIdentifier("clip.error.\(reason.rawValue)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ClipDottedBackground().ignoresSafeArea())
        .background {
            ClipSKOverlayHost(isPresented: $presentsAppClipOverlay)
        }
        .overlay(alignment: .top) {
            if presentsAppClipOverlay {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("clip.skoverlay")
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            handleIncomingURL(activity.webpageURL)
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .task {
#if DEBUG
            if applyLaunchFixtureIfNeeded() {
                return
            }
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
                failure = .empty
                isLoading = false
            }
        }
        .onDisappear {
            incomingURLTask?.cancel()
            incomingURLTask = nil
            activeIncomingURLRequestID = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            ClipWordmark()
            Spacer(minLength: 8)
            ClipSharedChip()
        }
        .padding(.horizontal, ClipJournalLayout.screenMargin)
        .padding(.top, ClipJournalLayout.headerTop)
        .padding(.bottom, ClipJournalLayout.headerBottom)
    }

    // MARK: - Place

    private func placeContentView(_ receipt: SharedPlaceReceipt) -> some View {
        let place = receipt.payload
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Map(position: $cameraPosition) {
                    Annotation("", coordinate: place.coordinate, anchor: .bottom) {
                        ClipDoodlePin()
                            .accessibilityLabel(ClipCopy.format("a11y.pin", 1, place.name))
                    }
                }
                .mapStyle(.standard)
                .frame(maxWidth: ClipJournalLayout.placeMapWidth)
                .frame(height: ClipJournalLayout.placeMapHeight)
                .clipJournalMapFrame()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("clip.place.map")

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: ClipJournalLayout.stickerToText) {
                        ClipCategorySticker(kind: .forCategory(place.category))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name)
                                .font(ClipJournalType.system(20, weight: .semibold, relativeTo: .title3))
                                .foregroundStyle(ClipJournalPalette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if !place.category.isEmpty {
                                Text(place.category)
                                    .font(ClipJournalType.system(13, weight: .regular, relativeTo: .footnote))
                                    .foregroundStyle(ClipJournalPalette.muted)
                            }
                        }
                    }
                    if !place.address.isEmpty {
                        Text(place.address)
                            .font(ClipJournalType.system(15, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(ClipJournalPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let sender = receipt.verifiedSenderLabel {
                        Text(ClipCopy.format("clip.place.sender", sender))
                            .font(ClipJournalType.system(15, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(ClipJournalPalette.muted)
                    }
                    if let note = place.note, !note.isEmpty {
                        ClipWashiNote(text: note)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipJournalCard()
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: ClipJournalLayout.buttonGap) {
                ClipJournalPrimaryButton(
                    title: ClipCopy.string("clip.place.save")
                ) {
                    saveToMySavvy()
                }
                .accessibilityIdentifier("clip.place.open")

                if let mapsURL = place.appleMapsURL {
                    ClipMapsTextLink(title: ClipCopy.string("clip.place.openMaps")) {
                        UIApplication.shared.open(mapsURL)
                    }
                    .accessibilityIdentifier("clip.place.maps")
                }

                Text(ClipCopy.string("clip.footnote.howSave"))
                    .font(ClipJournalType.system(13, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(ClipJournalPalette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, ClipJournalLayout.buttonGroupBottom)
            .background(ClipJournalPalette.canvas)
        }
        .accessibilityIdentifier("clip.place.preview")
    }

    // MARK: - List

    private func listContentView(_ list: SharedListData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Map(position: $cameraPosition) {
                    ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                        Annotation("", coordinate: item.coordinate, anchor: .bottom) {
                            ClipDoodlePin(number: index + 1, outlined: true)
                                .accessibilityLabel(ClipCopy.format("a11y.pin", index + 1, item.title))
                        }
                    }
                }
                .mapStyle(.standard)
                .frame(height: ClipJournalLayout.listMapHeight)
                .clipJournalMapFrame()
                .accessibilityIdentifier("clip.list.map")

                VStack(alignment: .leading, spacing: 8) {
                    ClipDisplayTitle(text: list.title, pointSize: 28, relativeTo: .title)
                    Text(listCountLine(list))
                        .font(ClipJournalType.system(15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(ClipJournalPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle()
                                .fill(ClipJournalPalette.line)
                                .frame(height: ClipJournalPalette.strokeWidth)
                        }
                        listItemRow(item, index: index)
                    }
                }
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: ClipJournalLayout.buttonGap) {
                ClipJournalPrimaryButton(
                    title: ClipCopy.string("clip.list.open")
                ) {
                    saveToMySavvy()
                }
                .accessibilityIdentifier("clip.list.open")
                Text(ClipCopy.string("clip.footnote.howSave"))
                    .font(ClipJournalType.system(13, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(ClipJournalPalette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, ClipJournalLayout.buttonGroupBottom)
            .background(ClipJournalPalette.canvas)
        }
        .accessibilityIdentifier("clip.list.preview")
    }

    private func listCountLine(_ list: SharedListData) -> String {
        let sender = list.ownerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if sender.isEmpty {
            return ClipCopy.format("clip.list.count", list.items.count)
        }
        return ClipCopy.format("clip.list.countSender", list.items.count, sender)
    }

    private func listItemRow(_ item: SharedListItem, index: Int) -> some View {
        HStack(alignment: .center, spacing: 0) {
            ClipCircledNumber(number: index + 1)
            ClipCategorySticker(kind: .forCategory(item.category))
                .padding(.leading, ClipJournalLayout.numberToSticker)
            VStack(alignment: .leading, spacing: ClipJournalLayout.nameToMeta) {
                Text(item.title)
                    .font(ClipJournalType.system(17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(ClipJournalPalette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(ClipJournalType.system(13, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(ClipJournalPalette.muted)
                        .lineLimit(2)
                }
            }
            .padding(.leading, ClipJournalLayout.stickerToText)
            Spacer(minLength: 4)
        }
        .padding(.vertical, 10)
        .frame(minHeight: ClipJournalLayout.rowMinHeight, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("clip.list.item.\(index)")
    }

    // MARK: - Trip / referral / My Savvy (no restyle; no Google photos)

    private func tripContentView(_ trip: SharedTripData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Map(position: $cameraPosition) {
                    ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                        Annotation("", coordinate: stop.coordinate, anchor: .bottom) {
                            ClipDoodlePin(number: index + 1)
                        }
                    }
                }
                .mapStyle(.standard)
                .frame(height: ClipJournalLayout.listMapHeight)
                .clipJournalMapFrame()
                .accessibilityIdentifier("clip.trip.map")

                Text(trip.name)
                    .font(ClipJournalType.system(20, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(ClipJournalPalette.ink)
                ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                    Text("\(index + 1). \(stop.name)")
                        .font(ClipJournalType.system(17, weight: .regular, relativeTo: .body))
                        .foregroundStyle(ClipJournalPalette.ink)
                }
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ClipJournalPrimaryButton(
                title: ClipCopy.string("clip.trip.open"),
                action: saveToMySavvy
            )
            .accessibilityIdentifier("clip.trip.open")
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.bottom, ClipJournalLayout.buttonGroupBottom)
        }
        .accessibilityIdentifier("clip.trip.preview")
    }

    private func mySavesContentView(_ payload: SharedMySavesData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ClipDisplayTitle(text: "My Savvy", pointSize: 28, relativeTo: .title)
                ForEach(payload.places, id: \.id) { place in
                    Text(place.name)
                        .font(ClipJournalType.system(17, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(ClipJournalPalette.ink)
                }
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ClipJournalPrimaryButton(
                title: ClipCopy.string("clip.trip.open"),
                action: saveToMySavvy
            )
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.bottom, ClipJournalLayout.buttonGroupBottom)
        }
    }

    private func referralContentView(_ profile: SharedReferralProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(profile.displayName)
                    .font(ClipJournalType.system(20, weight: .semibold, relativeTo: .title3))
                    .foregroundStyle(ClipJournalPalette.ink)
                Text(ClipCopy.format("clip.referral.invite", profile.handle))
                    .font(ClipJournalType.system(15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(ClipJournalPalette.muted)
            }
            .padding(.horizontal, ClipJournalLayout.screenMargin)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ClipJournalPrimaryButton(
                title: ClipCopy.string("clip.trip.open"),
                action: saveToMySavvy
            )
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            .padding(.bottom, ClipJournalLayout.buttonGroupBottom)
        }
    }

    private func stateScreen(
        title: String,
        bodyText: String,
        sticker: ClipStickerKind,
        badge: String,
        showProgress: Bool,
        retry: URL?
    ) -> some View {
        VStack(spacing: ClipJournalLayout.stateTitleGap) {
            ClipStateIllustration(sticker: sticker, badge: badge)
            VStack(spacing: ClipJournalLayout.stateBodyGap) {
                ClipDisplayTitle(text: title, pointSize: 24, relativeTo: .title2)
                    .multilineTextAlignment(.center)
                Text(bodyText)
                    .font(ClipJournalType.system(15, weight: .regular, relativeTo: .body))
                    .foregroundStyle(ClipJournalPalette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: ClipJournalLayout.stateBodyMaxWidth)
            }
            .accessibilityElement(children: .combine)
            if showProgress {
                ClipLoadingDots(reduceMotion: reduceMotion)
            }
            if let retry {
                ClipJournalPrimaryButton(
                    title: ClipCopy.string("clip.retry")
                ) {
                    handleIncomingURL(retry)
                }
                .accessibilityIdentifier("clip.error.retry")
                .padding(.horizontal, ClipJournalLayout.screenMargin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, ClipJournalLayout.screenMargin)
    }

    // MARK: - URL Handling

    private func handleIncomingURL(_ url: URL?) {
        guard let url else { return }
        incomingURLTask?.cancel()
        incomingURLTask = nil
        lastIncomingURL = url
        failure = nil
        let requestID = UUID()
        activeIncomingURLRequestID = requestID

        if let referral = SharedReferralProfile.from(url: url) {
            apply(referral: referral)
            isLoading = false
            return
        }

        if SharedListPayload.isListLink(url) {
            if let payload = SharedListPayload.from(url: url) {
                apply(list: payload.list)
                isLoading = false
                return
            }
            guard SharedListPayload.shareCode(from: url) != nil else {
                presentFailure(.malformed)
                return
            }
            isLoading = true
            incomingURLTask = Task { @MainActor in
                do {
                    let payload = try await SharedListPayload.resolve(from: url)
                    guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                    apply(list: payload.list)
                    isLoading = false
                    incomingURLTask = nil
                } catch is CancellationError {
                    return
                } catch let error as SharedListPreviewError {
                    guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                    presentFailure(Self.failure(from: error))
                    incomingURLTask = nil
                } catch {
                    guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                    presentFailure(.server)
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
                if let resolved {
                    apply(mySaves: resolved, url: url)
                } else {
                    presentFailure(.server)
                    return
                }
                isLoading = false
                incomingURLTask = nil
            }
            return
        }

        if isPlaceLink(url) {
            guard url.absoluteString.utf8.count <= ShareRoutePayloadLimits.pendingPlaceURLMaxBytes else {
                presentFailure(.malformed)
                return
            }
            clearContent()
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
                        updateCamera(for: [SharedTripData.SharedStop(id: data.id, name: data.name, address: data.address, lat: data.lat, lng: data.lng, time: nil, note: data.note, day: nil, order: nil)])
                        isLoading = false
                        if let code = receipt.code {
                            await SharedPlaceReceipt.recordPublicEvent(
                                code: code,
                                eventType: "friend_share_receipt_opened"
                            )
                        }
                        incomingURLTask = nil
                    } catch is CancellationError {
                        return
                    } catch let error as SharedPlaceReceiptError {
                        guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                        presentFailure(Self.failure(from: error))
                        if let code = SharedPlaceData.shortCode(from: url) {
                            await SharedPlaceReceipt.recordPublicEvent(
                                code: code,
                                eventType: "friend_share_open_failed",
                                reasonCode: error.eventFailureReason
                            )
                        }
                        incomingURLTask = nil
                    } catch {
                        guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                        presentFailure(.server)
                        if let code = SharedPlaceData.shortCode(from: url) {
                            await SharedPlaceReceipt.recordPublicEvent(
                                code: code,
                                eventType: "friend_share_open_failed",
                                reasonCode: "unknown"
                            )
                        }
                        incomingURLTask = nil
                    }
                }
                return
            }
            presentFailure(.malformed)
            return
        }

        guard isTripLink(url) else {
            presentFailure(.malformed)
            return
        }

        if let data = SharedTripData.from(url: url) {
            apply(trip: data)
        } else {
            presentFailure(.malformed)
        }
        isLoading = false
    }

    private func presentFailure(_ reason: ClipPreviewFailure) {
        clearContent()
        failure = reason
        isLoading = false
    }

    private func clearContent() {
        placeReceipt = nil
        tripData = nil
        listData = nil
        referralData = nil
        mySavesData = nil
        mySavesSourceURL = nil
    }

    private func apply(list: SharedListData) {
        clearContent()
        listData = list
        updateCamera(for: list.items.map {
            SharedTripData.SharedStop(id: $0.id.uuidString, name: $0.title, address: $0.subtitle, lat: $0.latitude, lng: $0.longitude, time: nil, note: $0.note, day: nil, order: nil)
        })
    }

    private func apply(referral: SharedReferralProfile) {
        clearContent()
        referralData = referral
        updateCamera(for: referral.featuredPlaces.map {
            SharedTripData.SharedStop(id: $0.id, name: $0.name, address: $0.address, lat: $0.lat, lng: $0.lng, time: nil, note: $0.signal, day: nil, order: nil)
        })
    }

    private func apply(trip: SharedTripData) {
        clearContent()
        tripData = trip
        updateCamera(for: trip.stops)
    }

    private func apply(mySaves: SharedMySavesData, url: URL) {
        clearContent()
        mySavesData = mySaves
        mySavesSourceURL = url
    }

    private static func failure(from error: SharedPlaceReceiptError) -> ClipPreviewFailure {
        switch error {
        case .missingOrExpired: return .expired
        case .networkUnavailable: return .offline
        case .serverUnavailable: return .server
        case .malformedOrUnconfigured, .invalidResponse: return .malformed
        }
    }

    private static func failure(from error: SharedListPreviewError) -> ClipPreviewFailure {
        switch error {
        case .notFound, .expired: return .expired
        case .network: return .offline
        case .invalidLink: return .malformed
        case .invalidResponse: return .server
        }
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

    private func saveToMySavvy() {
        persistPendingShare()
        let url: URL?
        if mySavesData != nil {
            url = mySavesSourceURL
        } else if listData != nil {
            url = currentListAppURL()
        } else if let referralData {
            url = referralData.fullAppURL()
        } else if let placeReceipt {
            url = placeReceipt.fullAppURL ?? lastIncomingURL ?? URL(string: "https://sav-e-app.vercel.app/p")
        } else {
            url = tripData?.toURL(baseURL: "savvy://trip") ?? URL(string: "savvy://trip")
        }
        guard let url else {
            presentsAppClipOverlay = true
            return
        }
        UIApplication.shared.open(url) { opened in
            if !opened {
                DispatchQueue.main.async {
                    presentsAppClipOverlay = true
                }
            }
        }
    }

    private func persistPendingShare() {
        if let list = listData {
            let code = lastIncomingURL.flatMap { SharedListPayload.shareCode(from: $0) }
            let url = currentListAppURL()?.absoluteString
                ?? lastIncomingURL?.absoluteString
                ?? ""
            guard !url.isEmpty else { return }
            PendingShareStore.write(
                PendingSharePayload(
                    kind: .list,
                    shareCode: code,
                    placeId: nil,
                    listId: list.id.uuidString,
                    sender: list.ownerDisplayName,
                    url: url
                )
            )
            return
        }
        if let receipt = placeReceipt {
            let url = (receipt.fullAppURL ?? lastIncomingURL)?.absoluteString ?? ""
            guard !url.isEmpty else { return }
            PendingShareStore.write(
                PendingSharePayload(
                    kind: .place,
                    shareCode: receipt.code ?? lastIncomingURL.flatMap { SharedPlaceData.shortCode(from: $0) },
                    placeId: receipt.payload.id,
                    listId: nil,
                    sender: receipt.verifiedSenderLabel,
                    url: url
                )
            )
        }
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

/// System App Clip overlay. Unstyled — SKOverlay owns the chrome.
private struct ClipSKOverlayHost: UIViewControllerRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard isPresented, !context.coordinator.didPresent else { return }
        guard let scene = controller.view.window?.windowScene ?? activeScene() else { return }
        context.coordinator.didPresent = true
        let overlay = SKOverlay(configuration: SKOverlay.AppClipConfiguration(position: .bottom))
        overlay.present(in: scene)
    }

    private func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    final class Coordinator {
        var didPresent = false
    }
}

#if DEBUG
extension ClipContentView {
    @discardableResult
    fileprivate func applyLaunchFixtureIfNeeded() -> Bool {
        guard let screen = ClipPreviewFixtures.requestedScreen() else { return false }
        isLoading = false
        failure = nil
        clearContent()
        switch screen {
        case "place-sender":
            let place = ClipPreviewFixtures.samplePlace()
            placeReceipt = SharedPlaceReceipt(
                code: "AbC123_x",
                payload: place,
                sourcePlaceID: nil,
                expiresAt: nil,
                sender: SharedPlaceSender(displayName: "Mina", handle: "mina")
            )
            updateCamera(for: [SharedTripData.SharedStop(id: place.id, name: place.name, address: place.address, lat: place.lat, lng: place.lng, time: nil, note: place.note, day: nil, order: nil)])
        case "place-inline":
            let place = ClipPreviewFixtures.samplePlace()
            placeReceipt = .embedded(place)
            updateCamera(for: [SharedTripData.SharedStop(id: place.id, name: place.name, address: place.address, lat: place.lat, lng: place.lng, time: nil, note: place.note, day: nil, order: nil)])
        case "skoverlay":
            let place = ClipPreviewFixtures.samplePlace()
            placeReceipt = .embedded(place)
            presentsAppClipOverlay = true
            updateCamera(for: [SharedTripData.SharedStop(id: place.id, name: place.name, address: place.address, lat: place.lat, lng: place.lng, time: nil, note: place.note, day: nil, order: nil)])
        case "list":
            apply(list: ClipPreviewFixtures.sampleList())
        case "loading":
            isLoading = true
        case "expired":
            failure = .expired
        case "offline":
            lastIncomingURL = URL(string: "https://sav-e-app.vercel.app/p/AbC123_x")
            failure = .offline
        case "server":
            lastIncomingURL = URL(string: "https://sav-e-app.vercel.app/p/AbC123_x")
            failure = .server
        case "malformed":
            failure = .malformed
        default:
            failure = .empty
        }
        return true
    }
}
#endif
