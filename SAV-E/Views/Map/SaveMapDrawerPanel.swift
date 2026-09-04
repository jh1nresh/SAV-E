import SwiftUI

/// One resizable drawer surface for the Map tab.
///
/// Collapsed is the Apple Maps–style floating search pill. Medium and large
/// keep the existing in-tree panel. The map stays interactive above it, and
/// expanding never presents a second layer. The embedded drawer intentionally
/// doesn't use sheet presentation modifiers because those can abort SwiftUI's
/// presentation coordinator when attached to an in-tree view.
struct SaveMapDrawerPanel<ExpandedContent: View>: View {
    @Binding var isExpanded: Bool
    @Binding var detent: PresentationDetent
    let mapStampCount: Int
    let showsCollapsedShelf: Bool
    /// `focusesSearch` is true for a tap and false for a resize drag. Dragging
    /// the card shouldn't summon the keyboard; tapping the field should.
    let onExpand: (_ focusesSearch: Bool) -> Void
    let onCollapse: () -> Void
    @ViewBuilder let expandedContent: () -> ExpandedContent

    /// Keeps the collapsed floating pill clear of the root tab bar.
    private let collapsedBottomInset: CGFloat = 88
    private let collapsedHeight: CGFloat = 72
    @State private var collapsedDragConsumedTap = false
    @GestureState private var dragTranslation: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if isExpanded {
                    expandedPanel(totalHeight: proxy.size.height)
                        .transition(.move(edge: .bottom))
                } else if showsCollapsedShelf {
                    collapsedShelf
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .animation(SaveTheme.Motion.standardSpring, value: isExpanded)
        .animation(SaveTheme.Motion.standardSpring, value: showsCollapsedShelf)
        .animation(SaveTheme.Motion.standardSpring, value: detent)
    }

    private var collapsedShelf: some View {
        SaveAtlasMapCommandShelf(
            mapStampCount: mapStampCount,
            onOpenAssistant: {
                guard !collapsedDragConsumedTap else { return }
                onExpand(true)
            }
        )
        .frame(height: 68)
        .padding(.horizontal, 15)
        .padding(.bottom, collapsedBottomInset)
        .offset(y: max(-96, min(0, dragTranslation)))
        .simultaneousGesture(resizeGesture(stage: .collapsed))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map search drawer")
        .accessibilityValue(MapDrawerStage.collapsed.accessibilityValue)
        .accessibilityIdentifier(MapDrawerStage.collapsed.accessibilityIdentifier)
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
                .gesture(resizeGesture(stage: expandedStage))
                .onTapGesture { cycleExpandedStage() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Resize map search drawer")
                .accessibilityValue(expandedStage.accessibilityValue)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        moveUp(from: expandedStage)
                    case .decrement:
                        moveDown(from: expandedStage)
                    @unknown default:
                        break
                    }
                }
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
        // Container only: the keyboard safe area still applies, so the panel
        // rises with the keyboard instead of letting it cover the content.
        .ignoresSafeArea(.container, edges: .bottom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map search drawer")
        .accessibilityValue(expandedStage.accessibilityValue)
        .accessibilityIdentifier(expandedStage.accessibilityIdentifier)
    }

    /// `totalHeight` already excludes the keyboard, so every stage remains
    /// visible while typing. During a drag the panel tracks the finger 1:1,
    /// then settles at the nearest directional stop on release.
    private func panelHeight(totalHeight: CGFloat) -> CGFloat {
        let largeHeight = max(320, totalHeight - 12)
        let baseHeight = expandedStage == .large
            ? largeHeight
            : max(320, totalHeight * 0.42)
        return min(largeHeight, max(collapsedHeight, baseHeight - dragTranslation))
    }

    private var expandedStage: MapDrawerStage {
        detent == .large ? .large : .medium
    }

    private func resizeGesture(stage: MapDrawerStage) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onChanged { value in
                guard stage == .collapsed,
                      abs(value.translation.height) >= 8
                else { return }
                collapsedDragConsumedTap = true
            }
            .onEnded { value in
                if stage == .collapsed {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        collapsedDragConsumedTap = false
                    }
                }

                let projectedTravel = value.predictedEndTranslation.height
                let actualTravel = value.translation.height
                let travel = abs(projectedTravel) > abs(actualTravel)
                    ? projectedTravel
                    : actualTravel

                guard abs(travel) >= 44 else { return }
                if travel < 0 {
                    moveUp(from: stage)
                } else {
                    moveDown(from: stage)
                }
            }
    }

    private func moveUp(from stage: MapDrawerStage) {
        switch stage {
        case .collapsed:
            onExpand(false)
        case .medium:
            withAnimation(SaveTheme.Motion.standardSpring) {
                detent = .large
            }
        case .large:
            break
        }
    }

    private func moveDown(from stage: MapDrawerStage) {
        switch stage {
        case .collapsed:
            break
        case .medium:
            collapse()
        case .large:
            withAnimation(SaveTheme.Motion.standardSpring) {
                detent = .medium
            }
        }
    }

    private func cycleExpandedStage() {
        if expandedStage == .large {
            moveDown(from: .large)
        } else {
            moveUp(from: .medium)
        }
    }

    private func collapse() {
        onCollapse()
    }
}

private enum MapDrawerStage {
    case collapsed
    case medium
    case large

    var accessibilityIdentifier: String {
        switch self {
        case .collapsed: "map.drawerPanel.collapsed"
        case .medium: "map.drawerPanel.medium"
        case .large: "map.drawerPanel.large"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .collapsed: "Collapsed"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}
