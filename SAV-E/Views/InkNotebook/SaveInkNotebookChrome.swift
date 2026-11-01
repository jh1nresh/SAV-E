import CoreText
import SwiftUI
import UIKit

enum SaveInkPalette {
    static let ink = Color(hex: "1E1D1B")
    static let inkSub = Color(hex: "5F5B55")
    static let paper = Color(hex: "FAF9F4")
    static let card = Color(hex: "FFFFFF")
    /// sRGB. `UIColor(red:green:blue:alpha:)` is extended sRGB, and the still
    /// renderer uses a standard-range bitmap so the pixels stay `#B8481F`.
    static let accent = Color(hex: "B8481F")
    static let unverifiedLine = Color(hex: "6B6862")
    static let unverifiedFill = Color(hex: "EFECE6")
    static let scrim = Color(hex: "1E1D1B").opacity(0.38)
    static let mapRoad = Color(hex: "D8D2C7")
    static let emptyLine = Color(hex: "C9C4BB")
    static let onAccent = Color.white
}

enum SaveInkType {
    static let faceName = "Iansui-Ink"
    private static let register: Void = {
        let candidates = [
            Bundle.main.url(forResource: "Iansui-Ink", withExtension: "ttf", subdirectory: "DisplayFont"),
            Bundle.main.url(forResource: "Iansui-Ink", withExtension: "ttf"),
        ]
        if let url = candidates.compactMap({ $0 }).first {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func font(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        _ = register
        let name = UIFont(name: faceName, size: size) != nil ? faceName : "Iansui-Regular"
        return Font.custom(name, size: size, relativeTo: style)
    }

    static var pageTitle: Font { font(30, relativeTo: .title) }
    static var brand: Font { font(44, relativeTo: .largeTitle) }
    static var sheetTitle: Font { font(26, relativeTo: .title2) }
    static var subpageTitle: Font { font(24, relativeTo: .title2) }
    static var shop: Font { font(23, relativeTo: .title3) }
    static var friendShop: Font { font(21, relativeTo: .title3) }
    static var button: Font { font(24, relativeTo: .title2) }
    static var secondaryButton: Font { font(19, relativeTo: .body) }
    static var body: Font { font(16, relativeTo: .body) }
    static var aux: Font { font(14, relativeTo: .footnote) }
    static var minimum: Font { font(13, relativeTo: .caption) }
}

enum SaveInkRough {
    nonisolated static func jitter(seed: Int, index: Int, amplitude: CGFloat) -> CGFloat {
        var value = UInt64(bitPattern: Int64(seed &+ index &* 374761393))
        value = (value ^ (value >> 13)) &* 1274126177
        value ^= value >> 16
        let unit = Double(value % 2001) / 1000 - 1
        return CGFloat(unit) * amplitude
    }

    nonisolated static func quads(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count >= 3 else { return path }
        func mid(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
            CGPoint(x: (lhs.x + rhs.x) / 2, y: (lhs.y + rhs.y) / 2)
        }
        path.move(to: mid(points[points.count - 1], points[0]))
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(to: mid(current, next), control: current)
        }
        path.closeSubpath()
        return path
    }

    nonisolated static func roundedRect(
        _ rect: CGRect,
        radius: CGFloat,
        step: CGFloat,
        seed: Int,
        amplitude: CGFloat
    ) -> [CGPoint] {
        let radius = min(max(radius, 0), min(rect.width, rect.height) / 2)
        var samples: [(CGPoint, CGPoint)] = []
        func addLine(from: CGPoint, to: CGPoint, normal: CGPoint) {
            let length = max(hypot(to.x - from.x, to.y - from.y), 0.001)
            let count = max(Int(length / step), 1)
            for index in 0..<count {
                let t = CGFloat(index) / CGFloat(count)
                samples.append((
                    CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t),
                    normal
                ))
            }
        }
        func addArc(center: CGPoint, start: CGFloat, end: CGFloat) {
            let sweep = end - start
            let length = abs(sweep) * radius
            let count = max(Int(length / step), 2)
            for index in 0..<count {
                let angle = start + sweep * CGFloat(index) / CGFloat(count)
                samples.append((
                    CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius),
                    CGPoint(x: cos(angle), y: sin(angle))
                ))
            }
        }
        let minX = rect.minX + radius
        let maxX = rect.maxX - radius
        let minY = rect.minY + radius
        let maxY = rect.maxY - radius
        addLine(from: CGPoint(x: minX, y: rect.minY), to: CGPoint(x: maxX, y: rect.minY), normal: CGPoint(x: 0, y: -1))
        addArc(center: CGPoint(x: maxX, y: minY), start: -.pi / 2, end: 0)
        addLine(from: CGPoint(x: rect.maxX, y: minY), to: CGPoint(x: rect.maxX, y: maxY), normal: CGPoint(x: 1, y: 0))
        addArc(center: CGPoint(x: maxX, y: maxY), start: 0, end: .pi / 2)
        addLine(from: CGPoint(x: maxX, y: rect.maxY), to: CGPoint(x: minX, y: rect.maxY), normal: CGPoint(x: 0, y: 1))
        addArc(center: CGPoint(x: minX, y: maxY), start: .pi / 2, end: .pi)
        addLine(from: CGPoint(x: rect.minX, y: maxY), to: CGPoint(x: rect.minX, y: minY), normal: CGPoint(x: -1, y: 0))
        addArc(center: CGPoint(x: minX, y: minY), start: .pi, end: .pi * 1.5)
        return samples.enumerated().map { index, sample in
            let offset = jitter(seed: seed, index: index, amplitude: amplitude)
            return CGPoint(x: sample.0.x + sample.1.x * offset, y: sample.0.y + sample.1.y * offset)
        }
    }

    nonisolated static func circle(_ rect: CGRect, seed: Int, amplitude: CGFloat) -> [CGPoint] {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let count = max(Int((2 * CGFloat.pi * radius) / 7), 12)
        return (0..<count).map { index in
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            let adjusted = radius + jitter(seed: seed, index: index, amplitude: amplitude)
            return CGPoint(x: center.x + cos(angle) * adjusted, y: center.y + sin(angle) * adjusted)
        }
    }
}

