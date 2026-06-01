import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @State private var selectedState: FirstRunDemoState = .clue
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            SaveDottedBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $selectedState) {
                    ForEach(FirstRunDemoState.allCases, id: \.self) { state in
                        FirstRunMascotPage(state: state, language: languageSettings.language)
                            .tag(state)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 12) {
                    FirstRunPageDots(selectedState: selectedState, language: languageSettings.language)

                    FirstRunTrustNote(language: languageSettings.language)

                    Button(action: onComplete) {
                        Text(addSpotsTitle)
                            .font(.headline)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.saveHoney)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 24)

                    Button(skipTitle) {
                        onComplete()
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.saveMutedText)
                }
                .padding(.bottom, 22)
            }
        }
    }

    private var addSpotsTitle: String {
        switch languageSettings.language {
        case .english: return "Add your first spots"
        case .traditionalChinese: return "開始存第一個地點"
        }
    }

    private var skipTitle: String {
        switch languageSettings.language {
        case .english: return "Skip for now"
        case .traditionalChinese: return "先跳過"
        }
    }
}

private struct FirstRunPageDots: View {
    let selectedState: FirstRunDemoState
    let language: AppLanguage

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FirstRunDemoState.allCases, id: \.self) { state in
                Capsule()
                    .fill(state == selectedState ? Color.saveInk : Color.saveNotebookLine.opacity(0.45))
                    .frame(width: state == selectedState ? 22 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.18), value: selectedState)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch language {
        case .english:
            return "Onboarding page \(selectedState.pageNumber) of \(FirstRunDemoState.allCases.count)"
        case .traditionalChinese:
            return "新手導覽第 \(selectedState.pageNumber) 頁，共 \(FirstRunDemoState.allCases.count) 頁"
        }
    }
}

// MARK: - First Run Demo

private enum FirstRunDemoState: String, CaseIterable {
    case clue
    case candidate
    case mapStamp
    case tripPlan

    func pageHeadline(language: AppLanguage) -> String {
        switch (self, language) {
        case (.clue, .english): return "Save places from anywhere."
        case (.clue, .traditionalChinese): return "從任何地方存地點。"
        case (.candidate, .english): return "Review uncertain finds."
        case (.candidate, .traditionalChinese): return "不確定的先確認。"
        case (.mapStamp, .english): return "Build your private map."
        case (.mapStamp, .traditionalChinese): return "累積你的私人地圖。"
        case (.tripPlan, .english): return "Ask before you decide."
        case (.tripPlan, .traditionalChinese): return "決定前先問 SAV-E。"
        }
    }

    func pageSubtitle(language: AppLanguage) -> String {
        switch (self, language) {
        case (.clue, .english):
            return "Links, screenshots, notes, and map shares all start as one clean place memory."
        case (.clue, .traditionalChinese):
            return "連結、截圖、筆記、地圖分享，都先變成乾淨的地點記憶。"
        case (.candidate, .english):
            return "SAV-E keeps guesses out of your map until you confirm the real spot."
        case (.candidate, .traditionalChinese):
            return "SAV-E 不會把猜測直接放進地圖，等你確認才儲存。"
        case (.mapStamp, .english):
            return "Confirmed places become Map Stamps with why you saved them."
        case (.mapStamp, .traditionalChinese):
            return "確認後變成地圖章，連同你當初想存的理由一起保留。"
        case (.tripPlan, .english):
            return "Plan from the places you already cared about, not a generic list."
        case (.tripPlan, .traditionalChinese):
            return "用你真的想去過的地方規劃，不是又一份通用清單。"
        }
    }

    var pageNumber: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }

    func visualTitle(language: AppLanguage) -> String {
        switch (self, language) {
        case (.clue, .english): return "From a post"
        case (.clue, .traditionalChinese): return "從貼文來的線索"
        case (.candidate, .english): return "Needs review"
        case (.candidate, .traditionalChinese): return "待確認"
        case (.mapStamp, .english): return "Map Stamp saved"
        case (.mapStamp, .traditionalChinese): return "地圖章已儲存"
        case (.tripPlan, .english): return "Date night?"
        case (.tripPlan, .traditionalChinese): return "今晚約會？"
        }
    }

    func visualSubtitle(language: AppLanguage) -> String {
        switch (self, language) {
        case (.clue, .english): return "Memo catches the place clue."
        case (.clue, .traditionalChinese): return "Memo 先抓住地點線索。"
        case (.candidate, .english): return "Confirm before it hits your map."
        case (.candidate, .traditionalChinese): return "確認後才進你的地圖。"
        case (.mapStamp, .english): return "Saved with source and reason."
        case (.mapStamp, .traditionalChinese): return "來源和理由一起存好。"
        case (.tripPlan, .english): return "Built from your Map Stamps."
        case (.tripPlan, .traditionalChinese): return "用你的地圖章組出答案。"
        }
    }

    var icon: String {
        switch self {
        case .clue: return "square.and.arrow.down"
        case .candidate: return "checkmark.seal"
        case .mapStamp: return "mappin.and.ellipse"
        case .tripPlan: return "sparkles"
        }
    }

    func detailText(language: AppLanguage) -> String {
        switch (self, language) {
        case (.clue, .english): return "Tucked away from IG"
        case (.clue, .traditionalChinese): return "從 IG 收進來"
        case (.candidate, .english): return "No fake pins"
        case (.candidate, .traditionalChinese): return "不亂放假地點"
        case (.mapStamp, .english): return "Private food + travel"
        case (.mapStamp, .traditionalChinese): return "私人的美食與旅行"
        case (.tripPlan, .english): return "3 saved spots nearby"
        case (.tripPlan, .traditionalChinese): return "附近 3 個已存地點"
        }
    }

    var tint: Color {
        switch self {
        case .clue: return .saveHoney
        case .candidate: return .saveSky
        case .mapStamp: return .saveMint
        case .tripPlan: return .savePink
        }
    }
}

