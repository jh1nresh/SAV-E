import SwiftUI

struct OnboardingView: View {
    @State private var selectedState: FirstRunDemoState = .clue
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            SaveDottedBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $selectedState) {
                    ForEach(FirstRunDemoState.allCases, id: \.self) { state in
                        FirstRunMascotPage(state: state)
                            .tag(state)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 12) {
                    FirstRunPageDots(selectedState: selectedState)

                    FirstRunTrustNote()

                    Button(action: onComplete) {
                        Text("Add your first spots")
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

                    Button("Skip for now") {
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
}

private struct FirstRunPageDots: View {
    let selectedState: FirstRunDemoState

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FirstRunDemoState.allCases, id: \.self) { state in
                Capsule()
                    .fill(state == selectedState ? Color.saveInk : Color.saveNotebookLine.opacity(0.45))
                    .frame(width: state == selectedState ? 22 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.18), value: selectedState)
            }
        }
        .accessibilityLabel("Onboarding page \(selectedState.pageNumber) of \(FirstRunDemoState.allCases.count)")
    }
}

// MARK: - First Run Demo

private enum FirstRunDemoState: String, CaseIterable {
    case clue
    case candidate
    case mapStamp
    case tripPlan

    var pageHeadline: String {
        switch self {
        case .clue: return "Save places from anywhere."
        case .candidate: return "Review uncertain finds."
        case .mapStamp: return "Build your private map."
        case .tripPlan: return "Ask before you decide."
        }
    }

    var pageSubtitle: String {
        switch self {
        case .clue:
            return "Links, screenshots, notes, and map shares all start as one clean place memory."
        case .candidate:
            return "SAV-E keeps guesses out of your map until you confirm the real spot."
        case .mapStamp:
            return "Confirmed places become Map Stamps with why you saved them."
        case .tripPlan:
            return "Plan from the places you already cared about, not a generic list."
        }
    }

    var pageNumber: Int {
        Self.allCases.firstIndex(of: self)! + 1
    }

    var visualTitle: String {
        switch self {
        case .clue: return "From a post"
        case .candidate: return "Needs review"
        case .mapStamp: return "Map Stamp saved"
        case .tripPlan: return "Date night?"
        }
    }

    var visualSubtitle: String {
        switch self {
        case .clue: return "Memo catches the place clue."
        case .candidate: return "Confirm before it hits your map."
        case .mapStamp: return "Saved with source and reason."
        case .tripPlan: return "Built from your Map Stamps."
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

    var detailText: String {
        switch self {
        case .clue: return "Tucked away from IG"
        case .candidate: return "No fake pins"
        case .mapStamp: return "Private food + travel"
        case .tripPlan: return "3 saved spots nearby"
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

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)

            MemoMascotMark(size: 72, framed: false)

            FirstRunVisualCard(state: state)

            VStack(spacing: 8) {
                Text(state.pageHeadline)
                    .font(.title2)
                    .fontWeight(.black)
                    .foregroundColor(.saveInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(state.pageSubtitle)
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
                        Text(state.visualTitle)
                            .font(.title3)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)
                            .multilineTextAlignment(.center)

                        Text(state.visualSubtitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.saveMutedText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 22)

                    Text(state.detailText)
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
        "\(state.visualTitle). \(state.visualSubtitle). \(state.detailText)."
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
                    pill("Reject", tint: .saveNotebookPage)
                    pill("Confirm", tint: .saveHoney)
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
                pill("Dessert nearby", tint: .savePink)
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
}

private struct FirstRunTrustNote: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption.weight(.black))
                .foregroundColor(.saveInk)

            Text("Private food + travel memory, not public reviews.")
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
}

#Preview {
    OnboardingView(onComplete: {})
}
