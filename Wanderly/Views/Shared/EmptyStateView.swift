import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.saveSignal)

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.saveInk)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.black)
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.saveHoney)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.saveNotebookLine.opacity(0.82), lineWidth: 1.1)
                        )
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}
