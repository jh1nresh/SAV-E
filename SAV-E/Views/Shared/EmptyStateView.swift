import SwiftUI

/// Memo-led empty state per DESIGN.md: Memo signals guidance, the cream
/// notebook card keeps it personal, and the CTA gives the next action.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?
    @State private var appeared = false

    var body: some View {
        VStack(spacing: SaveTheme.Spacing.lg) {
            ZStack(alignment: .bottomTrailing) {
                MemoMascotMark(size: 88)

                SaveIconTile(
                    systemName: icon,
                    size: 34,
                    fill: .saveHoney,
                    foreground: .saveInk,
                    strokeOpacity: 1,
                    cornerRadius: 11
                )
                .rotationEffect(.degrees(appeared ? -6 : 8))
                .offset(x: 12, y: 10)
            }
            .padding(.bottom, SaveTheme.Spacing.xs)

            VStack(spacing: SaveTheme.Spacing.sm) {
                Text(title)
                    .font(.system(.title3, design: .rounded).weight(.black))
                    .foregroundColor(.saveInk)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.saveMutedText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SaveTheme.Spacing.sm)

            if let actionTitle = actionTitle, let action = action {
                Button {
                    SaveHaptics.tap()
                    action()
                } label: {
                    Text(actionTitle)
                        .font(.subheadline.weight(.black))
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, SaveTheme.Spacing.xl)
                        .frame(minHeight: 44)
                        .background(Color.saveHoney)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 1.6)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SaveTheme.Spacing.xl)
        .saveNotebookPage(cornerRadius: 22)
        .padding(SaveTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(SaveTheme.Motion.standardSpring) {
                appeared = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    EmptyStateView(
        icon: "mappin.and.ellipse",
        title: "No Saved Places",
        subtitle: "Share a link from Instagram or any app to start building your map.",
        actionTitle: "Learn How",
        action: {}
    )
    .background(SaveDottedBackground())
}
