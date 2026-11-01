import CoreLocation
import SwiftUI

enum SaveInkLaunchMode: Equatable {
    case interactive
    case preview(SaveInkPreviewScreen)
}

enum SaveInkLaunch {
    static var mode: SaveInkLaunchMode? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--savvy-ink-notebook") else { return nil }
        guard let raw = arguments.first(where: { $0.hasPrefix("--savvy-ink-screen=") }) else {
            return .interactive
        }
        let name = String(raw.dropFirst("--savvy-ink-screen=".count))
        guard let screen = SaveInkPreviewScreen(rawValue: name) else { return .interactive }
        return .preview(screen)
    }
}

struct SaveInkNotebookRoot: View {
    var launch: SaveInkLaunchMode = .interactive

    var body: some View {
        switch launch {
        case .interactive:
            SaveInkOwnedNotebook()
        case .preview(let screen):
            SaveInkScreenPreview(screen: screen)
        }
    }
}

private struct SaveInkOwnedNotebook: View {
    @StateObject private var store = SaveInkNotebookStore()

    var body: some View {
        SaveInkNavigator(store: store)
    }
}

struct SaveInkNavigator: View {
    @ObservedObject var store: SaveInkNotebookStore

    var body: some View {
        NavigationStack(path: $store.path) {
            SaveInkShell(store: store) {
                SaveInkHomeScreen(store: store)
            }
            .navigationDestination(for: SaveInkRoute.self) { route in
                destination(route)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func destination(_ route: SaveInkRoute) -> some View {
        switch route {
        case .passport:
            SaveInkPassportScreen(store: store)
        case .place(let id):
            SaveInkShell(store: store) {
                SaveInkPlaceScreen(store: store, placeID: id)
            }
        case .friends:
            SaveInkFriendsScreen(store: store)
        case .review(let id):
            SaveInkReviewScreen(store: store, placeID: id)
        case .arrival(let id):
            SaveInkArrivalScreen(store: store, placeID: id)
        case .welcome:
            SaveInkWelcomeScreen(onStart: store.goBack, onSignIn: store.goBack)
        }
    }
}

struct SaveInkShell<Content: View>: View {
    @ObservedObject var store: SaveInkNotebookStore
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            content()
            if let sheet = store.sheet {
                SaveInkPalette.scrim.ignoresSafeArea()
                sheetView(sheet)
            }
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: SaveInkSheet) -> some View {
        switch sheet {
        case .save:
            SaveInkSaveSheet(store: store)
        case .checkIn(let situation, let placeID):
            if let place = store.place(placeID) {
                SaveInkCheckInSheet(store: store, place: place, situation: situation)
            }
        }
    }
}

struct SaveInkScreenPreview: View {
    var screen: SaveInkPreviewScreen
    private let store: SaveInkNotebookStore

    init(screen: SaveInkPreviewScreen) {
        self.screen = screen
        store = SaveInkPreviewFactory.store(for: screen)
    }

    var body: some View {
        Group {
            switch screen {
            case .main, .savePlace, .checkInSuccess, .checkInFailed, .checkInNoPermission, .checkInApproximate, .checkInTooFar:
                SaveInkShell(store: store) {
                    SaveInkHomeScreen(store: store)
                }
            case .passport:
                SaveInkPassportScreen(store: store)
            case .stampConfirm:
                SaveInkArrivalScreen(store: store, placeID: SaveInkFixture.dingtai)
            case .shopDetail:
                SaveInkPlaceScreen(store: store, placeID: SaveInkFixture.dingtai)
            case .welcome:
                SaveInkWelcomeScreen(onStart: {}, onSignIn: {})
            case .friends:
                SaveInkFriendsScreen(store: store)
            case .reviewVisibility:
                SaveInkReviewScreen(store: store, placeID: SaveInkFixture.dingtai)
            }
        }
        .frame(width: 393, height: 852)
        .clipped()
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }
}

enum SaveInkPreviewFactory {
    @MainActor
    static func store(for screen: SaveInkPreviewScreen) -> SaveInkNotebookStore {
        let name = "save.ink.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        let store = SaveInkNotebookStore(
            defaults: defaults,
            now: { SaveInkClock.previewNow },
            seedFixture: true,
            makeLocator: { SaveInkScriptedLocator() }
        )
        switch screen {
        case .savePlace:
            store.saveLink = "https://短影音連結/v/8f2k…"
            store.recognizedPlaceID = SaveInkFixture.qingtian
            store.sheet = .save
        case .checkInSuccess:
            store.sheet = .checkIn(.verified, placeID: SaveInkFixture.dingtai)
        case .checkInFailed:
            store.sheet = .checkIn(.locationFailed, placeID: SaveInkFixture.dingtai)
        case .checkInNoPermission:
            store.sheet = .checkIn(.permissionDenied, placeID: SaveInkFixture.dingtai)
        case .checkInApproximate:
            store.sheet = .checkIn(.approximateOnly, placeID: SaveInkFixture.dingtai)
        case .checkInTooFar:
            store.sheet = .checkIn(.tooFar(meters: 320), placeID: SaveInkFixture.dingtai)
        case .reviewVisibility:
            store.activePlaceID = SaveInkFixture.dingtai
            store.draftVisibility = .public
        case .main, .passport, .stampConfirm, .shopDetail, .welcome, .friends:
            break
        }
        return store
    }
}

@MainActor
final class SaveInkOneShotLocator: NSObject, SaveInkLocating, @preconcurrency CLLocationManagerDelegate {
    static let purposeKey = "SaveInkCheckIn"

    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<SaveInkFix, Never>?
    private var target: SaveInkPlace?
    private var timeout: Task<Void, Never>?
    private var started = false

