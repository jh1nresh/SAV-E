#if SAVVY_CITY_MVP
import MapKit
import SwiftUI
import simd

struct CityDistrictCamera: Equatable {
    static let space = "cityMVP.viewport"
    static let nearDistance = 1_650.0
    static let farDistance = 2_650.0

    struct Projection: Equatable {
        let eye: SIMD3<Double>
        let target: SIMD3<Double>
        let up: SIMD3<Double>
        let focalLength: Double
        let principalPoint: CGPoint
        let error: Double
    }

    let latitude: Double
    let longitude: Double
    let distance: Double
    let heading: Double
    let pitch: Double
    let projection: Projection?
    let opacity: Double
    let shouldPrewarm: Bool

    var mapCamera: MapCamera {
        MapCamera(centerCoordinate: .init(latitude: latitude, longitude: longitude),
                  distance: distance, heading: heading, pitch: pitch)
    }

    @MainActor
    init(camera: MapCamera, registration: CityDistrictRegistration?, project: (CLLocationCoordinate2D) -> CGPoint?) {
        latitude = camera.centerCoordinate.latitude
        longitude = camera.centerCoordinate.longitude
        distance = camera.distance
        heading = camera.heading
        pitch = camera.pitch
        let target = Self.world(registration?.sceneCoordinate(camera.centerCoordinate) ?? camera.centerCoordinate)
        let edge = max(abs(target.x), abs(target.z))
        shouldPrewarm = registration != nil && distance < 4_300 && edge < 850
        let zoom = Self.fade((Self.farDistance - distance) / (Self.farDistance - Self.nearDistance))
        let coverage = Self.fade((680 - edge) / 230)
        let mix = zoom * coverage
        if mix > 0, let registration,
           let fit = Self.fit(camera: camera, target: target, project: { project(registration.mapCoordinate($0)) }),
           fit.error < 8 {
            projection = fit
            opacity = mix
        } else {
            projection = nil
            opacity = 0
        }
    }

    static func world(_ coordinate: CLLocationCoordinate2D) -> SIMD3<Double> {
        SIMD3((coordinate.longitude - CityScenePlace.originLongitude) * 100_850,
              0, -(coordinate.latitude - CityScenePlace.originLatitude) * 111_195)
    }

    static func coordinate(x: Double, z: Double) -> CLLocationCoordinate2D {
        .init(latitude: CityScenePlace.originLatitude - z / 111_195,
              longitude: CityScenePlace.originLongitude + x / 100_850)
    }

    private static func fade(_ fraction: Double) -> Double {
        let x = min(1, max(0, fraction))
        return x * x * (3 - 2 * x)
    }

    private struct Sample {
        let right: Double
        let up: Double
        let towardEye: Double
        let pixel: SIMD2<Double>
    }

    private static func fit(camera: MapCamera, target: SIMD3<Double>,
                            project: (CLLocationCoordinate2D) -> CGPoint?) -> Projection? {
        guard camera.distance.isFinite, camera.distance > 0,
              camera.heading.isFinite, camera.pitch.isFinite else { return nil }
        let heading = camera.heading * .pi / 180
        let pitch = camera.pitch * .pi / 180
        let right = SIMD3(cos(heading), 0, sin(heading))
        let towardEye = SIMD3(-sin(heading) * sin(pitch), cos(pitch), cos(heading) * sin(pitch))
        let up = simd_cross(towardEye, right)
        let step = max(12, min(140, camera.distance * 0.13))
        var samples: [Sample] = []
        for x in [-step, 0, step] {
            for z in [-step, 0, step] {
                let offset = SIMD3(x, 0, z)
                guard let pixel = project(coordinate(x: target.x + x, z: target.z + z)),
                      pixel.x.isFinite, pixel.y.isFinite else { continue }
                samples.append(Sample(right: simd_dot(right, offset), up: simd_dot(up, offset),
                                      towardEye: simd_dot(towardEye, offset), pixel: SIMD2(Double(pixel.x), Double(pixel.y))))
            }
        }
        guard samples.count >= 5 else { return nil }

        func evaluate(_ distance: Double) -> Projection? {
            var projected: [SIMD2<Double>] = []
            var mean = SIMD2<Double>.zero
            var meanPixel = SIMD2<Double>.zero
            for sample in samples {
                let depth = distance - sample.towardEye
                guard depth > 2 else { return nil }
                let point = SIMD2(sample.right / depth, -sample.up / depth)
                projected.append(point)
                mean += point
                meanPixel += sample.pixel
            }
            mean /= Double(samples.count)
            meanPixel /= Double(samples.count)
            var covariance = 0.0
            var variance = 0.0
            for (point, sample) in zip(projected, samples) {
                let delta = point - mean
                covariance += simd_dot(delta, sample.pixel - meanPixel)
                variance += simd_length_squared(delta)
            }
            guard variance > 1e-9 else { return nil }
            let focalLength = covariance / variance
            guard focalLength > 50, focalLength < 10_000 else { return nil }
            let center = meanPixel - focalLength * mean
            let error = zip(projected, samples).map { simd_length(center + focalLength * $0.0 - $0.1.pixel) }.max() ?? .infinity
            return Projection(eye: target + towardEye * distance, target: target, up: up,
                              focalLength: focalLength, principalPoint: .init(x: center.x, y: center.y), error: error)
        }

        // At zero tilt, distance and focal length are interchangeable on the
        // ground plane. Use the native distance to keep elevated geometry stable.
        var low = camera.distance * 0.50
        var high = camera.distance * 2.0
        if abs(camera.pitch) < 4 {
            low = camera.distance
            high = camera.distance
        } else {
            for _ in 0..<18 {
                let a = (2 * low + high) / 3
                let b = (low + 2 * high) / 3
                if (evaluate(a)?.error ?? .infinity) < (evaluate(b)?.error ?? .infinity) {
                    high = b
                } else {
                    low = a
                }
            }
        }
        let depthAtCenter = (low + high) / 2
        guard let fit = evaluate(depthAtCenter) else { return nil }
        var error = fit.error
        for offset in [SIMD3(step * 0.63, 0, -step * 1.16),
                       SIMD3(-step * 1.16, 0, step * 0.63)] {
            let coordinate = coordinate(x: target.x + offset.x, z: target.z + offset.z)
            guard let point = project(coordinate), point.x.isFinite, point.y.isFinite else { return nil }
            let depth = depthAtCenter - simd_dot(towardEye, offset)
            guard depth > 2 else { return nil }
            let x = fit.principalPoint.x + fit.focalLength * simd_dot(right, offset) / depth
            let y = fit.principalPoint.y - fit.focalLength * simd_dot(up, offset) / depth
            error = max(error, hypot(x - point.x, y - point.y))
        }
        return Projection(eye: fit.eye, target: fit.target, up: up, focalLength: fit.focalLength,
                          principalPoint: fit.principalPoint, error: error)
    }
}
#endif
