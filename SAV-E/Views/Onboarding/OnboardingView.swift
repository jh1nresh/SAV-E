import SwiftUI

/// One local example, from source to confirmed memory. Personal input takes a
/// separate route into the existing pending-clue capture flow after sign-in.
struct OnboardingView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var step: OnboardingStep = .clue
    @State private var showsLanguage = false
    @State private var showsInput = false
    @State private var showsRejection = false
    @State private var clueText = ""
    private let isReplay: Bool
    var onComplete: (String?) -> Void

    private var language: AppLanguage { languageSettings.language }

    init(isReplay: Bool = false, onComplete: @escaping (String?) -> Void) {
        self.isReplay = isReplay
        self.onComplete = onComplete
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 710
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: compact ? 18 : 24) {
                        heading
                        postcard(photoHeight: step == .clue ? (compact ? 168 : 214) : (compact ? 148 : 174))
                        memoNote
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, compact ? 16 : 24)
                    .padding(.bottom, 20)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actions
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .background(SaveAtlasPalette.canvas)
            }
            .background(SaveAtlasPalette.canvas.ignoresSafeArea())
        }
        .sheet(isPresented: $showsLanguage) { languageSheet }
        .sheet(isPresented: $showsInput) { inputSheet }
        .sheet(isPresented: $showsRejection) { rejectionSheet }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            if step != .clue {
                Button { move(to: step == .mapStamp ? .candidate : .clue) } label: {
                    Image(systemName: "arrow.left")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(text("Back", "返回"))
                .accessibilityIdentifier("onboarding.back")
            } else {
                if dynamicType.isAccessibilitySize {
                    Text("Savvy").font(SaveAtlasType.strong(20, relativeTo: .largeTitle))
                } else {
                    SaveFirstRunBrandLockup(compact: true)
                }
            }
            Spacer(minLength: 8)
            Button { showsLanguage = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                    if !dynamicType.isAccessibilitySize { Text(language == .english ? "EN" : "繁中") }
                }
                .font(SaveAtlasType.body(13))
                .frame(minWidth: 60, minHeight: 44)
            }
            .accessibilityLabel(text("Choose language", "選擇語言"))
            .accessibilityIdentifier("onboarding.language")
            if isReplay {
                Button { onComplete(nil) } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel(text("Close tutorial", "關閉教學"))
                .accessibilityIdentifier("onboarding.close")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(SaveAtlasPalette.forest)
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? SaveAtlasPalette.forest : SaveAtlasPalette.line.opacity(0.22))
                        .frame(width: item == step ? 24 : 6, height: 4)
                }
                Text("0\(step.rawValue + 1) / 03")
                    .font(SaveAtlasType.body(11, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .padding(.leading, 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text("Step \(step.rawValue + 1) of 3", "第 \(step.rawValue + 1) 步，共 3 步"))
            Text(step.title(language: language))
                .font(SaveAtlasType.display(32, relativeTo: .largeTitle))
                .foregroundStyle(SaveAtlasPalette.forest)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .accessibilityIdentifier("onboarding.title")
            Text(step.subtitle(language: language))
                .font(SaveAtlasType.regular(15))
                .foregroundStyle(SaveAtlasPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func postcard(photoHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("OnboardingNightCafe")
                .resizable()
                .scaledToFill()
                .frame(height: photoHeight)
                .clipped()
                .overlay(alignment: .topLeading) {
                    Text(text("EXAMPLE", "示範素材"))
                        .font(SaveAtlasType.strong(10))
                        .tracking(0.8)
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(SaveAtlasPalette.paper, in: Capsule())
                        .padding(14)
                }
                .accessibilityLabel(text("Illustrative cafe with a green storefront", "綠色店面的咖啡店示意照"))
            VStack(alignment: .leading, spacing: 12) {
                if step == .clue {
                    HStack {
                        Label(text("Source Clue", "來源線索"), systemImage: "link")
                            .font(SaveAtlasType.strong(12))
                            .foregroundStyle(SaveAtlasPalette.ink)
                        Spacer()
                        Circle().fill(SaveAtlasPalette.coral).frame(width: 7, height: 7)
                    }
                    Text(text("“A little patio.\nSaving this for a slow afternoon.”", "「有小庭院的咖啡店，\n下次想在這裡待一下午。」"))
                        .font(SaveAtlasType.body(18))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    sourceLine
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Hidden Moon Cafe")
                                .font(SaveAtlasType.strong(22))
                                .foregroundStyle(SaveAtlasPalette.forest)
                                .fixedSize(horizontal: false, vertical: true)
                            Label(step == .candidate ? text("Review Candidate", "待確認地點") : text("Map Stamp · Example", "地圖章・範例"),
                                  systemImage: step == .candidate ? "magnifyingglass" : "checkmark.seal.fill")
                                .font(SaveAtlasType.body(12))
                                .foregroundStyle(SaveAtlasPalette.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(step == .candidate ? SaveAtlasPalette.sky : SaveAtlasPalette.mint, in: Capsule())
                        }
                        Spacer(minLength: 0)
                        if step == .mapStamp {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(SaveAtlasPalette.forest)
                                .padding(.top, 3)
                                .accessibilityHidden(true)
                        }
                    }
                    Rectangle().fill(SaveAtlasPalette.line.opacity(0.25)).frame(height: 1)
                    sourceLine
                    Text(step == .candidate
                        ? text("The name matches the post. You decide if it’s the right place.", "店名符合貼文線索。是不是同一間，由你確認。")
                        : text("The place and the post, kept together.", "地點和當初心動的貼文，一起留下。"))
                        .font(SaveAtlasType.regular(14))
                        .foregroundStyle(SaveAtlasPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .background(SaveAtlasPalette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.3), lineWidth: 0.75)
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.07), radius: 16, x: 0, y: 8)
        .rotationEffect(.degrees(reduceMotion || step != .clue ? 0 : -2))
        .accessibilityIdentifier("onboarding.postcard.\(step)")
    }

    private var sourceLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble")
            Text("@hidden.moon.cafe")
        }
        .font(SaveAtlasType.regular(12))
        .foregroundStyle(SaveAtlasPalette.muted)
        .accessibilityLabel(text("Example source: @hidden.moon.cafe", "範例來源：@hidden.moon.cafe"))
    }

    private var memoNote: some View {
        HStack(alignment: .center, spacing: 10) {
            MemoMascotMark(size: 44, framed: false)
            Text(step == .clue
                ? text("I’m Memo. Let’s try one together.", "我是 Memo，一起試存一個地方。")
                : step == .candidate
                    ? text("Not the right place? Keep the clue and try again.", "找錯了也沒關係，線索會留下。")
                    : text("Just a preview. This example won’t enter your collection.", "這次只是示範，不會加入你的收藏。"))
                .font(SaveAtlasType.regular(13))
                .foregroundStyle(SaveAtlasPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    private var actions: some View {
        VStack(spacing: 4) {
            Button(action: advance) {
                HStack(spacing: 10) {
                    Text(step == .mapStamp && isReplay
                        ? text("Back to Passport", "返回護照")
                        : step.primaryTitle(language: language))
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(OnboardingPrimaryStyle())
            .accessibilityIdentifier("onboarding.primary")
            Group {
                if dynamicType.isAccessibilitySize {
                    VStack(spacing: 0) { secondaryActions }
                } else {
                    HStack(spacing: 16) { secondaryActions }
                }
            }
            .font(SaveAtlasType.body(13))
            .foregroundStyle(SaveAtlasPalette.muted)
            .buttonStyle(OnboardingSecondaryStyle())
        }
        .padding(.bottom, 4)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var secondaryActions: some View {
        if step == .candidate {
            Button(text("Not this place", "不是這個地方")) { showsRejection = true }
                .accessibilityIdentifier("onboarding.reject")
        } else if !isReplay && step == .clue {
            Button(text("I have a post", "我有想存的貼文")) { showsInput = true }
                .accessibilityIdentifier("onboarding.ownClue")
        } else if step == .mapStamp {
            Button(text("Replay", "再看一次")) { move(to: .clue) }
                .accessibilityIdentifier("onboarding.restart")
        }
        Button(isReplay ? text("Close tutorial", "關閉教學") : text("Explore first", "先逛逛")) { onComplete(nil) }
            .accessibilityIdentifier("onboarding.skip")
    }

    private var languageSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ForEach(AppLanguage.allCases) { choice in
                    Button {
                        languageSettings.language = choice
                        showsLanguage = false
                    } label: {
                        HStack {
                            Text(choice.displayName)
                            Spacer()
                            if language == choice { Image(systemName: "checkmark") }
                        }
                        .padding(18)
                        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityIdentifier("onboarding.language.\(choice.rawValue)")
                }
            }
            .font(SaveAtlasType.body(18))
            .foregroundStyle(SaveAtlasPalette.forest)
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(SaveAtlasPalette.canvas)
            .navigationTitle(text("Language", "語言"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(text("Done", "完成")) { showsLanguage = false }
            } }
        }
        .presentationDetents([.medium, .large])
    }

    private var inputSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(text("What caught your eye?", "哪個地方讓你心動？"))
                        .font(SaveAtlasType.display(28))
                        .foregroundStyle(SaveAtlasPalette.forest)
                    Text(text("Paste a link, a caption, or a place note. After sign-in, you can review it before anything is saved.", "貼上連結、貼文內容或地點筆記。登入後再檢查線索，由你決定是否保存。"))
                        .font(SaveAtlasType.regular(16))
                        .foregroundStyle(SaveAtlasPalette.muted)
                    TextEditor(text: $clueText)
                        .font(SaveAtlasType.body(18))
                        .foregroundStyle(SaveAtlasPalette.ink)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 180)
                        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SaveAtlasPalette.line.opacity(0.5)))
                        .accessibilityLabel(text("Your place clue", "你的地點線索"))
                        .accessibilityIdentifier("onboarding.clueEditor")
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SaveAtlasPalette.canvas)
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard !isReplay, let clue = Self.clueWorthKeeping(rawClue: clueText, language: language) else { return }
                    onComplete(clue)
                } label: {
                    Text(text("Continue with my clue", "帶著我的線索繼續"))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(OnboardingPrimaryStyle())
                .disabled(Self.clueWorthKeeping(rawClue: clueText, language: language) == nil)
                .accessibilityIdentifier("onboarding.continueClue")
                .padding(24)
                .background(SaveAtlasPalette.canvas)
            }
            .navigationTitle(text("Your first place", "你的第一個地點"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button(text("Back", "返回")) { showsInput = false }
                    .accessibilityIdentifier("onboarding.cancelInput")
            } }
        }
    }

    private var rejectionSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Label(text("Keep the clue. Try another match.", "線索留下，再找找。"), systemImage: "text.magnifyingglass")
                    .font(SaveAtlasType.display(24))
                    .foregroundStyle(SaveAtlasPalette.forest)
                Text(text("In Savvy, you can add an address or choose another place. Nothing is saved until you confirm. This walkthrough uses one fictional cafe.", "在 Savvy 裡，你可以補上地址或改選其他地點；確認之前都不會保存。這段教學只用一間虛構咖啡店示範。"))
                    .font(SaveAtlasType.regular(16))
                    .foregroundStyle(SaveAtlasPalette.muted)
                Button(text("Back to the example", "回到範例")) { showsRejection = false }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding.backToExample")
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(SaveAtlasPalette.canvas)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func advance() {
        switch step {
        case .clue: move(to: .candidate)
        case .candidate: move(to: .mapStamp)
        case .mapStamp:
            if isReplay { onComplete(nil) } else { showsInput = true }
        }
    }

    private func move(to next: OnboardingStep) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { step = next }
    }

    private func text(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }

    // Keep old sample literals excluded from the real-input handoff in either language.
    static func clueWorthKeeping(rawClue: String, language: AppLanguage) -> String? {
        let clue = rawClue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clue.isEmpty else { return nil }
        let samples = AppLanguage.allCases.map { sampleClue(language: $0) }
        return samples.contains(clue) ? nil : clue
    }

    static func sampleClue(language: AppLanguage) -> String {
        language.localized(
            english: "IG Reel: quiet cafe with a tiny patio near the station, tagged @hidden.moon.cafe",
            traditionalChinese: "IG Reels：捷運站旁有小庭院的安靜咖啡店，標記 @hidden.moon.cafe"
        )
    }
}

