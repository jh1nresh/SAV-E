import SwiftUI

struct MemoMark: View {
    let size: CGFloat

    var body: some View {
        Image("MemoMascot")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Memo")
    }
}

struct BrandHeader<Trailing: View>: View {
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 9) {
            MemoMark(size: 31)
            Text("SAV-E")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(AtlasPalette.forest)

            Spacer()
            trailing()
        }
        .frame(height: 50)
        .padding(.horizontal, 18)
    }
}

struct AtlasTabBar<Item: Identifiable & Equatable>: View {
    let items: [Item]
    let selection: Item
    let title: KeyPath<Item, String>
    let icon: KeyPath<Item, String>
    let onSelect: (Item) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item[keyPath: icon])
                            .font(.system(size: 18, weight: .semibold))
                        Text(item[keyPath: title])
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selection == item ? AtlasPalette.forest : AtlasPalette.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        if selection == item {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AtlasPalette.mint.opacity(0.80))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("prototype.tab.\(item[keyPath: title].lowercased())")
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(AtlasPalette.ink.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: AtlasPalette.ink.opacity(0.07), radius: 12, y: 4)
        .padding(.horizontal, 14)
        .padding(.top, 5)
        .padding(.bottom, 5)
        .background(AtlasPalette.canvas.opacity(0.90))
    }
}

struct AtlasMapArt: View {
    enum Variant {
        case home
        case full
    }

    let variant: Variant

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Canvas { context, canvas in
                    context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(AtlasPalette.paper))

