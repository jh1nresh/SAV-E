import SwiftUI

/// Proof-first onboarding.
///
/// Instead of a feature carousel, the first run walks one scripted clue through
/// the real product loop: Language -> Clue -> Review Candidate -> Map Stamp.
/// All demo data is local; no parsing or network.
struct OnboardingView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep
    @State private var clueText = ""
    private let autoUseSampleClue: Bool
    var onComplete: (String?) -> Void

    private var language: AppLanguage { languageSettings.language }

    init(startWithSampleProof: Bool = false, onComplete: @escaping (String?) -> Void) {
        _step = State(initialValue: startWithSampleProof ? .clue : .language)
        self.autoUseSampleClue = startWithSampleProof
        self.onComplete = onComplete
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompactHeight = proxy.size.height < 760
            let horizontalPadding: CGFloat = proxy.size.width < 380 ? 16 : 24

            ZStack {
                SaveDottedBackground()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    OnboardingTopBar(
                        step: step,
                        language: language,
                        onBack: goBack
                    )
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, isCompactHeight ? 6 : 14)

                    stepBody(isCompactHeight: isCompactHeight)
                        .padding(.horizontal, horizontalPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    bottomActions(isCompactHeight: isCompactHeight)
                        .padding(.horizontal, horizontalPadding)
                }
            }
        }
        .onAppear {
            if autoUseSampleClue && trimmedClue.isEmpty {
                useSampleClue()
            }
        }
    }

    // MARK: - Step Body

    @ViewBuilder
    private func stepBody(isCompactHeight: Bool) -> some View {
        switch step {
        case .language:
            LanguageStepView(
                language: language,
                isCompactHeight: isCompactHeight,
                onChoose: chooseLanguage
            )
            .transition(stepTransition)
        case .clue:
            ClueStepView(
                clueText: $clueText,
                language: language,
                isCompactHeight: isCompactHeight,
                reduceMotion: reduceMotion,
                onUseSample: useSampleClue
            )
            .transition(stepTransition)
        case .candidate, .mapStamp:
            proofSection(isCompactHeight: isCompactHeight)
                .transition(stepTransition)
        }
    }

    private func proofSection(isCompactHeight: Bool) -> some View {
        VStack(spacing: isCompactHeight ? 12 : 18) {
            Spacer(minLength: 0)

            OnboardingStepTitle(
                eyebrow: step.eyebrow(language: language),
                title: step.title(language: language),
                subtitle: step.subtitle(language: language),
                tint: step.tint,
                isCompactHeight: isCompactHeight
            )
            .id(step)
            .transition(.opacity)

            ProofDemoCanvas(
                step: step,
                clueText: trimmedClue,
                language: language,
                height: isCompactHeight ? 218 : 268
            )

            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom Actions

    private func bottomActions(isCompactHeight: Bool) -> some View {
        VStack(spacing: isCompactHeight ? 6 : 10) {
            Button(action: advance) {
                HStack(spacing: 8) {
                    Text(step.primaryTitle(language: language))
                    Image(systemName: step == .mapStamp ? "arrow.right" : "chevron.right")
                        .font(.subheadline.weight(.black))
                }
                .font(isCompactHeight ? .subheadline.weight(.black) : .headline.weight(.black))
                .foregroundColor(.saveInk)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .padding(.vertical, isCompactHeight ? 13 : 16)
                .background(primaryDisabled ? Color.saveDisabled.opacity(0.6) : step.tint)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(primaryDisabled)
            .accessibilityIdentifier("onboarding.primary")
            .accessibilityHint(step.primaryHint(language: language))

            if step.isSkippable {
                Button(step.skipTitle(language: language)) {
                    skipCurrentStep()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.saveMutedText)
                .accessibilityIdentifier("onboarding.skip")
            }
        }
        .padding(.bottom, isCompactHeight ? 8 : 20)
        .padding(.top, 6)
    }

    private var primaryDisabled: Bool {
        step == .clue && trimmedClue.isEmpty
    }

    // MARK: - Flow

    private var trimmedClue: String {
        clueText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var stepAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : SaveTheme.Motion.standardSpring
    }

    private var stepTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private func advance() {
        switch step {
        case .language:
            move(to: .clue)
        case .clue:
            guard !trimmedClue.isEmpty else { return }
            move(to: .candidate)
        case .candidate:
            move(to: .mapStamp)
        case .mapStamp:
            finish()
        }
    }

    private func skipCurrentStep() {
        switch step {
        case .language:
            break
        case .clue:
            move(to: .candidate)
        case .candidate:
            move(to: .mapStamp)
        case .mapStamp:
            finish()
        }
    }

    private func goBack() {
        switch step {
        case .language:
            break
        case .clue:
            move(to: .language)
        case .candidate:
            move(to: .clue)
        case .mapStamp:
            move(to: .candidate)
        }
    }

    private func move(to next: OnboardingStep) {
        withAnimation(stepAnimation) {
            step = next
        }
    }

    private func finish() {
        onComplete(trimmedClue.isEmpty ? nil : trimmedClue)
    }

    private func useSampleClue() {
        clueText = language.localized(
            english: "Sample IG Reel: quiet cafe with a tiny patio near the station, tagged @hidden.moon.cafe",
            traditionalChinese: "範例 IG Reels：捷運站旁有小庭院的安靜咖啡店，標記 @hidden.moon.cafe"
        )
    }

    private func chooseLanguage(_ chosen: AppLanguage) {
        withAnimation(stepAnimation) {
            languageSettings.language = chosen
        }
    }
}

// MARK: - Steps

private enum OnboardingStep: Int, CaseIterable {
    case language
    case clue
    case candidate
    case mapStamp

    var isSkippable: Bool {
        self != .language
    }

    var tint: Color {
        switch self {
        case .language: return .saveHoney
        case .clue: return .saveHoney
        case .candidate: return .saveSky
        case .mapStamp: return .saveMint
        }
    }

    func railLabel(language: AppLanguage) -> String {
        switch self {
        case .language: return language.localized(english: "Language", traditionalChinese: "語言")
        case .clue: return language.localized(english: "Clue", traditionalChinese: "線索")
        case .candidate: return language.localized(english: "Review", traditionalChinese: "確認")
        case .mapStamp: return language.localized(english: "Stamp", traditionalChinese: "蓋章")
        }
    }

    func eyebrow(language: AppLanguage) -> String {
        switch self {
        case .language: return language.localized(english: "Welcome", traditionalChinese: "歡迎")
        case .clue: return language.localized(english: "Source Clue", traditionalChinese: "來源線索")
        case .candidate: return language.localized(english: "Review Candidate", traditionalChinese: "待確認地點")
        case .mapStamp: return language.localized(english: "Map Stamp", traditionalChinese: "地圖章")
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .language:
            return language.localized(english: "Hi, I'm Memo.", traditionalChinese: "嗨，我是 Memo。")
        case .clue:
            return language.localized(english: "Drop one messy clue", traditionalChinese: "丟給我一個混亂線索")
        case .candidate:
            return language.localized(english: "Memo found a likely place", traditionalChinese: "Memo 找到一個可能地點")
        case .mapStamp:
            return language.localized(english: "You confirmed it. Stamped.", traditionalChinese: "你確認了，蓋章。")
        }
    }

    func subtitle(language: AppLanguage) -> String {
        switch self {
        case .language:
            return language.localized(
                english: "Pick the language for your place notebook.",
                traditionalChinese: "先選你地點筆記本的語言。"
            )
        case .clue:
            return language.localized(
                english: "A Reel caption, a map link, a friend's message. Memo keeps the source as proof.",
                traditionalChinese: "短影音文案、地圖連結、朋友訊息都行。Memo 會把來源留作證據。"
            )
        case .candidate:
            return language.localized(
                english: "It stays in review until you confirm — no fake pins.",
                traditionalChinese: "在你確認之前都先待確認，不會出現假地點。"
            )
        case .mapStamp:
            return language.localized(
                english: "Only places you confirm become private Map Stamps — then just ask Memo anytime.",
                traditionalChinese: "只有你確認的地點會變成私人地圖章——之後隨時問 Memo 就好。"
            )
        }
    }

    func primaryTitle(language: AppLanguage) -> String {
        switch self {
        case .language:
            return language.localized(english: "Continue", traditionalChinese: "繼續")
        case .clue:
            return language.localized(english: "Find this place", traditionalChinese: "找出這個地點")
        case .candidate:
            return language.localized(english: "Stamp it on my map", traditionalChinese: "蓋上我的地圖")
        case .mapStamp:
            return language.localized(english: "Open SAV-E", traditionalChinese: "打開 SAV-E")
        }
    }

    func primaryHint(language: AppLanguage) -> String {
        switch self {
        case .mapStamp:
            return language.localized(english: "Finishes onboarding and opens the app", traditionalChinese: "完成新手引導並打開 App")
        default:
            return language.localized(english: "Goes to the next onboarding step", traditionalChinese: "前往下一個引導步驟")
        }
    }

    func skipTitle(language: AppLanguage) -> String {
        switch self {
        case .mapStamp:
            return language.localized(english: "Skip and open SAV-E", traditionalChinese: "跳過，直接打開")
        default:
            return language.localized(english: "Skip this step", traditionalChinese: "跳過這一步")
        }
    }
}

// MARK: - Top Bar

private struct OnboardingTopBar: View {
    let step: OnboardingStep
    let language: AppLanguage
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.black))
                    .foregroundColor(.saveInk)
                    .frame(width: 38, height: 38)
                    .background(Color.saveNotebookPage.opacity(step == .language ? 0.24 : 0.78))
                    .overlay(Circle().stroke(Color.saveNotebookLine.opacity(step == .language ? 0.14 : 0.5), lineWidth: 1.2))
                    .clipShape(Circle())
            }
            .opacity(step == .language ? 0.26 : 1)
            .disabled(step == .language)
            .accessibilityIdentifier("onboarding.back")
            .accessibilityLabel(language.localized(english: "Back", traditionalChinese: "上一步"))

            Spacer(minLength: 8)

            OnboardingProgressRail(step: step, language: language)

            Spacer(minLength: 8)

            // Balance the back button so the rail stays centered.
            Color.clear
                .frame(width: 38, height: 38)
        }
    }
}

