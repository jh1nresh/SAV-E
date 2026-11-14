#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import Combine
import Foundation
import MapKit

enum LivePlaceInformationError: Error, Equatable {
    case unavailable, notFound, ambiguous

    @MainActor func message(language: AppLanguage) -> String {
        switch self {
        case .unavailable:
            return language.localized(english: "Apple place information is unavailable. Try again.", traditionalChinese: "暫時無法取得 Apple 地點資訊，請再試一次。")
        case .notFound:
            return language.localized(english: "No exact Apple place match was found.", traditionalChinese: "找不到確切符合的 Apple 地點。")
        case .ambiguous:
            return language.localized(english: "More than one place matches. Select the place on the map.", traditionalChinese: "有多個符合的地點，請在地圖上選擇確切地點。")
        }
    }
}

@MainActor
protocol LivePlaceInformationReading {
    func appleItem(identifier: String) async throws -> MKMapItem?
    func search(name: String, address: String, coordinate: CLLocationCoordinate2D) async throws -> [MKMapItem]
    func cancel()
}

/// Ephemeral Apple metadata only. No Place, saved memory or photo URL is created.
@MainActor
final class LivePlaceInformationModel: ObservableObject {
    @Published private(set) var item: MKMapItem?
    @Published private(set) var isLoading = false
    @Published private(set) var error: LivePlaceInformationError?
    private let reader: any LivePlaceInformationReading
    private let sessionIsCurrent: (String, Int) -> Bool
    private var revision = UUID()

    convenience init() {
        self.init(reader: ApplePlaceInformationReader()) { owner, generation in
            let auth = PrivyAuthService.shared
            guard case .authenticated(let currentOwner) = auth.authState else { return false }
            return currentOwner == owner && auth.currentUserId == owner && auth.sessionGeneration == generation
        }
    }

    init(reader: any LivePlaceInformationReading, sessionIsCurrent: @escaping (String, Int) -> Bool) {
        self.reader = reader
        self.sessionIsCurrent = sessionIsCurrent
    }

    func load(pin: LiveMapPlace, ownerSubject: String, sessionGeneration: Int) async {
        cancel()
        let ticket = revision
        isLoading = true
        func check() throws {
            try Task.checkCancellation()
            guard revision == ticket, sessionIsCurrent(ownerSubject, sessionGeneration) else { throw CancellationError() }
        }
        do {
            try check()
            guard pin.place.isMapKitMappable else { throw LivePlaceInformationError.notFound }
            if let provided = pin.nativeMapItem, Self.matches(provided, pin: pin) {
                try check()
                item = provided
                isLoading = false
                return
            }
            let candidates = try await withTaskCancellationHandler {
                try check()
                if #available(iOS 18.0, *), pin.place.locationProvider == .appleMaps,
                   let identifier = pin.place.providerPlaceId?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !identifier.isEmpty {
                    return try await reader.appleItem(identifier: identifier).map { [$0] } ?? []
                }
                return try await reader.search(name: pin.place.name, address: pin.place.address, coordinate: pin.coordinate)
            } onCancel: {
                Task { @MainActor [weak self] in
                    guard let self, self.revision == ticket else { return }
                    self.cancel()
                }
            }
            try check()
            let exact = candidates.filter { Self.matches($0, pin: pin) }
            guard exact.count == 1 else {
                throw exact.isEmpty ? LivePlaceInformationError.notFound : .ambiguous
            }
            item = exact[0]
            isLoading = false
        } catch {
            guard revision == ticket else { return }
            item = nil
            isLoading = false
            self.error = !Task.isCancelled && sessionIsCurrent(ownerSubject, sessionGeneration)
                && !(error is CancellationError) ? (error as? LivePlaceInformationError ?? .unavailable) : nil
        }
    }

    /// The presenting surface calls this on disappearance/account invalidation.
    func cancel() {
        revision = UUID()
        reader.cancel()
        item = nil
        isLoading = false
        error = nil
    }

    private static func matches(_ item: MKMapItem, pin: LiveMapPlace) -> Bool {
        let coordinate = item.placemark.coordinate
        guard !item.isCurrentLocation, CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              normalized(item.name ?? item.placemark.name ?? "") == normalized(pin.place.name),
              !normalized(pin.place.name).isEmpty else { return false }
        let venue = CLLocation(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude)
        return venue.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) <= 120
    }

    private static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

@MainActor
private final class ApplePlaceInformationReader: LivePlaceInformationReading {
    private var itemRequest: MKMapItemRequest?
    private var localSearch: MKLocalSearch?

    func appleItem(identifier: String) async throws -> MKMapItem? {
        guard #available(iOS 18.0, *), let identifier = MKMapItem.Identifier(rawValue: identifier) else {
            throw LivePlaceInformationError.unavailable
        }
        let request = MKMapItemRequest(mapItemIdentifier: identifier)
        itemRequest = request
        defer { if itemRequest === request { itemRequest = nil } }
        return try await request.mapItem
    }

    func search(name: String, address: String, coordinate: CLLocationCoordinate2D) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [name, address].filter { !$0.isEmpty }.joined(separator: " ")
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)
        request.resultTypes = .pointOfInterest
        let search = MKLocalSearch(request: request)
        localSearch = search
        defer { if localSearch === search { localSearch = nil } }
        return try await search.start().mapItems
    }

    func cancel() {
        itemRequest?.cancel()
        localSearch?.cancel()
        itemRequest = nil
        localSearch = nil
    }
}
#endif
