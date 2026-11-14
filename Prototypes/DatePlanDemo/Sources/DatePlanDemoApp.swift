#if !SAVVY_MAIN_APP || (DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW)
import SwiftUI
import MapKit

#if !SAVVY_MAIN_APP
@main
struct SavvyDateDemoApp: App {
    var body: some Scene {
        WindowGroup { DateDemoRoot().preferredColorScheme(.light) }
    }
}
#endif

enum DemoDestination: String, CaseIterable {
    case saved = "收藏", map = "地圖", passport = "Passport"
    var symbol: String {
        switch self { case .saved: "tray.fill"; case .map: "globe.asia.australia.fill"; case .passport: "book.closed.fill" }
    }
    var key: String {
        switch self { case .saved: "saved"; case .map: "map"; case .passport: "passport" }
    }
}

@MainActor
struct DateDemoRoot: View {
    @State private var store = DatePlanStore()
    @State private var destination = DemoDestination.map
    @State private var step = 0
    @State private var searchPresented = false
    @State private var selectedPlace: String?
    @State private var startEditor = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                DateMap(store: store, selectedPlace: $selectedPlace)
                    .opacity(destination == .map ? 1 : 0)
                    .allowsHitTesting(destination == .map)
                    .accessibilityHidden(destination != .map)
                if destination != .map { DateTheme.canvas.ignoresSafeArea() }
                LinearGradient(colors: [.white.opacity(0.90), .white.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150).frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea().allowsHitTesting(false)
                VStack(spacing: 12) {
                    header
                    if destination == .map {
                        steps
                        Spacer(minLength: 8)
                        DatePlanningPanel(store: store, step: $step, startEditor: $startEditor, selectedPlace: $selectedPlace)
                            .frame(maxHeight: max(260, geometry.size.height * (step == 2 ? 0.57 : 0.49)))
                            .demoCard()
                    } else if destination == .saved {
                        DemoSavedScreen(store: store) { selectedPlace = $0; destination = .map }
                    } else {
                        DemoPassportScreen(store: store) { step = 2; destination = .map }
                    }
                    dock
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
            }
            .foregroundStyle(DateTheme.ink)
        }
        .sheet(isPresented: $searchPresented) {
            DemoSearchScreen(store: store)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(item: Binding(get: { selectedPlace.flatMap(store.place).map(DemoSelection.init) },
                             set: { selectedPlace = $0?.place.id })) { selection in
            DemoPlaceDetail(store: store, place: selection.place)
                .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $startEditor) {
            VStack(alignment: .leading, spacing: 24) {
                Text("幾點開始這次約會？").font(.title2.bold())
                Text("改動後，後面的停留與移動時間會一起順延。")
                    .font(.subheadline).foregroundStyle(DateTheme.muted)
                HStack {
                    Button { store.setStartMinutes(store.startsAtMinutes - 15) } label: {
                        Image(systemName: "minus").frame(width: 52, height: 52).background(DateTheme.soft, in: Circle())
                    }.accessibilityLabel("提早15分鐘")
                    Spacer()
                    Text(DatePlanStore.clock(store.startsAtMinutes)).font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit().accessibilityIdentifier("demo.startTime")
                    Spacer()
                    Button { store.setStartMinutes(store.startsAtMinutes + 15) } label: {
                        Image(systemName: "plus").frame(width: 52, height: 52).background(DateTheme.soft, in: Circle())
                    }.accessibilityLabel("延後15分鐘").accessibilityIdentifier("demo.laterStart")
                }.buttonStyle(.plain)
                DemoPrimaryButton(title: "就這個時間") { startEditor = false }
                    .accessibilityIdentifier("demo.confirmStart")
            }.padding(24).presentationDetents([.height(300)])
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SAVVY  /  本地預覽・示範資料")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1)
                    .foregroundStyle(DateTheme.muted)
                Text(destination == .map ? "週六，和小安出門" : destination.rawValue)
                    .font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.8)
                    .minimumScaleFactor(0.8).lineLimit(1)
                Text("台北大安・2 個人・半天約會")
                    .font(.system(size: 12)).foregroundStyle(DateTheme.muted)
            }
            Spacer(minLength: 2)
            HStack(spacing: -8) { DemoAvatar(person: .you, size: 35); DemoAvatar(person: .an, size: 35) }
        }
        .padding(.horizontal, 4).padding(.vertical, 8)
        .background {
            LinearGradient(colors: [.white.opacity(0.97), .white.opacity(0.80), .white.opacity(0)],
                           startPoint: .top, endPoint: .bottom).padding(-20)
        }
    }

    private var steps: some View {
        HStack(spacing: 8) {
            ForEach(Array(["朋友推薦", "一起挑", "Guide"].enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84)) { step = index }
                } label: {
                    HStack(spacing: 5) {
                        Text("\(index + 1)").opacity(0.6)
                        Text(title)
                    }.font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .foregroundStyle(step == index ? .white : DateTheme.ink)
                        .background(step == index ? DateTheme.ink : .white.opacity(0.95), in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("demo.step.\(index)")
                    .accessibilityAddTraits(step == index ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
    }

    private var dock: some View {
        HStack(spacing: 12) {
            Button { searchPresented = true } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 23, weight: .medium))
                    .frame(width: 58, height: 58).background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
            }.accessibilityLabel("搜尋地點").accessibilityIdentifier("demo.search")
            DemoDock(selection: $destination)
        }.buttonStyle(.plain).padding(.horizontal, 12)
    }
}

