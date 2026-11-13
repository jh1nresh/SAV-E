#if SAVVY_CITY_MVP
import UIKit

/// UIKit-only offscreen drawing. Never constructs a SwiftUI tree during
/// updateUIView or while SceneKit owns a scene transaction.
@MainActor
enum CityPinRaster {
    struct PhotoMetrics {
        let diameter: CGFloat
        let revealScale: CGFloat
        var renderedDiameter: CGFloat { diameter * revealScale }
    }

    /// Shared with the SpriteKit transition: match the raster's rounding and
    /// reveal scale rather than measuring its transparent 140x92 canvas.
    static func photoMetrics(selected: Bool, browseDiameter: CGFloat, reveal: Double,
                             reduceMotion: Bool) -> PhotoMetrics? {
        guard browseDiameter.isFinite, browseDiameter > 0, reveal.isFinite else { return nil }
        let roundedReveal = (reveal * 100).rounded() / 100
        guard roundedReveal.isFinite else { return nil }
        let diameter = selected ? CityPinArtwork.selectedPhotoDiameter : browseDiameter.rounded()
        let scale = CityPinArtwork.visibleScale(reveal: roundedReveal, reduceMotion: reduceMotion)
        let metrics = PhotoMetrics(diameter: diameter, revealScale: scale)
        guard metrics.renderedDiameter.isFinite, metrics.renderedDiameter > 0 else { return nil }
        return metrics
    }

    static func head(_ pin: CityScenePin, night: Bool, reduceMotion: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let contact = (pin.placement.contactOpacity * 10).rounded() / 10
        let reveal = (pin.reveal * 100).rounded() / 100
        let metrics = Self.photoMetrics(selected: pin.selected, browseDiameter: pin.photoDiameter,
                                 reveal: pin.reveal, reduceMotion: reduceMotion)
        let rim = night ? rgb(0xC7DBFA) : .white
        let accent = UIColor(red: 0.53, green: 0.81, blue: 0.99, alpha: 1)
        return UIGraphicsImageRenderer(size: CGSize(width: 140, height: 92), format: format).image { output in
            let g = output.cgContext
            let shadowWidth: CGFloat = pin.selected ? 13 : 6
            UIColor.black.withAlphaComponent((pin.selected ? 0.17 : 0.10) * (1 - contact)).setFill()
            UIBezierPath(ovalIn: CGRect(x: 70 - shadowWidth / 2, y: 70, width: shadowWidth, height: 2)).fill()
            g.saveGState()
            g.setAlpha(contact)
            UIColor.black.withAlphaComponent(0.30).setFill()
            UIBezierPath(ovalIn: CGRect(x: 63, y: 68.5, width: 14, height: 6)).fill()
            (pin.selected ? accent : rim).setStroke()
            let ring = UIBezierPath(ovalIn: CGRect(x: 65, y: 69.5, width: 10, height: 5))
            ring.lineWidth = 1.2
            ring.stroke()
            g.restoreGState()

            g.saveGState()
            let scale = metrics?.revealScale ?? CityPinArtwork.visibleScale(reveal: reveal, reduceMotion: reduceMotion)
            g.translateBy(x: 70, y: 72)
            g.scaleBy(x: scale, y: scale)
            g.translateBy(x: -70, y: -72)
            if let photo = CityPinArtwork.photo(for: pin.contextID)?.image {
                let diameter = metrics?.diameter ?? (pin.selected ? CityPinArtwork.selectedPhotoDiameter : pin.photoDiameter.rounded())
                let ratio = diameter / CityPinArtwork.photoDiameter
                let pad = 3.2 - 2 * contact
                let circle = CGRect(x: 70 - diameter / 2, y: 72 - pad - 2.8 * ratio - diameter,
                                    width: diameter, height: diameter)
                let border = pin.selected ? accent : rim
                fillCircle(circle, color: border, shadow: 0.30, blur: 3 * ratio, offset: 2.5 * ratio, context: g)
                let face = circle.insetBy(dx: 2.5 * ratio, dy: 2.5 * ratio)
                drawFace(photo, in: face, pin: pin, rim: rim, night: night, context: g)
                rim.withAlphaComponent(0.85).setStroke()
                let line = UIBezierPath(ovalIn: face.insetBy(dx: 0.45 * ratio, dy: 0.45 * ratio))
                line.lineWidth = 0.9 * ratio
                line.stroke()
                border.setFill()
                tip(CGRect(x: 70 - 4 * ratio, y: circle.maxY - 2.2 * ratio,
                           width: 8 * ratio, height: 5 * ratio)).fill()
            } else {
                let diameter = CityPinArtwork.headDiameter(hasPhoto: false, selected: pin.selected,
                                                            browseDiameter: pin.photoDiameter)
                let ratio = diameter / CityPinArtwork.photoDiameter
                let pad = 3.2 - 2 * contact
                let circle = CGRect(x: 70 - diameter / 2, y: 72 - pad - 2.8 * ratio - diameter,
                                    width: diameter, height: diameter)
                let border = pin.selected ? accent : rim
                fillCircle(circle, color: border, shadow: 0.30, blur: 3 * ratio, offset: 2.5 * ratio, context: g)
                drawFace(nil, in: circle.insetBy(dx: 2.5 * ratio, dy: 2.5 * ratio),
                         pin: pin, rim: rim, night: night, context: g)
                border.setFill()
                tip(CGRect(x: 70 - 4 * ratio, y: circle.maxY - 2.2 * ratio,
                           width: 8 * ratio, height: 5 * ratio)).fill()
            }
            g.restoreGState()
        }
    }

