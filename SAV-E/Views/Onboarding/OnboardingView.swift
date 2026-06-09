import SwiftUI

struct OnboardingView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Namespace private var proofNamespace
    @State private var stage: ProofStage
    @State private var clueText = ""
    @State private var selectedTags: Set<ProofIntentTag> = []
    private let autoUseSampleClue: Bool
    var onComplete: () -> Void

    private var language: AppLanguage { languageSettings.language }
    private var isBrandEntryStage: Bool { stage == .promise }

    init(startWithSampleProof: Bool = false, onComplete: @escaping () -> Void) {
        _stage = State(initialValue: startWithSampleProof ? .clue : .promise)
        self.autoUseSampleClue = startWithSampleProof
        self.onComplete = onComplete
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompactHeight = proxy.size.height < 760
            let horizontalPadding: CGFloat = proxy.size.width < 380 ? 16 : 22
            let verticalSpacing: CGFloat = isCompactHeight ? 12 : 18

            onboardingContent(
                isCompactHeight: isCompactHeight,
                horizontalPadding: horizontalPadding,
                verticalSpacing: verticalSpacing
            )
        }
        .onAppear {
            if autoUseSampleClue && trimmedClue.isEmpty {
                useSampleClue()
            }
        }
    }

    private func onboardingContent(
        isCompactHeight: Bool,
        horizontalPadding: CGFloat,
        verticalSpacing: CGFloat
    ) -> some View {
        ZStack {
            SaveDottedBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: verticalSpacing) {
                    if isBrandEntryStage {
                        BrandEntryHero(language: language, isCompactHeight: isCompactHeight)
                    } else {
                        header(isCompactHeight: isCompactHeight)
                        AnimatedProofHero(
                            stage: stage,
                            clueText: clueText,
                            language: language,
                            namespace: proofNamespace,
                            height: isCompactHeight ? 178 : 214
                        )
                        ProofProgressRail(stage: stage, language: language)
                    }
                    ProofStageCard(
                        stage: stage,
                        clueText: $clueText,
                        selectedTags: $selectedTags,
                        language: language,
                        isCompactHeight: isCompactHeight,
                        onChooseLanguage: chooseLanguage,
                        onUseSample: useSampleClue
                    )
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, isCompactHeight ? 8 : 28)
                .padding(.bottom, isCompactHeight ? 14 : 18)
                .frame(maxHeight: .infinity, alignment: .center)
                .clipped()

                bottomActions(isCompactHeight: isCompactHeight)
            }
        }
    }

    private func header(isCompactHeight: Bool) -> some View {
        VStack(spacing: isCompactHeight ? 8 : 12) {
            if !isCompactHeight {
                MemoMascotMark(size: 70, framed: false)
            }

            VStack(spacing: isCompactHeight ? 5 : 8) {
                Text(localized(
                    english: "Rescue one place before it disappears",
                    traditionalChinese: "先救回一個快忘掉的地點"
                ))
                .font(isCompactHeight ? .headline : .title2)
                .fontWeight(.black)
                .foregroundColor(.saveInk)
                .multilineTextAlignment(.center)

                Text(localized(
                    english: "Paste one messy clue. Memo finds the likely place and keeps proof until you confirm.",
                    traditionalChinese: "貼上一個混亂線索。Memo 會找出可能地點、保留證據，等你確認才保存。"
                ))
                .font(isCompactHeight ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineSpacing(2)
                .foregroundColor(.saveMutedText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bottomActions(isCompactHeight: Bool) -> some View {
        VStack(spacing: isCompactHeight ? 0 : 10) {
            Button(action: advance) {
                Text(primaryActionTitle)
                    .font(isCompactHeight ? .subheadline.weight(.black) : .headline.weight(.black))
                    .foregroundColor(primaryActionForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isCompactHeight ? 12 : 16)
                    .background(primaryActionFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(stage == .clue && trimmedClue.isEmpty)
            .opacity(stage == .clue && trimmedClue.isEmpty ? 0.58 : 1)
            .padding(.horizontal, 24)

            if (!isCompactHeight || stage != .promise) && stage != .tag {
                Button(secondaryActionTitle) {
                    skipCurrentStep()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.saveMutedText)
                .opacity(stage == .promise ? 0 : 1)
                .disabled(stage == .promise)
            }
        }
        .padding(.bottom, isCompactHeight ? 8 : 22)
        .background(Color.saveNotebookPage.opacity(0.72))
    }

    private var primaryActionTitle: String {
        switch stage {
        case .promise:
            return localized(english: "Save my first place", traditionalChinese: "存下第一個地點")
        case .clue:
            return localized(english: "Find the real place", traditionalChinese: "找出真正地點")
        case .candidate:
            return localized(english: "Add to my map", traditionalChinese: "加到我的地圖")
        case .mapStamp:
            return localized(english: "Ask my saved places", traditionalChinese: "問我存過的地點")
        case .ask:
            return localized(english: "Add why it mattered", traditionalChinese: "補上為什麼重要")
        case .tag:
            return localized(english: "Open SAV-E", traditionalChinese: "打開 SAV-E")
        }
    }

    private var primaryActionFill: Color {
        switch stage {
        case .promise: return .saveHoney
        case .clue, .candidate: return .saveHoney
        case .mapStamp: return .saveMint
        case .ask: return .saveSky
        case .tag: return .saveMint
        }
    }

    private var primaryActionForeground: Color {
        switch stage {
        case .promise: return .saveInk
        default: return .saveInk
        }
    }

    private var secondaryActionTitle: String {
        switch stage {
        case .tag:
            return localized(english: "Open SAV-E", traditionalChinese: "打開 SAV-E")
        default:
            return localized(english: "Skip this step", traditionalChinese: "跳過這一步")
        }
    }

    private var trimmedClue: String {
        clueText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func advance() {
        switch stage {
        case .promise:
            stage = .clue
        case .clue:
            guard !trimmedClue.isEmpty else { return }
            stage = .candidate
        case .candidate:
            stage = .mapStamp
        case .mapStamp:
            stage = .ask
        case .ask:
            stage = .tag
        case .tag:
            onComplete()
        }
    }

    private func skipCurrentStep() {
        switch stage {
        case .promise:
            break
        case .clue:
            stage = .candidate
        case .candidate:
            stage = .mapStamp
        case .mapStamp:
            stage = .ask
        case .ask:
            stage = .tag
        case .tag:
            onComplete()
        }
    }

    private func useSampleClue() {
        clueText = localized(
            english: "Friend sent: try Utopia Euro Caffe near Irvine for a quiet coffee date",
            traditionalChinese: "朋友傳：Irvine 附近的 Utopia Euro Caffe 很適合安靜咖啡約會"
        )
    }

    private func chooseLanguage(_ language: AppLanguage) {
        languageSettings.language = language
    }

    private func localized(english: String, traditionalChinese: String) -> String {
        switch language {
        case .english: return english
        case .traditionalChinese: return traditionalChinese
        }
    }
}

private enum ProofStage: Int, CaseIterable {
    case promise
    case clue
    case candidate
    case mapStamp
    case ask
    case tag

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.promise, .english): return "Start"
        case (.promise, .traditionalChinese): return "開始"
        case (.clue, .english): return "Clue"
        case (.clue, .traditionalChinese): return "線索"
        case (.candidate, .english): return "Review"
        case (.candidate, .traditionalChinese): return "確認"
        case (.mapStamp, .english): return "Stamp"
        case (.mapStamp, .traditionalChinese): return "地圖章"
        case (.ask, .english): return "Ask"
        case (.ask, .traditionalChinese): return "提問"
        case (.tag, .english): return "Taste"
        case (.tag, .traditionalChinese): return "偏好"
        }
    }
}

private enum ProofIntentTag: String, CaseIterable {
    case coffee
    case dateNight
    case cheapEats
    case quiet
    case travel
    case friends

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.coffee, .english): return "Coffee"
        case (.coffee, .traditionalChinese): return "咖啡"
        case (.dateNight, .english): return "Date night"
        case (.dateNight, .traditionalChinese): return "約會"
        case (.cheapEats, .english): return "Cheap eats"
        case (.cheapEats, .traditionalChinese): return "平價美食"
        case (.quiet, .english): return "Quiet spot"
        case (.quiet, .traditionalChinese): return "安靜地點"
        case (.travel, .english): return "Trip idea"
        case (.travel, .traditionalChinese): return "旅行靈感"
        case (.friends, .english): return "Friend sent"
        case (.friends, .traditionalChinese): return "朋友推薦"
        }
    }
}

private struct BrandEntryHero: View {
    var language: AppLanguage
    var isCompactHeight: Bool
    @State private var isBreathing = false

    var body: some View {
        VStack(spacing: isCompactHeight ? 7 : 18) {
            if !isCompactHeight {
                HStack {
                    entryBadge
                    Spacer()
                }
            } else {
                entryBadge
            }

            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: isCompactHeight ? 30 : 42, style: .continuous)
                    .fill(Color.saveBlush.opacity(0.72))
                    .frame(width: isCompactHeight ? 104 : 168, height: isCompactHeight ? 86 : 140)
                    .rotationEffect(.degrees(-5))

                RoundedRectangle(cornerRadius: isCompactHeight ? 28 : 38, style: .continuous)
                    .fill(Color.saveSky.opacity(0.22))
                    .frame(width: isCompactHeight ? 92 : 146, height: isCompactHeight ? 78 : 122)
                    .offset(x: isCompactHeight ? 12 : 18, y: isCompactHeight ? 8 : 12)
                    .scaleEffect(isBreathing ? 1.04 : 0.97)
                    .animation(SaveTheme.Motion.breathing, value: isBreathing)

                MemoMascotMark(size: isCompactHeight ? 66 : 108, framed: true)
                    .shadow(color: Color.saveInk.opacity(0.12), radius: isCompactHeight ? 18 : 26, x: 0, y: isCompactHeight ? 9 : 14)

                MascotTrustBubble(
                    text: localized(english: "I keep the proof.", traditionalChinese: "我會保留證據。"),
                    isCompactHeight: isCompactHeight
                )
                .offset(x: isCompactHeight ? 22 : 36, y: isCompactHeight ? 16 : 18)
            }

            VStack(spacing: isCompactHeight ? 4 : 10) {
                Text("SAV-E")
                    .font(.system(size: isCompactHeight ? 38 : 64, weight: .black, design: .rounded))
                    .foregroundColor(.saveInk)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)

                Text(localized(
                    english: "Stop losing places friends send you.",
                    traditionalChinese: "別再弄丟朋友傳來的地點。"
                ))
                .font(isCompactHeight ? .subheadline.weight(.black) : SaveTheme.Typography.entryTitle)
                .foregroundColor(.saveInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                Text(localized(
                    english: "Memo keeps the clue and proof until you confirm.",
                    traditionalChinese: "Memo 會接住線索、保留證據，等你確認才保存。"
                ))
                .font(isCompactHeight ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineSpacing(2)
                .foregroundColor(.saveMutedText)
                .multilineTextAlignment(.center)
                .lineLimit(isCompactHeight ? 3 : nil)
                .minimumScaleFactor(0.76)
                .fixedSize(horizontal: false, vertical: !isCompactHeight)
            }

            OnboardingProofPromiseStrip(language: language, isCompactHeight: isCompactHeight)
        }
        .padding(.top, isCompactHeight ? 3 : 18)
        .padding(.bottom, 6)
        .onAppear { isBreathing = true }
    }

    private func localized(english: String, traditionalChinese: String) -> String {
        switch language {
        case .english: return english
        case .traditionalChinese: return traditionalChinese
        }
    }

    private var entryBadge: some View {
        Text(localized(english: "FIRST RESCUE", traditionalChinese: "第一次救回地點"))
            .font(SaveTheme.Typography.eyebrow)
            .foregroundColor(.saveInk)
            .padding(.horizontal, isCompactHeight ? 9 : 10)
            .padding(.vertical, isCompactHeight ? 5 : 6)
            .background(Color.saveHoney.opacity(0.48))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.46), lineWidth: 1))
    }
}