private struct FirstRunMascotPage: View {
    let state: FirstRunDemoState
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)

            MemoMascotMark(size: 72, framed: false)

            FirstRunVisualCard(state: state, language: language)

            VStack(spacing: 8) {
                Text(state.pageHeadline(language: language))
                    .font(.title2)
                    .fontWeight(.black)
                    .foregroundColor(.saveInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(state.pageSubtitle(language: language))
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundColor(.saveMutedText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 30)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FirstRunVisualCard: View {
    let state: FirstRunDemoState
    let language: AppLanguage

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.saveNotebookPage.opacity(0.98))
                    .shadow(color: Color.saveInk.opacity(0.08), radius: 16, x: 0, y: 10)

                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 2)

                VStack(spacing: 18) {
                    HStack {
                        Circle()
                            .fill(Color.saveInk)
                            .frame(width: 8, height: 8)

                        Spacer()

                        Text("SAV-E")
                            .font(.caption)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)

                        Spacer()

                        Circle()
                            .fill(state.tint)
                            .frame(width: 8, height: 8)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)

                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(state.tint.opacity(0.4))
                            .frame(height: 148)

                        Image(systemName: state.icon)
                            .font(.system(size: 54, weight: .black))
                            .foregroundColor(.saveInk)

                        visualAccent
                    }
                    .padding(.horizontal, 18)

                    VStack(spacing: 6) {
                        Text(state.visualTitle(language: language))
                            .font(.title3)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)
                            .multilineTextAlignment(.center)

                        Text(state.visualSubtitle(language: language))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.saveMutedText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 22)

                    Text(state.detailText(language: language))
                        .font(.caption)
                        .fontWeight(.black)
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.saveNotebookPage)
                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                        .clipShape(Capsule())

                    Spacer(minLength: 10)
                }
            }
            .frame(width: min(264, max(0, geometry.size.width - 48)), height: 326)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 326)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        "\(state.visualTitle(language: language)). \(state.visualSubtitle(language: language)). \(state.detailText(language: language))."
    }

    @ViewBuilder
    private var visualAccent: some View {
        switch state {
        case .clue:
            VStack {
                HStack {
                    Text("@friend")
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Text("save this")
                }
            }
            .font(.caption2.weight(.black))
            .foregroundColor(.saveCocoa)
            .padding(18)
        case .candidate:
            VStack {
                Spacer()
                HStack(spacing: 10) {
                    pill(rejectTitle, tint: .saveNotebookPage)
                    pill(confirmTitle, tint: .saveHoney)
                }
            }
            .padding(.bottom, 16)
        case .mapStamp:
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(index == 1 ? Color.saveHoney : Color.saveNotebookPage)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1))
                        .offset(x: CGFloat(index - 1) * 44, y: index == 1 ? -28 : 26)
                }
            }
        case .tripPlan:
            VStack(alignment: .leading, spacing: 8) {
                pill("Speranza", tint: .saveHoney)
                pill("Alma", tint: .saveMint)
                pill(dessertTitle, tint: .savePink)
            }
            .offset(y: 46)
        }
    }

    private func pill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.black)
            .foregroundColor(.saveInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.9))
            .overlay(
                Capsule()
                    .stroke(Color.saveNotebookLine.opacity(0.7), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private var rejectTitle: String {
        switch language {
        case .english: return "Reject"
        case .traditionalChinese: return "略過"
        }
    }

    private var confirmTitle: String {
        switch language {
        case .english: return "Confirm"
        case .traditionalChinese: return "確認"
        }
    }

    private var dessertTitle: String {
        switch language {
        case .english: return "Dessert nearby"
        case .traditionalChinese: return "附近甜點"
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
        .padding(.horizontal, 24)
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
        .environmentObject(AppLanguageSettings())
}
