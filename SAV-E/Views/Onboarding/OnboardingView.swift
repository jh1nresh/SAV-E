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
            let stepBodyUsesCompactLayout = isCompactHeight || (
                step == .language && proxy.size.height < 900
            )
            let horizontalPadding: CGFloat = proxy.size.width < 380 ? 16 : 24
            let bottomActionLift = proxy.safeAreaInsets.bottom + 22

            ZStack(alignment: .bottom) {
                AtlasCanvas()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    OnboardingTopBar(
                        step: step,
                        language: language,
                        onBack: goBack
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, isCompactHeight ? 6 : -14)

                    stepBody(isCompactHeight: stepBodyUsesCompactLayout)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, (step.isSkippable ? 102 : 82) + bottomActionLift)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                bottomActions(isCompactHeight: isCompactHeight)
                    .padding(.horizontal, horizontalPadding)
                    .background(SaveAtlasPalette.canvas.opacity(0.96))
                    .offset(y: -bottomActionLift)
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
        VStack(spacing: isCompactHeight ? 8 : 20) {
            OnboardingStepTitle(
                eyebrow: step.eyebrow(language: language),
                title: step.title(language: language),
                subtitle: step.subtitle(language: language),
                isCompactHeight: isCompactHeight,
                showsEyebrow: false
            )
            .id(step)
            .transition(.opacity)

            ProofDemoCanvas(
                step: step,
                clueText: trimmedClue,
                language: language,
                isCompactHeight: isCompactHeight,
                height: proofStageHeight(isCompactHeight: isCompactHeight)
            )

            Spacer(minLength: 0)
        }
        .padding(.top, isCompactHeight ? 10 : 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func proofStageHeight(isCompactHeight: Bool) -> CGFloat {
        guard !isCompactHeight else { return 300 }
        return step == .mapStamp ? 506 : 496
    }

    // MARK: - Bottom Actions

    private func bottomActions(isCompactHeight: Bool) -> some View {
        VStack(spacing: isCompactHeight ? 6 : 10) {
            Button(action: advance) {
                HStack(spacing: 8) {
                    Text(step.primaryTitle(language: language))
                    Image(systemName: step == .mapStamp ? "arrow.right" : "chevron.right")
                        .font(.subheadline.weight(.bold))
                }
                .font(SaveAtlasType.strong(isCompactHeight ? 16 : 18))
                .foregroundStyle(SaveAtlasPalette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity)
                .padding(.vertical, isCompactHeight ? 13 : 18)
                .background(
                    primaryDisabled
                        ? SaveAtlasPalette.muted.opacity(0.36)
                        : SaveAtlasPalette.coral
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(SaveAtlasPalette.ink.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(primaryDisabled)
            .accessibilityIdentifier("onboarding.primary")
            .accessibilityHint(step.primaryHint(language: language))

            if step.isSkippable {
                // The approved composition reserves this baseline below the
                // CTA without rendering a second visible action. Preserve the
                // existing one-step skip affordance for accessibility and UI
                // regression coverage without changing the approved artwork.
                Button(action: skipCurrentStep) {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 17)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.skip")
                .accessibilityLabel(step.skipTitle(language: language))
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
            english: "IG Reel: quiet cafe with a tiny patio near the station, tagged @hidden.moon.cafe",
            traditionalChinese: "IG Reels：捷運站旁有小庭院的安靜咖啡店，標記 @hidden.moon.cafe"
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
                english: "A link, caption, or note is enough.",
                traditionalChinese: "連結、文案或筆記都可以。"
            )
        case .candidate:
            return language.localized(
                english: "It stays in review until you confirm.",
                traditionalChinese: "在你確認之前都會留在待確認。"
            )
        case .mapStamp:
            return language.localized(
                english: "Only places you confirm become private Map Stamps.",
                traditionalChinese: "只有你確認的地點會變成私人地圖章。"
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
            return language.localized(english: "Confirm this place", traditionalChinese: "確認這個地點")
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

struct SaveFirstRunBrandLockup: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            MemoMark(size: compact ? 28 : 36)

            Text("SAV-E")
                .font(SaveAtlasType.strong(compact ? 20 : 25))
                .tracking(1)
                .foregroundStyle(SaveAtlasPalette.forest)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SAV-E")
    }
}

private struct OnboardingTopBar: View {
    let step: OnboardingStep
    let language: AppLanguage
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 26) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .frame(width: 38, height: 38)
                        .background(SaveAtlasPalette.paper.opacity(step == .language ? 0.38 : 0.96), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(SaveAtlasPalette.line.opacity(step == .language ? 0.16 : 0.42), lineWidth: 1)
                        }
                }
                .opacity(step == .language ? 0.30 : 1)
                .disabled(step == .language)
                .accessibilityIdentifier("onboarding.back")
                .accessibilityLabel(language.localized(english: "Back", traditionalChinese: "上一步"))

                Spacer(minLength: 8)

                SaveFirstRunBrandLockup()

                Spacer(minLength: 8)

                Text("\(step.rawValue + 1)/\(OnboardingStep.allCases.count)")
                    .font(SaveAtlasType.strong(12))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .frame(width: 38, height: 38)
                    .background(SaveAtlasPalette.mint, in: SavePostcardSealShape())
                    .overlay {
                        SavePostcardSealShape()
                            .stroke(SaveAtlasPalette.forest.opacity(0.34), lineWidth: 1)
                    }
            }

            OnboardingProgressRail(step: step, language: language)
        }
    }
}

