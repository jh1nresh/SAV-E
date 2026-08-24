import SwiftUI

/// Placeholder for the Origin tab (W4 in
/// `specs/2026-08-24-save-tab-restructure-and-origin-surface-v0.md`).
///
/// Origin's job is: *where did this place come from* — the user's own capture,
/// quoted verbatim with its original link. It is deliberately **not** a social
/// feed. Production measurement on 2026-08-24 found one user, 73 places, zero
/// `place_visibility` rows and zero `place_social_signals` rows, so any surface
/// implying other people would be fabricating.
///
/// This view exists so the five-tab bar shape is real and testable before the
/// content surface is built. It renders an honest empty state rather than
/// seeded cards: the same rule the Review pipeline enforces — do not pretend to
/// have evidence you do not have.
///
/// Do not add sample data here. W4 must be built against real captures.
struct SaveOriginPlaceholderView: View {
    let onOpenPassport: () -> Void
    @Environment(\.appLanguageSettings) private var languageSettings

    var body: some View {
        ZStack {
            AtlasCanvas()

            BrandHeader {
                EmptyView()
            }
            .placed(x: 0, y: 48, width: AtlasMetrics.width, height: 51)

            VStack(spacing: 10) {
                Image(systemName: "paperclip")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(SaveAtlasPalette.muted.opacity(0.55))

                Text(title)
                    .font(AtlasType.display(20))
                    .foregroundStyle(SaveAtlasPalette.ink)

                Text(subtitle)
                    .font(AtlasType.body(14))
                    .foregroundStyle(SaveAtlasPalette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("origin.placeholder")
        }
        .frame(width: AtlasMetrics.width, height: AtlasMetrics.height)
        .environment(\.atlasPresentation, atlasPresentation)
    }

    private var atlasPresentation: AtlasPresentation {
        var presentation = AtlasPresentation.reference
        presentation.onOpenPassport = onOpenPassport
        return presentation
    }

    private var title: String {
        languageSettings.language.localized(
            english: "Origin",
            traditionalChinese: "來處"
        )
    }

    private var subtitle: String {
        languageSettings.language.localized(
            english: "The post each saved place came from will appear here.",
            traditionalChinese: "你存的每個地點，是從哪一則貼文來的，之後會出現在這裡。"
        )
    }
}
