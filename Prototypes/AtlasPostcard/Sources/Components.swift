import SwiftUI

struct MemoMark: View {
    let size: CGFloat

    var body: some View {
        Image("MemoMascot")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(1.6)
            .accessibilityLabel("Memo")
    }
}

struct BrandHeader<Trailing: View>: View {
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 9) {
            MemoMark(size: 40)

            Text("SAV-E")
                .font(AtlasType.strong(24))
                .tracking(1.1)
                .foregroundStyle(AtlasPalette.forest)

            Spacer()
            trailing()
        }
        .padding(.horizontal, 11)
    }
}

struct AtlasTabBar<Item: Identifiable & Equatable>: View {
    let items: [Item]
    let selection: Item
    let title: KeyPath<Item, String>
    let icon: KeyPath<Item, String>
    let accessibilityPrefix: String
    let onSelect: (Item) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item[keyPath: icon])
                            .font(.system(size: 23, weight: .regular))
                            .frame(height: 27)

                        Text(item[keyPath: title])
                            .font(AtlasType.display(12))
                    }
                    .foregroundStyle(AtlasPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background {
                        if selection == item {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(AtlasPalette.mint.opacity(0.82))
                                .frame(width: 90, height: 64)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item[keyPath: title])
                .accessibilityIdentifier(
                    "prototype.\(accessibilityPrefix).\(item[keyPath: title].lowercased())"
                )
            }
        }
        .padding(.horizontal, 4)
        .frame(width: 402, height: 76)
        .background(AtlasPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(AtlasPalette.line.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: AtlasPalette.ink.opacity(0.035), radius: 5, y: 1)
    }
}

struct RoundStamp: View {
    enum Style {
        case mapStamp
        case tripStop
    }

    let text: String
    let style: Style

    var body: some View {
        Group {
            switch style {
            case .mapStamp:
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AtlasPalette.forest)
                    .frame(width: 35, height: 35)
                    .background(AtlasPalette.mint, in: Circle())
            case .tripStop:
                Text(text)
                    .font(AtlasType.strong(17))
                    .foregroundStyle(AtlasPalette.ink)
                    .frame(width: 38, height: 38)
                    .background(AtlasPalette.coral.opacity(0.90), in: Circle())
                    .overlay {
                        Circle().stroke(AtlasPalette.coral, lineWidth: 1)
                    }
            }
        }
    }
}

struct ScallopedRectangle: Shape {
    var depth: CGFloat = 4
    var pitch: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = pitch / 2
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY + depth))

        var x = rect.minX + radius
        while x < rect.maxX - radius {
            path.addQuadCurve(
                to: CGPoint(x: x + pitch, y: rect.minY + depth),
                control: CGPoint(x: x + radius, y: rect.minY - depth)
            )
            x += pitch
        }

        path.addLine(to: CGPoint(x: rect.maxX - depth, y: rect.minY + radius))
        var y = rect.minY + radius
        while y < rect.maxY - radius {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - depth, y: y + pitch),
                control: CGPoint(x: rect.maxX + depth, y: y + radius)
            )
            y += pitch
        }

        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY - depth))
        x = rect.maxX - radius
        while x > rect.minX + radius {
            path.addQuadCurve(
                to: CGPoint(x: x - pitch, y: rect.maxY - depth),
                control: CGPoint(x: x - radius, y: rect.maxY + depth)
            )
            x -= pitch
        }

        path.addLine(to: CGPoint(x: rect.minX + depth, y: rect.maxY - radius))
        y = rect.maxY - radius
        while y > rect.minY + radius {
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + depth, y: y - pitch),
                control: CGPoint(x: rect.minX - depth, y: y - radius)
            )
            y -= pitch
        }

        path.closeSubpath()
        return path
    }
}

struct PerforatedMedallion: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 21, weight: .regular))
            .foregroundStyle(AtlasPalette.ink)
            .frame(width: 52, height: 52)
            .background(tint, in: SealShape())
            .overlay {
                SealShape()
                    .stroke(AtlasPalette.ink.opacity(0.16), lineWidth: 1)
            }
    }
}

private struct SealShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2 - 2
        let steps = 128
        var path = Path()

        for step in 0...steps {
            let angle = CGFloat(step) / CGFloat(steps) * .pi * 2 - .pi / 2
            let radius = baseRadius + cos(angle * 16) * 2
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