private struct OnboardingProgressRail: View {
    let step: OnboardingStep
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(progressTint(for: item))
                        .frame(height: item == step ? 6 : 4)

                    Text(item.railLabel(language: language).uppercased())
                        .font(SaveAtlasType.strong(9))
                        .tracking(0.45)
                        .foregroundStyle(item == step ? SaveAtlasPalette.forest : SaveAtlasPalette.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(railAccessibilityLabel)
    }

    private func progressTint(for item: OnboardingStep) -> Color {
        if item.rawValue < step.rawValue { return SaveAtlasPalette.mint }
        if item == step { return SaveAtlasPalette.coral }
        return SaveAtlasPalette.line.opacity(0.22)
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
    let isCompactHeight: Bool
    var showsEyebrow = true

    var body: some View {
        VStack(spacing: isCompactHeight ? 6 : 10) {
            if showsEyebrow {
                Text(eyebrow)
                    .font(SaveAtlasType.strong(10))
                    .tracking(0.9)
                    .foregroundStyle(SaveAtlasPalette.coral)
            }

            Text(title)
                .font(SaveAtlasType.strong(isCompactHeight ? 26 : 34, relativeTo: .title))
                .foregroundStyle(SaveAtlasPalette.forest)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(SaveAtlasType.body(isCompactHeight ? 13 : 15))
                .foregroundStyle(SaveAtlasPalette.muted)
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

            OnboardingStepTitle(
                eyebrow: OnboardingStep.language.eyebrow(language: language),
                title: OnboardingStep.language.title(language: language),
                subtitle: OnboardingStep.language.subtitle(language: language),
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
                    .font(SaveAtlasType.strong(17))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .frame(width: 48, height: 48)
                    .background(
                        isSelected ? SaveAtlasPalette.mint : SaveAtlasPalette.kraft.opacity(0.48),
                        in: SavePostcardSealShape()
                    )
                    .overlay {
                        SavePostcardSealShape()
                            .stroke(
                                SaveAtlasPalette.forest.opacity(isSelected ? 0.62 : 0.28),
                                style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                            )
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .font(SaveAtlasType.strong(18))
                        .foregroundStyle(SaveAtlasPalette.forest)

                    Text(caption)
                        .font(SaveAtlasType.body(12))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(
                        isSelected
                            ? SaveAtlasPalette.forest
                            : SaveAtlasPalette.line.opacity(0.46)
                    )
            }
            .padding(14)
            .background(SaveAtlasPalette.paper.opacity(0.98))
            .padding(4)
            .background {
                SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                    .fill(isSelected ? SaveAtlasPalette.mint.opacity(0.74) : SaveAtlasPalette.kraft.opacity(0.46))
            }
            .overlay {
                SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                    .stroke(
                        isSelected
                            ? SaveAtlasPalette.forest.opacity(0.62)
                            : SaveAtlasPalette.line.opacity(0.46),
                        style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                    )
            }
            .shadow(color: SaveAtlasPalette.ink.opacity(isSelected ? 0.07 : 0.035), radius: 5, y: 2)
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

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepTitle(
                eyebrow: OnboardingStep.clue.eyebrow(language: language),
                title: OnboardingStep.clue.title(language: language),
                subtitle: OnboardingStep.clue.subtitle(language: language),
                isCompactHeight: isCompactHeight,
                showsEyebrow: false
            )

            CluePocketStage(
                clueText: $clueText,
                language: language,
                isCompactHeight: isCompactHeight
            )
            .frame(height: isCompactHeight ? 250 : 460)
            .padding(.top, isCompactHeight ? 8 : 20)

            HStack(spacing: 10) {
                Button(action: onUseSample) {
                    Label(
                        language.localized(english: "Try sample", traditionalChinese: "試用範例"),
                        systemImage: "airplane"
                    )
                    .font(SaveAtlasType.strong(13))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .lineLimit(1)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(SaveAtlasPalette.paper.opacity(0.96))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                SaveAtlasPalette.forest.opacity(0.56),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .accessibilityIdentifier("onboarding.sampleClue")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isCompactHeight ? 4 : 4)

            Spacer(minLength: 0)
        }
        .padding(.top, isCompactHeight ? 8 : 20)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct CluePocketStage: View {
    @Binding var clueText: String
    let language: AppLanguage
    let isCompactHeight: Bool

    var body: some View {
        OnboardingOpenEnvelopeShell(
            caption: language.localized(
                english: "Memo keeps the source as proof.",
                traditionalChinese: "Memo 會把來源留作證據。"
            ),
            isCompactHeight: isCompactHeight,
            memoPose: .clue
        ) { scale, _ in
            OnboardingSourceTicket(
                clueText: $clueText,
                language: language,
                isCompactHeight: isCompactHeight
            )
            .frame(width: 300, height: 286)
            .scaleEffect(scale, anchor: .bottom)
            .frame(width: 300 * scale, height: 286 * scale)
            .rotationEffect(.degrees(-1.2))
            .offset(x: -8 * scale, y: -153 * scale)
        }
        .accessibilityIdentifier("onboarding.pocketStage.clue")
    }
}

private struct OnboardingSourceTicket: View {
    @Binding var clueText: String
    let language: AppLanguage
    let isCompactHeight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 7 : 10) {
            Text(language.localized(english: "Source Clue", traditionalChinese: "來源線索").uppercased())
                .font(SaveAtlasType.strong(10))
                .tracking(1)
                .foregroundStyle(SaveAtlasPalette.coral)
                .frame(maxWidth: .infinity, alignment: .center)

            ZStack(alignment: .topLeading) {
                linedNoteBackground

                TextEditor(text: $clueText)
                    .font(.custom("Noteworthy-Light", size: isCompactHeight ? 13 : 21, relativeTo: .headline))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .lineSpacing(2)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .frame(height: isCompactHeight ? 76 : 126)
                    .accessibilityIdentifier("onboarding.clueEditor")
                    .accessibilityLabel(language.localized(
                        english: "Place clue text",
                        traditionalChinese: "地點線索文字"
                    ))

                if clueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(language.localized(
                        english: "IG Reel: quiet cafe near the station, tagged @hidden.moon.cafe...",
                        traditionalChinese: "IG Reels：捷運站旁的安靜咖啡，標記 @hidden.moon.cafe..."
                    ))
                    .font(SaveAtlasType.body(isCompactHeight ? 12 : 13))
                    .foregroundStyle(SaveAtlasPalette.muted.opacity(0.70))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }

            OnboardingDashedRule(color: SaveAtlasPalette.coral.opacity(0.56))

            HStack(spacing: 9) {
                OnboardingInstagramMark()
                VStack(alignment: .leading, spacing: 1) {
                    Text("instagram.com/reel/")
                    Text("C8xK...7bQ")
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(language.localized(english: "Saved", traditionalChinese: "保存"))
                    Text(language.localized(english: "Oct 12", traditionalChinese: "10 月 12 日"))
                }
            }
            .font(SaveAtlasType.body(11))
            .foregroundStyle(SaveAtlasPalette.muted)
        }
        .padding(isCompactHeight ? 10 : 12)
        .frame(height: isCompactHeight ? 220 : 286)
        .background {
            ZStack {
                SaveAtlasPalette.paper
                SaveAtlasPalette.coral.opacity(0.14)
                OnboardingTicketPaperGrain()
            }
        }
        .onboardingPostageTicket(
            tint: SaveAtlasPalette.coral,
            edge: SaveAtlasPalette.coral
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.sourceTicket")
    }

    private var linedNoteBackground: some View {
        Canvas { context, size in
            let spacing: CGFloat = isCompactHeight ? 18 : 27
            for y in stride(from: spacing, through: size.height, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(SaveAtlasPalette.line.opacity(0.22)), lineWidth: 1)
            }
        }
        .frame(height: isCompactHeight ? 76 : 126)
        .allowsHitTesting(false)
    }
}

private struct OnboardingInstagramMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(lineWidth: 2.2)
            Circle()
                .stroke(lineWidth: 2.2)
                .frame(width: 11, height: 11)
            Circle()
                .fill()
                .frame(width: 3.5, height: 3.5)
                .offset(x: 9, y: -9)
        }
        .foregroundStyle(SaveAtlasPalette.muted)
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}

private struct OnboardingDashedRule: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
            )
        }
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

