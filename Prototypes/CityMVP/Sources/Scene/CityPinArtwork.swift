#if SAVVY_CITY_MVP
import SwiftUI
import UIKit

/// Upright artwork attached at the point supplied by the current map renderer.
struct CityPinArtwork: View {
    static let height: CGFloat = 72
    static let selectedTitleClearance: CGFloat = 32
    static var nativeSelectedHeight: CGFloat { height + selectedTitleClearance }
    static var nativeSelectedAnchor: UnitPoint { .init(x: 0.5, y: height / nativeSelectedHeight) }
    static let photoDiameter: CGFloat = 42
    static let expandedPhotoDiameter: CGFloat = 58

    static let selectedPhotoDiameter: CGFloat = 62
    static let categoryDiameter: CGFloat = 36

    static func headDiameter(hasPhoto: Bool, selected: Bool, browseDiameter: CGFloat) -> CGFloat {
        selected ? selectedPhotoDiameter : hasPhoto ? browseDiameter : categoryDiameter
    }

    // Camera sampling drives the zoom size directly. The spring only affects
    // the local head on arrival or selection, never its projected position.
    static func zoomPhotoDiameter(distance: Double) -> CGFloat {
        let overview = CityDistrictCamera.overviewDistance
        guard distance.isFinite, distance > 0 else { return photoDiameter }
        let close = overview / 1.42
        let fraction = min(1, max(0, (overview - distance) / (overview - close)))
        let eased = fraction * fraction * (3 - 2 * fraction)
        return photoDiameter + (expandedPhotoDiameter - photoDiameter) * eased
    }

    static func visibleScale(reveal: Double, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : 0.85 + 0.15 * reveal
    }

    struct Photo {
        let image: UIImage
        let author: String
        let source: URL
    }

    private static let photos: [String: Photo] = [
        ("landmark-101", "taipei101-pin", "AnthonySantiago101", "Tower_of_Taipei_101.jpg"),
        ("way/234589397", "att4fun-pin", "Wikipedia user – Wpcpey", "ATT_4_Fun_Exterior_view_201911.jpg"),
    ].reduce(into: [:]) { photos, entry in
        let (id, asset, author, source) = entry
        guard let url = Bundle.main.url(forResource: asset, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path),
              let sourceURL = URL(string: "https://commons.wikimedia.org/wiki/File:\(source)") else { return }
        photos[id] = Photo(image: image, author: author, source: sourceURL)
    }

    static func photo(for id: String?) -> Photo? { id.flatMap { photos[$0] } }

    static func savedBadgeSymbol(saved: Bool, visited: Bool) -> String? {
        saved ? (visited ? "checkmark" : "bookmark.fill") : nil
    }

    static func stateDescription(saved: Bool, visited: Bool) -> String {
        saved ? (visited ? "Map Stamp · visited" : "Map Stamp · want to go") : "Unsaved place"
    }

    let id: String?
    let title: String
    let symbol: String
    let saved: Bool
    let selected: Bool
    var visited = false
    var contactOpacity: Double = 0
    var browsePhotoDiameter = Self.photoDiameter
    var zoomReveal = 1.0
    var titleOpacity = 1.0

    @Environment(\.accessibilityReduceMotion) private var environmentReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var settled = false
    // Offscreen textures have no onAppear lifecycle; preserve the final head size.
    var rendersStaticFrame = false
    // ImageRenderer has no installed accessibility environment. Supply only
    // its raster preference explicitly; ordinary views keep the system value.
    var rasterReduceMotion: Bool? = nil
    private var reduceMotion: Bool { rasterReduceMotion ?? environmentReduceMotion }

    static let photoSpring = Spring(response: 0.36, dampingRatio: 0.64)

    private let accent = Color(red: 0.53, green: 0.81, blue: 0.99)
    private var rim: Color { Self.rim(for: colorScheme) }