struct SaveInkRoughRoundedRect: Shape {
    var cornerRadius: CGFloat
    var seed: Int
    var amplitude: CGFloat = 0.8
    var step: CGFloat = 7

    nonisolated func path(in rect: CGRect) -> Path {
        SaveInkRough.quads(
            SaveInkRough.roundedRect(rect, radius: cornerRadius, step: step, seed: seed, amplitude: amplitude)
        )
    }
}

struct SaveInkRoughCircle: Shape {
    var seed: Int
    var amplitude: CGFloat = 0.55

    nonisolated func path(in rect: CGRect) -> Path {
        SaveInkRough.quads(SaveInkRough.circle(rect, seed: seed, amplitude: amplitude))
    }
}

struct SaveInkRoughFrame<Content: View>: View {
    var seed: Int
    var cornerRadius: CGFloat = 18
    var lineWidth: CGFloat = 2
    var dashed: Bool = false
    var dash: [CGFloat] = [6, 5]
    var stroke: Color = SaveInkPalette.ink
    var fill: Color = SaveInkPalette.card
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = SaveInkRoughRoundedRect(cornerRadius: cornerRadius, seed: seed)
        content()
            .padding(padding)
            .background(shape.fill(fill))
            .overlay(
                shape.stroke(
                    stroke,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: dashed ? dash : []
                    )
                )
            )
    }
}

struct SaveInkCircleButton: View {
    var label: String
    var identifier: String
    var personIcon: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if personIcon {
                    SaveInkPersonIcon()
                        .frame(width: 22, height: 22)
                } else {
                    Text(label)
                        .font(SaveInkType.font(22, relativeTo: .title3))
                }
            }
            .foregroundStyle(SaveInkPalette.ink)
            .frame(width: 46, height: 46)
            .background(
                SaveInkRoughCircle(seed: SaveInkSeed.of(identifier), amplitude: 0.4)
                    .stroke(SaveInkPalette.ink, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .frame(minWidth: 46, minHeight: 46)
    }
}

