#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import SwiftUI
import MapKit

enum LiveMapMode: String, CaseIterable {
    case personal = "個人", outing = "朋友出遊"
}

/// A child of the existing verified account root. The parent owns loading and persistence.
@MainActor
struct LivePlanningMapRoot: View {
    @ObservedObject var mapVM: MapViewModel
    let ownerSubject: String
    let sessionGeneration: Int
    let onOpenSaved: (Place) -> Void
    let onOpenAccount: () -> Void
    let onCapture: () -> Void
    @StateObject private var outing: LiveOutingModel
    @StateObject private var plan: LiveRoutePlan
    @State private var destination = DemoDestination.map
    @State private var mode: LiveMapMode = .personal
    @State private var camera = MapCameraPosition.region(MKCoordinateRegion(
        center: .init(latitude: 25.04, longitude: 121.54), span: .init(latitudeDelta: 0.07, longitudeDelta: 0.07)))
    @State private var searchRegion = MKCoordinateRegion(center: .init(latitude: 25.04, longitude: 121.54),
                                                       span: .init(latitudeDelta: 0.07, longitudeDelta: 0.07))
    @State private var didFitSaved = false
    @State private var searchPresented = false
    @State private var selected: LiveMapPlace?
    @State private var mapSelection: String?
    @State private var showsPinDetails = false
    @State private var searchPin: LiveMapPlace?
    @State private var selectedStops: [String] = []
    @State private var teamPresented = false
    @State private var newListTitle = ""
    @State private var joinCode = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(mapVM: MapViewModel, ownerSubject: String, sessionGeneration: Int,
         onOpenSaved: @escaping (Place) -> Void, onOpenAccount: @escaping () -> Void,
         onCapture: @escaping () -> Void) {
        self.mapVM = mapVM; self.ownerSubject = ownerSubject; self.sessionGeneration = sessionGeneration
        self.onOpenSaved = onOpenSaved; self.onOpenAccount = onOpenAccount; self.onCapture = onCapture
        _outing = StateObject(wrappedValue: LiveOutingModel(ownerSubject: ownerSubject, sessionGeneration: sessionGeneration))
        _plan = StateObject(wrappedValue: LiveRoutePlan(ownerSubject: ownerSubject, sessionGeneration: sessionGeneration))
    }

    private var saved: [LiveMapPlace] { mapVM.places.compactMap(LiveMapPlace.saved) }
    private var groupPlaces: [LiveMapPlace] {
        guard let id = outing.selectedListID else { return [] }
        return outing.items.compactMap { LiveMapPlace.shared($0, listID: id) }
    }
    private var friendPlaces: [LiveMapPlace] { outing.posts.compactMap(LiveMapPlace.sharedPost) }
    private var pins: [LiveMapPlace] {
        let values = mode == .personal ? saved : (outing.selectedListID == nil ? friendPlaces : groupPlaces)
        return values + [searchPin].compactMap { $0 }.filter { pin in !values.contains(where: { $0.id == pin.id }) }
    }
    private var sessionIsCurrent: Bool {
        let auth = PrivyAuthService.shared
        guard case .authenticated = auth.authState else { return false }
        return auth.currentUserId == ownerSubject && auth.sessionGeneration == sessionGeneration
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                realMap.opacity(destination == .map ? 1 : 0)
                    .allowsHitTesting(destination == .map).accessibilityHidden(destination != .map)
                if destination != .map { DateTheme.canvas.ignoresSafeArea() }
                VStack(spacing: 12) {
                    if destination != .map { header }
                    if destination == .map {
                        modeControl
                        Spacer(minLength: 0)
                        HStack {
                            Spacer()
                            LiveMapLocationControl(position: $camera, ownerSubject: ownerSubject,
                                                   sessionGeneration: sessionGeneration)
                        }
                        if mode == .outing {
                            outingPanel.frame(maxHeight: (groupPlaces.isEmpty && plan.stops.isEmpty)
                                              ? min(240, geometry.size.height * 0.35)
                                              : geometry.size.height * 0.51).demoCard()
                        } else {
                            personalSummary.demoCard()
                        }
                    } else if destination == .saved {
                        savedPage
                    } else {
                        passport
                    }
                    dock
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
            }.foregroundStyle(DateTheme.ink)
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--preview-tab-saved") { destination = .saved }
            if ProcessInfo.processInfo.arguments.contains("--preview-tab-passport") { destination = .passport }
            fitSavedIfNeeded()
            if ProcessInfo.processInfo.arguments.contains("--map-mode-group") { mode = .outing }
        }
        .onChange(of: saved.map(\.id)) { _, _ in fitSavedIfNeeded() }
        .onChange(of: mode) { _, next in
            selected = nil; mapSelection = nil; searchPin = nil; selectedStops = []; plan.cancel()
            if next == .outing { Task { await outing.refresh() } }
            else { outing.deactivate() }
        }
        .onChange(of: outing.items.map(\.id)) { _, _ in
            selectedStops = []; plan.cancel()
            if selected?.origin == .shared { selected = nil }
            if !groupPlaces.isEmpty { fit(groupPlaces) }
        }
        .onChange(of: outing.posts.map(\.id)) { _, _ in
            if selected?.origin == .shared { selected = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, mode == .outing { Task { await outing.refresh() } }
            else if phase != .active { outing.deactivate(); plan.cancel(); selected = nil }
        }
        .onDisappear { outing.deactivate(); plan.cancel() }
        .sheet(isPresented: $searchPresented) {
            LiveMapSearch(region: searchRegion) { pin in
                guard sessionIsCurrent else { return }
                destination = .map
                searchPin = pin
                camera = .region(.init(center: pin.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))
            }.presentationDetents([.large])
        }
        .sheet(item: $selected, onDismiss: { mapSelection = nil }) { pin in
            placeCard(pin).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $teamPresented) { teamSheet.presentationDetents([.large]) }
    }

