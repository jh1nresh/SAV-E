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

                    MemoMascotMark(size: 92, framed: false)

                    VStack(spacing: 8) {
                        Text("Capture intent now. Use it when deciding.")
                            .font(.title2)
                            .fontWeight(.black)
                            .foregroundColor(.saveInk)
                            .multilineTextAlignment(.center)

                        Text("Save the place today, let SAV-E wake it up for date night, nearby coffee, or Tokyo next month.")
                            .font(.subheadline)
                            .lineSpacing(3)
                            .foregroundColor(.saveMutedText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    FirstRunProgressionChips(selectedState: $selectedState)

                    FirstRunPlaceDemoCard(state: selectedState)

                    Button(action: onComplete) {
                        Text("Add Spots")
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
        case .clue: return "Import a place you saved"
        case .candidate: return "Review before saving"
        case .mapStamp: return "Confirm into Map Stamp"
        case .tripPlan: return "Ask when deciding"
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
        case .clue: return "friend's Reel, map list, or link"
        case .candidate: return "one Review Candidate"
        case .mapStamp: return "Speranza · Silver Lake"
        case .tripPlan: return "date night near my saved spots"
        }
    }

    var known: String {
        switch self {
        case .clue: return "source + why it caught your eye"
        case .candidate: return "source text + map name + neighborhood"
        case .mapStamp: return "confirmed place identity"
        case .tripPlan: return "memory first, public second"
        }
    }

    var missing: String {
        switch self {
        case .clue: return "exact map place"
        case .candidate: return "your confirmation"
        case .mapStamp: return "nothing before saving"
        case .tripPlan: return "public discovery if needed"
        }
    }

    var primaryAction: String {
        switch self {
        case .clue: return "Find exact place"
        case .candidate: return "Confirm candidate"
        case .mapStamp: return "Ask around this"
        case .tripPlan: return "Open suggestions"
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
                Image(systemName: state.icon)
                    .font(.title3.weight(.black))
                    .foregroundColor(.saveInk)
                    .frame(width: 44, height: 44)
                    .background(state.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.4)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(.headline)
                        .fontWeight(.black)
                        .foregroundColor(.saveInk)

                    Text("Source Clue -> Review Candidate -> Map Stamp -> Ask / Plan")
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