private struct MascotTrustBubble: View {
    let text: String
    let isCompactHeight: Bool

    var body: some View {
        Text(text)
            .font(.caption2.weight(.black))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .padding(.horizontal, isCompactHeight ? 8 : 10)
            .padding(.vertical, isCompactHeight ? 5 : 7)
            .background(Color.saveNotebookPage.opacity(0.94))
            .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.50), lineWidth: 1))
            .clipShape(Capsule())
            .shadow(color: Color.saveInk.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

private struct OnboardingProofPromiseStrip: View {
    let language: AppLanguage
    let isCompactHeight: Bool

    var body: some View {
        HStack(spacing: isCompactHeight ? 7 : 10) {
            promiseChip(
                title: localized(english: "Paste clue", traditionalChinese: "貼上線索"),
                systemImage: "link",
                tint: .saveBlush
            )
            promiseChip(
                title: localized(english: "Confirm place", traditionalChinese: "確認地點"),
                systemImage: "checklist.unchecked",
                tint: .saveSky
            )
            promiseChip(
                title: localized(english: "Ask map", traditionalChinese: "詢問地圖"),
                systemImage: "sparkles",
                tint: .saveLeaf
            )
        }
        .padding(.horizontal, isCompactHeight ? 8 : 10)
        .padding(.vertical, isCompactHeight ? 7 : 9)
        .background(Color.saveNotebookPage.opacity(0.58))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func promiseChip(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.black))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.64)
            .padding(.horizontal, isCompactHeight ? 7 : 9)
            .padding(.vertical, isCompactHeight ? 6 : 7)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(0.66))
            .clipShape(Capsule())
    }

    private func localized(english: String, traditionalChinese: String) -> String {
        switch language {
        case .english: return english
        case .traditionalChinese: return traditionalChinese
        }
    }
}

