#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Explicit, one-shot camera focus. A coordinate is never saved or shared here.
@MainActor
struct LiveMapLocationControl: View {
    @Binding private var position: MapCameraPosition
    let ownerSubject: String
    let sessionGeneration: Int
    @ObservedObject private var auth = PrivyAuthService.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.appLanguageSettings) private var language
    @State private var requestTask: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var isLoading = false
    @State private var failure: LocationFailure?
    @State private var activityPhase: ScenePhase = .inactive
    @State private var pendingResult: PendingResult?

    init(position: Binding<MapCameraPosition>, ownerSubject: String, sessionGeneration: Int) {
        _position = position
        self.ownerSubject = ownerSubject
        self.sessionGeneration = sessionGeneration
    }

    var body: some View {
        Button(action: locate) {
            Group {
                if isLoading {
                    ProgressView().tint(DateTheme.ink)
                } else {
                    Image(systemName: "location.fill")
                        .font(.system(size: 19, weight: .semibold))
                }
            }
            .foregroundStyle(DateTheme.ink)
            .frame(width: 48, height: 48)
            .background(DateTheme.surface, in: Circle())
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || scenePhase != .active || !sessionIsCurrent)
        .accessibilityLabel(isLoading
            ? language.localized(english: "Finding your location", traditionalChinese: "正在定位")
            : language.localized(english: "Show my location", traditionalChinese: "顯示我的位置"))
        .accessibilityHint(language.localized(
            english: "Gets your current location when tapped to center the map. Your location is not shared.",
            traditionalChinese: "點擊後取得目前位置，僅移動地圖，不會分享位置。"))
        .accessibilityIdentifier("live.map.locate")
        .alert(failure?.title(language: language)
            ?? language.localized(english: "Location", traditionalChinese: "定位"), isPresented: Binding(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        ), presenting: failure) { failure in
            switch failure {
            case .permission:
                Button(language.localized(english: "Open Settings", traditionalChinese: "開啟設定")) {
                    guard sessionIsCurrent, scenePhase == .active,
                          let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                Button(language.localized(english: "Cancel", traditionalChinese: "取消"), role: .cancel) {}
            case .unavailable:
                Button(language.localized(english: "Retry", traditionalChinese: "重試"), action: locate)
                Button(language.localized(english: "Cancel", traditionalChinese: "取消"), role: .cancel) {}
            }
        } message: { failure in
            Text(failure.message(language: language))
        }
        .onAppear { activityPhase = scenePhase }
        .onDisappear(perform: cancelRequest)
        .onChange(of: scenePhase) { _, phase in
            activityPhase = phase
            switch phase {
            case .background:
                cancelRequest()
            case .active:
                if let pendingResult { apply(pendingResult) }
            case .inactive:
                // The system permission prompt is transiently inactive. Preserve
                // the explicit request, but never move the camera in this phase.
                break
            @unknown default:
                cancelRequest()
            }
        }
        .onChange(of: auth.authState) { _, _ in
            if !sessionIsCurrent { cancelRequest() }
        }
        .onChange(of: auth.sessionGeneration) { _, _ in
            if !sessionIsCurrent { cancelRequest() }
        }
        .onChange(of: ownerSubject) { _, _ in cancelRequest() }
        .onChange(of: sessionGeneration) { _, _ in cancelRequest() }
    }

    private var sessionIsCurrent: Bool {
        guard case .authenticated(let owner) = auth.authState else { return false }
        return owner == ownerSubject && auth.currentUserId == ownerSubject
            && auth.sessionGeneration == sessionGeneration
    }

    private func locate() {
        guard sessionIsCurrent, scenePhase == .active, !isLoading else { return }
        cancelRequest()
        let service = LocationService.shared
        guard !service.isAuthorizationDenied else {
            failure = .permission
            return
        }
        let ticket = UUID()
        requestID = ticket
        let requestedAt = Date()
        isLoading = true
        requestTask = Task { @MainActor in
            // State-backed phase stays current inside this suspended task; a
            // captured Environment value can belong to an earlier view update.
            defer {
                if requestID == ticket {
                    requestTask = nil
                    isLoading = false
                }
            }
            guard !Task.isCancelled, requestID == ticket,
                  sessionIsCurrent, activityPhase != .background else { return }
            let location = await service.requestCurrentLocation(forceRefresh: true)
            // The shared service's continuation can outlive caller cancellation.
            // A late fix may update its cache, but cannot move this view's camera.
            guard !Task.isCancelled, requestID == ticket,
                  sessionIsCurrent, activityPhase != .background else { return }
            let result: LocationResult
            if service.isAuthorizationDenied {
                result = .failure(.permission)
            } else if let location, isUsable(location, requestedAt: requestedAt) {
                result = .location(location, requestedAt: requestedAt)
            } else {
                result = .failure(.unavailable)
            }
            let pending = PendingResult(ticket: ticket, owner: ownerSubject,
                                        generation: sessionGeneration, result: result)
            if activityPhase == .active {
                apply(pending)
            } else if activityPhase == .inactive {
                pendingResult = pending
            }
        }
    }

    private func apply(_ pending: PendingResult) {
        guard pending.ticket == requestID, pending.owner == ownerSubject,
              pending.generation == sessionGeneration, sessionIsCurrent,
              activityPhase == .active else { return }
        pendingResult = nil
        switch pending.result {
        case .failure(let result):
            failure = result
        case .location(let location, let requestedAt):
            guard !LocationService.shared.isAuthorizationDenied else {
                failure = .permission
                return
            }
            guard isUsable(location, requestedAt: requestedAt) else {
                failure = .unavailable
                return
            }
            position = .region(MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            ))
        }
    }

    private func isUsable(_ location: CLLocation, requestedAt: Date) -> Bool {
        // A failed shared request can return an old cache. A queued fix must
        // also remain fresh when the app becomes active, rather than on receipt
        // alone. No second location request is made to consume this result.
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.coordinate.latitude.isFinite && location.coordinate.longitude.isFinite
            && location.horizontalAccuracy.isFinite && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 10_000
            && location.timestamp >= requestedAt.addingTimeInterval(-5)
            && location.timestamp.timeIntervalSinceNow >= -SaveLocationFreshness.maxAge
            && location.timestamp.timeIntervalSinceNow <= 5
    }

    private func cancelRequest() {
        requestID = UUID()
        requestTask?.cancel()
        requestTask = nil
        isLoading = false
        failure = nil
        pendingResult = nil
    }

    private struct PendingResult {
        let ticket: UUID
        let owner: String
        let generation: Int
        let result: LocationResult
    }

    private enum LocationResult {
        case location(CLLocation, requestedAt: Date)
        case failure(LocationFailure)
    }

    private enum LocationFailure {
        case permission, unavailable

        func title(language: AppLanguageSettings) -> String {
            switch self {
            case .permission:
                return language.localized(english: "Location access is off", traditionalChinese: "定位權限未開啟")
            case .unavailable:
                return language.localized(english: "Couldn't get your location", traditionalChinese: "無法取得目前位置")
            }
        }

        func message(language: AppLanguageSettings) -> String {
            switch self {
            case .permission:
                return language.localized(
                    english: "Allow Savvy to use your location in Settings. If access is restricted by device management, contact your administrator. You can still browse the map manually.",
                    traditionalChinese: "請在設定中允許 Savvy 使用定位。若權限受裝置管理限制，請聯絡管理者；仍可手動瀏覽地圖。")
            case .unavailable:
                return language.localized(
                    english: "No valid, recent location was received. The map hasn't moved. Please try again shortly.",
                    traditionalChinese: "尚未取得有效的新位置，地圖保持原位。請稍後重試。")
            }
        }
    }
}
#endif
