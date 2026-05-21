import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0
    var onComplete: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "sparkle.magnifyingglass",
            title: "Send Any Place Signal",
            subtitle: "Share links, posts, screenshots, notes, or map URLs. SAV-E investigates the real place before it saves anything.",
            color: .wanderlyTerracotta
        ),
        OnboardingPage(
            icon: "checklist.checked",
            title: "Review Before Saving",
            subtitle: "Uncertain places become review candidates with evidence, confidence, and missing details instead of fake pins.",
            color: Color(hex: "5B8FA8")
        ),
        OnboardingPage(
            icon: "map.fill",
            title: "Plan From Memory",
            subtitle: "Confirmed places become agent-readable memory SAV-E can use for trips, maps, and future restaurant or flight actions.",
            color: Color(hex: "8B5E83")
        ),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 30) {
                        Spacer()

                        ZStack {
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .fill(pages[index].color.opacity(0.10))
                                .frame(width: 132, height: 132)

                            Image(systemName: pages[index].icon)
                                .font(.system(size: 64, weight: .semibold))
                                .foregroundColor(pages[index].color)
                        }

                        VStack(spacing: 12) {
                            Text(pages[index].title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.wanderlyCharcoal)
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
                            .fill(index == currentPage ? Color.wanderlyTerracotta : Color.wanderlyTerracotta.opacity(0.3))
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
                        .background(Color.wanderlyTerracotta)
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
        .background(Color.wanderlyCream)
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
