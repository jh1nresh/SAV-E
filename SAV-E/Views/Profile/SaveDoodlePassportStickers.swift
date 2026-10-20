import SwiftUI

/// Official DESIGN stickers on the Passport grid. The die-cut (or pencil
/// outline) is the primary mark; rank rings are a second layer and must not
/// wrap a shrunken icon in a filled circle.
struct SaveDoodlePassportSticker: View {
    let kind: SaveDoodleStickerKind
    let visited: Bool

    var body: some View {
        Image(kind.officialSticker.imageName(visited: visited, pointSize: SaveLayout.passportSlot))
            .resizable()
            .interpolation(.high)
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: SaveLayout.passportSlot, height: SaveLayout.passportSlot)
            .accessibilityHidden(true)
    }
}

struct SaveDoodlePassportStamp: View {
    let rank: SavePassportStampRank
    let seed: String

    var body: some View {
        Group {
            switch rank {
            case .none:
                EmptyView()
            case .single:
                Circle()
                    .stroke(SaveDoodle.stampRed, lineWidth: 2)
            case .double:
                ZStack {
                    Circle().stroke(SaveDoodle.stampRed, lineWidth: 1.5)
                    Circle()
                        .stroke(SaveDoodle.stampRed, lineWidth: 1.5)
                        .padding(4)
                }
            case .gold:
                Circle()
                    .stroke(SaveDoodle.stampGold, lineWidth: 2.5)
            }
        }
        .rotationEffect(.degrees(SaveDoodlePassportCatalog.rotationDegrees(for: seed)))
        .accessibilityHidden(true)
    }
}

struct SaveDoodlePassportSlotView: View {
    let slot: SaveDoodlePassportSlot
    var isStamping: Bool = false

    var body: some View {
        ZStack {
            switch slot.content {
            case let .place(_, kind, rank):
                SaveDoodlePassportSticker(kind: kind, visited: rank != .none)
                if rank == .none {
                    Circle()
                        .stroke(
                            SaveDoodle.pencil,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                }
                SaveDoodlePassportStamp(rank: rank, seed: slot.id)
            case .empty:
                Circle()
                    .stroke(
                        SaveDoodle.pencil,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            }
        }
        .frame(
            width: SaveDoodlePassportCatalog.slotSize,
            height: SaveDoodlePassportCatalog.slotSize
        )
        .scaleEffect(isStamping ? 1.08 : 1)
        .animation(SaveTheme.Motion.stampSpring, value: isStamping)
    }
}

extension SaveDoodleStickerKind {
    /// Sample set is six official stickers. Extra catalog kinds map to the
    /// nearest official mark until DESIGN ships the full place set.
    var officialSticker: SaveDoodleOfficialSticker {
        switch self {
        case .duck, .baozi, .dessert:
            return .duck
        case .noodles, .hotpot:
            return .noodle
        case .coffee, .tea:
            return .coffee
        case .temple, .tree, .hill, .museum, .beach, .bridge, .camera, .bicycle, .ferris, .pin:
            return .temple
        case .lantern, .wine, .beer, .bag, .bookstore:
            return .lantern
        }
    }
}