private struct AnimatedProofHero: View {
    let stage: ProofStage
    let clueText: String
    let language: AppLanguage
    let namespace: Namespace.ID
    let height: CGFloat

    @State private var isFloating = false
    @State private var scanOffset: CGFloat = -92

    private var progress: CGFloat {
        CGFloat(stage.rawValue) / CGFloat(max(ProofStage.allCases.count - 1, 1))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.saveNotebookPage.opacity(0.96),
                            Color.saveNotebookPage.opacity(0.74)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(0.62), lineWidth: 1.5)
                )

            SaveProofRouteShape(progress: progress)
                .stroke(Color.saveNotebookLine.opacity(0.18), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                .padding(.horizontal, 28)
                .padding(.vertical, 34)

            SaveProofRouteShape(progress: progress)
                .trim(from: 0, to: min(1, max(0.08, progress + 0.08)))
                .stroke(Color.saveHoney.opacity(0.78), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .padding(.horizontal, 28)
                .padding(.vertical, 34)

            proofContent
                .padding(16)

            if stage == .clue || stage == .candidate {
                scanningBand
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.saveInk.opacity(0.08), radius: 16, x: 0, y: 10)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                isFloating = true
            }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                scanOffset = 120
            }
        }
        .animation(.spring(response: 0.52, dampingFraction: 0.82), value: stage)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var proofContent: some View {
        switch stage {
        case .promise, .clue:
            messySignalView
        case .candidate:
            reviewCandidateView
        case .mapStamp:
            mapStampView
        case .ask, .tag:
            askMemoryView
        }
    }

    private var messySignalView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SourceBubble(label: "IG", tint: .savePink, offsetY: isFloating ? -4 : 4)
                SourceBubble(label: "TT", tint: .saveSky, offsetY: isFloating ? 5 : -3)
                SourceBubble(label: "MAP", tint: .saveMint, offsetY: isFloating ? -2 : 5)
                Spacer()
                Image(systemName: "arrow.down.forward.circle.fill")
                    .font(.title2.weight(.black))
                    .foregroundColor(.saveInk.opacity(0.62))
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(localized(english: "Messy place signal", traditionalChinese: "混亂地點線索"))
                    .font(.caption)
                    .fontWeight(.black)
                    .textCase(.uppercase)
                    .foregroundColor(.saveMutedText)

                Text(signalLine)
                    .font(.headline)
                    .fontWeight(.black)
                    .foregroundColor(.saveInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    miniChip(localized(english: "caption", traditionalChinese: "文案"), tint: .saveHoney)
                    miniChip(localized(english: "friend tip", traditionalChinese: "朋友推薦"), tint: .saveSky)
                    miniChip(localized(english: "needs proof", traditionalChinese: "待確認"), tint: .saveMint)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.saveNotebookPage.opacity(0.52))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(0.34), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .matchedGeometryEffect(id: "proof-card", in: namespace)
        }
    }

    private var reviewCandidateView: some View {
        HStack(alignment: .top, spacing: 14) {
            stageIcon(systemImage: "checklist.unchecked", tint: .saveHoney)

            VStack(alignment: .leading, spacing: 10) {
                Text(localized(english: "Review Candidate", traditionalChinese: "待確認地點"))
                    .font(.caption)
                    .fontWeight(.black)
                    .textCase(.uppercase)
                    .foregroundColor(.saveMutedText)

                Text("Utopia Euro Caffe")
                    .font(.title3)
                    .fontWeight(.black)
                    .foregroundColor(.saveInk)

                ProofHeroLine(icon: "checkmark.seal.fill", text: localized(english: "Name found", traditionalChinese: "找到名稱"), tint: .saveMint)
                ProofHeroLine(icon: "link", text: localized(english: "Source kept", traditionalChinese: "保留來源"), tint: .saveSky)
                ProofHeroLine(icon: "exclamationmark.triangle.fill", text: localized(english: "Missing coordinates", traditionalChinese: "還缺座標"), tint: .saveHoney)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.saveNotebookPage.opacity(0.52))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.42), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .matchedGeometryEffect(id: "proof-card", in: namespace)
    }

    private var mapStampView: some View {
        ZStack(alignment: .bottomLeading) {
            SaveMiniMap(language: language)

            HStack(spacing: 12) {
                stageIcon(systemImage: "mappin.and.ellipse", tint: .saveMint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localized(english: "Map Stamp saved", traditionalChinese: "已存成地圖章"))
                        .font(.caption)
                        .fontWeight(.black)
                        .textCase(.uppercase)
                        .foregroundColor(.saveMutedText)

                    Text("Utopia Euro Caffe")
                        .font(.headline)
                        .fontWeight(.black)
                        .foregroundColor(.saveInk)

                    Text(localized(english: "Coffee · friend sent · private", traditionalChinese: "咖啡 · 朋友推薦 · 私人"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.saveMutedText)
                }

                Spacer()
            }
            .padding(14)
            .background(Color.saveNotebookPage.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .matchedGeometryEffect(id: "proof-card", in: namespace)
        }
    }

    private var askMemoryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                stageIcon(systemImage: "sparkles", tint: .saveSky)
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized(english: "Ask saved memory", traditionalChinese: "詢問已存記憶"))
                        .font(.caption)
                        .fontWeight(.black)
                        .textCase(.uppercase)
                        .foregroundColor(.saveMutedText)
                    Text(localized(english: "Saved-first answer", traditionalChinese: "先用你的記憶回答"))
                        .font(.headline)
                        .fontWeight(.black)
                        .foregroundColor(.saveInk)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(localized(english: "Recommend nearby coffee", traditionalChinese: "推薦附近咖啡"))
                    .font(.subheadline)
                    .fontWeight(.black)
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.saveHoney.opacity(0.42))
                    .clipShape(Capsule())

                Text(localized(
                    english: "Start with Utopia. It matches your saved coffee clue. Public options stay separate.",
                    traditionalChinese: "先從 Utopia 開始。它符合你存下的咖啡線索；公開搜尋會分開。"
                ))
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.saveMint.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.saveNotebookPage.opacity(0.52))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.42), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .matchedGeometryEffect(id: "proof-card", in: namespace)
    }

    private var scanningBand: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.saveNotebookPage.opacity(0.34),
                        Color.saveSky.opacity(0.24),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 80)
            .rotationEffect(.degrees(12))
            .offset(x: scanOffset)
            .allowsHitTesting(false)
    }

    private var signalLine: String {
        let trimmed = clueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return localized(
                english: "Friend sent: quiet coffee date near Irvine",
                traditionalChinese: "朋友傳：Irvine 附近安靜咖啡約會"
            )
        }
        return String(trimmed.prefix(74))
    }

    private func stageIcon(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.black))
            .foregroundColor(.saveInk)
            .frame(width: 48, height: 48)
            .background(tint.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(0.46), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func miniChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.black)
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.50))
            .clipShape(Capsule())
    }

    private func localized(english: String, traditionalChinese: String) -> String {
        switch language {
        case .english: return english
        case .traditionalChinese: return traditionalChinese
        }
    }

    private var accessibilityLabel: String {
        switch language {
        case .english:
            return "Animated SAV-E proof flow showing \(stage.title(language: language))"
        case .traditionalChinese:
            return "SAV-E 動態流程，目前是\(stage.title(language: language))"
        }
    }
}

