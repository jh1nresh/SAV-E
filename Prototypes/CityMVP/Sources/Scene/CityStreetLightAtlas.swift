#if SAVVY_CITY_MVP
import CoreGraphics
import CoreFoundation

/// Baked light on the street plane. The clear center keeps lane markings legible.
enum CityStreetLightAtlas {
    static func make(bounds: CGRect, shoulders: CGPath, curbs: CGPath,
                     carriageway: CGPath, crossings: CGPath, lamps: [CGPoint]) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: -bounds.minX, y: bounds.maxY)
        context.scaleBy(x: 1, y: -1)

        func fill(_ path: CGPath, color: CGColor) {
            context.setFillColor(color)
            context.addPath(path)
            context.fillPath()
        }
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        fill(shoulders, color: CGColor(red: 1, green: 0.61, blue: 0.32, alpha: 0.05))
        fill(curbs, color: CGColor(red: 1, green: 0.75, blue: 0.48, alpha: 0.16))
        context.setBlendMode(.destinationOut)
        fill(carriageway, color: CGColor(gray: 0, alpha: 1))
        fill(crossings, color: CGColor(gray: 0, alpha: 1))
        context.setBlendMode(.normal)
        context.endTransparencyLayer()
        context.restoreGState()

        if let pool = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 1, green: 0.82, blue: 0.54, alpha: 0.58),
            CGColor(red: 1, green: 0.66, blue: 0.33, alpha: 0.19),
            CGColor(red: 1, green: 0.63, blue: 0.29, alpha: 0),
        ] as CFArray, locations: [0, 0.37, 1]) {
            for lamp in lamps {
                context.drawRadialGradient(pool, startCenter: lamp, startRadius: 0,
                                           endCenter: lamp, endRadius: 13.5, options: [])
            }
        }

        // Soften the edge in the same region as the underlying road texture.
        if let edge = CGGradient(colorsSpace: space, colors: [
            CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0),
        ] as CFArray, locations: [0, 1]) {
            context.setBlendMode(.destinationOut)
            for (start, end) in [
                (CGPoint(x: bounds.minX, y: 0), CGPoint(x: bounds.minX + 20, y: 0)),
                (CGPoint(x: bounds.maxX, y: 0), CGPoint(x: bounds.maxX - 20, y: 0)),
                (CGPoint(x: 0, y: bounds.minY), CGPoint(x: 0, y: bounds.minY + 16)),
                (CGPoint(x: 0, y: bounds.maxY), CGPoint(x: 0, y: bounds.maxY - 16)),
            ] {
                context.drawLinearGradient(edge, start: start, end: end, options: [])
            }
        }
        CityStreetSurface.fadeNorthernCoverage(context)
        return context.makeImage()
    }
}
#endif
