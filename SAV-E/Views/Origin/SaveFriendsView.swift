import SwiftUI

/// Friends stays visible in the root bar while its sharing experience is deferred.
struct SaveFriendsView: View {
    @Environment(\.appLanguageSettings) private var language

    var body: some View {
        ZStack(alignment: .topLeading) {
            AtlasCanvas()
            BrandHeader { EmptyView() }
                .placed(x: 0, y: 48, width: AtlasMetrics.width, height: 51)

            Text(language.localized(english: "Friends", traditionalChinese: "朋友"))
                .font(SaveAtlasType.display(28))
                .foregroundStyle(SaveAtlasPalette.forest)
                .frame(maxWidth: .infinity, alignment: .leading)
                .placed(x: 16, y: 122, width: AtlasMetrics.width - 32, height: 42)

            VStack(spacing: 24) {
                Image(systemName: "person.2")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .frame(width: 96, height: 96)
                    .background(SaveAtlasPalette.mint, in: Circle())
                    .accessibilityHidden(true)

                Text(language.localized(english: "Coming soon", traditionalChinese: "即將推出"))
                    .font(SaveAtlasType.display(26))
                    .foregroundStyle(SaveAtlasPalette.forest)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("friends.comingSoon")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .placed(x: 24, y: 240, width: AtlasMetrics.width - 48, height: 300)
        }
        .frame(width: AtlasMetrics.width, height: AtlasMetrics.height)
        .background(SaveAtlasPalette.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends.root")
    }
}
