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
    case inbox
    case share

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: "Plan"
        case .map: "Map"
        case .inbox: "Inbox"
        case .share: "Share"
        }
    }

    var icon: String {
        switch self {
        case .plan: "map"
        case .map: "globe.asia.australia"
        case .inbox: "envelope"
        case .share: "point.3.connected.trianglepath.dotted"
        }
    }
}

private struct PrototypeShell: View {
    @State private var root: RootDestination = .home
    @State private var trip: TripDestination = .plan

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
                            TripPlanScreen(onBack: { root = .home })
                        case .map:
                            TripAtlasMapScreen(onBack: { root = .home })
                        case .inbox:
                            TripInboxPlaceholderScreen(onBack: { root = .home })
                        case .share:
                            TripSharePlaceholderScreen(onBack: { root = .home })
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
                        accessibilityPrefix: "tripTab",
                        onSelect: { trip = $0 }
                    )
                    .placed(x: 0, y: 786, width: 402, height: 76)
                    .accessibilityIdentifier("prototype.tripTabs")
                } else {
                    AtlasTabBar(
                        items: RootDestination.allCases,
                        selection: root,
                        title: \.title,
                        icon: \.icon,
                        accessibilityPrefix: "rootTab",
                        onSelect: { root = $0 }
                    )
                    .placed(
                        x: 0,
                        y: root == .map ? 788 : 786,
                        width: 402,
                        height: 76
                    )
                    .accessibilityIdentifier("prototype.rootTabs")
                }
            }
        }
        .tint(AtlasPalette.forest)
    }
}