private struct SourceBubble: View {
    let label: String
    let tint: Color
    let offsetY: CGFloat

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.black)
            .foregroundColor(.saveInk)
            .frame(width: label.count > 2 ? 42 : 34, height: 34)
            .background(tint.opacity(0.84))
            .overlay(Circle().stroke(Color.saveNotebookBackground.opacity(0.82), lineWidth: 2))
            .clipShape(Circle())
            .offset(y: offsetY)
    }
}

private struct ProofHeroLine: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.58))
                .clipShape(Circle())

            Text(text)
                .font(.caption)
                .fontWeight(.black)
                .foregroundColor(.saveInk)
        }
    }
}

private struct SaveMiniMap: View {
    let language: AppLanguage

    var body: some View {
        ZStack {
            Color.saveMint.opacity(0.28)

            Path { path in
                path.move(to: CGPoint(x: 20, y: 40))
                path.addLine(to: CGPoint(x: 130, y: 96))
                path.addLine(to: CGPoint(x: 250, y: 54))
                path.move(to: CGPoint(x: 38, y: 156))
                path.addLine(to: CGPoint(x: 156, y: 88))
                path.addLine(to: CGPoint(x: 300, y: 170))
            }
            .stroke(Color.saveNotebookLine.opacity(0.22), style: StrokeStyle(lineWidth: 10, lineCap: .round))

            ForEach(SaveMiniMapPin.sample) { pin in
                VStack(spacing: 3) {
                    Image(systemName: pin.icon)
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveInk)
                        .frame(width: pin.isPrimary ? 38 : 30, height: pin.isPrimary ? 38 : 30)
                        .background(pin.tint.opacity(0.88))
                        .overlay(Circle().stroke(Color.saveNotebookBackground.opacity(0.82), lineWidth: 2))
                        .clipShape(Circle())

                    if pin.isPrimary {
                        Text(language.localized(english: "Map Stamp", traditionalChinese: "地圖章"))
                            .font(.caption2)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.saveNotebookPage.opacity(0.88))
                            .clipShape(Capsule())
                    }
                }
                .position(pin.position)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct SaveMiniMapPin: Identifiable {
    let id = UUID()
    let icon: String
    let tint: Color
    let position: CGPoint
    let isPrimary: Bool

    static let sample: [SaveMiniMapPin] = [
        SaveMiniMapPin(icon: "cup.and.saucer.fill", tint: .saveHoney, position: CGPoint(x: 106, y: 92), isPrimary: true),
        SaveMiniMapPin(icon: "fork.knife", tint: .saveSky, position: CGPoint(x: 236, y: 48), isPrimary: false),
        SaveMiniMapPin(icon: "camera.fill", tint: .savePink, position: CGPoint(x: 268, y: 142), isPrimary: false)
    ]
}

private struct SaveProofRouteShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.70))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.46, y: rect.minY + rect.height * 0.36),
            control1: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.36),
            control2: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.78)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.minY + rect.height * 0.28),
            control1: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.06),
            control2: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.58)
        )
        return path
    }
}