    private var realMap: some View {
        Map(position: $camera, selection: $mapSelection) {
            ForEach(pins) { pin in
                if showsPinDetails {
                Annotation(pin.place.name, coordinate: pin.coordinate, anchor: .bottom) {
                    Button { selected = pin } label: {
                        VStack(spacing: 5) {
                            Image(systemName: pin.place.category.iconName).font(.system(size: 20, weight: .semibold))
                                .frame(width: 46, height: 46).background(DateTheme.surface, in: Circle())
                                .overlay(Circle().stroke(pin.origin == .saved ? DateTheme.blue.opacity(0.55) : DateTheme.coral, lineWidth: 2))
                            VStack(spacing: 2) {
                                Text(pin.place.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                Text(pin.sourceLabel).font(.system(size: 9)).foregroundStyle(DateTheme.muted)
                            }.padding(.horizontal, 9).padding(.vertical, 5).background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                        }.foregroundStyle(DateTheme.ink).shadow(color: .black.opacity(0.1), radius: 5, y: 3)
                    }.buttonStyle(.plain).accessibilityLabel("\(pin.place.name)，\(pin.sourceLabel)")
                }.annotationTitles(.hidden)
                } else {
                    Marker("\(pin.place.name)，\(pin.sourceLabel)", systemImage: pin.origin == .saved ? "bookmark.fill" : "questionmark", coordinate: pin.coordinate)
                        .tint(pin.origin == .saved ? DateTheme.blue : DateTheme.coral)
                        .tag(pin.id).annotationTitles(.hidden)
                }
            }
            if mode == .outing {
                ForEach(Array(plan.routes.enumerated()), id: \.offset) { _, route in
                    MapPolyline(route.polyline).stroke(DateTheme.coral, lineWidth: 5)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, showsTraffic: false))
        .mapControls { MapCompass() }
        .onMapCameraChange(frequency: .onEnd) {
            searchRegion = $0.region
            showsPinDetails = $0.camera.distance < 20_000
        }
        .onChange(of: mapSelection) { _, id in
            if let id { selected = pins.first { $0.id == id } }
        }
        .ignoresSafeArea().accessibilityIdentifier("live.map")
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(destination.rawValue).font(.title2.weight(.bold))
            Spacer()
            if destination == .saved {
                Text("\(mapVM.places.count)").font(.subheadline.weight(.semibold))
                    .foregroundStyle(DateTheme.muted)
            }
        }.padding(.horizontal, 4).frame(minHeight: 44)
    }

    private var modeControl: some View {
        HStack(spacing: 0) {
            ForEach(LiveMapMode.allCases, id: \.self) { value in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { mode = value }
                } label: {
                    Label(value.rawValue, systemImage: value == .personal ? "person.fill" : "person.2.fill")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(mode == value ? DateTheme.ink : DateTheme.muted)
                        .background {
                            if mode == value {
                                Capsule().fill(DateTheme.surface)
                                    .shadow(color: DateTheme.blue.opacity(0.12), radius: 6, y: 2)
                            }
                        }
                }.buttonStyle(.plain).accessibilityIdentifier(value == .personal ? "live.mode.personal" : "live.mode.group")
                    .accessibilityAddTraits(mode == value ? .isSelected : [])
            }
        }.padding(4).background(DateTheme.canvas.opacity(0.96), in: Capsule())
            .overlay(Capsule().stroke(DateTheme.ink.opacity(0.06)))
            .frame(maxWidth: 300).frame(maxWidth: .infinity)
    }