private struct OnboardingProgressRail: View {
    let step: OnboardingStep
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                if item == step {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.saveInk)
                            .frame(width: 6, height: 6)
                        Text(item.railLabel(language: language))
                            .font(.caption2.weight(.black))
                            .foregroundColor(.saveInk)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(item.tint.opacity(0.66))
                    .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.62), lineWidth: 1.2))
                    .clipShape(Capsule())
                } else {
                    Circle()
                        .fill(item.rawValue < step.rawValue ? Color.saveHoney : Color.saveNotebookPage.opacity(0.84))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color.saveNotebookLine.opacity(0.44), lineWidth: 1))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(railAccessibilityLabel)
    }

    private var railAccessibilityLabel: String {
        let position = step.rawValue + 1
        let total = OnboardingStep.allCases.count
        let name = step.railLabel(language: language)
        switch language {
        case .english:
            return "Onboarding step \(position) of \(total): \(name)"
        case .traditionalChinese:
            return "新手引導第 \(position) 步，共 \(total) 步：\(name)"
        }
    }
}

// MARK: - Step Title

private struct OnboardingStepTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let tint: Color
    let isCompactHeight: Bool

    var body: some View {
        VStack(spacing: isCompactHeight ? 6 : 10) {
            Text(eyebrow)
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(tint.opacity(0.5))
                .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.5), lineWidth: 1))
                .clipShape(Capsule())

            Text(title)
                .font(.system(size: isCompactHeight ? 24 : 29, weight: .black, design: .rounded))
                .foregroundColor(.saveInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(isCompactHeight ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundColor(.saveMutedText)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(3)
                .minimumScaleFactor(0.84)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Language Step

private struct LanguageStepView: View {
    let language: AppLanguage
    let isCompactHeight: Bool
    let onChoose: (AppLanguage) -> Void

    var body: some View {
        VStack(spacing: isCompactHeight ? 16 : 26) {
            Spacer(minLength: 0)

            MemoMascotMark(size: isCompactHeight ? 96 : 124, framed: false)
                .shadow(color: Color.saveInk.opacity(0.12), radius: 16, x: 0, y: 9)

            OnboardingStepTitle(
                eyebrow: OnboardingStep.language.eyebrow(language: language),
                title: OnboardingStep.language.title(language: language),
                subtitle: OnboardingStep.language.subtitle(language: language),
                tint: OnboardingStep.language.tint,
                isCompactHeight: isCompactHeight
            )

            VStack(spacing: 12) {
                ForEach(AppLanguage.allCases) { option in
                    LanguageChoiceCard(
                        option: option,
                        isSelected: option == language,
                        onChoose: { onChoose(option) }
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct LanguageChoiceCard: View {
    let option: AppLanguage
    let isSelected: Bool
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 12) {
                Text(option == .english ? "EN" : "繁")
                    .font(.headline.weight(.black))
                    .foregroundColor(.saveInk)
                    .frame(width: 42, height: 42)
                    .background(isSelected ? Color.saveHoney.opacity(0.85) : Color.saveNotebookPage.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color.saveNotebookLine.opacity(0.62), lineWidth: 1.3)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .font(.headline.weight(.black))
                        .foregroundColor(.saveInk)

                    Text(caption)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.saveMutedText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.black))
                    .foregroundColor(isSelected ? .saveInk : .saveMutedText.opacity(0.5))
            }
            .padding(14)
            .background(isSelected ? Color.saveHoney.opacity(0.34) : Color.saveNotebookPage.opacity(0.86))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(isSelected ? 1 : 0.4), lineWidth: isSelected ? 2 : 1.3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.language.\(option.rawValue)")
        .accessibilityLabel(option.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var caption: String {
        switch option {
        case .english:
            return "Keep my place memory in English"
        case .traditionalChinese:
            return "用繁體中文記住我的地點"
        }
    }
}

// MARK: - Clue Step

private struct ClueStepView: View {
    @Binding var clueText: String
    let language: AppLanguage
    let isCompactHeight: Bool
    let reduceMotion: Bool
    let onUseSample: () -> Void

    @State private var chipsSettled = false

    var body: some View {
        VStack(spacing: isCompactHeight ? 12 : 18) {
            Spacer(minLength: 0)

            if !isCompactHeight {
                sourceChipsRow
            }

            OnboardingStepTitle(
                eyebrow: OnboardingStep.clue.eyebrow(language: language),
                title: OnboardingStep.clue.title(language: language),
                subtitle: OnboardingStep.clue.subtitle(language: language),
                tint: OnboardingStep.clue.tint,
                isCompactHeight: isCompactHeight
            )

            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.saveNotebookPage.opacity(0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.saveNotebookLine.opacity(0.5), lineWidth: 1.5)
                        )

                    TextEditor(text: $clueText)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.saveInk)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: isCompactHeight ? 118 : 148)
                        .accessibilityIdentifier("onboarding.clueEditor")
                        .accessibilityLabel(language.localized(
                            english: "Place clue text",
                            traditionalChinese: "地點線索文字"
                        ))

                    if clueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(language.localized(
                            english: "Example: IG Reel caption says quiet cafe near the station, tagged @hidden.moon.cafe...",
                            traditionalChinese: "例如：IG Reels 文案寫捷運站旁安靜咖啡，標記 @hidden.moon.cafe..."
                        ))
                        .font(.body.weight(.semibold))
                        .foregroundColor(.saveMutedText.opacity(0.72))
                        .padding(.horizontal, 17)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }

                HStack {
                    Button(action: onUseSample) {
                        Label(
                            language.localized(english: "Try sample clue", traditionalChinese: "試用範例線索"),
                            systemImage: "wand.and.stars"
                        )
                        .font(.subheadline.weight(.black))
                        .foregroundColor(.saveInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.saveHoney.opacity(0.56))
                        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.52), lineWidth: 1.2))
                        .clipShape(Capsule())
                    }
                    .accessibilityIdentifier("onboarding.sampleClue")

                    Spacer(minLength: 0)
                }
            }

            trustNote

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            chipsSettled = true
        }
    }

    private var sourceChipsRow: some View {
        HStack(spacing: 14) {
            sourceChip(label: "IG", icon: "camera.fill", tint: .savePink, restingOffset: -5, order: 0)
            sourceChip(label: "CHAT", icon: "bubble.left.and.bubble.right.fill", tint: .saveSky, restingOffset: 4, order: 1)
            MemoMascotMark(size: 56, framed: false)
                .opacity(chipsSettled ? 1 : 0)
                .animation(.easeInOut(duration: 0.3), value: chipsSettled)
            sourceChip(label: "MAP", icon: "map.fill", tint: .saveMint, restingOffset: 5, order: 2)
            sourceChip(label: "NOTE", icon: "note.text", tint: .saveHoney, restingOffset: -4, order: 3)
        }
        .accessibilityHidden(true)
    }

    private func sourceChip(label: String, icon: String, tint: Color, restingOffset: CGFloat, order: Int) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.subheadline.weight(.black))
            Text(label)
                .font(.system(size: 9, weight: .black))
        }
        .foregroundColor(.saveInk)
        .frame(width: 52, height: 50)
        .background(tint.opacity(0.74))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.4), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.saveInk.opacity(0.08), radius: 9, x: 0, y: 6)
        .rotationEffect(.degrees(restingOffset > 0 ? 4 : -5))
        .offset(y: chipsSettled ? restingOffset : restingOffset - 18)
        .opacity(chipsSettled ? 1 : 0)
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.18)
                : .spring(response: 0.55, dampingFraction: 0.66).delay(Double(order) * 0.07),
            value: chipsSettled
        )
    }

    private var trustNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)

            Text(language.localized(
                english: "Private food + travel memory, not public reviews.",
                traditionalChinese: "這是私人的美食與旅行記憶，不是公開評論。"
            ))
            .font(.footnote.weight(.bold))
            .foregroundColor(.saveMutedText)
            .lineLimit(2)
            .minimumScaleFactor(0.84)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.saveNotebookPage.opacity(0.74))
        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.38), lineWidth: 1))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Proof Demo Canvas

