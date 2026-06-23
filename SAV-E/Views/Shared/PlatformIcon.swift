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
        case .douyin: return "play.rectangle.fill"
        case .dianping: return "fork.knife"
        case .googleMaps: return "map.fill"
        case .appleMaps: return "mappin.and.ellipse"
        case .amap: return "map.circle.fill"
        case .baidu: return "mappin.circle.fill"
        case .other: return "link"
        }
    }

    private var iconColor: Color {
        switch platform {
        case .instagram, .threads, .xiaohongshu, .douyin, .dianping, .googleMaps, .appleMaps, .amap, .baidu: return .saveCocoa
        case .other: return .saveMutedText
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