    private static func rim(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.78, green: 0.86, blue: 0.98) : .white
    }

    var body: some View {
        let photo = Self.photo(for: id)?.image
        ZStack(alignment: .bottom) {
            Ellipse().fill(.black.opacity(selected ? 0.17 : 0.10))
                .frame(width: selected ? 13 : 6, height: 2)
                .opacity(1 - contactOpacity)
                .accessibilityHidden(true)
            ZStack {
                Ellipse().fill(.black.opacity(0.30)).frame(width: 14, height: 6)
                Ellipse().strokeBorder(selected ? accent : rim, lineWidth: 1.2)
                    .frame(width: 10, height: 5)
            }
            .offset(y: 2.5)
            .opacity(contactOpacity)
            .accessibilityHidden(true)
            circularFace(photo)
            .scaleEffect(Self.visibleScale(reveal: zoomReveal, reduceMotion: reduceMotion), anchor: .bottom)
            .animation(reduceMotion ? nil : .spring(Self.photoSpring), value: selected)
            if !selected {
                Color.clear.frame(height: 0)
                    .overlay(alignment: .top) {
                        Title(text: title, selected: false).offset(y: 4)
                            .opacity(titleOpacity)
                            .accessibilityHidden(true)
                    }
            }
        }
        .frame(width: selected ? 140 : 94, height: Self.height, alignment: .bottom)
        .contentShape(CityPinHitArea(diameter: hitDiameter(hasPhoto: photo != nil), selected: selected))
        .onAppear { settled = true }
    }

    private func hitDiameter(hasPhoto: Bool) -> CGFloat {
        if selected { return 64 }
        guard hasPhoto else { return 44 }
        return max(44, browsePhotoDiameter + 4)
    }

    var transparentControl: some View {
        Color.clear.frame(width: selected ? 140 : 94, height: Self.height)
            .contentShape(CityPinHitArea(diameter: hitDiameter(hasPhoto: Self.photo(for: id) != nil), selected: selected))
    }

    private func circularFace(_ photo: UIImage?) -> some View {
        let diameter = Self.headDiameter(hasPhoto: photo != nil, selected: selected, browseDiameter: browsePhotoDiameter)
        // An already selected photo can mount when ownership returns from
        // SceneKit. Only actual selection changes animate its diameter below.
        let entrance: CGFloat = reduceMotion || settled || rendersStaticFrame || selected ? 1 : 0.68
        let border = selected ? accent : rim
        return ZStack {
            Circle().fill(border)
                .shadow(color: .black.opacity(0.30), radius: 3, y: 2.5)
            face(photo, diameter: Self.photoDiameter - 5)
                .overlay(Circle().strokeBorder(rim.opacity(0.85), lineWidth: 0.9))
        }
        .frame(width: Self.photoDiameter, height: Self.photoDiameter)
        .overlay(alignment: .bottom) {
            CityPinTip().fill(border).frame(width: 8, height: 5).offset(y: 2.8)
        }
        // Include the tip in the scaled bounds so its bottom stays put.
        .padding(.bottom, 2.8)
        .scaleEffect(entrance, anchor: .bottom)
        .animation(reduceMotion ? nil : .spring(Self.photoSpring), value: settled)
        .scaleEffect(diameter / Self.photoDiameter, anchor: .bottom)
        .animation(reduceMotion ? nil : .spring(Self.photoSpring), value: selected)
        .padding(.bottom, 3.2 - 2 * contactOpacity)
    }

    struct Title: View {
        let text: String
        let selected: Bool
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            Text(text)
                .font(.system(size: selected ? 11 : 10, weight: .bold, design: .rounded))
                .foregroundStyle(CityMVPStyle.ink)
                .lineLimit(selected ? 1 : 2).multilineTextAlignment(.center)
                .padding(.horizontal, selected ? 10 : 1)
                .padding(.vertical, selected ? 5 : 0)
                .background {
                    if selected {
                        Capsule().fill(CityMVPStyle.surface)
                            .overlay(Capsule().strokeBorder(CityPinArtwork.rim(for: colorScheme).opacity(0.6), lineWidth: 0.6))
                            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                    }
                }
                .shadow(color: CityMVPStyle.surface, radius: selected ? 0 : 0.5, x: 0.7, y: 0)
                .shadow(color: CityMVPStyle.surface, radius: selected ? 0 : 0.5, x: -0.7, y: 0)
                .shadow(color: CityMVPStyle.surface, radius: selected ? 0 : 0.5, y: 0.7)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: selected ? 140 : 94)
        }
    }

    private func face(_ photo: UIImage?, diameter: CGFloat) -> some View {
        Group {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [CityMVPStyle.surface, CityMVPStyle.selected],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: id == "way/142113976" ? "building.columns.fill" : symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(CityMVPStyle.ink.opacity(0.80))
                    }
            }
        }
        .frame(width: diameter, height: diameter).clipShape(Circle())
        .overlay(Circle().strokeBorder(.black.opacity(0.10), lineWidth: 0.5))
        .overlay(alignment: .bottomTrailing) {
            if let symbol = Self.savedBadgeSymbol(saved: saved, visited: visited) {
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 13, height: 13).background(Color(red: 0.13, green: 0.35, blue: 0.83), in: Circle())
                    .overlay(Circle().strokeBorder(rim, lineWidth: 1.3)).offset(x: 1, y: 1)
            }
        }
    }
}

