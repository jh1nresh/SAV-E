import SwiftUI

struct SavePetAvatar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let preset: SavePetPreset
    let stage: SavePetStage
    var size: CGFloat = 84
    var animates = true

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            stageBackdrop

            Image(preset.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: mascotSize, height: mascotSize)
                .scaleEffect(isAnimating ? animatedScale : 1)
                .rotationEffect(.degrees(isAnimating ? animatedRotation : 0))
                .offset(y: mascotOffset + (isAnimating ? animatedOffset : 0))
                .shadow(color: Color.saveInk.opacity(0.16), radius: 0, x: 0, y: size * 0.055)

            stageForeground
            presetBadge
        }
        .frame(width: size, height: size)
        .animation(SaveTheme.Motion.standardSpring, value: stage)
        .onAppear(perform: updateMotion)
        .onDisappear { isAnimating = false }
        .onChange(of: reduceMotion) { _, _ in updateMotion() }
        .onChange(of: animates) { _, _ in updateMotion() }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var stageBackdrop: some View {
        switch stage {
        case .hatchling:
            Circle()
                .fill(Color.saveCream.opacity(0.98))
                .overlay(Circle().stroke(accentColor.opacity(0.72), lineWidth: max(1.5, size * 0.025)))
                .frame(width: size * 0.76, height: size * 0.76)
                .offset(y: size * 0.06)
        case .companion:
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(accentColor.opacity(0.46))
                .frame(width: size * 0.76, height: size * 0.74)
                .rotationEffect(.degrees(-7))
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.saveCream.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(0.38), lineWidth: 1)
                )
                .frame(width: size * 0.76, height: size * 0.74)
                .rotationEffect(.degrees(4))
        case .guardian:
            Circle()
                .stroke(accentColor.opacity(isAnimating ? 0.18 : 0.44), lineWidth: size * 0.08)
                .frame(width: size * 0.92, height: size * 0.92)
                .scaleEffect(isAnimating ? 1.08 : 0.94)
            Image(systemName: "shield.fill")
                .font(.system(size: size * 0.80, weight: .bold))
                .foregroundStyle(accentColor.opacity(0.70))
                .shadow(color: Color.saveNotebookLine.opacity(0.20), radius: 0, x: 0, y: 1)
                .offset(y: size * 0.045)
        }
    }

    @ViewBuilder
    private var stageForeground: some View {
        switch stage {
        case .hatchling:
            SavePetEggShell()
                .fill(Color.saveCream)
                .overlay(SavePetEggShell().stroke(Color.saveNotebookLine.opacity(0.58), lineWidth: 1.2))
                .frame(width: size * 0.72, height: size * 0.34)
                .offset(y: size * 0.30)
        case .companion:
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.16, weight: .bold))
                .foregroundStyle(accentColor)
                .padding(size * 0.08)
                .background(Color.saveCream.opacity(0.96), in: Circle())
                .overlay(Circle().stroke(Color.saveNotebookLine.opacity(0.42), lineWidth: 1))
                .offset(x: -size * 0.30, y: -size * 0.25)
        case .guardian:
            Image(systemName: "crown.fill")
                .font(.system(size: size * 0.26, weight: .black))
                .foregroundStyle(Color.saveHoney)
                .rotationEffect(.degrees(-4))
                .offset(y: -size * 0.39)

            Image(systemName: "sparkles")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(Color.saveHoney)
                .offset(x: size * 0.34, y: -size * 0.18)
        }
    }

    private var presetBadge: some View {
        Image(systemName: preset.systemImage)
            .font(.system(size: size * 0.14, weight: .bold))
            .foregroundStyle(Color.saveInk)
            .frame(width: size * 0.29, height: size * 0.29)
            .background(accentColor, in: Circle())
            .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: max(1, size * 0.014)))
            .offset(x: size * 0.32, y: size * 0.31)
    }

    private var accentColor: Color {
        switch preset {
        case .sprout: .saveLeaf
        case .spark: .saveHoney
        case .cloud: .saveSky
        }
    }

    private var mascotSize: CGFloat {
        switch stage {
        case .hatchling: size * 0.78
        case .companion: size * 0.90
        case .guardian: size * 0.88
        }
    }

    private var mascotOffset: CGFloat {
        switch stage {
        case .hatchling: size * 0.03
        case .companion: size * 0.02
        case .guardian: size * 0.05
        }
    }

    private var animatedOffset: CGFloat {
        switch stage {
        case .hatchling: -size * 0.035
        case .companion: -size * 0.045
        case .guardian: -size * 0.025
        }
    }

    private var animatedScale: CGFloat {
        switch stage {
        case .hatchling: 1.025
        case .companion: 1.045
        case .guardian: 1.02
        }
    }

    private var animatedRotation: Double {
        switch stage {
        case .hatchling: 1.8
        case .companion: -1.4
        case .guardian: 0
        }
    }

    private var idleAnimation: Animation {
        switch stage {
        case .hatchling: .easeInOut(duration: 1.35).repeatForever(autoreverses: true)
        case .companion: .easeInOut(duration: 2.15).repeatForever(autoreverses: true)
        case .guardian: .easeInOut(duration: 2.8).repeatForever(autoreverses: true)
        }
    }

    private func updateMotion() {
        guard animates, !reduceMotion else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { isAnimating = false }
            return
        }

        isAnimating = false
        withAnimation(idleAnimation) {
            isAnimating = true
        }
    }
}

private struct SavePetEggShell: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.30))
        path.addLine(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.width * 0.30, y: rect.height * 0.38))
        path.addLine(to: CGPoint(x: rect.width * 0.47, y: rect.height * 0.14))
        path.addLine(to: CGPoint(x: rect.width * 0.63, y: rect.height * 0.36))
        path.addLine(to: CGPoint(x: rect.width * 0.82, y: rect.height * 0.16))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.30))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.58))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.height * 0.58),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

#if DEBUG
struct SavePetStageGalleryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SaveTheme.Spacing.lg) {
                Text("SAV-E companion stages")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.saveInk)

                ForEach(SavePetStage.allCases, id: \.rawValue) { stage in
                    VStack(alignment: .leading, spacing: SaveTheme.Spacing.sm) {
                        Text(stage.rawValue.capitalized)
                            .font(SaveTheme.Typography.eyebrow)
                            .foregroundStyle(Color.saveCocoa)

                        HStack(spacing: SaveTheme.Spacing.sm) {
                            ForEach(SavePetPreset.allCases) { preset in
                                VStack(spacing: SaveTheme.Spacing.xs) {
                                    SavePetAvatar(preset: preset, stage: stage, size: 88)
                                    Text(preset.rawValue.capitalized)
                                        .font(SaveTheme.Typography.supporting)
                                        .foregroundStyle(Color.saveMutedText)
                                }
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("pet.gallery.\(stage.rawValue).\(preset.rawValue)")
                            }
                        }
                    }
                    .padding(SaveTheme.Spacing.md)
                    .saveNotebookSurface(cornerRadius: 18)
                }
            }
            .padding(SaveTheme.Spacing.lg)
        }
        .background(SaveDottedBackground().ignoresSafeArea())
        .accessibilityIdentifier("pet.gallery.root")
    }
}

#Preview("Companion stages") {
    SavePetStageGalleryView()
}
#endif
