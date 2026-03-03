import SwiftUI

struct PlatformIcon: View {
    let platform: SourcePlatform
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: iconName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundColor(iconColor)
    }

    private var iconName: String {
        switch platform {
        case .instagram: return "camera.fill"
        case .threads: return "at"
        case .xiaohongshu: return "book.fill"
        case .googleMaps: return "map.fill"
        case .other: return "link"
        }
    }

    private var iconColor: Color {
        switch platform {
        case .instagram: return Color(hex: "E1306C")
        case .threads: return .primary
        case .xiaohongshu: return Color(hex: "FE2C55")
        case .googleMaps: return Color(hex: "4285F4")
        case .other: return .secondary
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(SourcePlatform.allCases, id: \.self) { platform in
            PlatformIcon(platform: platform)
        }
    }
    .padding()
}