private struct ProofProgressRail: View {
    let stage: ProofStage
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProofStage.allCases, id: \.self) { item in
                VStack(spacing: 7) {
                    Circle()
                        .fill(fill(for: item))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.saveNotebookLine.opacity(0.72), lineWidth: 1)
                        )
                        .overlay {
                            if item.rawValue < stage.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.black))
                                    .foregroundColor(.saveInk)
                            }
                        }

                    Text(item.title(language: language))
                        .font(.caption2)
                        .fontWeight(.black)
                        .foregroundColor(item.rawValue <= stage.rawValue ? .saveInk : .saveMutedText.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.56)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)

                if item != ProofStage.allCases.last {
                    Rectangle()
                        .fill(item.rawValue < stage.rawValue ? Color.saveHoney : Color.saveNotebookLine.opacity(0.34))
                        .frame(height: 2)
                        .padding(.horizontal, 2)
                        .offset(y: -13)
                }
            }
        }
        .padding(.horizontal, 2)
        .accessibilityLabel(accessibilityLabel)
    }

    private func fill(for item: ProofStage) -> Color {
        if item.rawValue < stage.rawValue { return .saveHoney }
        if item == stage { return .saveSky }
        return .saveNotebookPage
    }

    private var accessibilityLabel: String {
        switch language {
        case .english:
            return "Onboarding step \(stage.rawValue + 1) of \(ProofStage.allCases.count)"
        case .traditionalChinese:
            return "新手設定第 \(stage.rawValue + 1) 步，共 \(ProofStage.allCases.count) 步"
        }
    }
}

