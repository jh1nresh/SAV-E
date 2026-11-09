#if SAVVY_CITY_MVP
import SwiftUI
import UIKit

/// Appearance only. The parent positions the bottom at the native MapKit point.
struct CityPinArtwork: View {
    static let height: CGFloat = 72
    struct Photo {
        let image: UIImage
        let author: String
        let source: URL
    }

    private static let photos: [String: Photo] = [
        ("landmark-101", "taipei101-pin", "AnthonySantiago101", "Tower_of_Taipei_101.jpg"),
        ("way/234589397", "att4fun-pin", "Wikipedia user – Wpcpey", "ATT_4_Fun_Exterior_view_201911.jpg"),
    ].reduce(into: [:]) { photos, entry in
        let (id, asset, author, source) = entry
        guard let url = Bundle.main.url(forResource: asset, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path),
              let sourceURL = URL(string: "https://commons.wikimedia.org/wiki/File:\(source)") else { return }
        photos[id] = Photo(image: image, author: author, source: sourceURL)
    }

    static func photo(for id: String?) -> Photo? {
        id.flatMap { photos[$0] }
    }

    let id: String?
    let title: String
    let symbol: String
    let saved: Bool
    let selected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        let photo = Self.photo(for: id)?.image
        let diameter: CGFloat = photo == nil ? (selected ? 40 : 30) : (selected ? 49 : 40)
        let rim = selected ? CityMVPStyle.selected : Color.white
        VStack(spacing: 0) {
            if selected {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .foregroundStyle(CityMVPStyle.ink)
                    .background(CityMVPStyle.surface, in: Capsule())
                    .padding(.bottom, 3)
            }
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(rim)
                    .frame(width: 10, height: 10)
                    .rotationEffect(.degrees(45))
                    .offset(y: 3)
                Group {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable().scaledToFill()
                            .accessibilityHidden(true)
                    } else {
                        CityMVPStyle.panel.overlay {
                            Image(systemName: symbol)
                                .font(.system(size: selected ? 17 : 13, weight: .semibold))
                                .foregroundStyle(CityMVPStyle.ink)
                        }
                    }
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(rim, lineWidth: selected ? 3.5 : 2.5))
                .overlay(alignment: .bottomTrailing) {
                    if saved {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(CityMVPStyle.actionFill, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                    }
                }
            }
            .scaleEffect(selected && !reduceMotion && !settled ? 0.84 : 1, anchor: .bottom)
            .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
            Rectangle().fill(CityMVPStyle.blue).frame(width: 1, height: 3)
            Circle().fill(CityMVPStyle.blue).frame(width: 5, height: 5)
        }
        .frame(minWidth: 44, minHeight: 44, alignment: .bottom)
        .contentShape(Rectangle())
        .frame(width: selected ? 136 : 46, height: Self.height, alignment: .bottom)
        .onAppear {
            guard selected, !reduceMotion else { settled = true; return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.59)) { settled = true }
        }
    }
}
#endif
