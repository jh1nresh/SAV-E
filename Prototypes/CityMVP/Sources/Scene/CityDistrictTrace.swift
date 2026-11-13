#if SAVVY_CITY_MVP
import Foundation

/// Used by native map verification. Records public landmark geometry, never vault data.
@MainActor
enum CityDistrictTrace {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--verify-xinyi")
    static let opensDistrictOnLaunch = enabled && ProcessInfo.processInfo.arguments.contains("--verify-xinyi-auto")
    static let opensCornerOnLaunch = opensDistrictOnLaunch && ProcessInfo.processInfo.arguments.contains("--verify-xinyi-corner")
    static let opensCityHallOnLaunch = opensDistrictOnLaunch && ProcessInfo.processInfo.arguments.contains("--verify-xinyi-cityhall")
    static let opensOverviewOnly = opensDistrictOnLaunch && ProcessInfo.processInfo.arguments.contains("--verify-xinyi-overview")
    static let selectsLandmarkOnLaunch = opensDistrictOnLaunch && ProcessInfo.processInfo.arguments.contains("--verify-xinyi-selected")
    private static let handle: FileHandle? = {
        guard enabled else { return nil }
        let filename = ProcessInfo.processInfo.arguments.contains("--verify-xinyi-overview-journey")
            ? "xinyi-overview-journey.tsv" : "xinyi-zoom.tsv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        guard (try? Data().write(to: url)) != nil else { return nil }
        return try? FileHandle(forWritingTo: url)
    }()

    static func write(_ row: String) {
        guard let handle else { return }
        try? handle.write(contentsOf: Data((row + "\n").utf8))
    }

    static func navigation(_ event: String, style: CityDistrictMapStyle, distance: Double) {
        guard enabled else { return }
        write("navigation\t\(ProcessInfo.processInfo.systemUptime)\t\(event)\t\(style.rawValue)\t\(distance)")
    }

    static func record(_ sample: CityDistrictCamera, landmarkSelection: CityDistrictCamera.Pin?) {
        let time = ProcessInfo.processInfo.systemUptime
        write("camera\t\(time)\t\(sample.style.rawValue)\t\(sample.styleRevision)\t\(sample.distance)")
        guard sample.distance < 5_500 else { return }

        let point = sample.landmarkPoint
        write("map\t\(sample.distance)\t\(sample.opacity)\t\(sample.projection?.error ?? -1)\t\(landmarkSelection != nil)\t\(point?.x ?? -1)\t\(point?.y ?? -1)")
        let owner = landmarkSelection.map { sample.ownsSelectedPin($0) ? "overlay" : "native" } ?? "none"
        let center = sample.cameraCenterPoint
        write("fit\t\(time)\t\(sample.requestedOpacity)\t\(sample.hasRegistration)\t\(sample.viewport.width)\t\(sample.viewport.height)\t\(sample.heading)\t\(sample.pitch)\t\(center?.x ?? -1)\t\(center?.y ?? -1)\t\(owner)")
    }
}
#endif
