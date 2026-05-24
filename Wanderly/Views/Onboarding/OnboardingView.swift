import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0
    var onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "magnifyingglass.circle.fill",
            title: "Save spots while you scroll",
            subtitle: "Share an IG post, map link, screenshot, or note. SAV-E turns messy clues into reviewable places.",
            color: .saveHoney
        ),
        OnboardingPage(
            icon: "checkmark.seal.fill",
            title: "No more fake pins",
            subtitle: "If SAV-E is unsure, it keeps the clue in Review until you confirm it.",
            color: .saveSky
        ),
        OnboardingPage(
            icon: "rectangle.stack.badge.plus",
            title: "Turn memories into trips",
            subtitle: "Your confirmed spots become a private travel memory SAV-E can plan from.",
            color: .saveCocoa
        ),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 30) {
                        Spacer()

                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.saveNotebookPage)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(Color.saveNotebookLine.opacity(0.86), lineWidth: 1.2)
                                )
                                .frame(width: 132, height: 132)

                            Image(systemName: pages[index].icon)
                                .font(.system(size: 64, weight: .semibold))
                                .foregroundColor(pages[index].color)
                        }

                        VStack(spacing: 12) {
                            Text(pages[index].title)
                                .font(.title2)
                                .fontWeight(.black)
                                .foregroundColor(.saveInk)
                                .multilineTextAlignment(.center)

                            Text(pages[index].subtitle)
                                .font(.subheadline)
                                .lineSpacing(3)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Bottom controls
            VStack(spacing: 0) {
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? Color.saveCocoa : Color.saveCocoa.opacity(0.26))
                            .frame(width: index == currentPage ? 24 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }
                .padding(.bottom, 32)

                // Button
                Button(action: {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        onComplete()
                    }
                }) {
                    Text(currentPage < pages.count - 1 ? "Next" : "Start with SAV-E")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.saveInk)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        onComplete()
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(SaveDottedBackground())
    }
}

// MARK: - Onboarding Page Model

struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
}

#Preview {
    OnboardingView(onComplete: {})
}
