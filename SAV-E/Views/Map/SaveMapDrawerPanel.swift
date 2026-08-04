import SwiftUI

/// One drawer surface for the Map tab (spec P2: one surface, two states).
///
/// The resting command shelf and the expanded ask/search drawer are the same
/// container morphing in place — expanding never presents a second layer, so
/// two drawers can never stack. Collapse via the grab handle drag, the scrim,
/// or programmatic dismissal; both states share the panel's rounded paper
/// chrome so the transition reads as one object growing.
struct SaveMapDrawerPanel<ExpandedContent: View>: View {
    @Binding var isExpanded: Bool
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
        ZStack(alignment: .bottom) {
            if isExpanded {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { collapse() }
                    .accessibilityIdentifier("map.drawerPanel.scrim")
            }

            if isExpanded {
                expandedPanel
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
        .animation(SaveTheme.Motion.standardSpring, value: isExpanded)
        .animation(SaveTheme.Motion.standardSpring, value: showsCollapsedShelf)
    }

    private var expandedPanel: some View {
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
                            if value.translation.height > 80 { collapse() }
                        }
                )
                .accessibilityIdentifier("map.drawerPanel.handle")

            expandedContent()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            AtlasPalette.canvas,
            in: UnevenRoundedRectangle(
                topLeadingRadius: 28,
                topTrailingRadius: 28,
                style: .continuous
            )
        )
        .shadow(color: SaveAtlasPalette.ink.opacity(0.18), radius: 18, y: -4)
        .padding(.top, 64)
        .offset(y: dragOffset)
        .ignoresSafeArea(edges: .bottom)
        // No identifier here: the drawer content inside must keep exposing
        // its own `drawer.root` container to the accessibility tree.
    }

    private func collapse() {
        onCollapse()
    }
}