private struct ProofStageCard: View {
    let stage: ProofStage
    @Binding var clueText: String
    @Binding var selectedTags: Set<ProofIntentTag>
    let language: AppLanguage
    let isCompactHeight: Bool
    let onChooseLanguage: (AppLanguage) -> Void
    let onUseSample: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 13 : 18) {
            stageHeader
            stageContent
        }
        .padding(isCompactHeight ? 16 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.saveNotebookPage.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.saveInk.opacity(0.08), radius: 16, x: 0, y: 10)
    }

    private var stageHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font((isCompactHeight ? Font.headline : Font.title2).weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: isCompactHeight ? 38 : 44, height: isCompactHeight ? 38 : 44)
                .background(headerTint.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(0.62), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(isCompactHeight ? .headline : .title3)
                    .fontWeight(.black)
                    .foregroundColor(.saveInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(isCompactHeight ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundColor(.saveMutedText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .promise:
            promiseChoice
        case .clue:
            clueInput
        case .candidate:
            candidateProof
        case .mapStamp:
            mapStampProof
        case .ask:
            askProof
        case .tag:
            tagProof
        }
    }

    private var promiseChoice: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 10 : 14) {
            VStack(alignment: .leading, spacing: isCompactHeight ? 8 : 10) {
                rescueLine(
                    icon: "tray.and.arrow.down.fill",
                    title: localized(english: "You paste one messy clue", traditionalChinese: "你貼上一個混亂線索"),
                    subtitle: localized(english: "A Reel, map link, screenshot text, or friend message.", traditionalChinese: "短影音文案、地圖連結、截圖文字或朋友訊息都可以。"),
                    tint: .saveBlush
                )
                rescueLine(
                    icon: "sparkles",
                    title: localized(english: "Memo finds what is real", traditionalChinese: "Memo 找出真正地點"),
                    subtitle: localized(english: "Uncertain matches stay in Review instead of becoming fake pins.", traditionalChinese: "不確定的結果會留在待確認，不會變成假地圖點。"),
                    tint: .saveHoney
                )
                rescueLine(
                    icon: "mappin.and.ellipse",
                    title: localized(english: "You add it to your map", traditionalChinese: "你再加到自己的地圖"),
                    subtitle: localized(english: "The first useful memory is the reward.", traditionalChinese: "第一個有用地點記憶，就是這次的新手獎勵。"),
                    tint: .saveMint
                )
            }

            HStack(spacing: 10) {
                Button(action: onUseSample) {
                    Label(localized(english: "Try sample clue", traditionalChinese: "試用範例線索"), systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.black))
                        .foregroundColor(.saveInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color.saveHoney.opacity(0.50))
                        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.50), lineWidth: 1))
                        .clipShape(Capsule())
                }

                languageSwitcher
            }

            if !isCompactHeight {
                FirstRunTrustNote(language: language)
            }
        }
    }

    private func rescueLine(icon: String, title: String, subtitle: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.64))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.saveMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var languageSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(AppLanguage.allCases) { option in
                Button {
                    onChooseLanguage(option)
                } label: {
                    Text(option == .english ? "EN" : "繁中")
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveInk)
                        .frame(minWidth: 38)
                        .padding(.vertical, 10)
                        .background(option == language ? Color.saveSky.opacity(0.58) : Color.saveNotebookPage.opacity(0.58))
                        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.42), lineWidth: 1))
                        .clipShape(Capsule())
                }
                .accessibilityLabel(option.displayName)
            }
        }
    }

    private var clueInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.saveNotebookPage.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.saveNotebookLine.opacity(0.44), lineWidth: 1)
                    )

                TextEditor(text: $clueText)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 116)

                if clueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.saveMutedText.opacity(0.72))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 116)

            Button(action: onUseSample) {
                Label(sampleTitle, systemImage: "sparkles")
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.saveHoney.opacity(0.48))
                    .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.58), lineWidth: 1))
                    .clipShape(Capsule())
            }
        }
    }

    private var candidateProof: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProofLine(
                label: localized(english: "Found", traditionalChinese: "找到"),
                value: localized(english: "Utopia Euro Caffe", traditionalChinese: "Utopia Euro Caffe"),
                icon: "checkmark.seal.fill",
                tint: .saveMint
            )
            ProofLine(
                label: localized(english: "Source", traditionalChinese: "來源"),
                value: sourceSummary,
                icon: "link",
                tint: .saveSky
            )
            ProofLine(
                label: localized(english: "Missing", traditionalChinese: "還缺"),
                value: localized(english: "Exact address and coordinates before it becomes a Map Stamp", traditionalChinese: "變成地圖章前，要確認地址與座標"),
                icon: "exclamationmark.triangle.fill",
                tint: .saveHoney
            )

            Text(localized(
                english: "This stays in Review until you confirm the exact place.",
                traditionalChinese: "這會先留在待確認，等你確認正確地點後再保存。"
            ))
            .font(.footnote)
            .fontWeight(.bold)
            .foregroundColor(.saveMutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mapStampProof: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.title2.weight(.black))
                    .foregroundColor(.saveInk)
                    .frame(width: 56, height: 56)
                    .background(Color.saveMint.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Utopia Euro Caffe")
                        .font(.headline)
                        .fontWeight(.black)
                        .foregroundColor(.saveInk)

                    Text(localized(english: "Map Stamp · Coffee · Friend sent", traditionalChinese: "地圖章 · 咖啡 · 朋友推薦"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.saveMutedText)
                }
            }

            HStack(spacing: 10) {
                chip(localized(english: "confirmed", traditionalChinese: "已確認"), tint: .saveMint)
                chip(localized(english: "source kept", traditionalChinese: "保留來源"), tint: .saveSky)
                chip(localized(english: "private", traditionalChinese: "私人"), tint: .saveHoney)
            }
        }
    }

    private var askProof: some View {
        VStack(alignment: .leading, spacing: 12) {
            chatBubble(
                localized(english: "Recommend nearby coffee from my saved places", traditionalChinese: "從我存過的地方推薦附近咖啡"),
                isUser: true
            )
            chatBubble(
                localized(
                    english: "I’d start with Utopia Euro Caffe because it matches your saved coffee clue and looks quiet enough for a date. Public discovery stays separate.",
                    traditionalChinese: "我會先推薦 Utopia Euro Caffe，因為它符合你剛存的咖啡線索，也偏安靜適合約會。公開搜尋會另外標示。"
                ),
                isUser: false
            )
        }
    }

    private var tagProof: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized(
                english: "Now tell SAV-E why this mattered. These tags should come after proof, not before.",
                traditionalChinese: "現在再告訴 SAV-E 為什麼你想存。這些標籤應該在證明有用後才出現。"
            ))
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundColor(.saveMutedText)
            .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                ForEach(ProofIntentTag.allCases, id: \.self) { tag in
                    Button {
                        if selectedTags.contains(tag) {
                            selectedTags.remove(tag)
                        } else {
                            selectedTags.insert(tag)
                        }
                    } label: {
                        Label(tag.title(language: language), systemImage: selectedTags.contains(tag) ? "checkmark.circle.fill" : "circle")
                            .font(.subheadline.weight(.black))
                            .foregroundColor(.saveInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(selectedTags.contains(tag) ? Color.saveHoney.opacity(0.64) : Color.saveNotebookPage.opacity(0.54))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.saveNotebookLine.opacity(0.48), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }

            UpgradePreviewCard(language: language, isCompactHeight: isCompactHeight)
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.black)
            .foregroundColor(.saveInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.58))
            .clipShape(Capsule())
    }

    private func chatBubble(_ text: String, isUser: Bool) -> some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.saveInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .background(isUser ? Color.saveHoney.opacity(0.42) : Color.saveMint.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var iconName: String {
        switch stage {
        case .promise: return "wand.and.stars"
        case .clue: return "square.and.pencil"
        case .candidate: return "checklist.unchecked"
        case .mapStamp: return "mappin.and.ellipse"
        case .ask: return "sparkles"
        case .tag: return "tag.fill"
        }
    }

    private var headerTint: Color {
        switch stage {
        case .promise: return .saveHoney
        case .clue, .candidate: return .saveHoney
        case .mapStamp: return .saveMint
        case .ask: return .saveSky
        case .tag: return .savePink
        }
    }

    private var title: String {
        switch stage {
        case .promise:
            return localized(english: "Start with one rescue mission", traditionalChinese: "先完成一次救回地點任務")
        case .clue:
            return localized(english: "Paste the clue you almost lost", traditionalChinese: "貼上快被你忘掉的線索")
        case .candidate:
            return localized(english: "Check the likely place", traditionalChinese: "確認可能的地點")
        case .mapStamp:
            return localized(english: "Stamp it onto your map", traditionalChinese: "蓋到你的地圖上")
        case .ask:
            return localized(english: "Ask your saved places first", traditionalChinese: "先問你存過的地點")
        case .tag:
            return localized(english: "Tell Memo why it mattered", traditionalChinese: "告訴 Memo 為什麼重要")
        }
    }

    private var subtitle: String {
        switch stage {
        case .promise:
            return localized(
                english: "One clue becomes one confirmed private place. Change language here if you need to.",
                traditionalChinese: "一個線索會變成一個確認過的私人地點。需要的話，也可以在這裡切換語言。"
            )
        case .clue:
            return localized(english: "Use a Reel caption, map link, screenshot text, or friend message.", traditionalChinese: "可以用短影音文案、地圖連結、截圖文字或朋友訊息。")
        case .candidate:
            return localized(english: "Memo shows what it found and what still needs your confirmation.", traditionalChinese: "Memo 會顯示找到什麼，以及還需要你確認什麼。")
        case .mapStamp:
            return localized(english: "Only confirmed places become private map memory.", traditionalChinese: "只有確認後，才會變成你的私人地圖記憶。")
        case .ask:
            return localized(english: "SAV-E starts with your saved place, then keeps public discovery separate.", traditionalChinese: "SAV-E 會先用你存過的地點回答，再分開標示公開搜尋。")
        case .tag:
            return localized(english: "A few tags help future answers remember why you saved it.", traditionalChinese: "用幾個標籤，讓之後的回答記得你為什麼想存。")
        }
    }

    private var placeholder: String {
        localized(
            english: "Example: friend said this cafe is good for a quiet date near Irvine...",
            traditionalChinese: "例如：朋友說 Irvine 附近這間咖啡很適合安靜約會..."
        )
    }

    private var sampleTitle: String {
        localized(english: "Use sample clue", traditionalChinese: "使用範例線索")
    }

    private var sourceSummary: String {
        let trimmed = clueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return localized(english: "Friend message", traditionalChinese: "朋友訊息")
        }
        return String(trimmed.prefix(72))
    }

    private func localized(english: String, traditionalChinese: String) -> String {
        switch language {
        case .english: return english
        case .traditionalChinese: return traditionalChinese
        }
    }
}