                    drawLand(in: &context, size: canvas)
                    drawRiver(in: &context, size: canvas)
                    drawRoads(in: &context, size: canvas)
                    drawBlocks(in: &context, size: canvas)
                    if variant == .full {
                        drawRoute(in: &context, size: canvas)
                    }
                }

                atlasLabels(size: size)
                atlasLandmarks(size: size)
                atlasPins(size: size)
            }
            .clipShape(RoundedRectangle(cornerRadius: variant == .home ? 22 : 0, style: .continuous))
            .overlay {
                if variant == .home {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AtlasPalette.forest.opacity(0.14), lineWidth: 1)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Illustrated Tokyo atlas")
    }

    private func drawLand(in context: inout GraphicsContext, size: CGSize) {
        var park = Path()
        park.move(to: CGPoint(x: size.width * 0.54, y: 0))
        park.addCurve(
            to: CGPoint(x: size.width * 0.92, y: size.height),
            control1: CGPoint(x: size.width * 0.74, y: size.height * 0.22),
            control2: CGPoint(x: size.width * 0.58, y: size.height * 0.72)
        )
        park.addLine(to: CGPoint(x: size.width, y: size.height))
        park.addLine(to: CGPoint(x: size.width, y: 0))
        park.closeSubpath()
        context.fill(park, with: .color(AtlasPalette.leaf.opacity(0.43)))
    }

    private func drawRiver(in context: inout GraphicsContext, size: CGSize) {
        var river = Path()
        river.move(to: CGPoint(x: size.width * 0.15, y: -12))
        river.addCurve(
            to: CGPoint(x: size.width * 0.37, y: size.height + 12),
            control1: CGPoint(x: size.width * 0.38, y: size.height * 0.25),
            control2: CGPoint(x: size.width * 0.10, y: size.height * 0.70)
        )
        context.stroke(river, with: .color(AtlasPalette.water), lineWidth: variant == .home ? 34 : 48)
        context.stroke(river, with: .color(.white.opacity(0.65)), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
    }

    private func drawRoads(in context: inout GraphicsContext, size: CGSize) {
        let roadColor = Color.white.opacity(0.92)
        for fraction in [0.12, 0.31, 0.52, 0.74, 0.90] {
            var horizontal = Path()
            horizontal.move(to: CGPoint(x: -20, y: size.height * fraction))
            horizontal.addCurve(
                to: CGPoint(x: size.width + 20, y: size.height * (fraction + 0.04)),
                control1: CGPoint(x: size.width * 0.35, y: size.height * (fraction - 0.04)),
                control2: CGPoint(x: size.width * 0.67, y: size.height * (fraction + 0.08))
            )
            context.stroke(horizontal, with: .color(roadColor), lineWidth: 10)
            context.stroke(horizontal, with: .color(AtlasPalette.ink.opacity(0.10)), lineWidth: 1)
        }

        for fraction in [0.08, 0.44, 0.68, 0.88] {
            var vertical = Path()
            vertical.move(to: CGPoint(x: size.width * fraction, y: -20))
            vertical.addCurve(
                to: CGPoint(x: size.width * (fraction + 0.05), y: size.height + 20),
                control1: CGPoint(x: size.width * (fraction - 0.06), y: size.height * 0.35),
                control2: CGPoint(x: size.width * (fraction + 0.10), y: size.height * 0.64)
            )
            context.stroke(vertical, with: .color(roadColor), lineWidth: 8)
            context.stroke(vertical, with: .color(AtlasPalette.ink.opacity(0.10)), lineWidth: 1)
        }
    }

    private func drawBlocks(in context: inout GraphicsContext, size: CGSize) {
        let blocks: [(CGFloat, CGFloat, CGFloat, CGFloat, Color)] = [
            (0.04, 0.17, 0.16, 0.10, AtlasPalette.lavender),
            (0.40, 0.08, 0.18, 0.13, AtlasPalette.sky),
            (0.64, 0.27, 0.23, 0.12, AtlasPalette.kraft),
            (0.08, 0.58, 0.19, 0.14, AtlasPalette.mint),
            (0.46, 0.66, 0.20, 0.12, AtlasPalette.lavender),
            (0.74, 0.78, 0.16, 0.11, AtlasPalette.sky),
        ]
        for block in blocks {
            let rect = CGRect(
                x: size.width * block.0,
                y: size.height * block.1,
                width: size.width * block.2,
                height: size.height * block.3
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: 8),
                with: .color(block.4.opacity(0.50))
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 8),
                with: .color(AtlasPalette.ink.opacity(0.09)),
                lineWidth: 1
            )
        }
    }

    private func drawRoute(in context: inout GraphicsContext, size: CGSize) {
        var route = Path()
        route.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.75))
        route.addCurve(
            to: CGPoint(x: size.width * 0.75, y: size.height * 0.21),
            control1: CGPoint(x: size.width * 0.57, y: size.height * 0.91),
            control2: CGPoint(x: size.width * 0.40, y: size.height * 0.38)
        )
        context.stroke(
            route,
            with: .color(AtlasPalette.routeInk),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5])
        )
    }

    @ViewBuilder
    private func atlasLabels(size: CGSize) -> some View {
        Group {
            AtlasLabel(text: "SHIBUYA")
                .position(x: size.width * 0.22, y: size.height * 0.46)
            AtlasLabel(text: "CHUO")
                .position(x: size.width * 0.70, y: size.height * 0.48)
            AtlasLabel(text: "SHINJUKU")
                .position(x: size.width * 0.69, y: size.height * 0.08)
        }
    }

    @ViewBuilder
    private func atlasLandmarks(size: CGSize) -> some View {
        AtlasLandmark(icon: "building.columns.fill", tint: AtlasPalette.coral)
            .position(x: size.width * 0.75, y: size.height * 0.15)
        AtlasLandmark(icon: "tree.fill", tint: AtlasPalette.forest)
            .position(x: size.width * 0.81, y: size.height * 0.62)
        AtlasLandmark(icon: "tram.fill", tint: AtlasPalette.sky)
            .position(x: size.width * 0.43, y: size.height * 0.30)
    }

    @ViewBuilder
    private func atlasPins(size: CGSize) -> some View {
        if variant == .home {
            AtlasSavedPin()
                .position(x: size.width * 0.20, y: size.height * 0.24)
            AtlasSavedPin()
                .position(x: size.width * 0.68, y: size.height * 0.39)
        } else {
            AtlasSavedPin()
                .position(x: size.width * 0.20, y: size.height * 0.22)
            AtlasRoutePin(number: 1)
                .position(x: size.width * 0.25, y: size.height * 0.74)
            AtlasRoutePin(number: 2)
                .position(x: size.width * 0.47, y: size.height * 0.55)
            AtlasRoutePin(number: 3)
                .position(x: size.width * 0.72, y: size.height * 0.29)
            AtlasSavedPin()
                .position(x: size.width * 0.80, y: size.height * 0.50)
        }
    }
}

private struct AtlasLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.8)
            .foregroundStyle(AtlasPalette.forest.opacity(0.54))
    }
}

private struct AtlasLandmark: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(AtlasPalette.paper.opacity(0.90), in: Circle())
            .overlay { Circle().stroke(AtlasPalette.ink.opacity(0.12), lineWidth: 1) }
    }
}

struct AtlasSavedPin: View {
    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(AtlasPalette.forest, in: Circle())
            .overlay { Circle().stroke(AtlasPalette.paper, lineWidth: 3) }
            .shadow(color: AtlasPalette.ink.opacity(0.08), radius: 4, y: 2)
    }
}

struct AtlasRoutePin: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 31, height: 31)
            .background(AtlasPalette.coral, in: Circle())
            .overlay { Circle().stroke(AtlasPalette.paper, lineWidth: 3) }
    }
}