    static func title(_ pin: CityScenePin, night: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let font = roundedFont(size: pin.selected ? 11 : 10, weight: .bold)
        let ink = night ? rgb(0xF2F6FF) : rgb(0x121726)
        let surface = night ? rgb(0x202F45) : .white
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = pin.selected ? .byTruncatingTail : .byWordWrapping
        let width: CGFloat = pin.selected ? 120 : 92
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
        let measured = (pin.title as NSString).boundingRect(with: CGSize(width: width, height: font.lineHeight * (pin.selected ? 1 : 2)),
                                                           options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        let textRect = CGRect(x: 70 - width / 2, y: (40 - ceil(measured.height)) / 2,
                              width: width, height: ceil(measured.height))
        return UIGraphicsImageRenderer(size: CGSize(width: 140, height: 40), format: format).image { output in
            let g = output.cgContext
            if pin.selected {
                let capsuleWidth = min(140, ceil(measured.width) + 20)
                let rect = CGRect(x: 70 - capsuleWidth / 2, y: textRect.minY - 5,
                                  width: capsuleWidth, height: textRect.height + 10)
                g.saveGState()
                g.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.18).cgColor)
                surface.setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
                g.restoreGState()
                (night ? rgb(0xC7DBFA) : .white).withAlphaComponent(0.6).setStroke()
                let edge = UIBezierPath(roundedRect: rect.insetBy(dx: 0.3, dy: 0.3), cornerRadius: rect.height / 2)
                edge.lineWidth = 0.6
                edge.stroke()
            } else {
                var outlined = attributes
                outlined[.foregroundColor] = surface
                for offset in [CGPoint(x: 0.7, y: 0), CGPoint(x: -0.7, y: 0), CGPoint(x: 0, y: 0.7)] {
                    (pin.title as NSString).draw(with: textRect.offsetBy(dx: offset.x, dy: offset.y),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: outlined, context: nil)
                }
            }
            (pin.title as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
        }
    }

    private static func drawFace(_ photo: UIImage?, in rect: CGRect, pin: CityScenePin, rim: UIColor, night: Bool, context g: CGContext) {
        g.saveGState()
        UIBezierPath(ovalIn: rect).addClip()
        if let photo {
            let scale = max(rect.width / photo.size.width, rect.height / photo.size.height)
            let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            photo.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        } else {
            let colors = [(night ? rgb(0x202F45) : .white).cgColor, (night ? rgb(0x31496D) : rgb(0xC7E0FF)).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                g.drawLinearGradient(gradient, start: rect.origin, end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
            }
            let symbol = pin.contextID == "way/142113976" ? "building.columns.fill" : pin.symbol
            let config = UIImage.SymbolConfiguration(pointSize: 16 * rect.width / 37, weight: .medium)
            if let glyph = UIImage(systemName: symbol, withConfiguration: config)?.withTintColor((night ? rgb(0xF2F6FF) : rgb(0x121726)).withAlphaComponent(0.8), renderingMode: .alwaysOriginal) {
                glyph.draw(in: CGRect(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2, width: glyph.size.width, height: glyph.size.height))
            }
        }
        g.restoreGState()
        UIColor.black.withAlphaComponent(0.10).setStroke()
        let edge = UIBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
        edge.lineWidth = 0.5
        edge.stroke()
        if let savedSymbol = CityPinArtwork.savedBadgeSymbol(saved: pin.saved, visited: pin.visited) {
            let scale = rect.width / 37
            let badge = CGRect(x: rect.maxX - 12 * scale, y: rect.maxY - 12 * scale, width: 13 * scale, height: 13 * scale)
            rgb(0x2159D4).setFill()
            UIBezierPath(ovalIn: badge).fill()
            rim.setStroke()
            let line = UIBezierPath(ovalIn: badge.insetBy(dx: 0.65 * scale, dy: 0.65 * scale))
            line.lineWidth = 1.3 * scale
            line.stroke()
            let glyph = UIImage(systemName: savedSymbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 7 * scale, weight: .bold))?.withTintColor(.white, renderingMode: .alwaysOriginal)
            if let glyph { glyph.draw(in: CGRect(x: badge.midX - glyph.size.width / 2, y: badge.midY - glyph.size.height / 2, width: glyph.size.width, height: glyph.size.height)) }
        }
    }

    private static func fillCircle(_ rect: CGRect, color: UIColor, shadow: CGFloat, blur: CGFloat, offset: CGFloat, context g: CGContext) {
        g.saveGState()
        g.setShadow(offset: CGSize(width: 0, height: offset), blur: blur, color: UIColor.black.withAlphaComponent(shadow).cgColor)
        color.setFill()
        UIBezierPath(ovalIn: rect).fill()
        g.restoreGState()
    }
    private static func tip(_ r: CGRect) -> UIBezierPath {
        let p = UIBezierPath()
        p.move(to: r.origin)
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), controlPoint: CGPoint(x: r.midX - 1, y: r.minY + 1))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), controlPoint: CGPoint(x: r.midX + 1, y: r.minY + 1))
        p.close()
        return p
    }
    private static func badge(_ r: CGRect) -> UIBezierPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        let p = UIBezierPath()
        p.move(to: point(0.32, 0)); p.addLine(to: point(0.68, 0))
        p.addQuadCurve(to: point(1, 0.29), controlPoint: point(1, 0))
        p.addLine(to: point(1, 0.61))
        p.addCurve(to: point(0.5, 1), controlPoint1: point(1, 0.83), controlPoint2: point(0.72, 0.90))
        p.addCurve(to: point(0, 0.61), controlPoint1: point(0.28, 0.90), controlPoint2: point(0, 0.83))
        p.addLine(to: point(0, 0.29))
        p.addQuadCurve(to: point(0.32, 0), controlPoint: point(0, 0)); p.close()
        return p
    }
    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        return font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? font
    }
    private static func rgb(_ value: UInt32) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
#endif