private struct OnboardingTicketPaperGrain: View {
    var body: some View {
        Image("PaperTexture")
            .resizable(resizingMode: .tile)
            .opacity(0.045)
            .blendMode(.multiply)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Proof Pocket

/// Animated local proof: one retained source ticket advances from Review
/// Candidate to a user-confirmed saved postcard. No network.
private struct ProofDemoCanvas: View {
    let step: OnboardingStep
    let clueText: String
    let language: AppLanguage
    let isCompactHeight: Bool
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    private static let finalPhase = 3

    var body: some View {
        sceneContent
        .frame(height: height)
        .task(id: step) {
            await runPhaseScript()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(stageAccessibilityIdentifier)
        .accessibilityLabel(sceneAccessibilityLabel)
        .accessibilityValue(phase == Self.finalPhase ? "ready" : "preparing")
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
            ReviewPocketStage(
                clueLine: clueLine,
                language: language,
                isCompactHeight: isCompactHeight,
                phase: phase
            )
            .transition(sceneTransition)
        case .mapStamp:
            MapStampPocketStage(
                language: language,
                isCompactHeight: isCompactHeight,
                phase: phase
            )
            .transition(sceneTransition)
        default:
            EmptyView()
        }
    }

    private var sceneTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97))
    }

    // MARK: Helpers

    private var clueLine: String {
        if clueText.isEmpty {
            return language.localized(
                english: "IG Reel: quiet cafe near the station",
                traditionalChinese: "IG Reels：捷運站旁安靜咖啡"
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

    private var stageAccessibilityIdentifier: String {
        switch step {
        case .candidate:
            return "onboarding.pocketStage.review"
        case .mapStamp:
            return "onboarding.pocketStage.mapStamp"
        default:
            return "onboarding.pocketStage"
        }
    }
}

private struct ReviewPocketStage: View {
    let clueLine: String
    let language: AppLanguage
    let isCompactHeight: Bool
    let phase: Int

    var body: some View {
        OnboardingOpenEnvelopeShell(
            caption: language.localized(
                english: "Memo keeps the source as proof.",
                traditionalChinese: "Memo 會把來源留作證據。"
            ),
            isCompactHeight: isCompactHeight,
            memoPose: .review
        ) { scale, _ in
            ZStack(alignment: .bottom) {
                OnboardingSourceBackingTicket(clueLine: clueLine, language: language)
                    .frame(width: 300, height: 116)
                    .scaleEffect(scale, anchor: .bottom)
                    .frame(width: 300 * scale, height: 116 * scale)
                    .rotationEffect(.degrees(-1.2))
                    .offset(x: -12 * scale, y: -360 * scale)

                if phase >= 1 {
                    OnboardingReviewTicket(
                        language: language,
                        isCompactHeight: isCompactHeight,
                        phase: phase
                    )
                    .frame(width: 338, height: 302)
                    .scaleEffect(scale, anchor: .bottom)
                    .frame(width: 338 * scale, height: 302 * scale)
                    .offset(x: -10 * scale, y: -126 * scale)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct OnboardingSourceBackingTicket: View {
    let clueLine: String
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 8) {
            Text(language.localized(english: "Source Clue", traditionalChinese: "來源線索").uppercased())
                .font(SaveAtlasType.strong(10))
                .tracking(1)
                .foregroundStyle(SaveAtlasPalette.coral)

            Rectangle()
                .fill(SaveAtlasPalette.line.opacity(0.20))
                .frame(height: 1)

            Text(clueLine)
                .font(SaveAtlasType.editorial(12))
                .foregroundStyle(SaveAtlasPalette.ink.opacity(0.72))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .frame(height: 108, alignment: .top)
        .background {
            ZStack {
                SaveAtlasPalette.paper
                SaveAtlasPalette.coral.opacity(0.16)
                OnboardingTicketPaperGrain()
            }
        }
        .onboardingPostageTicket(
            tint: SaveAtlasPalette.coral,
            edge: SaveAtlasPalette.coral
        )
        .accessibilityHidden(true)
    }
}

private struct OnboardingReviewTicket: View {
    let language: AppLanguage
    let isCompactHeight: Bool
    let phase: Int

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 7 : 14) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(language.localized(english: "Review Candidate", traditionalChinese: "待確認地點").uppercased())
                        .font(SaveAtlasType.strong(14))
                        .tracking(0.8)
                        .foregroundStyle(Color.saveBlueInk)
                    Text("Hidden Moon Cafe?")
                        .font(SaveAtlasType.strong(isCompactHeight ? 18 : 38, relativeTo: .headline))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 0)

                Image("OnboardingMoonMug")
                    .resizable()
                    .scaledToFit()
                    .frame(width: isCompactHeight ? 42 : 62, height: isCompactHeight ? 42 : 62)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, isCompactHeight ? 0 : 12)

            OnboardingDashedRule(color: Color.saveBlueInk.opacity(0.42))

            HStack(alignment: .top, spacing: 6) {
                evidenceMark(
                    icon: "checkmark.seal.fill",
                    title: language.localized(english: "Name\nfound", traditionalChinese: "找到\n名稱"),
                    tint: SaveAtlasPalette.mint,
                    visibleAt: 1
                )

                Divider()
                    .overlay(Color.saveBlueInk.opacity(0.18))
                    .frame(height: isCompactHeight ? 48 : 58)

                evidenceMark(
                    icon: "link",
                    title: language.localized(english: "Source\nkept", traditionalChinese: "保留\n來源"),
                    tint: SaveAtlasPalette.sky,
                    visibleAt: 2
                )

                Divider()
                    .overlay(Color.saveBlueInk.opacity(0.18))
                    .frame(height: isCompactHeight ? 48 : 58)

                evidenceMark(
                    icon: "questionmark",
                    title: language.localized(english: "Exact pin\nmissing", traditionalChinese: "還缺\n座標"),
                    tint: SaveAtlasPalette.kraft,
                    visibleAt: 3
                )
            }
            .padding(.vertical, isCompactHeight ? 1 : 4)
            .offset(x: isCompactHeight ? 0 : -14)

            Divider()
                .overlay(Color.saveBlueInk.opacity(0.24))

            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "paperclip")
                    .font(.caption.weight(.bold))

                VStack(alignment: .leading, spacing: 1) {
                    Text(language.localized(english: "From IG Reel", traditionalChinese: "來自 IG Reels"))
                    Text("instagram.com/reel/C8xK...7bQ")
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(language.localized(english: "Saved", traditionalChinese: "保存"))
                    Text(language.localized(english: "Oct 12", traditionalChinese: "10 月 12 日"))
                }
            }
            .font(SaveAtlasType.body(isCompactHeight ? 9 : 10))
            .foregroundStyle(SaveAtlasPalette.muted)
            .padding(.leading, isCompactHeight ? 0 : 5)
        }
        .padding(
            EdgeInsets(
                top: isCompactHeight ? 10 : 23,
                leading: isCompactHeight ? 10 : 13,
                bottom: isCompactHeight ? 10 : 13,
                trailing: isCompactHeight ? 10 : 13
            )
        )
        .frame(minHeight: isCompactHeight ? 154 : 307, alignment: .top)
        .background {
            ZStack {
                SaveAtlasPalette.paper
                SaveAtlasPalette.sky.opacity(0.22)
                OnboardingTicketPaperGrain()
            }
        }
        .onboardingPostageTicket(
            tint: SaveAtlasPalette.sky,
            edge: Color.saveBlueInk
        )
        .accessibilityIdentifier("onboarding.reviewTicket")
    }

    @ViewBuilder
    private func evidenceMark(icon: String, title: String, tint: Color, visibleAt: Int) -> some View {
        if phase >= visibleAt {
            VStack(spacing: isCompactHeight ? 5 : 7) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .frame(
                        width: isCompactHeight ? 30 : 38,
                        height: isCompactHeight ? 30 : 38
                    )
                    .background(tint, in: SavePostcardSealShape())

                Text(title)
                    .font(SaveAtlasType.strong(isCompactHeight ? 10 : 14))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityIdentifier("onboarding.reviewEvidence.\(visibleAt)")
        } else {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 52)
                .accessibilityHidden(true)
        }
    }
}

