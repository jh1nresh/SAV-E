import CoreLocation
import SwiftUI

enum SaveInkLaunchMode: Equatable {
    case interactive
    case preview(SaveInkPreviewScreen)
}

enum SaveInkLaunch {
    static var defaults: UserDefaults {
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--savvy-ink-suite=") }) else {
            return .standard
        }
        let name = String(raw.dropFirst("--savvy-ink-suite=".count))
        return UserDefaults(suiteName: name) ?? .standard
    }

    /// A real launch with no friend visits. Screen 14 is that empty friends page.
    static var emptyFriends: Bool {
        ProcessInfo.processInfo.arguments.contains("--savvy-ink-empty-friends")
    }

    static func showsWelcome(seen: Bool) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--savvy-ink-skip-welcome") { return false }
        if arguments.contains("--savvy-ink-show-welcome") { return true }
        return !seen
    }

    static func makeLocator() -> any SaveInkLocating {
        if let fix = scriptedFix {
            return SaveInkScriptedLocator(fix: fix)
        }
        return SaveInkOneShotLocator()
    }

    /// UI-test locations. `isSimulated` stays false so an in-range fix can verify.
    static var scriptedFix: SaveInkFix? {
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--savvy-ink-fix=") }) else {
            return nil
        }
        switch String(raw.dropFirst("--savvy-ink-fix=".count)) {
        case "verified":
            return .inRange(meters: 18)
        case "tooFar":
            return .inRange(meters: 320)
        case "denied":
            var fix = SaveInkFix.inRange()
            fix.authorization = .denied
            return fix
        case "approximate":
            var fix = SaveInkFix.inRange()
            fix.precise = false
            return fix
        case "failed":
            var fix = SaveInkFix.inRange()
            fix.timedOut = true
            return fix
        default:
            return nil
        }
    }

    /// Screenshot stills. The notebook is the main screen without a feature flag.
    static var previewScreen: SaveInkPreviewScreen? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let raw = arguments.first(where: { $0.hasPrefix("--savvy-ink-screen=") }) else {
            return nil
        }
        let name = String(raw.dropFirst("--savvy-ink-screen=".count))
        return SaveInkPreviewScreen(rawValue: name)
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
    @AppStorage("save.ink.welcome.seen.v1") private var welcomeSeen = false
    @State private var dismissedWelcome = false
    @StateObject private var store = SaveInkNotebookStore(
        defaults: SaveInkLaunch.defaults,
        friendInputs: SaveInkLaunch.emptyFriends ? [] : nil,
        makeLocator: { SaveInkLaunch.makeLocator() }
    )

    var body: some View {
        if !dismissedWelcome && SaveInkLaunch.showsWelcome(seen: welcomeSeen) {
            SaveInkWelcomeScreen(
                onStart: {
                    welcomeSeen = true
                    dismissedWelcome = true
                },
                onSignIn: {
                    welcomeSeen = true
                    dismissedWelcome = true
                }
            )
        } else {
            SaveInkNavigator(store: store)
        }
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
            case .friends, .friendsEmpty:
                SaveInkFriendsScreen(store: store)
            case .reviewVisibility:
                SaveInkReviewScreen(store: store, placeID: SaveInkFixture.dingtai)
            }
        }
        .frame(width: 393, height: 852)
        .background(SaveInkPalette.paper.ignoresSafeArea())
        .clipped()
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.saveInkScreenshot, true)
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
            friendInputs: screen == .friendsEmpty ? [] : nil,
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
        case .main, .passport, .stampConfirm, .shopDetail, .welcome, .friends, .friendsEmpty:
            break
        }
        return store
    }
}

@MainActor
final class SaveInkOneShotLocator: NSObject, SaveInkLocating, CLLocationManagerDelegate {
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
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard pending != nil else { return }
            switch status {
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
