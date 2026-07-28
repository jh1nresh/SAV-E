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
        case .home: "house.fill"
        case .saves: "bookmark.fill"
        case .trips: "suitcase.fill"
        case .map: "map.fill"
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
        case .plan: "list.number"
        case .map: "map.fill"
        case .inbox: "tray.fill"
        case .share: "square.and.arrow.up.fill"
        }
    }
}

private struct PrototypeShell: View {
    @State private var root: RootDestination = .home
    @State private var trip: TripDestination = .plan

    var body: some View {
        ZStack {
            AtlasPalette.canvas.ignoresSafeArea()

            Group {
                switch root {
                case .home:
                    HomeAtlasScreen()
                case .saves:
                    SavesPocketScreen()
                case .trips:
                    TripPlanScreen(onBack: { root = .home })
                case .map:
                    RootAtlasMapScreen()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if root == .trips {
                AtlasTabBar(
                    items: TripDestination.allCases,
                    selection: trip,
                    title: \.title,
                    icon: \.icon,
                    onSelect: { trip = $0 }
                )
                .accessibilityIdentifier("prototype.tripTabs")
            } else {
                AtlasTabBar(
                    items: RootDestination.allCases,
                    selection: root,
                    title: \.title,
                    icon: \.icon,
                    onSelect: { root = $0 }
                )
                .accessibilityIdentifier("prototype.rootTabs")
            }
        }
        .tint(AtlasPalette.forest)
    }
}