private struct MapStampPocketStage: View {
    let language: AppLanguage
    let isCompactHeight: Bool
    let phase: Int

    var body: some View {
        OnboardingOpenEnvelopeShell(
            caption: language.localized(
                english: "Memo keeps the source as proof.",
                traditionalChinese: "Memo 會把來源留作證據。"
            ),
            isCompactHeight: isCompactHeight,
            memoPose: .stamp
        ) { scale, _ in
            if phase >= 1 {
                OnboardingSavedPostcard(language: language)
                    .frame(width: 340, height: 344)
                    .scaleEffect(scale, anchor: .bottom)
                    .frame(width: 340 * scale, height: 344 * scale)
                    .offset(x: -13 * scale, y: -123 * scale)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

private struct OnboardingSavedPostcard: View {
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(language.localized(
                english: "★ Lifted Saved Postcard ★",
                traditionalChinese: "★ 已提起的收藏明信片 ★"
            ).uppercased())
                .font(SaveAtlasType.strong(12))
                .tracking(0.8)
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hidden Moon Cafe")
                        .font(SaveAtlasType.strong(30, relativeTo: .headline))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Label(
                        language.localized(english: "Confirmed by you", traditionalChinese: "由你確認"),
                        systemImage: "hand.thumbsup.fill"
                    )
                    .font(SaveAtlasType.strong(13))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(SaveAtlasPalette.mint.opacity(0.96), in: Capsule())

                }

                Spacer(minLength: 0)

                Image("OnboardingNightCafe")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 104, height: 133)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(SaveAtlasPalette.line.opacity(0.48), lineWidth: 1)
                    }
                    .rotationEffect(.degrees(2))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(SaveAtlasPalette.muted)
                            .rotationEffect(.degrees(14))
                            .offset(x: 6, y: -7)
                    }
                    .overlay(alignment: .bottomLeading) {
                        OnboardingPostalCancellation()
                            .offset(x: -72, y: 8)
                    }
                    .padding(.trailing, 4)
            }
            .frame(height: 145, alignment: .top)
            .padding(.leading, 8)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "link")
                VStack(alignment: .leading, spacing: 1) {
                    Text(language.localized(english: "From IG Reel", traditionalChinese: "來自 IG Reels"))
                    Text("instagram.com/reel/C8xK...7bQ")
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(language.localized(english: "Saved", traditionalChinese: "保存"))
                    Text(language.localized(english: "Oct 12", traditionalChinese: "10 月 12 日"))
                }
            }
            .font(SaveAtlasType.body(12))
            .foregroundStyle(SaveAtlasPalette.muted)
            .padding(.leading, 6)
            .padding(.top, -10)

            ZStack(alignment: .bottomTrailing) {
                Image("MapAtlasScene")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 76)
                    .clipped()
                    .opacity(0.58)

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SaveAtlasPalette.coral)
                    .padding(5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(SaveAtlasPalette.forest.opacity(0.28), lineWidth: 1)
            }
            .padding(.horizontal, 7)
        }
        .padding(.horizontal, 12)
        .padding(.top, 27)
        .padding(.bottom, 12)
        .frame(minHeight: 344, alignment: .top)
        .background {
            ZStack {
                SaveAtlasPalette.paper
                SaveAtlasPalette.mint.opacity(0.30)
                OnboardingTicketPaperGrain()
            }
        }
        .onboardingPostageTicket(
            tint: SaveAtlasPalette.mint,
            edge: SaveAtlasPalette.forest
        )
        .accessibilityIdentifier("onboarding.savedPostcard")
    }
}

