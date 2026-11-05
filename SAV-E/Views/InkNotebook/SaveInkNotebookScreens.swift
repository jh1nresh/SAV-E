import SwiftUI

struct SaveInkHomeScreen: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var store: SaveInkNotebookStore
    @Environment(\.saveInkScreenshot) private var saveInkScreenshot
    @Environment(\.scenePhase) private var scenePhase

    private var showsLiveMap: Bool {
        store.usesLivePlaces && !saveInkScreenshot
    }

    private var picks: [SaveInkPlace] {
        store.homePlaces()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if showsLiveMap {
                            SaveInkLiveMap(
                                places: picks,
                                userCoordinate: store.userCoordinate,
                                focusPlaceID: nil,
                                showsRoute: false,
                                onSelect: { store.openPlace($0) }
                            )
                        }
                        friendsEntry
                        ForEach(picks) { place in
                            Button {
                                store.openPlace(place.id)
                            } label: {
                                placeCard(place)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(place.name)
                            .accessibilityIdentifier("ink.place.\(place.id)")
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                Text(picks.isEmpty ? languageSettings.localized(english: "Save a place, record your visit later", traditionalChinese: "存一個地點，到了再記") : languageSettings.localized(english: "Tap a place for walking directions", traditionalChinese: "輕點卡片，看地圖怎麼走"))
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                if let placeID = homeArrivalID {
                    SaveInkArriveButton {
                        Task { await store.checkIn(placeID: placeID) }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
                } else if let place = picks.first,
                          place.shopLatitude == nil || place.shopLongitude == nil {
                    SaveInkOutlineButton(title: languageSettings.localized(english: "Record visit (unverified)", traditionalChinese: "記錄到訪（未驗證）"), identifier: "ink.arrived.unverified") {
                        store.recordUnverifiedVisit(placeID: place.id)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 44)
                } else if !picks.isEmpty {
                    SaveInkArriveButton(isEnabled: false) {}
                        .padding(.horizontal, 24)
                        .padding(.bottom, 44)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SaveInkPalette.paper.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.home")
        .task { await store.refreshLivePlaces() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.refreshLivePlaces() }
        }
    }

    /// Fixture Home can check in the featured place. Live Home checks in only
    /// the nearest located stamp. Without a distance, the person opens a card.
    private var homeArrivalID: String? {
        store.arrivalPlaceID()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(languageSettings.localized(english: "Places nearby", traditionalChinese: "附近值得去的"))
                    .font(SaveInkType.pageTitle)
                    .foregroundStyle(SaveInkPalette.ink)
                homeCount
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                SaveInkCircleButton(label: "人", identifier: "ink.passport.entry", personIcon: true, spoken: languageSettings.localized(english: "Passport", traditionalChinese: "護照")) {
                    store.openPassport()
                }
                SaveInkCircleButton(label: "+", identifier: "ink.save.entry", spoken: languageSettings.localized(english: "Save a place", traditionalChinese: "存地點")) {
                    store.openSave()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var homeCount: some View {
        Text(store.homeSummary(count: picks.count, language: languageSettings.language))
            .font(SaveInkType.aux)
            .foregroundStyle(SaveInkPalette.inkSub)
            .accessibilityIdentifier(picks.isEmpty ? "ink.home.empty" : "ink.home.count")
    }

    private var friendsEntry: some View {
        Button(action: store.openFriends) {
            HStack(spacing: 12) {
                SaveInkPersonIcon()
                    .frame(width: 22, height: 22)
                Text(languageSettings.localized(english: "Friends’ places", traditionalChinese: "朋友推薦"))
                    .font(SaveInkType.body)
                    .foregroundStyle(SaveInkPalette.ink)
                Spacer()
                Text("→")
                    .font(SaveInkType.body)
                    .foregroundStyle(SaveInkPalette.ink)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(
                SaveInkRoughRoundedRect(cornerRadius: 18, seed: 7)
                    .fill(SaveInkPalette.card)
            )
            .overlay(
                SaveInkRoughRoundedRect(cornerRadius: 18, seed: 7)
                    .stroke(SaveInkPalette.ink, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ink.friends.entry")
        .accessibilityLabel(languageSettings.localized(english: "Friends’ places", traditionalChinese: "朋友推薦"))
    }

    private func placeCard(_ place: SaveInkPlace) -> some View {
        let badge = store.homeBadge(for: place)
        let saved = badge == .saved
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(place.name)
                    .font(SaveInkType.shop)
                    .foregroundStyle(SaveInkPalette.ink)
                Spacer(minLength: 8)
                SaveInkBadge(
                    text: badge == .unverified ? languageSettings.localized(english: "△ Unverified visit", traditionalChinese: "△ 未驗證造訪") : (saved ? languageSettings.localized(english: "○ Saved, not visited", traditionalChinese: "○ 存了還沒去") : languageSettings.localized(english: "✓ Visited", traditionalChinese: "✓ 去過")),
                    verified: badge == .visited
                )
            }
            Text(place.meta)
                .font(SaveInkType.aux)
                .foregroundStyle(SaveInkPalette.inkSub)
            if store.usesLivePlaces, let minutes = place.walkMinutes {
                Text(languageSettings.localized(english: "\(minutes) min walk", traditionalChinese: "步行 \(minutes) 分"))
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
            }
            Text(SaveInkSystemCopy.text(place.blurb, language: languageSettings.language, isUserContent: place.blurbIsUserContent))
                .font(SaveInkType.body)
                .foregroundStyle(SaveInkPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("▣")
                Text(SaveInkSystemCopy.text(place.sourceLabel, language: languageSettings.language))
            }
            .font(SaveInkType.aux)
            .foregroundStyle(SaveInkPalette.inkSub)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            SaveInkRoughRoundedRect(cornerRadius: 18, seed: SaveInkSeed.of(place.id))
                .fill(saved ? Color.clear : SaveInkPalette.card)
        )
        .overlay(
            SaveInkRoughRoundedRect(cornerRadius: 18, seed: SaveInkSeed.of(place.id))
                .stroke(
                    SaveInkPalette.ink,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: saved ? [6, 5] : [])
                )
        )
    }

}

struct SaveInkSaveSheet: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var store: SaveInkNotebookStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(SaveInkPalette.ink.opacity(0.35))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
            HStack {
                Text(languageSettings.localized(english: "Save a place", traditionalChinese: "存一個地點"))
                    .font(SaveInkType.sheetTitle)
                    .foregroundStyle(SaveInkPalette.ink)
                Spacer()
                SaveInkCircleButton(label: "×", identifier: "ink.save.close") {
                    store.cancelSheet()
                }
            }
            Text(languageSettings.localized(english: "Save content about places", traditionalChinese: "只收跟地點有關的內容"))
                .font(SaveInkType.aux)
                .foregroundStyle(SaveInkPalette.inkSub)
            Text(languageSettings.localized(english: "Paste a video link", traditionalChinese: "貼上影片連結"))
                .font(SaveInkType.body)
                .foregroundStyle(SaveInkPalette.ink)
            HStack {
                Text(store.saveLink.isEmpty ? languageSettings.localized(english: "https://example.com/video/…", traditionalChinese: "https://短影音連結/v/8f2k…") : store.saveLink)
                    .font(SaveInkType.aux)
                    .foregroundStyle(store.saveLink.isEmpty ? SaveInkPalette.inkSub : SaveInkPalette.ink)
                    .lineLimit(1)
                Spacer()
                Button(languageSettings.localized(english: "Paste", traditionalChinese: "貼上")) { store.pasteExampleLink() }
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.ink)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("ink.save.paste")
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(field)
            if let id = store.recognizedPlaceID, let place = store.place(id) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(place.name)
                            .font(SaveInkType.shop)
                        Spacer()
                        SaveInkBadge(text: languageSettings.localized(english: "✓ Place identified", traditionalChinese: "✓ 已辨識"), verified: true)
                    }
                    Text("\(place.addressLine ?? place.street)・\(place.meta.components(separatedBy: "・").last ?? "")")
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.inkSub)
                    Text("▣ \(place.videoSource ?? place.sourceLabel)")
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.inkSub)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(field)
            }
            Text(languageSettings.localized(english: "Or enter a place name", traditionalChinese: "或直接搜店名"))
                .font(SaveInkType.body)
                .foregroundStyle(SaveInkPalette.ink)
            SaveInkLineField(
                placeholder: languageSettings.localized(english: "Enter a place name", traditionalChinese: "輸入店名，例如「赤峰街」"),
                text: $store.saveQuery,
                identifier: "ink.save.query"
            )
            if let notice = store.saveNotice {
                Text(SaveInkSystemCopy.text(notice, language: languageSettings.language))
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ink.save.notice")
            }
            SaveInkOutlineButton(title: languageSettings.localized(english: "Save place", traditionalChinese: "存起來"), identifier: "ink.save.commit") {
                store.commitSave()
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .background(sheetBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.save")
    }

    private var field: some View {
        SaveInkRoughRoundedRect(cornerRadius: 18, seed: 19)
            .stroke(SaveInkPalette.ink, lineWidth: 2)
    }

    private var sheetBackground: some View {
        UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 30)
            .fill(SaveInkPalette.paper)
    }
}