    private var personalSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { destination = .saved } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bookmark.fill").foregroundStyle(DateTheme.blue)
                        .frame(width: 38, height: 38).background(DateTheme.soft, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("我的收藏").font(.subheadline.weight(.semibold))
                        Text("\(mapVM.places.count) 個地方").font(.caption).foregroundStyle(DateTheme.muted)
                    }
                    Spacer()
                    if mapVM.isLoading { ProgressView() }
                    else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DateTheme.muted) }
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !mapVM.isLoading, mapVM.places.isEmpty {
                Text("搜尋想去的地方，或從貼文加入收藏。").font(.caption).foregroundStyle(DateTheme.muted)
            }
            if mapVM.places.count > saved.count {
                Text("\(mapVM.places.count - saved.count) 筆未定位，保留於收藏清單")
                    .font(.caption).foregroundStyle(DateTheme.muted)
            }
        }
    }

    private var savedPage: some View {
        LivePlanningLibraryView(places: mapVM.places, isLoading: mapVM.isLoading, onOpen: { place in
            if let pin = LiveMapPlace.saved(place) { selected = pin }
            else { onOpenSaved(place) }
        }, onCapture: onCapture)
    }

    private var passport: some View {
        LivePlanningPassportView(places: mapVM.places,
                                onOpenLibrary: { destination = .saved }, onOpenAccount: onOpenAccount)
    }

    private var outingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(outing.selectedListID == nil ? "一起出遊" : outing.selectedTitle).font(.system(size: 21, weight: .bold))
                    Text(outing.selectedListID == nil ? "選擇共同清單，邀朋友一起加入地點。" : "\(outing.members.count) 位實際加入成員 · \(outing.items.count) 個地點")
                        .font(.system(size: 11)).foregroundStyle(DateTheme.muted)
                }
                Spacer()
                Button { teamPresented = true } label: { Image(systemName: "person.badge.plus").frame(width: 44, height: 44) }
                    .accessibilityLabel("共同清單與成員").accessibilityIdentifier("live.team")
            }
            if outing.isLoading || outing.isWorking { ProgressView("連線共同清單…") }
            if let error = outing.error {
                Text(error).font(.caption).foregroundStyle(DateTheme.coral)
                Button("重新載入") { Task { await outing.refresh() } }.frame(minHeight: 44)
            }
            if let notice = outing.notice {
                Text(notice).font(.caption).foregroundStyle(DateTheme.muted)
                Button("重新讀取共同清單") { Task { await outing.refresh() } }
                    .disabled(outing.isLoading || outing.isWorking).frame(minHeight: 44)
            }
            if outing.selectedListID == nil, let error = outing.feedError {
                Text(error).font(.caption).foregroundStyle(DateTheme.muted)
            }
            if outing.unmappedItemCount + outing.items.count - groupPlaces.count > 0 {
                Text("\(outing.unmappedItemCount + outing.items.count - groupPlaces.count) 筆地點尚無可顯示的 Apple Maps 座標，仍保留於共同清單。")
                    .font(.caption).foregroundStyle(DateTheme.muted)
            }
            if let error = plan.error { Text(error).font(.caption).foregroundStyle(DateTheme.coral) }
            if plan.isLoading { ProgressView("向 Apple Maps 查詢步行路線…") }
            if !plan.stops.isEmpty { guideTimeline }
            else {
                ScrollView {
                    VStack(spacing: 8) {
                        if outing.selectedListID == nil {
                            ForEach(friendPlaces) { pin in
                                Button { selected = pin } label: { venueRow(name: pin.place.name, address: pin.place.address, symbol: pin.place.category.iconName, suffix: "朋友分享") }
                                    .buttonStyle(.plain)
                            }
                            if friendPlaces.isEmpty, !outing.isLoading {
                                Text("還沒有共同清單或可顯示的朋友分享。先建立清單，或用邀請碼加入。")
                                    .font(.subheadline).foregroundStyle(DateTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            ForEach(groupPlaces) { pin in
                                HStack {
                                    Button { selected = pin } label: { venueRow(name: pin.place.name, address: pin.place.address, symbol: pin.place.category.iconName, suffix: "隊伍候選") }
                                        .buttonStyle(.plain)
                                    Button { toggleStop(pin.id) } label: {
                                        Image(systemName: selectedStops.contains(pin.id) ? "checkmark.circle.fill" : "plus.circle")
                                            .font(.system(size: 25)).frame(width: 44, height: 48)
                                    }.buttonStyle(.plain).foregroundStyle(DateTheme.coral).disabled(plan.isLoading)
                                }
                            }
                            if groupPlaces.isEmpty { Text("這份清單還沒有可放上地圖的地點。可從個人收藏或搜尋結果明確加入。")
                                .font(.subheadline).foregroundStyle(DateTheme.muted) }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            if plan.stops.isEmpty {
                DemoPrimaryButton(title: selectedStops.isEmpty ? "選擇出遊地點 · 最多 6 站" : "Guide 排路線 · \(selectedStops.count) 站",
                                  enabled: selectedStops.count >= 2 && !plan.isLoading) {
                    let values = selectedStops.compactMap { id in groupPlaces.first { $0.id == id } }
                    Task { await plan.build(values) }
                }
            }
        }
    }

    private var guideTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SAV-E GUIDE").font(.system(size: 10, weight: .bold)).tracking(1)
                Spacer()
                DatePicker("出發", selection: $plan.beginsAt, displayedComponents: .hourAndMinute)
                    .labelsHidden().disabled(plan.started)
                Button("重排") { plan.cancel() }.disabled(plan.started)
            }
            Text("實際步行路線 · 每站預留 \(plan.dwellMinutes) 分 · 預算待確認")
                .font(.system(size: 11)).foregroundStyle(DateTheme.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(plan.stops.enumerated()), id: \.element.id) { index, pin in
                        Button { selected = pin } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack {
                                    Text(plan.arrival(at: index), style: .time).font(.system(size: 12, weight: .semibold))
                                    Text("\(index + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                        .frame(width: 24, height: 24).background(DateTheme.coral, in: Circle())
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pin.place.name).font(.system(size: 15, weight: .semibold))
                                    Text(pin.place.address).font(.system(size: 11)).lineLimit(2).foregroundStyle(DateTheme.muted)
                                    if index > 0 {
                                        Text("步行約 \(Int(ceil(plan.routes[index - 1].expectedTravelTime / 60))) 分鐘")
                                            .font(.system(size: 11)).foregroundStyle(DateTheme.muted)
                                    }
                                }
                                Spacer(minLength: 0)
                            }.padding(12).background(DateTheme.soft, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.hidden)
            if !plan.started { DemoPrimaryButton(title: "開始照行程走") { plan.start() } }
            else if plan.currentIndex < plan.stops.count {
                DemoPrimaryButton(title: "下一站 · \(plan.stops[plan.currentIndex].place.name)") { plan.advance() }
            } else { Label("這次行程已走完", systemImage: "checkmark.circle.fill").font(.subheadline) }
        }
    }

    private var dock: some View {
        HStack(spacing: 12) {
            Button { searchPresented = true } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 21, weight: .medium)).frame(width: 54, height: 54)
                    .background(DateTheme.surface, in: Circle()).shadow(color: .black.opacity(0.09), radius: 10, y: 4)
            }.buttonStyle(.plain).accessibilityLabel("搜尋 Apple Maps").accessibilityIdentifier("live.search")
            DemoDock(selection: $destination)
        }.padding(.horizontal, 12)
    }

    private func placeCard(_ pin: LiveMapPlace) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: pin.place.category.iconName).font(.system(size: 36)).padding(.top, 8)
                    Text(pin.place.name).font(.title.bold())
                    DemoPill(text: pin.sourceLabel, tint: pin.origin == .saved ? DateTheme.blue : DateTheme.coral)
                    Text(pin.place.address).font(.body)
                    if pin.origin == .saved, let note = pin.place.note, !note.isEmpty {
                        Text("你的備註").font(.headline); Text(note).font(.body)
                    }
                    Text("營業時間、菜單與預算待確認。")
                        .font(.caption).foregroundStyle(DateTheme.muted)
                    Button("使用 Apple Maps 導航") {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: pin.coordinate))
                        item.name = pin.place.name
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                    }.frame(minHeight: 44)
                    if mode == .outing, outing.selectedListID != nil {
                        Text("只分享店名、地址與位置，不包含私人筆記或照片。")
                            .font(.caption).foregroundStyle(DateTheme.muted)
                        DemoPrimaryButton(title: "加入這次出遊清單", enabled: outing.canEditSelected && !outing.isWorking) {
                            Task { await outing.add(pin.listPayload); selected = nil }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            }.navigationTitle("地點").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { selected = nil } } }
        }
    }

    private var teamSheet: some View {
        NavigationStack {
            Form {
                Section("共同清單") {
                    ForEach(outing.lists) { list in
                        Button {
                            teamPresented = false
                            Task { await outing.selectList(list.id) }
                        } label: { HStack { Text(list.title); Spacer(); Text("\(list.itemCount) 個地點").foregroundStyle(.secondary) } }
                    }
                    if outing.isLoading { ProgressView() }
                    if let error = outing.error { Text(error).foregroundStyle(DateTheme.coral) }
                    if let notice = outing.notice { Text(notice).foregroundStyle(.secondary) }
                    if outing.error != nil || outing.notice != nil {
                        Button("重新讀取共同清單") { Task { await outing.refresh() } }
                            .disabled(outing.isLoading || outing.isWorking)
                    }
                }
                if outing.selectedListID != nil {
                    Section("已加入成員") {
                        ForEach(outing.members) { member in
                            Label(member.displayName, systemImage: member.role == .owner ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                        }
                        if outing.canInviteSelected {
                            Button("產生共同加店邀請") { Task { await outing.makeInvite() } }.disabled(outing.isWorking)
                        }
                        if let url = outing.shareURL { ShareLink("分享邀請連結", item: url) }
                    }
                }
                Section("建立新的出遊清單") {
                    TextField("例如：週六下午", text: $newListTitle)
                    Button("建立清單") { Task { await outing.createList(title: newListTitle) } }
                        .disabled(newListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || outing.isWorking)
                }
                Section("用朋友給的邀請碼加入") {
                    TextField("邀請碼", text: $joinCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("加入清單") { Task { await outing.join(code: joinCode) } }
                        .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || outing.isWorking)
                }
                Text("共同清單會同步地點；此版本由你安排路線，不會代替朋友投票。")
                    .font(.caption).foregroundStyle(.secondary)
            }.navigationTitle("一起出遊").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { teamPresented = false } } }
        }
    }

    private func venueRow(name: String, address: String, symbol: String, suffix: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 21)).frame(width: 42, height: 42)
                .background(DateTheme.soft, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(address).font(.system(size: 11)).foregroundStyle(DateTheme.muted).lineLimit(2)
                Text(suffix).font(.system(size: 10)).foregroundStyle(DateTheme.muted)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(10).background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 17))
    }

    private func toggleStop(_ id: String) {
        guard !plan.started, !plan.isLoading else { return }
        if selectedStops.contains(id) { selectedStops.removeAll { $0 == id } }
        else if selectedStops.count < 6 { selectedStops.append(id) }
    }
    private func fitSavedIfNeeded() {
        guard !didFitSaved, !saved.isEmpty else { return }
        didFitSaved = true
        if mode == .personal { fit(saved) }
    }
    private func fit(_ values: [LiveMapPlace]) {
        if let region = SaveInkMapCamera.region(around: values.map(\.coordinate), user: nil, focused: nil) { camera = .region(region) }
    }
}

