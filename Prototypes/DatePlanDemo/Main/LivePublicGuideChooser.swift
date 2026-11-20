#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import SwiftUI

enum LivePublicGuideDestination: Equatable {
    case list(UUID), manageLists
}

@MainActor
struct LivePublicGuideChooser: View {
    let name: String
    let address: String
    let expiresAt: Date
    let onDestination: (LivePublicGuideDestination) -> Void
    let onClose: () -> Void
    @StateObject private var model: LivePublicGuideModel
    @State private var operation: Task<Void, Never>?
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.scenePhase) private var scenePhase

    init(venue: LivePublicDiscoveryVenue, expiresAt: Date, ownerSubject: String, sessionGeneration: Int,
         model: LivePublicGuideModel? = nil,
         onDestination: @escaping (LivePublicGuideDestination) -> Void, onClose: @escaping () -> Void) {
        name = venue.place.name; address = venue.place.address; self.expiresAt = expiresAt
        self.onDestination = onDestination; self.onClose = onClose
        _model = StateObject(wrappedValue: model ?? LivePublicGuideModel(venue: venue, expiresAt: expiresAt,
            ownerSubject: ownerSubject, sessionGeneration: sessionGeneration))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.title2).foregroundStyle(DateTheme.blue)
                            .frame(width: 48, height: 48).background(DateTheme.soft, in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(name).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            Text(address).font(.subheadline).foregroundStyle(DateTheme.muted)
                        }
                    }
                    if model.isLoading || model.isWorking {
                        ProgressView(model.isWorking ? copy("Adding to your list…", "正在加入共同清單…") : copy("Loading your lists…", "正在讀取共同清單…"))
                            .frame(maxWidth: .infinity, minHeight: 72)
                    }
                    content
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }.background(DateTheme.canvas).foregroundStyle(DateTheme.ink)
                .navigationTitle(copy("Plan with friends", "和朋友一起安排"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button(copy("Close", "關閉"), action: onClose).accessibilityIdentifier("live.publicGuide.close")
                } }
        }.tint(DateTheme.blue)
            .task { if model.state == .idle { await model.prepare() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { stop() } }
            .onDisappear { stop() }
            .accessibilityIdentifier("live.publicGuide.chooser")
    }

    @ViewBuilder private var content: some View {
        if model.state == .inactive || (model.state == .unavailable && expiresAt <= Date()) {
            Label(copy("Return to the map and reopen this place to continue.", "請回到地圖，重新打開地點後再繼續。"), systemImage: "arrow.clockwise")
                .font(.subheadline).foregroundStyle(DateTheme.muted).fixedSize(horizontal: false, vertical: true)
        } else if let id = model.completedListID, model.state == .completed {
            VStack(alignment: .leading, spacing: 14) {
                Label(model.hasExistingVenue || !model.writeAcknowledged ? copy("This place is in your list", "地點已在這份清單中") : copy("Added to your shared list", "已加入共同清單"),
                      systemImage: "checkmark.circle.fill").font(.headline)
                if let title = model.lists.first(where: { $0.id == id })?.title {
                    Text(title).font(.subheadline).foregroundStyle(DateTheme.muted)
                }
                Text(copy("Open the list to choose stops and arrange your day.", "打開清單，和朋友挑選停留的地方，再交給 Guide 安排。"))
                    .font(.subheadline).foregroundStyle(DateTheme.muted)
                DemoPrimaryButton(title: copy("Open Guide", "打開 Guide"), enabled: scenePhase == .active) {
                    onDestination(.list(id))
                }.accessibilityIdentifier("live.publicGuide.open")
            }.demoCard()
        } else if model.state == .unconfirmed {
            VStack(alignment: .leading, spacing: 14) {
                Label(copy("Checking the result", "加入結果尚未確認"), systemImage: "clock.arrow.circlepath").font(.headline)
                Text(copy("Reload the list to check. This won’t submit the place again.", "重新讀取清單確認結果，不會再次提交這個地點。"))
                    .font(.subheadline).foregroundStyle(DateTheme.muted)
                DemoPrimaryButton(title: copy("Check shared list", "重新確認清單"), enabled: !model.isWorking && !model.isLoading) {
                    run { await model.reconcile() }
                }.accessibilityIdentifier("live.publicGuide.reconcile")
            }.demoCard()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text(copy("Choose a shared list", "選一份共同清單")).font(.headline)
                Text(copy("This adds a place to plan together. It doesn’t mark it visited or publish the original post.",
                          "把地點加入一起討論，不會標記去過，也不會轉發原貼文。"))
                    .font(.subheadline).foregroundStyle(DateTheme.muted)
                ForEach(model.lists) { list in
                    Button {
                        run { await model.add(to: list.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2").foregroundStyle(DateTheme.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                Text(list.role.canEdit ? copy("\(list.itemCount) places · Add here", "\(list.itemCount) 個地點 · 加入這份清單") : copy("View only", "僅供查看"))
                                    .font(.caption).foregroundStyle(DateTheme.muted)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: list.role.canEdit ? "plus.circle" : "lock").foregroundStyle(DateTheme.muted)
                        }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(16).background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain)
                        .disabled(!list.role.canEdit || model.isLoading || model.isWorking || model.attemptedWrite)
                        .accessibilityIdentifier("live.publicGuide.list.\(list.id.uuidString)")
                }
                if model.lists.isEmpty, model.state == .ready {
                    Text(copy("No shared lists yet.", "還沒有共同清單。")).font(.subheadline).foregroundStyle(DateTheme.muted)
                }
                if model.error != nil {
                    Text(copy("Couldn’t open this shared list. Try again.", "暫時無法開啟這份共同清單，請重試。"))
                        .font(.subheadline).foregroundStyle(DateTheme.muted)
                    Button(copy("Reload lists", "重新讀取清單")) { run { await model.prepare() } }
                        .frame(minHeight: 44).disabled(model.isLoading || model.isWorking || model.attemptedWrite)
                }
                Button { onDestination(.manageLists) } label: {
                    Label(copy("Manage shared lists", "管理共同清單"), systemImage: "person.badge.plus")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }.disabled(model.isLoading || model.isWorking || model.attemptedWrite)
            }
        }
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        guard operation == nil, scenePhase == .active else { return }
        operation = Task { @MainActor in
            defer { operation = nil }
            await action()
        }
    }
    private func stop() { operation?.cancel(); operation = nil; model.deactivate() }
    private func copy(_ english: String, _ chinese: String) -> String { language.localized(english: english, traditionalChinese: chinese) }
}
#endif