/// Keep the photo and its geographic contact in place when neighboring names overlap.
enum CityPinLabelLayout {
    struct Entry {
        let id: String
        let badge: CGRect
        let title: CGRect
        let reveal: Double
        let priority: Int
    }

    static func titleOpacities(_ entries: [Entry], selectedBounds: [CGRect]) -> [String: Double] {
        let ordered = entries.sorted {
            $0.priority == $1.priority ? $0.id < $1.id : $0.priority > $1.priority
        }
        var placed = selectedBounds.map { (rect: $0, reveal: 1.0) }
        var opacities: [String: Double] = [:]
        for entry in ordered {
            var opacity = 1.0
            for other in entries where other.id != entry.id {
                opacity = min(opacity, visibility(of: entry.title, avoiding: other.badge, reveal: other.reveal))
            }
            for other in placed {
                opacity = min(opacity, visibility(of: entry.title, avoiding: other.rect, reveal: other.reveal))
            }
            opacities[entry.id] = opacity
            placed.append((entry.title, opacity * entry.reveal))
        }
        return opacities
    }

    private static func visibility(of title: CGRect, avoiding rect: CGRect, reveal: Double) -> Double {
        let gap = max(rect.minX - title.maxX, title.minX - rect.maxX,
                      rect.minY - title.maxY, title.minY - rect.maxY)
        let fraction = min(1, max(0, gap / 4))
        let eased = fraction * fraction * (3 - 2 * fraction)
        return 1 - reveal * (1 - eased)
    }

    static func badge(at point: CGPoint, diameter: CGFloat, selected: Bool = false) -> CGRect {
        let height = selected ? CityPinArtwork.height : diameter + 5
        return CGRect(x: point.x - diameter / 2, y: point.y - height,
                      width: diameter, height: height + 2)
    }

    static func title(_ text: String, at point: CGPoint, selected: Bool = false, above: Bool = false) -> CGRect {
        let font = UIFont.systemFont(ofSize: selected ? 11 : 10, weight: .bold)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        let width = selected ? min(140, textWidth + 22) : min(94, textWidth + 2)
        let height: CGFloat = selected ? 26 : textWidth > 86 ? 30 : 17
        let y = above ? point.y - CityPinArtwork.height - 5 - height : point.y + 4
        return CGRect(x: point.x - width / 2, y: y, width: width, height: height)
    }
}

private struct CityPinHitArea: Shape {
    var diameter: CGFloat
    var selected: Bool
    nonisolated func path(in rect: CGRect) -> Path {
        let target = CGRect(x: rect.midX - diameter / 2,
                            y: rect.maxY - diameter - 3, width: diameter, height: diameter)
        return selected ? Path(roundedRect: target, cornerRadius: 20) : Path(ellipseIn: target)
    }
}

private struct CityPinBadge: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        return Path { p in
            p.move(to: CGPoint(x: w * 0.32, y: 0))
            p.addLine(to: CGPoint(x: w * 0.68, y: 0))
            p.addQuadCurve(to: CGPoint(x: w, y: h * 0.29), control: CGPoint(x: w, y: 0))
            p.addLine(to: CGPoint(x: w, y: h * 0.61))
            p.addCurve(to: CGPoint(x: w * 0.5, y: h), control1: CGPoint(x: w, y: h * 0.83), control2: CGPoint(x: w * 0.72, y: h * 0.90))
            p.addCurve(to: CGPoint(x: 0, y: h * 0.61), control1: CGPoint(x: w * 0.28, y: h * 0.90), control2: CGPoint(x: 0, y: h * 0.83))
            p.addLine(to: CGPoint(x: 0, y: h * 0.29))
            p.addQuadCurve(to: CGPoint(x: w * 0.32, y: 0), control: .zero)
            p.closeSubpath()
        }
    }
}

private struct CityPinTip: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.midX - 1, y: rect.minY + 1))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX + 1, y: rect.minY + 1))
            p.closeSubpath()
        }
    }
}
#endif