struct SaveInkCheckInSheet: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var store: SaveInkNotebookStore
    var place: SaveInkPlace
    var situation: SaveInkCheckInSituation

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(SaveInkPalette.ink.opacity(0.35))
                .frame(width: 42, height: 5)
                .padding(.top, 10)
            Text(title)
                .font(SaveInkType.sheetTitle)
                .foregroundStyle(SaveInkPalette.ink)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
                    .multilineTextAlignment(.center)
            }
            if situation != .placeChanged {
                stamp
                    .frame(width: stampSize, height: stampSize)
            }
            if showsComment {
                commentBox
                sentiment
            }
            buttons
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 30)
                .fill(SaveInkPalette.paper)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.checkin.\(situation.id)")
    }

    private var title: String {
        switch situation {
        case .verified:
            return languageSettings.localized(english: "Visit verified, stamp added", traditionalChinese: "到了，已蓋章")
        case .locationFailed:
            return languageSettings.localized(english: "Location unavailable, visit recorded", traditionalChinese: "定位不到，先幫你記下")
        case .placeChanged:
            return languageSettings.localized(english: "This place’s location has changed", traditionalChinese: "店家位置已更新")
        case .permissionDenied:
            return languageSettings.localized(english: "Location access is off.\nThis visit is unverified.", traditionalChinese: "沒有定位權限，\n這次記成未驗證")
        case .approximateOnly:
            return languageSettings.localized(english: "Precise location is needed\nto verify this visit.", traditionalChinese: "需要精確位置\n才能驗證這次造訪")
        case .tooFar(let meters):
            return languageSettings.localized(english: "You are about \(meters) m away", traditionalChinese: "你好像離這裡還有 \(meters) m")
        case .downgradedUnverified:
            return languageSettings.localized(english: "This visit is unverified", traditionalChinese: "這次記成未驗證")
        case .duplicate:
            if store.latestVisit(for: place.id)?.verification == .unverified {
                return languageSettings.localized(english: "This visit is unverified", traditionalChinese: "這次記成未驗證")
            }
            return languageSettings.localized(english: "Visit verified, stamp added", traditionalChinese: "到了，已蓋章")
        }
    }

    private var subtitle: String? {
        switch situation {
        case .locationFailed: languageSettings.localized(english: "Try verifying again when you arrive.", traditionalChinese: "到現場可再試一次驗證。")
        case .placeChanged: languageSettings.localized(english: "No visit was recorded. Check the location again.", traditionalChinese: "這次尚未記錄，請重新確認位置。")
        default: nil
        }
    }

    private var stampSize: CGFloat {
        switch situation {
        case .tooFar: 168
        case .verified: 168
        default: 150
        }
    }

    @ViewBuilder
    private var stamp: some View {
        switch situation {
        case .verified:
            SaveInkStampMark(
                kind: .verified,
                name: place.stampName,
                date: SaveInkClock.stampDate(store.currentDate),
                seed: 4
            )
        case .tooFar:
            SaveInkStampMark(kind: .notYet, seed: 8)
        default:
            SaveInkStampMark(
                kind: .unverified,
                name: place.stampName,
                date: SaveInkClock.stampDate(store.currentDate),
                seed: 5
            )
        }
    }

    private var showsComment: Bool {
        switch situation {
        case .locationFailed, .permissionDenied, .approximateOnly, .downgradedUnverified:
            return true
        case .verified, .tooFar, .duplicate, .placeChanged:
            return false
        }
    }

    private var commentBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(languageSettings.localized(english: "Add a comment (optional)", traditionalChinese: "留一句評論（選填）"))
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
                Spacer()
                if situation != .verified {
                    SaveInkBadge(text: languageSettings.localized(english: "△ Unverified visit", traditionalChinese: "△ 未驗證造訪"), verified: false)
                }
            }
            SaveInkLineField(
                placeholder: languageSettings.localized(english: "What was your visit like?", traditionalChinese: "小籠包皮很薄，排隊 15 分鐘…"),
                text: $store.draftComment,
                identifier: "ink.checkin.comment",
                minHeight: 72
            )
        }
        .padding(16)
        .background(
            SaveInkRoughRoundedRect(cornerRadius: 18, seed: 21)
                .stroke(SaveInkPalette.ink, lineWidth: 2)
        )
    }

    private var sentiment: some View {
        HStack(spacing: 8) {
            ForEach(SaveInkSentiment.allCases, id: \.self) { item in
                Button(item.title(language: languageSettings.language)) { store.draftSentiment = item }
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(
                        Capsule().stroke(SaveInkPalette.ink, lineWidth: store.draftSentiment == item ? 2.4 : 1.6)
                    )
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch situation {
        case .placeChanged:
            SaveInkOutlineButton(title: languageSettings.localized(english: "Check location again", traditionalChinese: "重新確認位置"), identifier: "ink.checkin.retry", compact: true) {
                Task { await store.retryCheckIn() }
            }
            SaveInkOutlineButton(title: languageSettings.localized(english: "Try later", traditionalChinese: "稍後再試"), identifier: "ink.checkin.cancel", compact: true) {
                store.cancelSheet()
            }
        case .verified:
            SaveInkOutlineButton(title: languageSettings.localized(english: "View stamp", traditionalChinese: "看這次的章"), identifier: "ink.checkin.stamp", compact: true) {
                store.beginArrival()
            }
            SaveInkOutlineButton(title: languageSettings.localized(english: "Add a comment", traditionalChinese: "留一句評論"), identifier: "ink.checkin.commentButton", compact: true) {
                store.beginReview()
            }
            SaveInkOutlineButton(title: languageSettings.localized(english: "Done", traditionalChinese: "完成"), identifier: "ink.checkin.done", compact: true) {
                store.commitDraft()
            }
        case .locationFailed, .downgradedUnverified:
            if place.shopLatitude != nil, place.shopLongitude != nil {
                SaveInkOutlineButton(title: languageSettings.localized(english: "Retry", traditionalChinese: "重試"), identifier: "ink.checkin.retry", compact: true) {
                    Task { await store.retryCheckIn() }
                }
            }
            SaveInkOutlineButton(title: languageSettings.localized(english: "Done", traditionalChinese: "完成"), identifier: "ink.checkin.done", compact: true) {
                store.commitDraft()
            }
        case .permissionDenied:
            SaveInkOutlineButton(title: languageSettings.localized(english: "Location settings", traditionalChinese: "開啟定位"), identifier: "ink.checkin.settings", compact: true) {
                store.openSettings()
            }
            SaveInkOutlineButton(title: languageSettings.localized(english: "Done", traditionalChinese: "完成"), identifier: "ink.checkin.done", compact: true) {
                store.commitDraft()
            }
        case .approximateOnly, .duplicate:
            SaveInkOutlineButton(title: languageSettings.localized(english: "Done", traditionalChinese: "完成"), identifier: "ink.checkin.done", compact: true) {
                store.commitDraft()
            }
        case .tooFar:
            SaveInkOutlineButton(title: languageSettings.localized(english: "Record unverified visit", traditionalChinese: "還是記下"), identifier: "ink.checkin.saveAnyway", compact: true) {
                store.saveAnyway()
            }
            SaveInkOutlineButton(title: languageSettings.localized(english: "Cancel", traditionalChinese: "取消"), identifier: "ink.checkin.cancel", compact: true) {
                store.cancelSheet()
            }
        }
    }
}

struct SaveInkStampGrid: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var store: SaveInkNotebookStore

    var body: some View {
        let stamps = store.stampedPlaceIDs()
        let empties = max(0, 6 - stamps.count)
        let cells = stamps.count + empties
        VStack(spacing: 14) {
            ForEach(Array(stride(from: 0, to: cells, by: 3)), id: \.self) { start in
                HStack(spacing: 14) {
                    ForEach(start..<min(start + 3, cells), id: \.self) { index in
                        stamp(at: index, stamps: stamps)
                            .frame(maxWidth: .infinity)
                            .frame(height: 112)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stamp(at index: Int, stamps: [String]) -> some View {
        if index < stamps.count {
            let id = stamps[index]
            if let place = store.place(id), let visit = store.latestVisit(for: id) {
                SaveInkStampMark(
                    kind: visit.verification == .verified ? .verified : .unverified,
                    name: place.stampName,
                    date: SaveInkClock.stampDate(visit.visitedAt),
                    seed: SaveInkSeed.of(id)
                )
            }
        } else {
            SaveInkStampMark(kind: .empty, seed: 80 &+ index)
        }
    }
}

struct SaveInkPassportScreen: View {
    @State private var showsLanguage = false
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var store: SaveInkNotebookStore

    var body: some View {
        ZStack {
            SaveInkPalette.paper.ignoresSafeArea()
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    SaveInkBackButton(action: store.goBack)
                    Text(languageSettings.localized(english: "My Passport", traditionalChinese: "我的護照"))
                        .font(SaveInkType.subpageTitle)
                        .foregroundStyle(SaveInkPalette.ink)
                }
                Button { showsLanguage = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                        Text("Language / 語言")
                        Spacer(minLength: 8)
                        Text(languageSettings.preference.displayName(language: languageSettings.language))
                            .foregroundStyle(SaveInkPalette.inkSub)
                        Image(systemName: "chevron.right")
                    }
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.ink)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ink.passport.language")
                if store.includesSampleCatalog {
                HStack(spacing: 12) {
                    SaveInkRoughCircle(seed: 3, amplitude: 0.4)
                        .stroke(SaveInkPalette.ink, lineWidth: 2)
                        .frame(width: 54, height: 54)
                        .overlay(Text("小").font(SaveInkType.body).foregroundStyle(SaveInkPalette.ink))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("小米")
                            .font(SaveInkType.sheetTitle)
                        Text(languageSettings.localized(english: "Taipei · \(store.stampedPlaceIDs().count) stamps · \(store.totalVisits()) visits", traditionalChinese: "台北・已蓋 \(store.stampedPlaceIDs().count) 個章・去過 \(store.totalVisits()) 次"))
                            .font(SaveInkType.aux)
                            .monospacedDigit()
                            .foregroundStyle(SaveInkPalette.inkSub)
                    }
                }
                } else {
                    SaveInkPassportIdentity()
                }
                savedPlaces
                Text(languageSettings.localized(english: "Stamps", traditionalChinese: "印章"))
                    .font(SaveInkType.body)
                SaveInkStampGrid(store: store)
                Text(languageSettings.localized(english: "Visited places", traditionalChinese: "去過的地方"))
                    .font(SaveInkType.body)
                VStack(spacing: 0) {
                    ForEach(ledger, id: \.placeID) { row in
                        HStack {
                            Text(row.mark + " " + row.title)
                                .font(SaveInkType.body)
                            Spacer()
                            Text(row.trailing)
                                .font(SaveInkType.aux)
                                .monospacedDigit()
                                .foregroundStyle(SaveInkPalette.inkSub)
                        }
                        .padding(.vertical, 12)
                        Divider().background(SaveInkPalette.ink.opacity(0.25))
                    }
                }
                .padding(16)
                .overlay(
                    SaveInkRoughRoundedRect(cornerRadius: 18, seed: 33)
                        .stroke(SaveInkPalette.ink, lineWidth: 2)
                )
            }
            .padding(24)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.passport")
        .sheet(isPresented: $showsLanguage) { LanguageSettingsSheet() }
    }

    private var savedPlaces: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(languageSettings.localized(english: "Saved places", traditionalChinese: "已存地點"))
                .font(SaveInkType.body)
            if store.homePlaces().isEmpty {
                Text(languageSettings.localized(english: "No saved places to show yet", traditionalChinese: "目前沒有可顯示的已存地點"))
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
            }
            ForEach(store.homePlaces()) { place in
                Button { store.openPlace(place.id) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name).font(SaveInkType.body)
                            Text(place.street).font(SaveInkType.aux).foregroundStyle(SaveInkPalette.inkSub)
                        }
                        Spacer(minLength: 8)
                        Text(savedState(place))
                            .font(SaveInkType.aux)
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(SaveInkPalette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ink.passport.place.\(place.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.passport.savedPlaces")
    }

    private func savedState(_ place: SaveInkPlace) -> String {
        switch store.homeBadge(for: place) {
        case .saved: languageSettings.localized(english: "Saved", traditionalChinese: "已收藏")
        case .visited: languageSettings.localized(english: "Visited", traditionalChinese: "去過")
        case .unverified: languageSettings.localized(english: "Unverified visit", traditionalChinese: "未驗證造訪")
        }
    }

    private var ledger: [(placeID: String, mark: String, title: String, trailing: String)] {
        store.stampedPlaceIDs().compactMap { id in
            guard let place = store.place(id) else { return nil }
            let rows = store.visits.filter { $0.placeID == id }
            let verified = rows.contains { $0.verification == .verified }
            let date = rows.map(\.visitedAt).max().map(SaveInkClock.shortDate) ?? ""
            let title = verified ? "\(place.name)・\(place.street)" : languageSettings.localized(english: "\(place.name) · Unverified", traditionalChinese: "\(place.name)・未驗證")
            return (
                placeID: id,
                mark: verified ? "✓" : "△",
                title: title,
                trailing: languageSettings.localized(english: "\(rows.count) visits · \(date)", traditionalChinese: "\(rows.count) 次・\(date)")
            )
        }
    }
}

private struct SaveInkPassportIdentity: View {
    @ObservedObject private var auth = PrivyAuthService.shared

    var body: some View {
        SaveInkPassportAccountIdentity(owner: auth.currentUserId)
            .id(auth.sessionGeneration)
    }
}

private struct SaveInkPassportAccountIdentity: View {
    let owner: String?
    @StateObject private var model = ProfileViewModel()
    @Environment(\.appLanguageSettings) private var languageSettings

    private var profile: UserProfile? {
        guard let owner, model.identityOwnerID == owner else { return nil }
        return model.profile
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let data = model.localAvatarData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image("SavvyLogo").resizable().scaledToFit()
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.displayName ?? languageSettings.localized(english: "Your account", traditionalChinese: "你的帳號"))
                    .font(SaveInkType.sheetTitle)
                    .accessibilityIdentifier("ink.passport.accountName")
                if let email = profile?.email {
                    Text(email).font(SaveInkType.aux).textSelection(.enabled)
                }
                if model.isLoading { ProgressView() }
                if model.errorMessage != nil || (!model.isLoading && profile == nil) {
                    Text(languageSettings.localized(english: "Account details are unavailable. Your saved places are unchanged.", traditionalChinese: "暫時無法載入帳號資料，你的收藏不受影響。"))
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.inkSub)
                    Button(languageSettings.localized(english: "Retry", traditionalChinese: "重試")) {
                        Task { await model.loadPassportIdentity() }
                    }
                    .accessibilityIdentifier("ink.passport.accountRetry")
                }
            }
        }
        .foregroundStyle(SaveInkPalette.ink)
        .task(id: owner) { await model.loadPassportIdentity() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.passport.account")
    }
}