enum OnboardingStep: Int, CaseIterable {
    case clue, candidate, mapStamp

    func title(language: AppLanguage) -> String {
        switch self {
        case .clue: return language.localized(english: "Some places deserve\na little more than a like.", traditionalChinese: "想去的地方，\n不只按個喜歡。")
        case .candidate: return language.localized(english: "A little clue.\nA place to remember.", traditionalChinese: "一點線索，\n找到心動的地方。")
        case .mapStamp: return language.localized(english: "From someday\nto your own map.", traditionalChinese: "把「下次想去」，\n留在自己的地圖。")
        }
    }

    func subtitle(language: AppLanguage) -> String {
        switch self {
        case .clue: return language.localized(english: "Start with a post, a link, or a passing thought.", traditionalChinese: "從一篇貼文、一個連結，或隨手筆記開始。")
        case .candidate: return language.localized(english: "Memo finds a match. You have the final say.", traditionalChinese: "Memo 幫你找，你來確認是不是這裡。")
        case .mapStamp: return language.localized(english: "Confirmed places become private Map Stamps.", traditionalChinese: "確認過的地點，才會成為你的私人地圖章。")
        }
    }

    func primaryTitle(language: AppLanguage) -> String {
        switch self {
        case .clue: return language.localized(english: "Try this example", traditionalChinese: "用這個範例試試")
        case .candidate: return language.localized(english: "Confirm the example", traditionalChinese: "確認範例地點")
        case .mapStamp: return language.localized(english: "Save my first place", traditionalChinese: "存我的第一個地點")
        }
    }
}

private struct OnboardingPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SaveAtlasType.strong(16))
            .foregroundStyle(SaveAtlasPalette.paper)
            .padding(.horizontal, 16)
            .background(isEnabled ? SaveAtlasPalette.coral : SaveAtlasPalette.muted.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct OnboardingSecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct SaveFirstRunBrandLockup: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            MemoMascotMark(size: compact ? 28 : 36, framed: false)

            Text("Savvy")
                .font(SaveAtlasType.strong(compact ? 20 : 25))
                .tracking(1)
                .foregroundStyle(SaveAtlasPalette.forest)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Savvy")
    }
}