    func requestFix(for place: SaveInkPlace) async -> SaveInkFix {
        await withCheckedContinuation { continuation in
            if pending != nil {
                finish(failed)
            }
            pending = continuation
            target = place
            started = false
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            timeout?.cancel()
            timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(SaveInkProvisional.timeoutSeconds * 1_000_000_000))
                self?.finishTimeout()
            }
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied:
                finish(denied(.denied))
            case .restricted:
                finish(denied(.restricted))
            case .authorizedAlways, .authorizedWhenInUse:
                requestPreciseThenLocation()
            @unknown default:
                finish(failed)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard pending != nil else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                requestPreciseThenLocation()
            case .denied:
                finish(denied(.denied))
            case .restricted:
                finish(denied(.restricted))
            case .notDetermined:
                break
            @unknown default:
                finish(failed)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let precise = manager.accuracyAuthorization == .fullAccuracy
        let snapshot = locations.last.map { location in
            (
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy,
                age: Date().timeIntervalSince(location.timestamp),
                simulated: location.sourceInformation?.isSimulatedBySoftware ?? false
            )
        }
        Task { @MainActor in
            guard let snapshot, let target else {
                finish(failed)
                return
            }
            let distance: Double?
            if let latitude = target.shopLatitude, let longitude = target.shopLongitude {
                distance = CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
                    .distance(from: CLLocation(latitude: latitude, longitude: longitude))
            } else {
                distance = nil
            }
            finish(SaveInkFix(
                authorization: .authorized,
                precise: precise,
                timedOut: false,
                distanceMeters: precise ? distance : nil,
                horizontalAccuracyMeters: precise ? snapshot.accuracy : nil,
                ageSeconds: snapshot.age,
                isSimulated: snapshot.simulated
            ))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            finish(failed)
        }
    }

    private func requestPreciseThenLocation() {
        guard !started else { return }
        started = true
        if manager.accuracyAuthorization == .reducedAccuracy {
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.purposeKey) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.pending != nil else { return }
                    if self.manager.accuracyAuthorization == .fullAccuracy {
                        self.manager.requestLocation()
                    } else {
                        self.finish(SaveInkFix(
                            authorization: .authorized,
                            precise: false,
                            timedOut: false,
                            distanceMeters: nil,
                            horizontalAccuracyMeters: nil,
                            ageSeconds: nil,
                            isSimulated: false
                        ))
                    }
                }
            }
        } else {
            manager.requestLocation()
        }
    }

    private func finishTimeout() {
        guard pending != nil else { return }
        finish(failed)
    }

    private func finish(_ fix: SaveInkFix, resume: Bool = true) {
        timeout?.cancel()
        timeout = nil
        target = nil
        started = false
        let continuation = pending
        pending = nil
        if resume {
            continuation?.resume(returning: fix)
        }
    }

    private var failed: SaveInkFix {
        SaveInkFix(
            authorization: .authorized,
            precise: true,
            timedOut: true,
            distanceMeters: nil,
            horizontalAccuracyMeters: nil,
            ageSeconds: nil,
            isSimulated: false
        )
    }

    private func denied(_ authorization: SaveInkAuthorization) -> SaveInkFix {
        SaveInkFix(
            authorization: authorization,
            precise: false,
            timedOut: false,
            distanceMeters: nil,
            horizontalAccuracyMeters: nil,
            ageSeconds: nil,
            isSimulated: false
        )
    }
}