private struct DemoSelection: Identifiable {
    let place: DemoPlace
    var id: String { place.id }
}

struct DemoDock: View {
    @Binding var selection: DemoDestination
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            ForEach(DemoDestination.allCases, id: \.self) { tab in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.79)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol).font(.system(size: 21, weight: .medium))
                        Text(tab.rawValue).font(.system(size: 10, weight: .semibold))
                    }.frame(maxWidth: .infinity).frame(height: 58)
                        .foregroundStyle(selection == tab ? DateTheme.ink : DateTheme.muted)
                        .background {
                            if selection == tab {
                                Capsule().fill(DateTheme.surface)
                                    .overlay(Capsule().stroke(DateTheme.blue.opacity(0.22), lineWidth: 2))
                                    .shadow(color: DateTheme.blue.opacity(0.27), radius: 10)
                                    .matchedGeometryEffect(id: "selection", in: highlight)
                            }
                        }
                }.buttonStyle(.plain).accessibilityIdentifier("demo.tab.\(tab.key)")
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }.padding(5).background(DateTheme.canvas.opacity(0.96), in: Capsule())
            .overlay(Capsule().stroke(DateTheme.ink.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.09), radius: 18, y: 6)
    }
}

@MainActor
struct DateMap: View {
    let store: DatePlanStore
    @Binding var selectedPlace: String?
    @State private var position = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.0285, longitude: 121.5411),
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.013)))
    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            if store.planIDs.count > 1 {
                MapPolyline(coordinates: store.planIDs.compactMap { id in
                    store.place(id).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                }).stroke(DateTheme.ink.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 6]))
            }
            ForEach(store.places) { place in
                Annotation(place.name, coordinate: .init(latitude: place.latitude, longitude: place.longitude), anchor: .bottom) {
                    Button { selectedPlace = place.id } label: {
                        VStack(spacing: 5) {
                            Text(place.emoji).font(.system(size: 27))
                                .frame(width: 49, height: 49).background(.white, in: Circle())
                                .overlay(Circle().stroke(store.sharedIDs.contains(place.id) ? DateTheme.coral : .white, lineWidth: 3))
                                .overlay(alignment: .topLeading) {
                                    if let index = store.planIDs.firstIndex(of: place.id) {
                                        Text("\(index + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                            .frame(width: 19, height: 19).background(DateTheme.ink, in: Circle())
                                    }
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if let recommender = place.recommendedBy { DemoAvatar(person: recommender, size: 21).offset(x: 5, y: 3) }
                                }
                            VStack(spacing: 3) {
                                Label(place.name, systemImage: store.savedIDs.contains(place.id) ? "bookmark.fill" : "questionmark.circle")
                                    .font(.system(size: 11, weight: .semibold))
                                Text((store.savedIDs.contains(place.id) ? "已收藏" : "候選")
                                     + (store.sharedIDs.contains(place.id) ? " · 都想去" : ""))
                                    .font(.system(size: 9, weight: .medium)).foregroundStyle(DateTheme.muted)
                            }.padding(.horizontal, 9).padding(.vertical, 6).background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }.foregroundStyle(DateTheme.ink).shadow(color: .black.opacity(0.10), radius: 5, y: 3)
                    }.buttonStyle(.plain).accessibilityLabel("\(place.name)，\(store.savedIDs.contains(place.id) ? "已收藏" : "候選")，\(store.sharedIDs.contains(place.id) ? "雙方都想去，" : "")示範地點")
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .safeAreaPadding(.bottom, 300).safeAreaPadding(.top, 100)
        .ignoresSafeArea()
        .accessibilityIdentifier("demo.map")
    }
}

#endif
