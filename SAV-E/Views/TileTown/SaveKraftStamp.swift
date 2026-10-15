import SwiftUI

/// One Map Stamp language for Home recent stamps and the Passport grid.
///
/// Two sizes of the same system, not two styles:
/// - Home recent: photo face + name
/// - Passport grid: photo or category glyph + name; locked slots show `???`
enum SaveKraftStampSize {
    case recent
    case grid

    var face: CGFloat {
        switch self {
        case .recent: return 52
        case .grid: return 72
        }
    }

    var title: CGFloat {
        switch self {
        case .recent: return 11
        case .grid: return 12
        }
    }
}

enum SaveKraftStampFace: Equatable {
    case photo(URL?)
    case glyph(String)
    case locked
}

struct SaveKraftStamp: View {
    let title: String
    let face: SaveKraftStampFace
    var size: SaveKraftStampSize = .grid
    var accessibilityIdentifier: String = "stamp.kraft"

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                SavePostcardScallopedRectangle(depth: 3, pitch: 8)
                    .fill(SaveAtlasPalette.paper)
                    .overlay {
                        SavePostcardScallopedRectangle(depth: 3, pitch: 8)
                            .stroke(SaveAtlasPalette.kraft.opacity(0.86), lineWidth: 1.2)
                    }
                    .shadow(color: SaveAtlasPalette.ink.opacity(0.06), radius: 2, y: 1)

                SaveKraftStampFaceView(face: face, glyph: fallbackGlyph)
                    .padding(7)
            }
            .frame(width: size.face, height: size.face)
            .accessibilityHidden(true)

            Text(visibleTitle)
                .font(SaveAtlasType.strong(size.title))
                .foregroundStyle(face == .locked ? SaveAtlasPalette.muted : SaveAtlasPalette.forest)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: size.face + 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(face == .locked ? "Locked stamp" : "Map Stamp, \(visibleTitle)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var visibleTitle: String {
        if case .locked = face { return "???" }
        return SaveSoftPixelAccentsLock.visibleStampText(title) ?? "Map Stamp"
    }

    private var fallbackGlyph: String {
        if case .glyph(let name) = face { return name }
        return "seal"
    }
}

struct SaveKraftStampFaceView: View {
    let face: SaveKraftStampFace
    var glyph: String = "seal"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SaveAtlasPalette.kraft.opacity(0.28))
            switch face {
            case .photo(let url):
                if let url {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            glyphView
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    glyphView
                }
            case .glyph:
                glyphView
            case .locked:
                Text("???")
                    .font(SaveAtlasType.strong(16))
                    .foregroundStyle(SaveAtlasPalette.muted)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var glyphView: some View {
        Image(systemName: glyph)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(SaveAtlasPalette.forest)
    }
}

struct SavePostageSealAvatar: View {
    var name: String
    var systemImage: String = "person.fill"
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            SavePostcardSealShape()
                .fill(SaveAtlasPalette.paper)
                .overlay {
                    SavePostcardSealShape()
                        .stroke(SaveAtlasPalette.kraft, lineWidth: 1.4)
                }
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(SaveAtlasPalette.forest)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .accessibilityLabel(name)
    }
}

enum SaveFriendLastAt {
    struct Row: Identifiable, Equatable {
        var id: String { authorID }
        let authorID: String
        let authorName: String
        let lastPost: SharedPlacePost
    }

    static func rows(from posts: [SharedPlacePost]) -> [Row] {
        var latest: [String: SharedPlacePost] = [:]
        for post in posts {
            if let existing = latest[post.author_id] {
                if post.shared_at > existing.shared_at {
                    latest[post.author_id] = post
                }
            } else {
                latest[post.author_id] = post
            }
        }
        return latest.values
            .sorted { lhs, rhs in
                if lhs.shared_at != rhs.shared_at { return lhs.shared_at > rhs.shared_at }
                return lhs.author_name.localizedCaseInsensitiveCompare(rhs.author_name) == .orderedAscending
            }
            .map { post in
                Row(authorID: post.author_id, authorName: post.author_name, lastPost: post)
            }
    }
}