struct SaveInkPlaceScreen: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var store: SaveInkNotebookStore
    @Environment(\.saveInkScreenshot) private var saveInkScreenshot
    var placeID: String

    private var showsLiveMap: Bool {
        store.usesLivePlaces && !saveInkScreenshot
    }

    var body: some View {
        let place = store.place(placeID)
        ZStack {
            SaveInkPalette.paper.ignoresSafeArea()
            if showsLiveMap {
                VStack(spacing: 0) {
                    heading(place)
                        .padding(.horizontal, 24)
                        .padding(.top, 18)
                    ScrollView {
                        liveDetails(place)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    arrive
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 44)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    heading(place)
                    if let place {
                        SaveInkWalkMap(label: walkLabel(place))
                        facts(place)
                    }
                    Spacer()
                    arrive
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.place")
    }

    @ViewBuilder
    private var arrive: some View {
        let place = store.place(placeID)
        if place?.shopLatitude != nil, place?.shopLongitude != nil {
            SaveInkArriveButton {
                Task { await store.checkIn(placeID: placeID) }
            }
        } else if place != nil {
            SaveInkOutlineButton(title: languageSettings.localized(english: "Record visit (unverified)", traditionalChinese: "記錄到訪（未驗證）"), identifier: "ink.place.arrived.unverified") {
                store.recordUnverifiedVisit(placeID: placeID)
            }
        }
    }

    private func heading(_ place: SaveInkPlace?) -> some View {
        HStack(spacing: 12) {
            SaveInkBackButton(action: store.goBack)
            Text(place.map { "\($0.name)・\($0.street)" } ?? "")
                .font(SaveInkType.subpageTitle)
                .foregroundStyle(SaveInkPalette.ink)
                .lineLimit(1)
        }
    }

    /// Map, Apple Maps, and the note scroll. The title and「我到了」stay on screen.
    private func liveDetails(_ place: SaveInkPlace?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let place {
                SaveInkLiveMap(
                    places: [place],
                    userCoordinate: store.userCoordinate,
                    focusPlaceID: place.id,
                    showsRoute: true,
                    onSelect: { _ in }
                )
                if SaveInkAppleMaps.canOpen(place) {
                    SaveInkOutlineButton(
                        title: languageSettings.localized(english: "Open in Apple Maps", traditionalChinese: "用 Apple 地圖打開"),
                        identifier: "ink.place.openMaps",
                        compact: true
                    ) {
                        SaveInkAppleMaps.open(place)
                    }
                }
                facts(place)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func facts(_ place: SaveInkPlace) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !store.includesSampleCatalog, store.homeBadge(for: place) == .unverified {
                SaveInkBadge(text: languageSettings.localized(english: "△ Unverified visit", traditionalChinese: "△ 未驗證造訪"), verified: false)
            }
            HStack(spacing: 10) {
                stat(languageSettings.localized(english: "\(store.includesSampleCatalog ? store.verifiedCount(for: place.id) : store.visitCount(for: place.id)) visits", traditionalChinese: "\(store.includesSampleCatalog ? store.verifiedCount(for: place.id) : store.visitCount(for: place.id)) 次"), languageSettings.localized(english: "Your visits", traditionalChinese: "你去過"))
                stat(languageSettings.localized(english: "\(place.friendUsualCount) friends", traditionalChinese: "\(place.friendUsualCount) 人"), languageSettings.localized(english: "Friends visit", traditionalChinese: "朋友常去"))
                stat(lastDate(place), languageSettings.localized(english: "Last stamp", traditionalChinese: "上次蓋章"))
            }
            Text(SaveInkSystemCopy.text(store.detailNote(for: place), language: languageSettings.language, isUserContent: place.detailNoteIsUserContent))
                .font(SaveInkType.body)
                .foregroundStyle(SaveInkPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let title = place.videoTitle {
                Text(languageSettings.localized(english: "Source video", traditionalChinese: "來源影片"))
                    .font(SaveInkType.body)
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SaveInkPalette.ink, lineWidth: 1.6)
                        .frame(width: 54, height: 54)
                        .overlay(Text("▶").font(SaveInkType.body))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("「\(title)」")
                            .font(SaveInkType.body)
                        Text(place.videoSource ?? "")
                            .font(SaveInkType.aux)
                            .foregroundStyle(SaveInkPalette.inkSub)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    SaveInkRoughRoundedRect(cornerRadius: 18, seed: 15)
                        .stroke(SaveInkPalette.ink, lineWidth: 2)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func walkLabel(_ place: SaveInkPlace) -> String {
        let distance = place.distanceMeters.map(SaveInkClock.distance) ?? ""
        guard let minutes = place.walkMinutes else {
            return distance.isEmpty ? languageSettings.localized(english: "Walking time unavailable", traditionalChinese: "步行時間還沒算") : languageSettings.localized(english: "Walking time unavailable · \(distance)", traditionalChinese: "步行時間還沒算・\(distance)")
        }
        return distance.isEmpty ? languageSettings.localized(english: "\(minutes) min walk", traditionalChinese: "步行 \(minutes) 分") : languageSettings.localized(english: "\(minutes) min walk · \(distance)", traditionalChinese: "步行 \(minutes) 分・\(distance)")
    }

    private func lastDate(_ place: SaveInkPlace) -> String {
        guard let date = store.latestVisit(for: place.id)?.visitedAt else { return "—" }
        return SaveInkClock.shortDate(date)
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(SaveInkType.sheetTitle).monospacedDigit()
            Text(caption).font(SaveInkType.aux).foregroundStyle(SaveInkPalette.inkSub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .overlay(
            SaveInkRoughRoundedRect(cornerRadius: 16, seed: SaveInkSeed.of(caption))
                .stroke(SaveInkPalette.ink, lineWidth: 1.6)
        )
    }
}

struct SaveInkArrivalScreen: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var store: SaveInkNotebookStore
    var placeID: String

    var body: some View {
        let place = store.place(placeID)
        let count = store.verifiedCount(for: placeID)
        ZStack {
            SaveInkPalette.paper.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer(minLength: 12)
                Text(languageSettings.localized(english: "You arrived at \(place?.name ?? "")", traditionalChinese: "你到了\(place?.name ?? "")"))
                    .font(SaveInkType.pageTitle)
                    .multilineTextAlignment(.center)
                Text(store.includesSampleCatalog
                     ? languageSettings.localized(english: "18 m from the door · Visit \(max(count, 1))", traditionalChinese: "距離店門 18 m・第 \(max(count, 1)) 次")
                     : languageSettings.localized(english: "Verified visit · Visit \(max(count, 1))", traditionalChinese: "這次造訪已驗證・第 \(max(count, 1)) 次"))
                    .font(SaveInkType.aux)
                    .monospacedDigit()
                    .foregroundStyle(SaveInkPalette.inkSub)
                SaveInkStampMark(
                    kind: .verified,
                    name: place?.stampName ?? "",
                    date: SaveInkClock.stampDate(store.currentDate),
                    seed: 4
                )
                .frame(width: 210, height: 210)
                VStack(alignment: .leading, spacing: 8) {
                    Text(languageSettings.localized(english: "Add a comment (optional)", traditionalChinese: "留一句評論（選填）"))
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.inkSub)
                    SaveInkLineField(
                        placeholder: languageSettings.localized(english: "What was your visit like?", traditionalChinese: "小籠包皮很薄，排隊 15 分鐘…"),
                        text: $store.draftComment,
                        identifier: "ink.arrival.comment",
                        minHeight: 72
                    )
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    SaveInkRoughRoundedRect(cornerRadius: 18, seed: 27)
                        .stroke(SaveInkPalette.ink, lineWidth: 2)
                )
                HStack(spacing: 8) {
                    ForEach(SaveInkSentiment.allCases, id: \.self) { item in
                        Button(item.title(language: languageSettings.language)) { store.draftSentiment = item }
                            .font(SaveInkType.aux)
                            .foregroundStyle(SaveInkPalette.ink)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(Capsule().stroke(SaveInkPalette.ink, lineWidth: 1.6))
                    }
                    Spacer(minLength: 0)
                }
                Spacer()
                SaveInkOutlineButton(title: languageSettings.localized(english: "Done, back to Home", traditionalChinese: "完成，回首頁"), identifier: "ink.arrival.done") {
                    store.commitDraft()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 44)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.arrival")
    }
}

struct SaveInkFriendsScreen: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var store: SaveInkNotebookStore

    var body: some View {
        let cards = store.friendCards()
        ZStack {
            SaveInkPalette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    SaveInkBackButton(identifier: "ink.friends.back", action: store.goBack)
                    Text(languageSettings.localized(english: "Friends’ places", traditionalChinese: "朋友推薦"))
                        .font(SaveInkType.subpageTitle)
                }
                Text(languageSettings.localized(english: "Places your friends have visited", traditionalChinese: "朋友去過的地方"))
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
                    .padding(.leading, 58)
                if cards.isEmpty {
                    emptyFriends
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(cards) { card in
                                friendCard(card)
                            }
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                    .scrollContentBackground(.hidden)
                    .background(SaveInkPalette.paper)
                    .accessibilityIdentifier("ink.friends.list")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.friends")
    }

    private var emptyFriends: some View {
        VStack(spacing: 16) {
            SaveInkStampMark(kind: .empty, seed: 14)
                .frame(width: 120, height: 120)
                .padding(.top, 48)
            Text(languageSettings.localized(english: "No visits shared yet", traditionalChinese: "朋友還沒有分享造訪"))
                .font(SaveInkType.subpageTitle)
                .foregroundStyle(SaveInkPalette.ink)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("ink.friends.empty")
            Text(languageSettings.localized(english: "Your friends’ public visits will appear here.", traditionalChinese: "朋友把造訪設成公開後，就會出現在這裡"))
                .font(SaveInkType.body)
                .foregroundStyle(SaveInkPalette.inkSub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.friends.empty")
    }

    private func friendCard(_ card: SaveInkFriendCard) -> some View {
        let unverified = card.segment == .unverified
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                SaveInkRoughCircle(seed: SaveInkSeed.of(card.authorName), amplitude: 0.35)
                    .stroke(SaveInkPalette.ink, lineWidth: 1.6)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(card.authorName.prefix(1)))
                            .font(SaveInkType.minimum)
                            .foregroundStyle(SaveInkPalette.ink)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.authorName).font(SaveInkType.body)
                        SaveInkBadge(
                            text: unverified ? languageSettings.localized(english: "△ Unverified visit", traditionalChinese: "△ 未驗證造訪") : languageSettings.localized(english: "✓ Verified", traditionalChinese: "✓ 已驗證"),
                            verified: !unverified
                        )
                    }
                    Text(card.subtitle(now: store.currentDate, language: languageSettings.language))
                        .font(SaveInkType.aux)
                        .monospacedDigit()
                        .foregroundStyle(SaveInkPalette.inkSub)
                }
                Spacer(minLength: 8)
                SaveInkStampMark(
                    kind: unverified ? .miniUnverified : .miniVerified,
                    seed: SaveInkSeed.of(card.id)
                )
            }
            Text("\(card.placeName)・\(card.street)")
                .font(SaveInkType.friendShop)
            HStack(alignment: .top) {
                Text("「\(card.comment)」")
                    .font(SaveInkType.body)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(languageSettings.localized(english: "Sample", traditionalChinese: SaveInkProvisional.commentMark))
                    .font(SaveInkType.minimum)
                    .foregroundStyle(SaveInkPalette.inkSub)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 24)
                    .overlay(
                        Capsule().stroke(
                            SaveInkPalette.inkSub,
                            style: StrokeStyle(lineWidth: 1.2, dash: [3, 3])
                        )
                    )
            }
        }
        .padding(16)
        .background(
            SaveInkRoughRoundedRect(cornerRadius: 18, seed: SaveInkSeed.of(card.id))
                .fill(unverified ? SaveInkPalette.unverifiedFill : SaveInkPalette.card)
        )
        .overlay(
            SaveInkRoughRoundedRect(cornerRadius: 18, seed: SaveInkSeed.of(card.id))
                .stroke(
                    unverified ? SaveInkPalette.unverifiedLine : SaveInkPalette.ink,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: unverified ? [6, 5] : [])
                )
        )
        .accessibilityIdentifier("ink.friends.card.\(card.id)")
    }
}

