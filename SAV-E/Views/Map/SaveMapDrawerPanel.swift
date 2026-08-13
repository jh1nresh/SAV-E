import SwiftUI

/// One drawer surface for the Map tab (spec P2: one surface, two states).
///
/// The resting command shelf and the expanded ask/search drawer are the same
/// container morphing in place — expanding never presents a second layer, so
/// two drawers can never stack. The expanded panel honors the shared
/// `PresentationDetent` the drawer content already drives (`.medium` when the
/// search field focuses, `.large` for full content), restoring the staged
/// drawer heights the presented-sheet design had. Collapse via the grab
/// handle drag, the scrim, or programmatic dismissal.
struct SaveMapDrawerPanel<ExpandedContent: View>: View {
    @Binding var isExpanded: Bool
    @Binding var detent: PresentationDetent
    let mapStampCount: Int
    let showsCollapsedShelf: Bool
    let onExpand: () -> Void
    let onCollapse: () -> Void
    @ViewBuilder let expandedContent: () -> ExpandedContent

    /// Keeps the collapsed shelf clear of the tab bar, matching the resting
    /// shelf position the map canvas used to draw.
    private let collapsedBottomInset: CGFloat = 90
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if isExpanded {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { collapse() }
                        .accessibilityIdentifier("map.drawerPanel.scrim")
                }

                if isExpanded {
                    expandedPanel(totalHeight: proxy.size.height)
                        .transition(.move(edge: .bottom))
                } else if showsCollapsedShelf {
                    SaveAtlasMapCommandShelf(
                        mapStampCount: mapStampCount,
                        onOpenAssistant: onExpand
                    )
                    .frame(height: 112)
                    .padding(.horizontal, 15)
                    .padding(.bottom, collapsedBottomInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .animation(SaveTheme.Motion.standardSpring, value: isExpanded)
        .animation(SaveTheme.Motion.standardSpring, value: showsCollapsedShelf)
        .animation(SaveTheme.Motion.standardSpring, value: detent)
    }

    private func expandedPanel(totalHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(AtlasPalette.line.opacity(0.48))
                .frame(width: 38, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .updating($dragOffset) { value, state, _ in
                            state = max(0, value.translation.height)
                        }
                        .onEnded { value in
                            let travel = value.predictedEndTranslation.height
                            if travel > 80 {
                                // Step down one stage; below medium the panel
                                // leaves and the shelf returns.
                                if detent == .large {
                                    detent = .medium
                                } else {
                                    collapse()
                                }
                            } else if travel < -80 {
                                detent = .large
                            }
                        }
                )
                .accessibilityIdentifier("map.drawerPanel.handle")

            expandedContent()
        }
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight(totalHeight: totalHeight), alignment: .top)
        .background(
            AtlasPalette.canvas,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 28,
                topTrailingRadius: 28,
                style: .continuous
            )
        )
        .shadow(color: SaveAtlasPalette.ink.opacity(0.18), radius: 18, y: -4)
        .offset(y: dragOffset)
        // Container only: the keyboard safe area still applies, so the panel
        // rises with the keyboard instead of letting it cover the content.
        .ignoresSafeArea(.container, edges: .bottom)
        // No identifier here: the drawer content inside must keep exposing
        // its own `drawer.root` container to the accessibility tree.
    }

    /// Stage heights mirroring the old sheet detents. `totalHeight` already
    /// excludes the keyboard, so every stage stays fully visible while typing.
    private func panelHeight(totalHeight: CGFloat) -> CGFloat {
        if detent == .medium {
            return max(220, totalHeight * 0.55)
        }
        if detent == .height(132) {
            return 200
        }
        return max(220, totalHeight - 12)
    }

    private func collapse() {
        onCollapse()
    }
}
