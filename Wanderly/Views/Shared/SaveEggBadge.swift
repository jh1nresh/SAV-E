import SwiftUI

struct SaveEggBadge: View {
    enum State {
        case clue
        case ready
        case hatched(PlaceCategory)
    }

    let state: State
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            EggShape()
                .fill(fillColor)
                .overlay(
                    EggShape()
                        .stroke(Color.saveNotebookLine.opacity(0.9), lineWidth: 1.3)
                )

            icon
                .font(.system(size: size * 0.34, weight: .black))
                .foregroundColor(iconColor)

            if case .hatched = state {
                crack
            }
        }
        .frame(width: size, height: size * 1.13)
        .accessibilityLabel(accessibilityLabel)
    }

    private var icon: some View {
        Group {
            switch state {
            case .clue:
                Image(systemName: "sparkles")
            case .ready:
                Image(systemName: "seal.fill")
            case .hatched(let category):
                Image(systemName: category.iconName)
            }
        }
    }

    private var fillColor: Color {
        switch state {
        case .clue:
            return .saveNotebookPage
        case .ready:
            return .saveHoney
        case .hatched(let category):
            return Color.saveStampColor(for: category)
        }
    }

    private var iconColor: Color {
        switch state {
        case .clue:
            return .saveInk
        case .ready:
            return .saveInk
        case .hatched(let category):
            return Color.saveStampForeground(for: category)
        }
    }

    private var crack: some View {
        Path { path in
            path.move(to: CGPoint(x: size * 0.26, y: size * 0.44))
            path.addLine(to: CGPoint(x: size * 0.40, y: size * 0.54))
            path.addLine(to: CGPoint(x: size * 0.50, y: size * 0.43))
            path.addLine(to: CGPoint(x: size * 0.64, y: size * 0.55))
            path.addLine(to: CGPoint(x: size * 0.76, y: size * 0.45))
        }
        .stroke(Color.saveNotebookPage.opacity(0.78), style: StrokeStyle(lineWidth: max(1.4, size * 0.045), lineCap: .round, lineJoin: .round))
    }

    private var accessibilityLabel: String {
        switch state {
        case .clue:
            return "Clue egg"
        case .ready:
            return "Ready to hatch"
        case .hatched:
            return "Hatched memory card"
        }
    }
}

private struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: rect.midX, y: rect.minY + h * 0.04))
        path.addCurve(
            to: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.58),
            control1: CGPoint(x: rect.minX + w * 0.20, y: rect.minY + h * 0.10),
            control2: CGPoint(x: rect.minX + w * 0.05, y: rect.minY + h * 0.32)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY - h * 0.02),
            control1: CGPoint(x: rect.minX + w * 0.10, y: rect.minY + h * 0.86),
            control2: CGPoint(x: rect.minX + w * 0.30, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - w * 0.08, y: rect.minY + h * 0.58),
            control1: CGPoint(x: rect.maxX - w * 0.30, y: rect.maxY),
            control2: CGPoint(x: rect.maxX - w * 0.10, y: rect.minY + h * 0.86)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + h * 0.04),
            control1: CGPoint(x: rect.maxX - w * 0.05, y: rect.minY + h * 0.32),
            control2: CGPoint(x: rect.maxX - w * 0.20, y: rect.minY + h * 0.10)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    HStack(spacing: 18) {
        SaveEggBadge(state: .clue)
        SaveEggBadge(state: .ready)
        SaveEggBadge(state: .hatched(.food))
    }
    .padding()
    .background(SaveDottedBackground())
}
