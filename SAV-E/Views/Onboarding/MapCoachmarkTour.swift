import SwiftUI

// MARK: - Step model

/// A single first-run coachmark step. Region-targeted (not per-element
/// spotlighting) so it stays robust across the map + bottom-sheet split
/// presentation without cross-presentation frame math.
struct MapCoachmarkStep: Identifiable, Equatable {
    enum Target: Equatable {
        /// Points up toward the map canvas (Map Stamps live here).
        case map
        /// Points down toward the persistent search / command drawer.
        case drawer

        var arrowSystemName: String {
            switch self {
            case .map: return "arrow.up"
            case .drawer: return "arrow.down"
            }
        }

        /// Where the tooltip card sits so the arrow can point at the target
        /// region while the card stays in the clear area.
        var cardAlignment: Alignment {
            switch self {
            // Map target is up top, so anchor the card lower-center.
            case .map: return .center
            // Drawer target is at the bottom, so float the card higher.
            case .drawer: return .top
            }
        }
    }

    let id: Int
    let title: String
    let body: String
    let target: Target
    /// Show the Memo mascot on this step (welcome / final beat).
    let showsMascot: Bool
}

// MARK: - Tour overlay

/// Full-screen first-run guided tour. Present this ABOVE everything (including
/// the bottom sheet) via a top-level `.fullScreenCover` on `ContentView`.
struct MapCoachmarkTour: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called when the tour ends (Skip or finishing the last step). The caller
    /// flips the AppStorage flag so the tour never shows again.
    let onFinish: () -> Void

    @State private var stepIndex = 0

    // Two interaction-focused steps only. The concepts (review-first, private
    // map) were just taught in onboarding — repeating them here doubled the
    // tour length and drove skips. The tour now only shows WHERE to act.
    private var steps: [MapCoachmarkStep] {
        [
            MapCoachmarkStep(
                id: 0,
                title: languageSettings.localized(
                    english: "This is your map",
                    traditionalChinese: "這是你的地圖"
                ),
                body: languageSettings.localized(
                    english: "Saved places land here as Map Stamps — tap one to see its details and source.",
                    traditionalChinese: "存的地點會變成地圖章落在這裡——點一下就能看細節和來源。"
                ),
                target: .map,
                showsMascot: true
            ),
            MapCoachmarkStep(
                id: 1,
                title: languageSettings.localized(
                    english: "Ask SAV-E down here",
                    traditionalChinese: "在這裡問 SAV-E"
                ),
                body: languageSettings.localized(
                    english: "Paste an Instagram, TikTok or 小紅書 link — or just ask. SAV-E finds the place and adds it.",
                    traditionalChinese: "貼上 Instagram、TikTok 或小紅書連結，或直接問。SAV-E 會找到地點並加進來。"
                ),
                target: .drawer,
                showsMascot: false
            )
        ]
    }

    private var step: MapCoachmarkStep { steps[stepIndex] }
    private var isLastStep: Bool { stepIndex == steps.count - 1 }

    var body: some View {
        ZStack {
            // Dim scrim. Tapping outside the card does nothing destructive —
            // the user advances/exits via explicit buttons.
            Color.saveInk.opacity(0.42)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            GeometryReader { geo in
                ZStack(alignment: step.target.cardAlignment) {
                    Color.clear

                    VStack(spacing: SaveTheme.Spacing.md) {
                        if step.target == .drawer {
                            // Card sits high, arrow points down toward the drawer.
                            tooltipCard
                            CoachmarkArrow(systemName: step.target.arrowSystemName, reduceMotion: reduceMotion)
                                .padding(.top, SaveTheme.Spacing.xs)
                        } else {
                            // Card sits centered, arrow points up toward the map.
                            CoachmarkArrow(systemName: step.target.arrowSystemName, reduceMotion: reduceMotion)
                                .padding(.bottom, SaveTheme.Spacing.xs)
                            tooltipCard
                        }
                    }
                    .frame(maxWidth: 360)
                    .padding(.horizontal, SaveTheme.Spacing.xl)
                    .padding(.top, step.target == .drawer ? geo.safeAreaInsets.top + SaveTheme.Spacing.xl : 0)
                    .padding(.bottom, step.target == .map ? geo.size.height * 0.26 : 0)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .transaction { txn in
            if reduceMotion { txn.animation = nil }
        }
        .onAppear { SaveHaptics.tap() }
    }

    // MARK: Tooltip card

    private var tooltipCard: some View {
        VStack(alignment: .leading, spacing: SaveTheme.Spacing.md) {
            HStack(alignment: .top, spacing: SaveTheme.Spacing.md) {
                if step.showsMascot {
                    MemoMascotMark(size: 46)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: SaveTheme.Spacing.xs) {
                    Text(stepCounter)
                        .font(SaveTheme.Typography.eyebrow)
                        .foregroundColor(.saveMutedText)
                        .accessibilityHidden(true)

                    Text(step.title)
                        .font(SaveTheme.Typography.cardTitle)
                        .foregroundColor(.saveInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Text(step.body)
                .font(SaveTheme.Typography.supporting)
                .foregroundColor(.saveInk.opacity(0.78))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: SaveTheme.Spacing.sm) {
                StepDots(count: steps.count, activeIndex: stepIndex)
                    .accessibilityHidden(true)

                Spacer(minLength: SaveTheme.Spacing.sm)

                Button(action: skip) {
                    Text(languageSettings.localized(english: "Skip", traditionalChinese: "跳過"))
                        .font(SaveTheme.Typography.cta)
                        .foregroundColor(.saveMutedText)
                        .padding(.horizontal, SaveTheme.Spacing.md)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(languageSettings.localized(
                    english: "Skip the tour",
                    traditionalChinese: "跳過導覽"
                ))

                Button(action: advance) {
                    Text(nextButtonTitle)
                        .font(SaveTheme.Typography.cta)
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, SaveTheme.Spacing.lg)
                        .frame(height: 38)
                        .background(Color.saveHoney)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 1.4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SaveTheme.Spacing.lg)
        .background(Color.saveNotebookPage)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.saveInk.opacity(0.15), radius: 12, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title). \(step.body)")
    }

    private var stepCounter: String {
        languageSettings.localized(
            english: "Step \(stepIndex + 1) of \(steps.count)",
            traditionalChinese: "第 \(stepIndex + 1) / \(steps.count) 步"
        )
    }

    private var nextButtonTitle: String {
        isLastStep
            ? languageSettings.localized(english: "Got it", traditionalChinese: "開始")
            : languageSettings.localized(english: "Next", traditionalChinese: "下一步")
    }

    // MARK: Actions

    private func advance() {
        SaveHaptics.select()
        if isLastStep {
            onFinish()
            return
        }
        if reduceMotion {
            stepIndex += 1
        } else {
            withAnimation(SaveTheme.Motion.standardSpring) {
                stepIndex += 1
            }
        }
    }

    private func skip() {
        SaveHaptics.tap()
        onFinish()
    }
}

// MARK: - Arrow / pointing hand

private struct CoachmarkArrow: View {
    let systemName: String
    let reduceMotion: Bool

    @State private var bob = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 30, weight: .black))
            .foregroundColor(.saveHoney)
            .padding(10)
            .background(
                Circle()
                    .fill(Color.saveNotebookPage)
                    .overlay(Circle().stroke(Color.saveNotebookLine.opacity(0.35), lineWidth: 1))
            )
            .shadow(color: Color.saveInk.opacity(0.15), radius: 6, x: 0, y: 3)
            .offset(y: bob ? bobOffset : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    bob = true
                }
            }
            .accessibilityHidden(true)
    }

    private var bobOffset: CGFloat {
        systemName == "arrow.up" ? -8 : 8
    }
}

// MARK: - Step dots

private struct StepDots: View {
    let count: Int
    let activeIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == activeIndex ? Color.saveHoney : Color.saveDisabled.opacity(0.6))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle().stroke(Color.saveNotebookLine.opacity(index == activeIndex ? 0.6 : 0.25), lineWidth: 1)
                    )
            }
        }
    }
}

#Preview {
    ZStack {
        SaveDottedBackground().ignoresSafeArea()
        MapCoachmarkTour(onFinish: {})
            .environment(\.appLanguageSettings, AppLanguageSettings())
    }
}
