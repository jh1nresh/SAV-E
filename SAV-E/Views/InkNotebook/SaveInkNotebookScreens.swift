import SwiftUI

struct SaveInkHomeScreen: View {
    @ObservedObject var store: SaveInkNotebookStore

    private var picks: [SaveInkPlace] {
        let featured = [SaveInkFixture.dingtai, SaveInkFixture.qingtian, SaveInkFixture.chifeng]
        let main = featured.compactMap { id in store.places.first { $0.id == id } }
        let added = store.places.filter { $0.id.hasPrefix("saved-") }
        return main + added
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        friendsEntry
                        ForEach(picks) { place in
                            Button {
                                store.openPlace(place.id)
                            } label: {
                                placeCard(place)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ink.place.\(place.id)")
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                Text("輕點卡片，看地圖怎麼走")
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                SaveInkArriveButton {
                    Task { await store.checkIn(placeID: picks.first?.id ?? SaveInkFixture.dingtai) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SaveInkPalette.paper.ignoresSafeArea())
        .accessibilityIdentifier("ink.home")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("附近值得去的")
                    .font(SaveInkType.pageTitle)
                    .foregroundStyle(SaveInkPalette.ink)
                Text("今天在\(store.city)，挑了 \(picks.count) 個給你")
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                SaveInkCircleButton(label: "人", identifier: "ink.passport.entry", personIcon: true) {
                    store.openPassport()
                }
                SaveInkCircleButton(label: "+", identifier: "ink.save.entry") {
                    store.openSave()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var friendsEntry: some View {
        Button(action: store.openFriends) {
            HStack(spacing: 12) {
                SaveInkPersonIcon()
                    .frame(width: 22, height: 22)
                Text("朋友推薦")
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
    }

    private func placeCard(_ place: SaveInkPlace) -> some View {
        let saved = place.badge == .saved
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(place.name)
                    .font(SaveInkType.shop)
                    .foregroundStyle(SaveInkPalette.ink)
                Spacer(minLength: 8)
                SaveInkBadge(text: saved ? "○ 存了還沒去" : "✓ 去過", verified: !saved)
            }
            Text(place.meta)
                .font(SaveInkType.aux)
                .foregroundStyle(SaveInkPalette.inkSub)
            Text(place.blurb)
                .font(SaveInkType.body)
                .foregroundStyle(SaveInkPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("▣")
                Text(place.sourceLabel)
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
    @ObservedObject var store: SaveInkNotebookStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(SaveInkPalette.ink.opacity(0.35))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
            HStack {
                Text("存一個地點")
                    .font(SaveInkType.sheetTitle)
                    .foregroundStyle(SaveInkPalette.ink)
                Spacer()
                SaveInkCircleButton(label: "×", identifier: "ink.save.close") {
                    store.cancelSheet()
                }
            }
            Text("只收跟地點有關的內容")
                .font(SaveInkType.aux)
                .foregroundStyle(SaveInkPalette.inkSub)
            Text("貼上影片連結")
                .font(SaveInkType.body)
                .foregroundStyle(SaveInkPalette.ink)
            HStack {
                Text(store.saveLink.isEmpty ? "https://短影音連結/v/8f2k…" : store.saveLink)
                    .font(SaveInkType.aux)
                    .foregroundStyle(store.saveLink.isEmpty ? SaveInkPalette.inkSub : SaveInkPalette.ink)
                    .lineLimit(1)
                Spacer()
                Button("貼上") { store.pasteExampleLink() }
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
                        SaveInkBadge(text: "✓ 已辨識", verified: true)
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
            Text("或直接搜店名")
                .font(SaveInkType.body)
                .foregroundStyle(SaveInkPalette.ink)
            SaveInkLineField(
                placeholder: "輸入店名，例如「赤峰街」",
                text: $store.saveQuery,
                identifier: "ink.save.query"
            )
            if let notice = store.saveNotice {
                Text(notice)
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ink.save.notice")
            }
            SaveInkOutlineButton(title: "存起來", identifier: "ink.save.commit") {
                store.commitSave()
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 28)
        .background(sheetBackground)
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
            stamp
                .frame(width: stampSize, height: stampSize)
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
        .accessibilityIdentifier("ink.checkin.\(situation.id)")
    }

    private var title: String {
        switch situation {
        case .verified:
            return "到了，已蓋章"
        case .locationFailed:
            return "定位不到，先幫你記下"
        case .permissionDenied:
            return "沒有定位權限，\n這次記成未驗證"
        case .approximateOnly:
            return "需要精確位置\n才能驗證這次造訪"
        case .tooFar(let meters):
            return "你好像離這裡還有 \(meters) m"
        case .downgradedUnverified:
            return "這次記成未驗證"
        case .duplicate:
            if store.latestVisit(for: place.id)?.verification == .unverified {
                return "這次記成未驗證"
            }
            return "到了，已蓋章"
        }
    }

    private var subtitle: String? {
        switch situation {
        case .locationFailed: "到現場可再試一次驗證。"
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
        case .verified, .tooFar, .duplicate:
            return false
        }
    }

    private var commentBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("留一句評論（選填）")
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
                Spacer()
                if situation != .verified {
                    SaveInkBadge(text: "△ 未驗證造訪", verified: false)
                }
            }
            SaveInkLineField(
                placeholder: "小籠包皮很薄，排隊 15 分鐘…",
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
                Button(item.title) { store.draftSentiment = item }
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
        case .verified:
            SaveInkOutlineButton(title: "看這次的章", identifier: "ink.checkin.stamp", compact: true) {
                store.beginArrival()
            }
            SaveInkOutlineButton(title: "留一句評論", identifier: "ink.checkin.commentButton", compact: true) {
                store.beginReview()
            }
            SaveInkOutlineButton(title: "完成", identifier: "ink.checkin.done", compact: true) {
                store.commitDraft()
            }
        case .locationFailed, .downgradedUnverified:
            SaveInkOutlineButton(title: "重試", identifier: "ink.checkin.retry", compact: true) {
                Task { await store.retryCheckIn() }
            }
            SaveInkOutlineButton(title: "完成", identifier: "ink.checkin.done", compact: true) {
                store.commitDraft()
            }
        case .permissionDenied:
            SaveInkOutlineButton(title: "開啟定位", identifier: "ink.checkin.settings", compact: true) {
                store.openSettings()
            }
            SaveInkOutlineButton(title: "完成", identifier: "ink.checkin.done", compact: true) {
                store.commitDraft()
            }
        case .approximateOnly, .duplicate:
            SaveInkOutlineButton(title: "完成", identifier: "ink.checkin.done", compact: true) {
                store.commitDraft()
            }
        case .tooFar:
            SaveInkOutlineButton(title: "還是記下", identifier: "ink.checkin.saveAnyway", compact: true) {
                store.saveAnyway()
            }
            SaveInkOutlineButton(title: "取消", identifier: "ink.checkin.cancel", compact: true) {
                store.cancelSheet()
            }
        }
    }
}

struct SaveInkStampGrid: View {
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
    @ObservedObject var store: SaveInkNotebookStore

    var body: some View {
        ZStack {
            SaveInkPalette.paper.ignoresSafeArea()
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    SaveInkBackButton(action: store.goBack)
                    Text("我的護照")
                        .font(SaveInkType.subpageTitle)
                        .foregroundStyle(SaveInkPalette.ink)
                }
                HStack(spacing: 12) {
                    SaveInkRoughCircle(seed: 3, amplitude: 0.4)
                        .stroke(SaveInkPalette.ink, lineWidth: 2)
                        .frame(width: 54, height: 54)
                        .overlay(Text("小").font(SaveInkType.body).foregroundStyle(SaveInkPalette.ink))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("小米")
                            .font(SaveInkType.sheetTitle)
                        Text("台北・已蓋 \(store.stampedPlaceIDs().count) 個章・去過 \(store.totalVisits()) 次")
                            .font(SaveInkType.aux)
                            .monospacedDigit()
                            .foregroundStyle(SaveInkPalette.inkSub)
                    }
                }
                Text("印章")
                    .font(SaveInkType.body)
                SaveInkStampGrid(store: store)
                Text("去過的地方")
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
        .accessibilityIdentifier("ink.passport")
    }

    private var ledger: [(placeID: String, mark: String, title: String, trailing: String)] {
        store.stampedPlaceIDs().compactMap { id in
            guard let place = store.place(id) else { return nil }
            let rows = store.visits.filter { $0.placeID == id }
            let verified = rows.contains { $0.verification == .verified }
            let date = rows.map(\.visitedAt).max().map(SaveInkClock.shortDate) ?? ""
            let title = verified ? "\(place.name)・\(place.street)" : "\(place.name)・未驗證"
            return (
                placeID: id,
                mark: verified ? "✓" : "△",
                title: title,
                trailing: "\(rows.count) 次・\(date)"
            )
        }
    }
}

struct SaveInkPlaceScreen: View {
    @ObservedObject var store: SaveInkNotebookStore
    var placeID: String

    var body: some View {
        let place = store.place(placeID)
        ZStack {
            SaveInkPalette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    SaveInkBackButton(action: store.goBack)
                    Text(place.map { "\($0.name)・\($0.street)" } ?? "")
                        .font(SaveInkType.subpageTitle)
                        .foregroundStyle(SaveInkPalette.ink)
                        .lineLimit(1)
                }
                if let place {
                    SaveInkWalkMap(label: walkLabel(place))
                    HStack(spacing: 10) {
                        stat("\(store.verifiedCount(for: place.id)) 次", "你去過")
                        stat("\(place.friendUsualCount) 人", "朋友常去")
                        stat(lastDate(place), "上次蓋章")
                    }
                    Text(place.detailNote)
                        .font(SaveInkType.body)
                        .foregroundStyle(SaveInkPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let title = place.videoTitle {
                        Text("來源影片")
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
                Spacer()
                SaveInkArriveButton {
                    Task { await store.checkIn(placeID: placeID) }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .accessibilityIdentifier("ink.place")
    }

    private func walkLabel(_ place: SaveInkPlace) -> String {
        let minutes = place.walkMinutes ?? 5
        let distance = place.distanceMeters.map(SaveInkClock.distance) ?? ""
        return "步行 \(minutes) 分・\(distance)"
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
    @ObservedObject var store: SaveInkNotebookStore
    var placeID: String

    var body: some View {
        let place = store.place(placeID)
        let count = store.verifiedCount(for: placeID)
        ZStack {
            SaveInkPalette.paper.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer(minLength: 12)
                Text("你到了\(place?.name ?? "")")
                    .font(SaveInkType.pageTitle)
                    .multilineTextAlignment(.center)
                Text("距離店門 18 m・第 \(max(count, 1)) 次")
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
                    Text("留一句評論（選填）")
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.inkSub)
                    SaveInkLineField(
                        placeholder: "小籠包皮很薄，排隊 15 分鐘…",
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
                        Button(item.title) { store.draftSentiment = item }
                            .font(SaveInkType.aux)
                            .foregroundStyle(SaveInkPalette.ink)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(Capsule().stroke(SaveInkPalette.ink, lineWidth: 1.6))
                    }
                    Spacer(minLength: 0)
                }
                Spacer()
                SaveInkOutlineButton(title: "完成，回首頁", identifier: "ink.arrival.done") {
                    store.commitDraft()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 44)
        }
        .accessibilityIdentifier("ink.arrival")
    }
}

struct SaveInkFriendsScreen: View {
    @ObservedObject var store: SaveInkNotebookStore

    var body: some View {
        let cards = store.friendCards()
        ZStack {
            SaveInkPalette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    SaveInkBackButton(identifier: "ink.friends.back", action: store.goBack)
                    Text("朋友推薦")
                        .font(SaveInkType.subpageTitle)
                }
                Text("朋友去過的地方")
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
        .accessibilityIdentifier("ink.friends")
    }

    private var emptyFriends: some View {
        VStack(spacing: 16) {
            SaveInkStampMark(kind: .empty, seed: 14)
                .frame(width: 120, height: 120)
                .padding(.top, 48)
            Text("朋友還沒有分享造訪")
                .font(SaveInkType.subpageTitle)
                .foregroundStyle(SaveInkPalette.ink)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("ink.friends.empty")
            Text("朋友把造訪設成公開後，就會出現在這裡")
                .font(SaveInkType.body)
                .foregroundStyle(SaveInkPalette.inkSub)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                            text: unverified ? "△ 未驗證造訪" : "✓ 已驗證",
                            verified: !unverified
                        )
                    }
                    Text(card.subtitle(now: store.currentDate))
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
                Text(SaveInkProvisional.commentMark)
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
                        Text("留一句評論")
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
                            Text("今天的造訪")
                                .font(SaveInkType.aux)
                                .foregroundStyle(SaveInkPalette.inkSub)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("評論（選填）")
                            .font(SaveInkType.aux)
                            .foregroundStyle(SaveInkPalette.inkSub)
                        SaveInkLineField(
                            placeholder: "寫下這次的感想…",
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
                    Text("這則造訪和評論要給誰看？")
                        .font(SaveInkType.body)
                    Text("每一則都由你自己選")
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.inkSub)
                    HStack(spacing: 12) {
                        visibilityCard(
                            title: "公開",
                            body: "朋友會在「朋友推薦」看到",
                            selected: store.draftVisibility == .public,
                            identifier: "ink.review.public",
                            icon: .person
                        ) { store.draftVisibility = .public }
                        visibilityCard(
                            title: "私密",
                            body: "只有你看得到",
                            selected: store.draftVisibility == .private,
                            identifier: "ink.review.private",
                            icon: .lock
                        ) { store.draftVisibility = .private }
                    }
                    Text("ⓘ 私密的造訪和評論不會出現在朋友推薦頁，也不算進朋友看到的「去過 N 次」。")
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
                    SaveInkOutlineButton(title: "完成", identifier: "ink.review.done") {
                        store.commitDraft()
                    }
                    .padding(.top, 8)
                }
                .padding(24)
            }
        }
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
    var onStart: () -> Void
    var onSignIn: () -> Void

    var body: some View {
        ZStack {
            SaveInkPalette.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Text("Savvy")
                    .font(SaveInkType.brand)
                    .padding(.top, 36)
                Text("把刷到的好店，\n變成真的去過")
                    .font(SaveInkType.sheetTitle)
                    .fixedSize(horizontal: false, vertical: true)
                step("存", "存", "貼上抖音、小紅書連結，自動抓出地點")
                step("去", "去", "附近值得去的，一張張排給你")
                step("章", "蓋章", "到了按「我到了」，蓋一個印章")
                Text("只在你按「我到了」時確認你在店裡，不會在背景追蹤，也不保存你的座標。")
                    .font(SaveInkType.aux)
                    .foregroundStyle(SaveInkPalette.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                SaveInkOutlineButton(title: "開始使用", identifier: "ink.welcome.start", action: onStart)
                Button(action: onSignIn) {
                    Text("已經有帳號？登入")
                        .font(SaveInkType.aux)
                        .foregroundStyle(SaveInkPalette.inkSub)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("ink.welcome.signIn")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("ink.welcome")
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