/// Animated scripted demo: one clue card becomes a Review Candidate, then a
/// stamped place on a mini map. No network.
private struct ProofDemoCanvas: View {
    let step: OnboardingStep
    let clueText: String
    let language: AppLanguage
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    private static let finalPhase = 3

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.saveNotebookPage.opacity(0.97),
                            Color.saveNotebookPage.opacity(0.78)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(0.62), lineWidth: 1.6)
                )

            sceneContent
                .padding(14)

            memoGuide
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.saveInk.opacity(0.08), radius: 16, x: 0, y: 10)
        .task(id: step) {
            await runPhaseScript()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sceneAccessibilityLabel)
    }

    @MainActor
    private func runPhaseScript() async {
        phase = 0
        if reduceMotion {
            phase = Self.finalPhase
            return
        }
        for next in 1...Self.finalPhase {
            try? await Task.sleep(nanoseconds: 430_000_000)
            if Task.isCancelled { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                phase = next
            }
        }
    }

    @ViewBuilder
    private var sceneContent: some View {
        switch step {
        case .candidate:
            candidateScene
                .transition(sceneTransition)
        case .mapStamp:
            mapStampScene
                .transition(sceneTransition)
        default:
            EmptyView()
        }
    }

    private var sceneTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
    }

    // MARK: Candidate scene

    private var candidateScene: some View {
        VStack(spacing: 10) {
            clueNote
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk.opacity(0.5))
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveHoney)
            }
            .opacity(phase >= 1 ? 1 : 0)

            candidateCard
                .opacity(phase >= 1 ? 1 : 0)
                .offset(y: phase >= 1 || reduceMotion ? 0 : 12)

            Spacer(minLength: 36)
        }
    }

    private var clueNote: some View {
        HStack(spacing: 9) {
            Image(systemName: "paperclip")
                .font(.caption.weight(.black))
                .foregroundColor(.saveMutedText)

            Text(clueLine)
                .font(.caption.weight(.bold))
                .foregroundColor(.saveInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.saveSky.opacity(0.3))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.38), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .rotationEffect(.degrees(-1.4))
    }

    private var candidateCard: some View {
        HStack(alignment: .top, spacing: 12) {
            SaveMemoryBadge(state: .ready, size: 44)

            VStack(alignment: .leading, spacing: 8) {
                Text(language.localized(english: "Review Candidate", traditionalChinese: "待確認地點"))
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveMutedText)

                Text("Hidden Moon Cafe?")
                    .font(.headline.weight(.black))
                    .foregroundColor(.saveInk)

                evidenceLine(
                    icon: "checkmark.seal.fill",
                    text: language.localized(english: "Name clue found", traditionalChinese: "找到名稱線索"),
                    tint: .saveMint,
                    visibleAt: 1
                )
                evidenceLine(
                    icon: "link",
                    text: language.localized(english: "Source kept as proof", traditionalChinese: "來源已留作證據"),
                    tint: .saveSky,
                    visibleAt: 2
                )
                evidenceLine(
                    icon: "exclamationmark.triangle.fill",
                    text: language.localized(english: "Missing exact address + pin", traditionalChinese: "還缺精確地址與座標"),
                    tint: .saveHoney,
                    visibleAt: 3
                )
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.saveNotebookPage.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.5), lineWidth: 1.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func evidenceLine(icon: String, text: String, tint: Color, visibleAt: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 21, height: 21)
                .background(tint.opacity(0.62))
                .clipShape(Circle())

            Text(text)
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .opacity(phase >= visibleAt ? 1 : 0)
        .offset(x: phase >= visibleAt || reduceMotion ? 0 : -8)
    }

    // MARK: Map Stamp scene

    private var mapStampScene: some View {
        ZStack(alignment: .bottom) {
            OnboardingMiniMap(stampVisible: phase >= 1, reduceMotion: reduceMotion)

            VStack(spacing: 8) {
                if phase >= 2 {
                    confirmedCapsule
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                }

                stampedPlaceCard
            }
            .padding(10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var confirmedCapsule: some View {
        Label(
            language.localized(english: "Confirmed by you", traditionalChinese: "由你確認"),
            systemImage: "hand.thumbsup.fill"
        )
        .font(.caption.weight(.black))
        .foregroundColor(.saveInk)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.saveMint.opacity(0.88))
        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.5), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var stampedPlaceCard: some View {
        HStack(spacing: 11) {
            SaveMemoryBadge(state: .saved(.cafe), size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hidden Moon Cafe")
                    .font(.subheadline.weight(.black))
                    .foregroundColor(.saveInk)

                Text(language.localized(
                    english: "Map Stamp · source kept · private",
                    traditionalChinese: "地圖章 · 保留來源 · 私人"
                ))
                .font(.caption2.weight(.bold))
                .foregroundColor(.saveMutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Color.saveNotebookPage.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.5), lineWidth: 1.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Memo guide

    private var memoGuide: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom, spacing: 6) {
                Spacer()

                if step != .mapStamp {
                    Text(memoLine)
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.saveBlush.opacity(0.94))
                        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.42), lineWidth: 1))
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)

                    MemoMascotMark(size: 38, framed: false)
                }
            }
            .padding(10)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var memoLine: String {
        switch step {
        case .candidate:
            return language.localized(english: "I found this — your call.", traditionalChinese: "我找到這個——由你決定。")
        default:
            return ""
        }
    }

    // MARK: Helpers

    private var clueLine: String {
        if clueText.isEmpty {
            return language.localized(
                english: "Sample Reel: quiet cafe near the station",
                traditionalChinese: "範例 Reels：捷運站旁安靜咖啡"
            )
        }
        return String(clueText.prefix(58))
    }

    private var sceneAccessibilityLabel: String {
        switch (step, language) {
        case (.candidate, .english):
            return "Demo: Memo turned the clue into Review Candidate Hidden Moon Cafe. Name found, source kept, exact address still missing."
        case (.candidate, .traditionalChinese):
            return "示範：Memo 把線索變成待確認地點 Hidden Moon Cafe。找到名稱、保留來源，還缺精確地址。"
        case (.mapStamp, .english):
            return "Demo: Hidden Moon Cafe is confirmed and stamped onto your private map."
        case (.mapStamp, .traditionalChinese):
            return "示範：Hidden Moon Cafe 已確認，蓋章到你的私人地圖。"
        default:
            return ""
        }
    }
}

