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
            let bottomActionLift = proxy.safeAreaInsets.bottom + 16

            ZStack(alignment: .bottom) {
                AtlasCanvas()
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    OnboardingTopBar(
                        step: step,
                        language: language,
                        onBack: goBack
                    )
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, isCompactHeight ? 6 : 14)

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
                height: isCompactHeight ? 290 : 430
            )

            Spacer(minLength: 0)
        }
        .padding(.top, isCompactHeight ? 10 : 24)
        .frame(maxHeight: .infinity, alignment: .top)
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
                .padding(.vertical, isCompactHeight ? 13 : 16)
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
                Button(step.skipTitle(language: language)) {
                    skipCurrentStep()
                }
                .font(SaveAtlasType.body(14))
                .foregroundStyle(SaveAtlasPalette.muted)
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
                english: "It stays in review until you confirm — no fake pins.",
                traditionalChinese: "在你確認之前都先待確認，不會出現假地點。"
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
            MemoMark(size: compact ? 28 : 34)

            Text("SAV-E")
                .font(SaveAtlasType.strong(compact ? 20 : 23))
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
        VStack(spacing: 10) {
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
                .font(SaveAtlasType.strong(isCompactHeight ? 26 : 28, relativeTo: .title))
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
        VStack(spacing: isCompactHeight ? 8 : 20) {
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
            .frame(height: isCompactHeight ? 250 : 416)

            HStack(spacing: 10) {
                Button(action: onUseSample) {
                    Label(
                        language.localized(english: "Try sample", traditionalChinese: "試用範例"),
                        systemImage: "wand.and.stars"
                    )
                    .font(SaveAtlasType.strong(13))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .lineLimit(1)
                    .padding(.horizontal, 13)
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

                Spacer(minLength: 0)

                Label(
                    language.localized(english: "Private", traditionalChinese: "私人"),
                    systemImage: "lock.fill"
                )
                .font(SaveAtlasType.body(12))
                .foregroundStyle(SaveAtlasPalette.muted)
            }

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
        ZStack(alignment: .bottom) {
            OnboardingSourceTicket(
                clueText: $clueText,
                language: language,
                isCompactHeight: isCompactHeight
            )
            .padding(.horizontal, 9)
            .offset(y: isCompactHeight ? -82 : -144)
            .zIndex(1)

            OnboardingPocketEnvelope(
                caption: language.localized(
                    english: "Memo keeps the source as proof.",
                    traditionalChinese: "Memo 會把來源留作證據。"
                ),
                isCompactHeight: isCompactHeight
            )
            .zIndex(2)

            SavePostcardMemoPeek(width: isCompactHeight ? 56 : 66)
                .offset(x: isCompactHeight ? 100 : 116, y: isCompactHeight ? -48 : -64)
                .zIndex(3)
        }
        .accessibilityIdentifier("onboarding.pocketStage.clue")
    }
}

private struct OnboardingSourceTicket: View {
    @Binding var clueText: String
    let language: AppLanguage
    let isCompactHeight: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 5 : 8) {
            Text(language.localized(english: "Source Clue", traditionalChinese: "來源線索").uppercased())
                .font(SaveAtlasType.strong(10))
                .tracking(1)
                .foregroundStyle(SaveAtlasPalette.coral)
                .frame(maxWidth: .infinity, alignment: .center)

            ZStack(alignment: .topLeading) {
                linedNoteBackground

                TextEditor(text: $clueText)
                    .font(SaveAtlasType.editorial(isCompactHeight ? 14 : 16))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .frame(height: isCompactHeight ? 70 : 104)
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
                    .font(SaveAtlasType.body(isCompactHeight ? 14 : 16))
                    .foregroundStyle(SaveAtlasPalette.muted.opacity(0.70))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "camera.fill")
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
            .font(SaveAtlasType.body(10))
            .foregroundStyle(SaveAtlasPalette.muted)
        }
        .padding(isCompactHeight ? 10 : 13)
        .background(SaveAtlasPalette.paper.opacity(0.98))
        .padding(5)
        .background {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .fill(SaveAtlasPalette.coral.opacity(0.24))
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .stroke(
                    SaveAtlasPalette.coral.opacity(0.86),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.07), radius: 6, y: 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.sourceTicket")
    }

    private var linedNoteBackground: some View {
        Canvas { context, size in
            let spacing: CGFloat = isCompactHeight ? 18 : 22
            for y in stride(from: spacing, through: size.height, by: spacing) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(SaveAtlasPalette.line.opacity(0.22)), lineWidth: 1)
            }
        }
        .frame(height: isCompactHeight ? 70 : 104)
        .allowsHitTesting(false)
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
            .offset(y: isCompactHeight ? 8 : 8)
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
        ZStack(alignment: .bottom) {
            OnboardingCompactSourceReceipt(clueLine: clueLine, language: language)
                .padding(.horizontal, 18)
                .rotationEffect(.degrees(-1.2))
                .offset(y: isCompactHeight ? -230 : -300)
                .zIndex(0)

            if phase >= 1 {
                OnboardingReviewTicket(
                    language: language,
                    isCompactHeight: isCompactHeight,
                    phase: phase
                )
                    .padding(.horizontal, 9)
                    .offset(y: isCompactHeight ? -95 : -155)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(1)
            }

            OnboardingPocketEnvelope(
                caption: language.localized(
                    english: "Your source stays attached.",
                    traditionalChinese: "原始來源會一直保留。"
                ),
                isCompactHeight: isCompactHeight
            )
            .zIndex(2)

            SavePostcardMemoPeek(width: isCompactHeight ? 56 : 66)
                .offset(
                    x: isCompactHeight ? 100 : 116,
                    y: isCompactHeight ? -48 : -64
                )
                .zIndex(3)
        }
    }
}

