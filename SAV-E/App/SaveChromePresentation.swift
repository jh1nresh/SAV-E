import CoreLocation
import Foundation

/// Exclusive chrome that UIKit presents as a sheet or cover.
///
/// Two of these at once is a known on-device abort: "Attempt to present
/// while a presentation is in progress" can terminate the process. There is
/// no .ips on the Mac for the founder report, so this gate is the harden
/// for Home / Saves / Review / Trips / Map / Passport / Capture taps.
enum SaveChromeExclusive: Equatable {
    case none
    case rootSheet
    case passport
    case cover
    case tripComposer
}

enum SaveChromeTransition: Equatable {
    case presentNow
    case dismissThenPresent
}

enum SaveChromeNavigation {
    static func occupyingExclusive(
        hasCover: Bool,
        isTripComposerPresented: Bool,
        isPassportPresented: Bool,
        isRootSheetPresented: Bool
    ) -> SaveChromeExclusive {
        if hasCover { return .cover }
        if isTripComposerPresented { return .tripComposer }
        if isPassportPresented { return .passport }
        if isRootSheetPresented { return .rootSheet }
        return .none
    }

    static func transition(
        from occupying: SaveChromeExclusive,
        to target: SaveChromeExclusive
    ) -> SaveChromeTransition {
        if occupying == .none {
            return .presentNow
        }
        return .dismissThenPresent
    }

    /// Capture is a control. Selecting it must not become the visible tab.
    static func destination(
        afterSelecting tab: SaveRootTab,
        current: SaveRootTab
    ) -> SaveRootTab {
        tab.isCaptureControl ? current : tab
    }

    /// Root tab changes leave Saves / Trips / Trip children.
    static func pathAfterSelectingRootTab() -> [SaveRootRoute] {
        []
    }

    /// Opening Saves or Trips replaces a stale child instead of stacking.
    static func pathByOpening(
        _ route: SaveRootRoute,
        currently path: [SaveRootRoute]
    ) -> [SaveRootRoute] {
        switch route {
        case .saves:
            return [.saves]
        case .trips:
            return [.trips]
        case .trip(let tripID):
            if path.contains(.trips) {
                return [.trips, .trip(tripID)]
            }
            return [.trip(tripID)]
        }
    }

    static func isSafeMapCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && coordinate.latitude.isFinite
            && coordinate.longitude.isFinite
            && (-90...90).contains(coordinate.latitude)
            && (-180...180).contains(coordinate.longitude)
    }
}
