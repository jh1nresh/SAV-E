import SwiftUI

@main
struct AtlasPostcardPrototypeApp: App {
    var body: some Scene {
        WindowGroup {
            PrototypeShell()
                .preferredColorScheme(.light)
        }
    }
}

private enum RootDestination: String, CaseIterable, Identifiable {
    case home
    case saves
    case trips
    case map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .saves: "Saves"
        case .trips: "Trips"
        case .map: "Map"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .saves: "bookmark"
        case .trips: "briefcase"
        case .map: "globe"
        }
    }
}

private enum TripDestination: String, CaseIterable, Identifiable {
    case plan
    case map

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: "Plan"
        case .map: "Map"
        }
    }

    var icon: String {
        switch self {
        case .plan: "map"
        case .map: "globe.asia.australia"
        }
    }
}

private struct PrototypeShell: View {
    @State private var root: RootDestination = .home
    @State private var trip: TripDestination = .plan
    @State private var showsTripShare = false

    var body: some View {
        ReferenceViewport {
            ZStack(alignment: .topLeading) {
                Group {
                    switch root {
                    case .home:
                        HomeAtlasScreen()
                    case .saves:
                        SavesPocketScreen()
                    case .trips:
                        switch trip {
                        case .plan:
                            TripPlanScreen(
                                onBack: { root = .home },
                                onShare: { showsTripShare = true }
                            )
                        case .map:
                            TripAtlasMapScreen(
                                onBack: { root = .home },
                                onShare: { showsTripShare = true }
                            )
                        }
                    case .map:
                        RootAtlasMapScreen()
                    }
                }

                if root == .trips {
                    AtlasTabBar(
                        items: TripDestination.allCases,
                        selection: trip,
                        title: \.title,
                        icon: \.icon,
                        accessibilityPrefix: "prototype.tripTab",
                        onSelect: { trip = $0 }
                    )
                    .placed(
                        x: AtlasTabBarMetrics.leadingInset,
                        y: AtlasTabBarMetrics.standardY,
                        width: AtlasTabBarMetrics.width,
                        height: AtlasTabBarMetrics.height
                    )
                    .accessibilityIdentifier("prototype.tripTabs")
                } else {
                    AtlasTabBar(
                        items: RootDestination.allCases,
                        selection: root,
                        title: \.title,
                        icon: \.icon,
                        accessibilityPrefix: "prototype.rootTab",
                        onSelect: { root = $0 }
                    )
                    .placed(
                        x: AtlasTabBarMetrics.leadingInset,
                        y: root == .map
                            ? AtlasTabBarMetrics.mapY
                            : AtlasTabBarMetrics.standardY,
                        width: AtlasTabBarMetrics.width,
                        height: AtlasTabBarMetrics.height
                    )
                    .accessibilityIdentifier("prototype.rootTabs")
                }
            }
        }
        .tint(AtlasPalette.forest)
        .sheet(isPresented: $showsTripShare) {
            TripSharePlaceholderScreen(onBack: { showsTripShare = false })
        }
    }
}