struct SaveInkOutlineButton: View {
    var title: String
    var identifier: String
    var compact: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(compact ? SaveInkType.secondaryButton : SaveInkType.button)
                .tracking(compact ? 1 : 3)
                .foregroundStyle(SaveInkPalette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 54 : 66)
                .background(
                    SaveInkRoughRoundedRect(cornerRadius: 24, seed: SaveInkSeed.of(identifier))
                        .fill(SaveInkPalette.card)
                )
                .overlay(
                    SaveInkRoughRoundedRect(cornerRadius: 24, seed: SaveInkSeed.of(identifier))
                        .stroke(SaveInkPalette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .frame(minHeight: 44)
    }
}

private struct SaveInkScreenshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var saveInkScreenshot: Bool {
        get { self[SaveInkScreenshotKey.self] }
        set { self[SaveInkScreenshotKey.self] = newValue }
    }
}

/// Screenshot stand-in. A live `TextField` paints a yellow system field.
struct SaveInkLineField: View {
    var placeholder: String
    @Binding var text: String
    var identifier: String
    var minHeight: CGFloat = 54
    @Environment(\.saveInkScreenshot) private var screenshot

    var body: some View {
        Group {
            if screenshot {
                Text(text.isEmpty ? placeholder : text)
                    .font(SaveInkType.body)
                    .foregroundStyle(text.isEmpty ? SaveInkPalette.inkSub : SaveInkPalette.ink)
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            } else {
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(SaveInkType.body)
                    .foregroundStyle(SaveInkPalette.ink)
                    .lineLimit(2...4)
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            }
        }
        .padding(16)
        .background(SaveInkPalette.card)
        .overlay(
            SaveInkRoughRoundedRect(cornerRadius: 18, seed: SaveInkSeed.of(identifier))
                .stroke(SaveInkPalette.ink, lineWidth: 2)
        )
        .accessibilityIdentifier(identifier)
    }
}

/// The only accent control in the ink notebook.
struct SaveInkArriveButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SaveInkPinIcon()
                    .frame(width: 18, height: 22)
                Text("我到了")
                    .font(SaveInkType.button)
                    .tracking(3)
            }
            .foregroundStyle(SaveInkPalette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(
                SaveInkRoughRoundedRect(cornerRadius: 24, seed: SaveInkSeed.of("arrive"), amplitude: 0.5)
                    .fill(SaveInkPalette.accent)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ink.arrived")
        .frame(minHeight: 44)
    }
}

struct SaveInkBackButton: View {
    var identifier: String = "ink.back"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("←")
                .font(SaveInkType.font(22, relativeTo: .title3))
                .foregroundStyle(SaveInkPalette.ink)
                .frame(width: 46, height: 46)
                .background(
                    SaveInkRoughCircle(seed: 11, amplitude: 0.35)
                        .stroke(SaveInkPalette.ink, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel("返回")
        .frame(minWidth: 44, minHeight: 44)
    }
}

struct SaveInkPageTitle: View {
    var title: String