private struct UpgradePreviewCard: View {
    let language: AppLanguage
    let isCompactHeight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 10 : 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.headline.weight(.black))
                    .foregroundColor(.saveInk)
                    .frame(width: 36, height: 36)
                    .background(Color.saveLavender.opacity(0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(localized(english: "Upgrade after the first useful memory", traditionalChinese: "先有第一個有用記憶，再升級"))
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)

                    Text(localized(english: "Start free. Pro is for heavier recovery and planning.", traditionalChinese: "先免費開始。進階版留給更重的找地點與規劃。"))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.saveMutedText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
            }

            HStack(spacing: 10) {
                planColumn(
                    title: localized(english: "Free", traditionalChinese: "免費"),
                    subtitle: localized(english: "Save, review, ask", traditionalChinese: "保存、確認、提問"),
                    systemImage: "checkmark.seal.fill",
                    tint: .saveMint
                )

                planColumn(
                    title: localized(english: "SAV-E Pro", traditionalChinese: "SAV-E 進階版"),
                    subtitle: localized(english: "OCR, recovery, planning", traditionalChinese: "截圖辨識、找回地點、規劃"),
                    systemImage: "lock.open.fill",
                    tint: .saveHoney
                )
            }
        }
        .padding(isCompactHeight ? 12 : 14)
        .background(
            LinearGradient(
                colors: [
                    Color.saveLavender.opacity(0.18),
                    Color.saveBlush.opacity(0.44),
                    Color.saveNotebookPage.opacity(0.68)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.38), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func planColumn(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.62))
                .clipShape(Circle())

            Text(title)
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(subtitle)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveMutedText)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.saveNotebookPage.opacity(0.58))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func localized(english: String, traditionalChinese: String) -> String {
        switch language {
        case .english: return english
        case .traditionalChinese: return traditionalChinese
        }
    }
}

private struct ProofLine: View {
    let label: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.64))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(.caption2)
                    .fontWeight(.black)
                    .foregroundColor(.saveMutedText)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.saveInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct FirstRunTrustNote: View {
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)

            Text(text)
                .font(.footnote)
                .fontWeight(.bold)
                .foregroundColor(.saveMutedText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.saveNotebookPage.opacity(0.74))
        .overlay(
            Capsule()
                .stroke(Color.saveNotebookLine.opacity(0.38), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var text: String {
        switch language {
        case .english: return "Private food + travel memory, not public reviews."
        case .traditionalChinese: return "這是私人的美食與旅行記憶，不是公開評論。"
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .environment(\.appLanguageSettings, AppLanguageSettings())
}