private struct OnboardingPostalCancellation: View {
    var body: some View {
        HStack(spacing: -8) {
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(SaveAtlasPalette.muted.opacity(0.58))
                        .frame(width: 54, height: 1)
                }
            }

            ZStack {
                Circle()
                    .stroke(SaveAtlasPalette.muted.opacity(0.64), lineWidth: 1.2)
                Circle()
                    .stroke(
                        SaveAtlasPalette.muted.opacity(0.42),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
                    .padding(5)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SaveAtlasPalette.muted.opacity(0.64))
            }
            .frame(width: 43, height: 43)
        }
        .rotationEffect(.degrees(-5))
        .accessibilityHidden(true)
    }
}

private enum OnboardingMemoPose {
    case clue
    case review
    case stamp

    var assetName: String {
        switch self {
        case .clue: return "OnboardingMemoClue"
        case .review: return "OnboardingMemoReview"
        case .stamp: return "OnboardingMemoStamp"
        }
    }

    var width: CGFloat {
        switch self {
        case .clue: return 102
        case .review: return 126
        case .stamp: return 118
        }
    }

    var horizontalOffset: CGFloat {
        switch self {
        case .clue: return 100
        case .review: return 92
        case .stamp: return 103
        }
    }

    var captionHorizontalOffset: CGFloat {
        switch self {
        case .clue: return -8
        case .review, .stamp: return -42
        }
    }

