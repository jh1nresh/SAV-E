#if SAVVY_CITY_MVP
import MapKit
import SwiftUI

/// Region configuration for the main Savvy map. A destination is not evidence
/// that its SDK, authored scene, or provider account is connected.
struct SavvyMapRegion: Identifiable {
    enum ID: String, CaseIterable {
        case world
        case taipeiXinyi = "taipei-xinyi"
        case shanghai
    }

    enum Renderer: String { case appleMaps, amap }

    /// MapKit chooses its own regional data provider. Requesting Apple Maps
    /// does not select, detect, or authenticate an Amap SDK.
    enum AppleDataProviderPolicy: Equatable { case selectedByMapKit }

    struct Bounds: Equatable {
        let south: Double
        let west: Double
        let north: Double
        let east: Double

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            CLLocationCoordinate2DIsValid(coordinate)
                && (south...north).contains(coordinate.latitude)
                && (west...east).contains(coordinate.longitude)
        }
    }

    /// The authored source envelope in WGS84, before live MapKit registration.
    /// This is not a claim of complete buildings, verified entrances, or reality.
    struct AuthoredCoverage: Equatable {
        let regionID: ID
        let sceneID: String
        let bounds: Bounds
        let opaqueGroundBounds: Bounds
    }

    enum Selection {
        case appleMaps(SavvyMapRegion)
        case amapPending(SavvyMapRegion, CityMVPConfiguration.AmapStatus)
    }

    let id: ID
    let requestedRenderer: Renderer
    let authoredCoverage: AuthoredCoverage?
    var appleDataProviderPolicy: AppleDataProviderPolicy { .selectedByMapKit }

    private init(id: ID, requestedRenderer: Renderer, authoredCoverage: AuthoredCoverage?) {
        self.id = id
        self.requestedRenderer = requestedRenderer
        self.authoredCoverage = authoredCoverage
    }

    /// Existing authored camera values remain owned by CityMVPCameras. Apply
    /// CityDistrictRegistration only to the Xinyi camera, as the map does today.
    /// Shanghai deliberately has no fabricated native camera or model anchor.
    var camera: MapCamera? {
        switch id {
        case .world: CityMVPCameras.world
        case .taipeiXinyi: CityMVPCameras.taipei
        case .shanghai: nil
        }
    }

    static let world = Self(id: .world, requestedRenderer: .appleMaps, authoredCoverage: nil)
    static let taipeiXinyi = Self(
        id: .taipeiXinyi,
        requestedRenderer: .appleMaps,
        authoredCoverage: .init(
            regionID: .taipeiXinyi,
            sceneID: "taipei-xinyi-101-city-hall",
            bounds: sourceBounds(
                halfExtent: CityDistrictCamera.groundHalfExtent,
                northernLimit: CityDistrictCamera.northernGroundLimit
            ),
            opaqueGroundBounds: sourceBounds(
                halfExtent: CityDistrictCamera.groundHalfExtent - CityDistrictCamera.groundFeather,
                northernLimit: CityDistrictCamera.northernOpaqueLimit
            )
        )
    )
    static let shanghai = Self(id: .shanghai, requestedRenderer: .amap, authoredCoverage: nil)
    static let catalog: [Self] = [.world, .taipeiXinyi, .shanghai]

    static func region(for id: ID) -> Self {
        switch id {
        case .world: .world
        case .taipeiXinyi: .taipeiXinyi
        case .shanghai: .shanghai
        }
    }

    /// Even a present matching key remains pending until an SDK connection is
    /// implemented and verified. Never silently substitute Xinyi's geometry.
    static func selection(for id: ID, amapStatus: CityMVPConfiguration.AmapStatus) -> Selection {
        let region = region(for: id)
        switch region.requestedRenderer {
        case .appleMaps: return .appleMaps(region)
        case .amap: return .amapPending(region, amapStatus)
        }
    }

    private static func sourceBounds(halfExtent: Double, northernLimit: Double) -> Bounds {
        let southwest = CityDistrictCamera.coordinate(x: -halfExtent, z: halfExtent)
        let northeast = CityDistrictCamera.coordinate(x: halfExtent, z: northernLimit)
        return Bounds(south: southwest.latitude, west: southwest.longitude,
                      north: northeast.latitude, east: northeast.longitude)
    }
}
#endif