// MARK: - Mini Map

private struct OnboardingMiniMap: View {
    let stampVisible: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Color.saveMint.opacity(0.26)

            GeometryReader { proxy in
                let w = proxy.size.width
                let h = proxy.size.height

                Path { path in
                    path.move(to: CGPoint(x: w * 0.04, y: h * 0.24))
                    path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.5))
                    path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.3))
                    path.move(to: CGPoint(x: w * 0.12, y: h * 0.86))
                    path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.48))
                    path.addLine(to: CGPoint(x: w * 0.96, y: h * 0.82))
                }
                .stroke(
                    Color.saveNotebookLine.opacity(0.2),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                )

                ghostPin(icon: "fork.knife", tint: .saveSky)
                    .position(x: w * 0.78, y: h * 0.26)
                ghostPin(icon: "camera.fill", tint: .savePink)
                    .position(x: w * 0.88, y: h * 0.66)

                stampPin
                    .position(x: w * 0.38, y: h * 0.42)
            }
        }
    }

    private func ghostPin(icon: String, tint: Color) -> some View {
        Image(systemName: icon)
            .font(.caption.weight(.black))
            .foregroundColor(.saveInk)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.8))
            .overlay(Circle().stroke(Color.saveNotebookBackground.opacity(0.84), lineWidth: 2))
            .clipShape(Circle())
            .opacity(0.66)
    }

    private var stampPin: some View {
        ZStack {
            Circle()
                .stroke(Color.saveHoney.opacity(0.5), lineWidth: 3)
                .frame(width: 62, height: 62)
                .opacity(stampVisible ? 1 : 0)

            Image(systemName: "cup.and.saucer.fill")
                .font(.headline.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 44, height: 44)
                .background(Color.saveHoney.opacity(0.94))
                .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1.8))
                .clipShape(Circle())
                .shadow(color: Color.saveInk.opacity(0.18), radius: 7, x: 0, y: 4)
        }
        .scaleEffect(stampVisible ? 1 : (reduceMotion ? 1 : 2.1))
        .opacity(stampVisible ? 1 : 0)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.6),
            value: stampVisible
        )
    }
}

#Preview {
    OnboardingView { _ in }
        .environment(\.appLanguageSettings, AppLanguageSettings())
}