    var bottomOffset: CGFloat {
        switch self {
        case .clue: return 90
        case .review: return 48
        case .stamp: return 50
        }
    }

    var captionBottomPadding: CGFloat {
        switch self {
        case .clue: return 87
        case .review: return 72
        case .stamp: return 56
        }
    }

    var layerIndex: Double {
        3
    }

    var rearBottomOffset: CGFloat {
        switch self {
        case .clue: return 103
        case .review: return 89
        case .stamp: return 90
        }
    }

    var rearHeight: CGFloat {
        220
    }

    var frontPocketHeight: CGFloat {
        switch self {
        case .clue: return 187
        case .review: return 170
        case .stamp: return 162
        }
    }

    var stageVerticalOffset: CGFloat {
        switch self {
        case .clue: return -8
        case .review: return -7
        case .stamp: return -4
        }
    }

    var canonicalStageHeight: CGFloat {
        switch self {
        case .clue: return 460
        case .review: return 496
        case .stamp: return 506
        }
    }
}

private struct OnboardingOpenEnvelopeShell<Cards: View>: View {
    let caption: String
    let isCompactHeight: Bool
    let memoPose: OnboardingMemoPose
    private let cards: (CGFloat, CGFloat) -> Cards

    init(
        caption: String,
        isCompactHeight: Bool,
        memoPose: OnboardingMemoPose,
        @ViewBuilder cards: @escaping (CGFloat, CGFloat) -> Cards
    ) {
        self.caption = caption
        self.isCompactHeight = isCompactHeight
        self.memoPose = memoPose
        self.cards = cards
    }