private struct OnboardingCompactSourceReceipt: View {
    let clueLine: String
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "paperclip")
                .font(.caption.weight(.bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(language.localized(english: "Source Clue", traditionalChinese: "來源線索").uppercased())
                    .font(SaveAtlasType.strong(9))
                    .tracking(0.8)
                    .foregroundStyle(SaveAtlasPalette.coral)
                Text(clueLine)
                    .font(SaveAtlasType.body(12))
                    .foregroundStyle(SaveAtlasPalette.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 68)
        .background(SaveAtlasPalette.paper.opacity(0.98))
        .padding(4)
        .background {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .fill(SaveAtlasPalette.coral.opacity(0.24))
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .stroke(
                    SaveAtlasPalette.coral.opacity(0.82),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
        }
        .accessibilityHidden(true)
    }
}

private struct OnboardingReviewTicket: View {
    let language: AppLanguage
    let isCompactHeight: Bool
    let phase: Int

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 7 : 10) {
            HStack(alignment: .top, spacing: 10) {
                SavePostcardPerforatedMedallion(
                    systemName: "magnifyingglass",
                    tint: SaveAtlasPalette.sky,
                    edge: Color.saveBlueInk.opacity(0.72)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(language.localized(english: "Review Candidate", traditionalChinese: "待確認地點").uppercased())
                        .font(SaveAtlasType.strong(9))
                        .tracking(0.8)
                        .foregroundStyle(Color.saveBlueInk)
                    Text("Hidden Moon Cafe?")
                        .font(SaveAtlasType.strong(isCompactHeight ? 18 : 20, relativeTo: .headline))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 6) {
                evidenceMark(
                    icon: "checkmark.seal.fill",
                    title: language.localized(english: "Name\nfound", traditionalChinese: "找到\n名稱"),
                    tint: SaveAtlasPalette.mint,
                    visibleAt: 1
                )
                evidenceMark(
                    icon: "link",
                    title: language.localized(english: "Source\nkept", traditionalChinese: "保留\n來源"),
                    tint: SaveAtlasPalette.sky,
                    visibleAt: 2
                )
                evidenceMark(
                    icon: "questionmark",
                    title: language.localized(english: "Exact pin\nmissing", traditionalChinese: "還缺\n座標"),
                    tint: SaveAtlasPalette.kraft,
                    visibleAt: 3
                )
            }

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
        }
        .padding(isCompactHeight ? 10 : 13)
        .background(SaveAtlasPalette.paper.opacity(0.98))
        .padding(5)
        .background {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .fill(SaveAtlasPalette.sky.opacity(0.54))
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .stroke(
                    Color.saveBlueInk.opacity(0.72),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.07), radius: 6, y: 3)
        .accessibilityIdentifier("onboarding.reviewTicket")
    }

    @ViewBuilder
    private func evidenceMark(icon: String, title: String, tint: Color, visibleAt: Int) -> some View {
        if phase >= visibleAt {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .frame(width: 30, height: 30)
                    .background(tint, in: SavePostcardSealShape())

                Text(title)
                    .font(SaveAtlasType.strong(10))
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
        ZStack(alignment: .bottom) {
            if phase >= 1 {
                OnboardingSavedPostcard(language: language)
                    .padding(.horizontal, 9)
                    .offset(y: isCompactHeight ? -52 : -134)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .zIndex(1)
            }

            OnboardingPocketEnvelope(
                caption: language.localized(
                    english: "Saved to your private pocket.",
                    traditionalChinese: "已放進你的私人收藏袋。"
                ),
                isCompactHeight: isCompactHeight
            )
            .zIndex(2)

            SavePostcardMemoPeek(width: isCompactHeight ? 56 : 66)
                .offset(
                    x: isCompactHeight ? 100 : 116,
                    y: isCompactHeight ? -48 : -64
                )
                .zIndex(3)
        }
    }
}

private struct OnboardingSavedPostcard: View {
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.localized(english: "Map Stamp · Confirmed", traditionalChinese: "地圖章 · 已確認").uppercased())
                .font(SaveAtlasType.strong(9))
                .tracking(0.8)
                .foregroundStyle(SaveAtlasPalette.forest)

            HStack(alignment: .top, spacing: 10) {
                Image("KoffeeMameyaThumbnail")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(SaveAtlasPalette.line.opacity(0.38), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Hidden Moon Cafe")
                        .font(SaveAtlasType.strong(19, relativeTo: .headline))
                        .foregroundStyle(SaveAtlasPalette.forest)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Label(
                        language.localized(english: "Confirmed by you", traditionalChinese: "由你確認"),
                        systemImage: "hand.thumbsup.fill"
                    )
                    .font(SaveAtlasType.strong(11))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(SaveAtlasPalette.mint.opacity(0.96), in: Capsule())

                    Text(language.localized(
                        english: "Source retained · Private",
                        traditionalChinese: "保留來源 · 私人"
                    ))
                    .font(SaveAtlasType.body(11))
                    .foregroundStyle(SaveAtlasPalette.muted)
                }

                Spacer(minLength: 0)

                SavePostcardPostmark()
                    .scaleEffect(0.72)
                    .frame(width: 42, height: 42)
            }

            ZStack(alignment: .bottomTrailing) {
                Image("MapAtlasScene")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 50)
                    .clipped()
                    .opacity(0.58)

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(SaveAtlasPalette.coral)
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(SaveAtlasPalette.forest.opacity(0.28), lineWidth: 1)
            }

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
            .font(SaveAtlasType.body(10))
            .foregroundStyle(SaveAtlasPalette.muted)
        }
        .padding(13)
        .background(SaveAtlasPalette.paper.opacity(0.98))
        .padding(5)
        .background {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .fill(SaveAtlasPalette.mint.opacity(0.62))
        }
        .overlay {
            SavePostcardScallopedRectangle(depth: 3, pitch: 10)
                .stroke(
                    SaveAtlasPalette.forest.opacity(0.72),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                )
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.07), radius: 6, y: 3)
        .accessibilityIdentifier("onboarding.savedPostcard")
    }
}

private struct OnboardingPocketEnvelope: View {
    let caption: String
    let isCompactHeight: Bool

    var body: some View {
        Image("SavesEnvelope")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: isCompactHeight ? 126 : 176, alignment: .bottom)
            .overlay(alignment: .bottom) {
                Text(caption)
                    .font(SaveAtlasType.editorial(isCompactHeight ? 12 : 14))
                    .foregroundStyle(SaveAtlasPalette.ink.opacity(0.78))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 90)
                    .padding(.bottom, isCompactHeight ? 20 : 28)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingView { _ in }
        .environment(\.appLanguageSettings, AppLanguageSettings())
}