@MainActor
private struct LiveMapSearch: View {
    let region: MKCoordinateRegion
    let onPick: (LiveMapPlace) -> Void
    @State private var query = ""
    @State private var values: [LiveMapPlace] = []
    @State private var searching = false
    @State private var error: String?
    @State private var request: MKLocalSearch?
    @State private var operation: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if searching { ProgressView("搜尋 Apple Maps…") }
                if let error { Text(error).foregroundStyle(.secondary) }
                ForEach(values) { pin in
                    Button { onPick(pin); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(pin.place.name).font(.headline)
                            Text(pin.place.address).font(.caption).foregroundStyle(.secondary)
                            Text("在地圖查看 · 尚未收藏").font(.caption2)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋地點、餐廳或地址")
                .onSubmit(of: .search, search)
                .navigationTitle("搜尋 Apple Maps").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }.onDisappear { operation?.cancel(); request?.cancel() }
    }
    private func search() {
        operation?.cancel(); request?.cancel(); values = []; error = nil; searching = false
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let input = MKLocalSearch.Request(); input.naturalLanguageQuery = text; input.region = region
        let search = MKLocalSearch(request: input); request = search; searching = true
        operation = Task {
            defer { if !Task.isCancelled { searching = false } }
            do {
                let response = try await search.start()
                guard !Task.isCancelled else { return }
                values = response.mapItems.compactMap(LiveMapPlace.search)
                if values.isEmpty { error = "沒有找到對應地點，可換個店名或地址。" }
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "目前無法完成搜尋，請稍後重試。"
            }
        }
    }
}
#endif