struct SaveInkReviewScreen: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @ObservedObject var store: SaveInkNotebookStore
    var placeID: String

    var body: some View {
        let place = store.place(placeID)
        let visit = store.latestVisit(for: placeID)
        let verified = visit?.verification != .unverified
        ZStack {
            SaveInkPalette.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        SaveInkBackButton(action: store.goBack)
                        Text(languageSettings.localized(english: "Add a comment", traditionalChinese: "留一句評論"))
                            .font(SaveInkType.subpageTitle)
                    }
                    HStack(alignment: .center, spacing: 12) {
                        SaveInkStampMark(
                            kind: verified ? .verified : .unverified,
                            name: place?.stampName ?? "",
                            date: SaveInkClock.stampDate(visit?.visitedAt ?? store.currentDate),
                            seed: 9
                        )
                        .frame(width: 92, height: 92)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.map { "\($0.name)・\($0.street)" } ?? "")
                                .font(SaveInkType.friendShop)
                            Text(languageSettings.localized(english: "Today’s visit", traditionalChinese: "今天的造訪"))
                                .font(SaveInkType.aux)
                                .foregroundStyle(SaveInkPalette.inkSub)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(languageSettings.localized(english: "Comment (optional)", traditionalChinese: "評論（選填）"))
                            .font(SaveInkType.aux)
                            .foregroundStyle(SaveInkPalette.inkSub)
                        SaveInkLineField(
                            placeholder: languageSettings.localized(english: "Write about your visit…", traditionalChinese: "寫下這次的感想…"),
                            text: $store.draftComment,
                            identifier: "ink.review.comment",
                            minHeight: 96
                        )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .overlay(
                        SaveInkRoughRoundedRect(cornerRadius: 18, seed: 41)
                            .stroke(SaveInkPalette.ink, lineWidth: 2)
                    )
                    Text(languageSettings.localized(english: "Who can see this visit and comment?", traditionalChinese: "這則造訪和評論要給誰看？"))
                        .font(SaveInkType.body)
                    Text(languageSettings.localized(english: "You choose for each visit", traditionalChinese: "每一則都由你自己選"))
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.inkSub)
                    HStack(spacing: 12) {
                        visibilityCard(
                            title: languageSettings.localized(english: "Public", traditionalChinese: "公開"),
                            body: languageSettings.localized(english: "Visible in Friends’ places", traditionalChinese: "朋友會在「朋友推薦」看到"),
                            selected: store.draftVisibility == .public,
                            identifier: "ink.review.public",
                            icon: .person
                        ) { store.draftVisibility = .public }
                        visibilityCard(
                            title: languageSettings.localized(english: "Private", traditionalChinese: "私密"),
                            body: languageSettings.localized(english: "Only you can see it", traditionalChinese: "只有你看得到"),
                            selected: store.draftVisibility == .private,
                            identifier: "ink.review.private",
                            icon: .lock
                        ) { store.draftVisibility = .private }
                    }
                    Text(languageSettings.localized(english: "ⓘ Private visits and comments stay out of Friends’ places and the visit counts your friends see.", traditionalChinese: "ⓘ 私密的造訪和評論不會出現在朋友推薦頁，也不算進朋友看到的「去過 N 次」。"))
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.inkSub)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            SaveInkRoughRoundedRect(cornerRadius: 16, seed: 52)
                                .stroke(
                                    SaveInkPalette.ink,
                                    style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])
                                )
                        )
                    SaveInkOutlineButton(title: languageSettings.localized(english: "Done", traditionalChinese: "完成"), identifier: "ink.review.done") {
                        store.commitDraft()
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.review")
    }

    private func visibilityCard(
        title: String,
        body: String,
        selected: Bool,
        identifier: String,
        icon: SaveInkVisibilityIcon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    visibilityIcon(icon)
                    Spacer()
                    ZStack {
                        Circle()
                            .stroke(SaveInkPalette.ink, lineWidth: 1.6)
                            .frame(width: 22, height: 22)
                        if selected {
                            Circle()
                                .fill(SaveInkPalette.ink)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
                Text(title).font(SaveInkType.sheetTitle)
                Text(body)
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(
                SaveInkRoughRoundedRect(cornerRadius: 18, seed: SaveInkSeed.of(identifier))
                    .stroke(SaveInkPalette.ink, lineWidth: selected ? 4 : 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func visibilityIcon(_ icon: SaveInkVisibilityIcon) -> some View {
        Group {
            switch icon {
            case .person:
                SaveInkPersonIcon(lineWidth: 1.5, color: SaveInkPalette.inkSub)
            case .lock:
                SaveInkLockIcon()
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

private enum SaveInkVisibilityIcon {
    case person
    case lock
}

struct SaveInkWelcomeScreen: View {
    @State private var showsLanguage = false
    @Environment(\.appLanguageSettings) private var languageSettings
    var onStart: () -> Void
    var onSignIn: () -> Void

    var body: some View {
        ZStack {
            SaveInkPalette.paper.ignoresSafeArea()
            ViewThatFits(in: .vertical) {
                welcomeContent
                ScrollView { welcomeContent }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ink.welcome")
        .sheet(isPresented: $showsLanguage) { LanguageSettingsSheet() }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Savvy").font(SaveInkType.brand)
                    Spacer()
                    Button { showsLanguage = true } label: {
                        Image(systemName: "globe").font(SaveInkType.body).frame(width: 46, height: 46)
                    }
                    .accessibilityLabel("Language / 語言")
                    .accessibilityIdentifier("ink.welcome.language")
                }
                .padding(.top, 36)
                Text(languageSettings.localized(english: "From places you discover\nto places you visit", traditionalChinese: "把刷到的好店，\n變成真的去過"))
                    .font(SaveInkType.sheetTitle)
                    .fixedSize(horizontal: false, vertical: true)
                step(languageSettings.localized(english: "Save", traditionalChinese: "存"), languageSettings.localized(english: "Save", traditionalChinese: "存"), languageSettings.localized(english: "Paste a Douyin or Xiaohongshu link to find the place", traditionalChinese: "貼上抖音、小紅書連結，自動抓出地點"))
                step(languageSettings.localized(english: "Go", traditionalChinese: "去"), languageSettings.localized(english: "Go", traditionalChinese: "去"), languageSettings.localized(english: "Find places worth visiting nearby", traditionalChinese: "附近值得去的，一張張排給你"))
                step(languageSettings.localized(english: "Stamp", traditionalChinese: "章"), languageSettings.localized(english: "Stamp", traditionalChinese: "蓋章"), languageSettings.localized(english: "Tap “I’m here” when you arrive to add a stamp", traditionalChinese: "到了按「我到了」，蓋一個印章"))
                Text(languageSettings.localized(english: "Home uses your location for distances and walking times and may ask for access. Savvy checks your arrival only when you tap “I’m here”. It does not track you in the background or store your coordinates.", traditionalChinese: "首頁用你的位置算距離和步行時間，可能先問一次定位。只在按「我到了」時確認你在店裡，不會在背景追蹤，也不保存座標。"))
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                SaveInkOutlineButton(title: languageSettings.localized(english: "Get started", traditionalChinese: "開始使用"), identifier: "ink.welcome.start", action: onStart)
                Button(action: onSignIn) {
                    Text(languageSettings.localized(english: "Already have an account? Sign in", traditionalChinese: "已經有帳號？登入"))
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.inkSub)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("ink.welcome.signIn")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
    }

    private func step(_ mark: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(mark)
                .font(SaveInkType.body)
                .frame(width: 54, height: 54)
                .background(
                    SaveInkRoughCircle(seed: SaveInkSeed.of(mark), amplitude: 0.4)
                        .stroke(SaveInkPalette.ink, lineWidth: 2)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(SaveInkType.body)
                Text(body)
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
