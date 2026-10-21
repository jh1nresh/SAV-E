import SwiftUI

enum ClipGooglePhotoMetrics {
    static let logoHeight: CGFloat = 18
    static let clearSpaceLeading: CGFloat = 10
    static let clearSpaceTrailing: CGFloat = 10
    static let clearSpaceTop: CGFloat = 10
    static let clearSpaceBottom: CGFloat = 5
    static let minimumTapTarget: CGFloat = ClipJournalLayout.minTap
    static let cardHeight: CGFloat = 180
    static let gradientTopOpacity: Double = 0.55
    static let gradientBottomOpacity: Double = 0.82
    static let authorShadowOpacity: Double = 0.5
}

/// Place-detail Google photo. Authors are required; otherwise the coral
/// fallback is shown. List rows must not use this view.
struct ClipGooglePhotoCard: View {
    let photo: (url: URL, authors: [SharedPlacePhotoAuthor], mapsURL: URL?)?

    var body: some View {
        if let photo, !photo.authors.isEmpty {
            ZStack(alignment: .bottom) {
                AsyncImage(url: photo.url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        ClipCoralPhotoFallback()
                    }
                }
                ClipGooglePhotoAttributionBar(authors: photo.authors, mapsURL: photo.mapsURL)
            }
            .frame(maxWidth: .infinity, minHeight: ClipGooglePhotoMetrics.cardHeight, maxHeight: ClipGooglePhotoMetrics.cardHeight)
            .clipped()
            .accessibilityIdentifier("clip.place.photo")
        } else {
            ClipCoralPhotoFallback()
                .frame(maxWidth: .infinity, minHeight: ClipGooglePhotoMetrics.cardHeight, maxHeight: ClipGooglePhotoMetrics.cardHeight)
                .accessibilityIdentifier("clip.place.photo.fallback")
        }
    }
}

struct ClipCoralPhotoFallback: View {
    var body: some View {
        ZStack {
            ClipJournalPalette.coral
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

struct ClipGooglePhotoAttributionBar: View {
    let authors: [SharedPlacePhotoAuthor]
    var mapsURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            authorRow
            HStack(alignment: .center, spacing: 8) {
                if let mapsURL {
                    Link(destination: mapsURL) {
                        Text(ClipCopy.text("View on Google Maps", "在 Google Maps 查看"))
                            .font(ClipJournalType.regular(13, relativeTo: .footnote))
                            .underline()
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(ClipGooglePhotoMetrics.authorShadowOpacity), radius: 2)
                            .frame(maxWidth: .infinity, minHeight: ClipGooglePhotoMetrics.minimumTapTarget, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("place.photo.attribution.viewOnMaps")
                } else {
                    Spacer(minLength: 0)
                }
                ClipGoogleMapsLogo()
            }
        }
        .padding(.leading, ClipGooglePhotoMetrics.clearSpaceLeading)
        .padding(.trailing, ClipGooglePhotoMetrics.clearSpaceTrailing)
        .padding(.top, ClipGooglePhotoMetrics.clearSpaceTop)
        .padding(.bottom, ClipGooglePhotoMetrics.clearSpaceBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    .black.opacity(ClipGooglePhotoMetrics.gradientTopOpacity),
                    .black.opacity(ClipGooglePhotoMetrics.gradientBottomOpacity),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var authorRow: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(authors.enumerated()), id: \.offset) { index, author in
                if index > 0 {
                    Text("、")
                        .font(ClipJournalType.regular(13, relativeTo: .footnote))
                        .foregroundStyle(.white)
                }
                authorLabel(author, index: index)
            }
        }
    }

    @ViewBuilder
    private func authorLabel(_ author: SharedPlacePhotoAuthor, index: Int) -> some View {
        let name = author.displayName
        let label = ClipCopy.text("Photo by \(name)", "照片作者 \(name)")
        if let uri = author.uri, let url = URL(string: uri) {
            Link(destination: url) {
                Text(name)
                    .font(ClipJournalType.strong(13, relativeTo: .footnote))
                    .underline()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(ClipGooglePhotoMetrics.authorShadowOpacity), radius: 2)
                    .frame(minHeight: ClipGooglePhotoMetrics.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier(index == 0 ? "place.photo.attribution.author" : "place.photo.attribution.author.\(index)")
            .accessibilityLabel(label)
        } else {
            Text(name)
                .font(ClipJournalType.strong(13, relativeTo: .footnote))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(ClipGooglePhotoMetrics.authorShadowOpacity), radius: 2)
                .frame(minHeight: ClipGooglePhotoMetrics.minimumTapTarget)
                .accessibilityIdentifier(index == 0 ? "place.photo.attribution.author" : "place.photo.attribution.author.\(index)")
                .accessibilityLabel(label)
        }
    }
}

struct ClipGoogleMapsLogo: View {
    var body: some View {
        Image("GoogleMapsLogoOnImage")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(height: ClipGooglePhotoMetrics.logoHeight)
            .frame(minWidth: ClipGooglePhotoMetrics.minimumTapTarget, minHeight: ClipGooglePhotoMetrics.minimumTapTarget)
            .accessibilityLabel("Google Maps")
            .accessibilityIdentifier("place.photo.attribution.logo")
    }
}