    var body: some View {
        GeometryReader { proxy in
            let fullWidth = min(max(proxy.size.width + 16, 0), 370)
            let widthScale = min(fullWidth / 370, isCompactHeight ? 270 / 370 : 1)
            let heightScale = min(proxy.size.height / memoPose.canonicalStageHeight, 1)
            let scale = isCompactHeight ? min(widthScale, heightScale) : widthScale
            let shellWidth = 370 * scale

            ZStack(alignment: .bottom) {
                OnboardingAirmailEnvelopeBack(
                    width: shellWidth,
                    height: memoPose.rearHeight * scale
                )
                .offset(y: -memoPose.rearBottomOffset * scale)

                cards(scale, shellWidth)
                    .zIndex(1)

                OnboardingPocketEnvelope(
                    caption: caption,
                    width: shellWidth,
                    height: memoPose.frontPocketHeight * scale,
                    captionBottomPadding: memoPose.captionBottomPadding * scale,
                    captionHorizontalOffset: memoPose.captionHorizontalOffset * scale
                )
                .zIndex(2)

                Image(memoPose.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: memoPose.width * scale)
                    .overlay(alignment: .topTrailing) {
                        OnboardingMemoAccentRays()
                            .scaleEffect(scale)
                            .offset(x: 9 * scale, y: -3 * scale)
                    }
                    .offset(
                        x: memoPose.horizontalOffset * scale,
                        y: -memoPose.bottomOffset * scale
                    )
                    .accessibilityHidden(true)
                    .zIndex(memoPose.layerIndex)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .offset(y: memoPose.stageVerticalOffset * scale)
        }
    }
}

private struct OnboardingPostageTicketStyle: ViewModifier {
    let tint: Color
    let edge: Color

