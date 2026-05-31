import SwiftUI

struct OnboardingView: View {
    @State private var selectedState: FirstRunDemoState = .clue
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            SaveDottedBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 28)

                    FirstRunMascotHero()

                    FirstRunProgressionChips(selectedState: $selectedState)

                    FirstRunPlaceDemoCard(state: selectedState)

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
                    .padding(.bottom, 24)
                }
            }
        }
    }
}

// MARK: - First Run Demo

private enum FirstRunDemoState: String, CaseIterable {
    case clue = "Source Clue"
    case candidate = "Review Candidate"
    case mapStamp = "Map Stamp"
    case tripPlan = "Ask / Plan"

    var title: String {
        switch self {
        case .clue: return "Import a place you already saved"
        case .candidate: return "No more fake pins"
        case .mapStamp: return "Know what is confirmed"
        case .tripPlan: return "Ask saved places first"
        }
    }

    var mascotLine: String {
        switch self {
        case .clue: return "Memo caught the clue. Now it needs the real place."
        case .candidate: return "Memo found a likely match. You decide before it saves."
        case .mapStamp: return "Memo stamps only places you confirm."
        case .tripPlan: return "Memo answers from your Map Stamps before looking outside."
        }
    }

    var icon: String {
        switch self {
        case .clue: return "magnifyingglass"
        case .candidate: return "checklist"
        case .mapStamp: return "mappin.and.ellipse"
        case .tripPlan: return "sparkles"
        }
    }

    var input: String {
        switch self {
        case .clue: return "friend's Reel, map link, screenshot, or note"
        case .candidate: return "one Review Candidate with evidence"
        case .mapStamp: return "Speranza · Silver Lake"
        case .tripPlan: return "date night near saved places"
        }
    }

    var known: String {
        switch self {
        case .clue: return "source + why it looked worth saving"
        case .candidate: return "source text + likely place match"
        case .mapStamp: return "confirmed identity, category, map location"
        case .tripPlan: return "your Map Stamps before public discovery"
        }
    }

    var missing: String {
        switch self {
        case .clue: return "exact map place"
        case .candidate: return "your confirmation"
        case .mapStamp: return "nothing before it enters memory"
        case .tripPlan: return "outside picks only when needed"
        }
    }

    var primaryAction: String {
        switch self {
        case .clue: return "Find exact place"
        case .candidate: return "Confirm or reject"
        case .mapStamp: return "Ask around this"
        case .tripPlan: return "Plan from memory"
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

private struct FirstRunMascotHero: View {
    var body: some View {
        VStack(spacing: 14) {
            MemoMascotMark(size: 132, framed: false)

            VStack(spacing: 8) {
                Text("Memo keeps your place clues safe.")
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundColor(.saveCocoa)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.saveHoney.opacity(0.72))
                    .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.42), lineWidth: 1))
                    .clipShape(Capsule())

                Text("Save spots while you scroll.")
                    .font(.title2)
                    .fontWeight(.black)
                    .foregroundColor(.saveInk)
                    .multilineTextAlignment(.center)

                Text("Share an IG post, map link, screenshot, or note. Memo keeps uncertain places in Review until you confirm the real Map Stamp.")
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundColor(.saveMutedText)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .background(Color.saveNotebookPage.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(0.34), lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(.horizontal, 24)
    }
}

private struct FirstRunProgressionChips: View {
    @Binding var selectedState: FirstRunDemoState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FirstRunDemoState.allCases, id: \.self) { state in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedState = state
                        }
                    } label: {
                        Text(state.rawValue)
                            .font(.caption)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(selectedState == state ? state.tint : Color.saveNotebookPage)
                            .overlay(
                                Capsule()
                                    .stroke(Color.saveNotebookLine, lineWidth: selectedState == state ? 1.8 : 1.1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct FirstRunPlaceDemoCard: View {
    let state: FirstRunDemoState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    MemoMascotMark(size: 48)

                    Image(systemName: state.icon)
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveInk)
                        .frame(width: 22, height: 22)
                        .background(state.tint)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(.headline)
                        .fontWeight(.black)
                        .foregroundColor(.saveInk)

                    Text(state.mascotLine)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.saveCocoa)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Source Clue -> Review Candidate -> Map Stamp -> Ask saved first")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.saveMutedText)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                FirstRunEvidenceRow(label: "Input", value: state.input)
                FirstRunEvidenceRow(label: "Known", value: state.known)
                FirstRunEvidenceRow(label: "Missing", value: state.missing)
            }

            Text("Next: \(state.primaryAction)")
                .font(.subheadline)
                .fontWeight(.black)
                .foregroundColor(.saveInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.saveNotebookPage)
                .overlay(
                    Capsule()
                        .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                )
        }
        .padding(18)
        .background(Color.saveNotebookPage.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 24)
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

private struct FirstRunEvidenceRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label.uppercased())
                .font(.caption2)
                .fontWeight(.black)
                .foregroundColor(.saveCocoa)
                .frame(width: 54, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
