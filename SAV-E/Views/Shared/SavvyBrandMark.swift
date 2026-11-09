import SwiftUI

struct SavvyBrandMark: View {
    var size: CGFloat = 72
    var framed = true

    var body: some View {
        Image("SavvyLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .padding(framed ? max(4, size * 0.08) : 0)
            .background(framed ? SaveAtlasPalette.paper.opacity(0.96) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: max(12, size * 0.22), style: .continuous))
            .overlay {
                if framed {
                    RoundedRectangle(cornerRadius: max(12, size * 0.22), style: .continuous)
                        .stroke(SaveAtlasPalette.line, lineWidth: max(1.4, size * 0.022))
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        SavvyBrandMark(size: 120)
        SavvyBrandMark(size: 46)
    }
    .padding()
    .background(SaveDottedBackground())
}