    func body(content: Content) -> some View {
        content
            .clipShape(SavePostcardScallopedRectangle(depth: 3, pitch: 10))
            .overlay {
                OnboardingPostageBand(depth: 3, pitch: 10, inset: 6)
                    .fill(tint.opacity(0.56), style: FillStyle(eoFill: true))
            }
            .overlay {
                SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                    .stroke(edge.opacity(0.48), lineWidth: 0.7)
            }
            .shadow(color: tint.opacity(0.14), radius: 4, y: 2)
    }
}

private struct OnboardingPostageBand: Shape {
    let depth: CGFloat
    let pitch: CGFloat
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = SavePostcardScallopedRectangle(depth: depth, pitch: pitch)
            .path(in: rect)
        path.addRoundedRect(
            in: rect.insetBy(dx: inset, dy: inset),
            cornerSize: CGSize(width: 2, height: 2)
        )
        return path
    }
}

private extension View {
    func onboardingPostageTicket(tint: Color, edge: Color) -> some View {
        modifier(OnboardingPostageTicketStyle(tint: tint, edge: edge))
    }
}

private struct OnboardingMemoAccentRays: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(SaveAtlasPalette.sky)
                .frame(width: 4, height: 14)
                .rotationEffect(.degrees(18))
                .offset(x: -7, y: -3)

            Capsule()
                .fill(Color(red: 0.98, green: 0.76, blue: 0.34))
                .frame(width: 4, height: 12)
                .rotationEffect(.degrees(52))
                .offset(x: 4, y: 2)

            Capsule()
                .fill(SaveAtlasPalette.coral.opacity(0.72))
                .frame(width: 4, height: 10)
                .rotationEffect(.degrees(78))
                .offset(x: 7, y: 12)
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

private struct OnboardingAirmailEnvelopeBack: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Image("OnboardingAirmailEnvelopeBack")
            .resizable()
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

private struct OnboardingPocketEnvelope: View {
    let caption: String
    let width: CGFloat
    let height: CGFloat
    let captionBottomPadding: CGFloat
    let captionHorizontalOffset: CGFloat

    var body: some View {
        Image("OnboardingEnvelopeFront")
            .resizable()
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                Text(caption)
                    .font(SaveAtlasType.editorial(14 * (width / 370)))
                    .foregroundStyle(SaveAtlasPalette.ink.opacity(0.78))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 90 * (width / 370))
                    .padding(.bottom, captionBottomPadding)
                    .offset(x: captionHorizontalOffset)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingView { _ in }
        .environment(\.appLanguageSettings, AppLanguageSettings())
}