    var body: some View {
        HStack(spacing: 12) {
            SaveInkBackButton(action: action)
            Text(title)
                .font(SaveInkType.subpageTitle)
                .foregroundStyle(SaveInkPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    var action: () -> Void = {}

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

enum SaveInkStampKind: Equatable {
    case verified
    case unverified
    case empty
    case notYet
    case miniVerified
    case miniUnverified
}

struct SaveInkStampMark: View {
    var kind: SaveInkStampKind
    var name: String = ""
    var date: String = ""
    var seed: Int

    var body: some View {
        switch kind {
        case .verified:
            roundStamp(line: 4, inner: 1.6, symbol: "✓ 已驗證", fill: .clear, stroke: SaveInkPalette.ink, dashed: false)
        case .unverified:
            squareStamp
        case .empty:
            emptyStamp
        case .notYet:
            notYetStamp
        case .miniVerified:
            miniVerifiedStamp
        case .miniUnverified:
            miniUnverifiedStamp
        }
    }

    private func roundStamp(
        line: CGFloat,
        inner: CGFloat,
        symbol: String,
        fill: Color,
        stroke: Color,
        dashed: Bool
    ) -> some View {
        ZStack {
            SaveInkRoughCircle(seed: seed, amplitude: 0.45)
                .fill(fill)
            SaveInkRoughCircle(seed: seed, amplitude: 0.45)
                .stroke(stroke, style: StrokeStyle(lineWidth: line, lineCap: .round, dash: dashed ? [6, 5] : []))
            SaveInkInsetCircle(amount: 10, seed: seed &+ 3)
                .stroke(stroke, style: StrokeStyle(lineWidth: inner, lineCap: .round))
            VStack(spacing: 2) {
                Text(symbol)
                    .font(SaveInkType.minimum)
                if !name.isEmpty {
                    Text(name)
                        .font(SaveInkType.aux)
                        .multilineTextAlignment(.center)
                }
                if !date.isEmpty {
                    Text(date)
                        .font(SaveInkType.minimum)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(SaveInkPalette.ink)
            .padding(16)
        }
    }

    private var squareStamp: some View {
        SaveInkRoughFrame(
            seed: seed,
            cornerRadius: 22,
            lineWidth: 3,
            dashed: true,
            dash: [9, 7],
            stroke: SaveInkPalette.unverifiedLine,
            fill: SaveInkPalette.unverifiedFill,
            padding: 10
        ) {
            VStack(spacing: 2) {
                Text("△ 未驗證")
                    .font(SaveInkType.minimum)
                Text(name)
                    .font(SaveInkType.aux)
                if !date.isEmpty {
                    Text(date)
                        .font(SaveInkType.minimum)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(SaveInkPalette.inkSub)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyStamp: some View {
        ZStack {
            SaveInkRoughCircle(seed: seed, amplitude: 0.3)
                .stroke(SaveInkPalette.emptyLine, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1.5, 4]))
            Text("還沒蓋")
                .font(SaveInkType.aux)
                .foregroundStyle(SaveInkPalette.inkSub)
        }
    }

    private var notYetStamp: some View {
        ZStack {
            SaveInkRoughCircle(seed: seed, amplitude: 0.7)
                .stroke(SaveInkPalette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 6]))
            Text("還沒蓋章")
                .font(SaveInkType.aux)
                .foregroundStyle(SaveInkPalette.ink)
        }
    }

    private var miniVerifiedStamp: some View {
        ZStack {
            SaveInkRoughCircle(seed: seed, amplitude: 0.3)
                .stroke(SaveInkPalette.ink, lineWidth: 3)
            SaveInkInsetCircle(amount: 6, seed: seed &+ 1)
                .stroke(SaveInkPalette.ink, lineWidth: 1.4)
            Text("✓")
                .font(SaveInkType.aux)
                .foregroundStyle(SaveInkPalette.ink)
        }
        .frame(width: 52, height: 52)
        .accessibilityLabel("已驗證")
    }

    private var miniUnverifiedStamp: some View {
        SaveInkRoughFrame(
            seed: seed,
            cornerRadius: 10,
            lineWidth: 2.4,
            dashed: true,
            dash: [6, 5],
            stroke: SaveInkPalette.unverifiedLine,
            fill: SaveInkPalette.unverifiedFill
        ) {
            Text("△")
                .font(SaveInkType.aux)
                .foregroundStyle(SaveInkPalette.inkSub)
                .frame(width: 52, height: 52)
        }
        .frame(width: 52, height: 52)
        .accessibilityLabel("未驗證造訪")
    }
}

struct SaveInkInsetCircle: Shape {
    var amount: CGFloat
    var seed: Int
    nonisolated func path(in rect: CGRect) -> Path {
        SaveInkRoughCircle(seed: seed, amplitude: 0.3).path(in: rect.insetBy(dx: amount, dy: amount))
    }
}

struct SaveInkBadge: View {
    var text: String
    var verified: Bool

    var body: some View {
        Text(text)
            .font(SaveInkType.minimum)
            .foregroundStyle(verified ? SaveInkPalette.ink : SaveInkPalette.inkSub)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(
                Capsule().fill(verified ? Color.clear : SaveInkPalette.unverifiedFill)
            )
            .overlay(
                Capsule().stroke(
                    verified ? SaveInkPalette.ink : SaveInkPalette.unverifiedLine,
                    style: StrokeStyle(lineWidth: 1.6, dash: verified ? [] : [4, 3])
                )
            )
    }
}

struct SaveInkPinIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            Path { path in
                path.addEllipse(in: CGRect(x: width * 0.18, y: 0, width: width * 0.64, height: width * 0.64))
                path.move(to: CGPoint(x: width * 0.5, y: width * 0.58))
                path.addLine(to: CGPoint(x: width * 0.5, y: height))
            }
            .stroke(SaveInkPalette.onAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

struct SaveInkPersonIcon: View {
    var lineWidth: CGFloat = 1.7
    var color: Color = SaveInkPalette.ink

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Path { path in
                path.addEllipse(in: CGRect(x: side * 0.3, y: side * 0.08, width: side * 0.4, height: side * 0.4))
                path.move(to: CGPoint(x: side * 0.16, y: side * 0.92))
                path.addQuadCurve(
                    to: CGPoint(x: side * 0.84, y: side * 0.92),
                    control: CGPoint(x: side * 0.5, y: side * 0.48)
                )
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

struct SaveInkLockIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let unit = side / 24
            Path { path in
                path.move(to: CGPoint(x: 7 * unit, y: 11 * unit))
                path.addQuadCurve(
                    to: CGPoint(x: 17 * unit, y: 11 * unit),
                    control: CGPoint(x: 12 * unit, y: 2 * unit)
                )
                path.addRoundedRect(
                    in: CGRect(x: 4 * unit, y: 11 * unit, width: 16 * unit, height: 10 * unit),
                    cornerSize: CGSize(width: 2 * unit, height: 2 * unit)
                )
            }
            .stroke(SaveInkPalette.inkSub, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

struct SaveInkWalkMap: View {
    var label: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SaveInkPalette.card
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                Path { path in
                    path.move(to: CGPoint(x: width * 0.05, y: height * 0.28))
                    path.addLine(to: CGPoint(x: width * 0.95, y: height * 0.62))
                    path.move(to: CGPoint(x: width * 0.42, y: height * 0.08))
                    path.addLine(to: CGPoint(x: width * 0.7, y: height * 0.95))
                }
                .stroke(SaveInkPalette.mapRoad, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                Path { path in
                    path.move(to: CGPoint(x: width * 0.22, y: height * 0.72))
                    path.addLine(to: CGPoint(x: width * 0.68, y: height * 0.28))
                }
                .stroke(
                    SaveInkPalette.ink,
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [5, 5])
                )
                Circle()
                    .stroke(SaveInkPalette.ink, lineWidth: 2)
                    .background(Circle().fill(SaveInkPalette.card))
                    .frame(width: 16, height: 16)
                    .position(x: width * 0.22, y: height * 0.72)
                SaveInkMapPin()
                    .frame(width: 22, height: 30)
                    .position(x: width * 0.68, y: height * 0.24)
            }
            Text(label)
                .font(SaveInkType.minimum)
                .foregroundStyle(SaveInkPalette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(SaveInkPalette.paper))
                .padding(12)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            SaveInkRoughRoundedRect(cornerRadius: 18, seed: 42, amplitude: 0.45)
                .stroke(SaveInkPalette.ink, lineWidth: 2)
        )
        .accessibilityLabel("步行地圖")
    }
}

private struct SaveInkMapPin: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Path { path in
                path.addEllipse(in: CGRect(x: width * 0.12, y: 0, width: width * 0.76, height: width * 0.76))
                path.move(to: CGPoint(x: width * 0.5, y: width * 0.7))
                path.addLine(to: CGPoint(x: width * 0.5, y: proxy.size.height))
            }
            .stroke(SaveInkPalette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}
