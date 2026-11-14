#if !SAVVY_MAIN_APP || (DEBUG && SAVVY_DATE_PLAN_PHONE_PREVIEW)
import SwiftUI

@MainActor
struct DatePlanningPanel: View {
    let store: DatePlanStore
    @Binding var step: Int
    @Binding var startEditor: Bool
    @Binding var selectedPlace: String?
    @State private var sourceFilter = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule().fill(DateTheme.ink.opacity(0.12)).frame(width: 32, height: 4).frame(maxWidth: .infinity)
            if step == 0 { recommendations }
            else if step == 1 { choices }
            else { guide }
        }
    }

    private var recommendations: some View {
        Group {
            HStack {
                Text("從熟人的口袋名單開始").font(.system(size: 21, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                ForEach(Array(["全部", "小安推薦", "我的收藏"].enumerated()), id: \.offset) { index, label in
                    Button { sourceFilter = index } label: {
                        Text(label).font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).frame(minHeight: 44)
                            .foregroundStyle(sourceFilter == index ? DateTheme.ink : DateTheme.muted)
                            .background(sourceFilter == index ? DateTheme.soft : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.places.filter { place in
                        sourceFilter == 0 || (sourceFilter == 1 && place.recommendedBy == .an)
                            || (sourceFilter == 2 && store.savedIDs.contains(place.id))
                    }) { place in
                        HStack(alignment: .center, spacing: 12) {
                            DemoPlaceIcon(place: place)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(place.name).font(.system(size: 16, weight: .semibold))
                                Text(store.savedIDs.contains(place.id) ? "你已收藏 · 示範地點"
                                     : place.recommendedBy == .an ? "小安推薦 · 候選地點" : "約會候選 · 尚未收藏")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(DateTheme.muted)
                                Text(place.note).font(.system(size: 12)).foregroundStyle(DateTheme.muted).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Button { store.toggleCandidate(place.id) } label: {
                                Image(systemName: store.candidateIDs.contains(place.id) ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 25)).foregroundStyle(store.candidateIDs.contains(place.id) ? DateTheme.coral : DateTheme.muted)
                                    .frame(width: 44, height: 48)
                            }.buttonStyle(.plain)
                                .accessibilityLabel("\(store.candidateIDs.contains(place.id) ? "移出" : "加入")候選：\(place.name)")
                                .accessibilityIdentifier("demo.candidate.\(place.id)")
                        }.padding(12).background(DateTheme.soft.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }.scrollIndicators(.hidden).accessibilityIdentifier("demo.recommendations")
            DemoPrimaryButton(title: "一起挑這 \(store.candidateIDs.count) 家", enabled: !store.candidateIDs.isEmpty) {
                transition(to: 1)
            }.accessibilityIdentifier("demo.beginChoosing")
        }
    }

    private var choices: some View {
        Group {
            HStack {
                Text("你們都想去哪裡？").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                DemoPill(text: "\(store.sharedIDs.count) 家交集", tint: DateTheme.coral)
            }
            HStack(spacing: 8) {
                Text("切換操作").font(.system(size: 11)).foregroundStyle(DateTheme.muted)
                ForEach([DemoParticipant.you, .an], id: \.self) { person in
                    Button { store.activeParticipant = person } label: {
                        HStack(spacing: 5) {
                            DemoAvatar(person: person, size: 23)
                            Text(person == .you ? "你" : "小安").font(.system(size: 13, weight: .semibold))
                        }.padding(.horizontal, 9).frame(minHeight: 44)
                            .background(store.activeParticipant == person ? DateTheme.soft : .clear, in: Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier(person == .you ? "demo.person.you" : "demo.person.an")
                }
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.candidateIDs, id: \.self) { id in
                        if let place = store.place(id) {
                            let mutual = store.sharedIDs.contains(id)
                            HStack(spacing: 10) {
                                DemoPlaceIcon(place: place, size: 42)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(place.name).font(.system(size: 16, weight: .semibold))
                                    HStack(spacing: 4) {
                                        ForEach([DemoParticipant.you, .an], id: \.self) { person in
                                            DemoAvatar(person: person, size: 19)
                                                .opacity(store.votes[id]?.contains(person) == true ? 1 : 0.25)
                                        }
                                        Text(mutual ? "都想去" : "等另一位選擇")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(mutual ? DateTheme.coral : DateTheme.muted)
                                    }
                                }
                                Spacer(minLength: 0)
                                Button { store.toggleVote(id, participant: store.activeParticipant) } label: {
                                    Image(systemName: store.votes[id]?.contains(store.activeParticipant) == true ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 27)).frame(width: 44, height: 48)
                                        .foregroundStyle(store.votes[id]?.contains(store.activeParticipant) == true ? DateTheme.coral : DateTheme.muted.opacity(0.4))
                                }.buttonStyle(.plain).accessibilityIdentifier("demo.vote.\(id)")
                                    .accessibilityLabel("\(store.activeParticipant == .you ? "你" : "小安")想去\(place.name)")
                                    .accessibilityValue(store.votes[id]?.contains(store.activeParticipant) == true ? "已選" : "未選")
                            }.padding(12)
                                .background(mutual ? DateTheme.coral.opacity(0.065) : DateTheme.soft.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
            }.scrollIndicators(.hidden).accessibilityIdentifier("demo.choices")
            Text("只有雙方都選的地點，才會放進這次行程。")
                .font(.system(size: 11)).foregroundStyle(DateTheme.muted)
            DemoPrimaryButton(title: "交給 Guide 安排 · \(store.sharedIDs.count) 站", enabled: !store.sharedIDs.isEmpty) {
                if store.generatePlan() { transition(to: 2) }
            }.accessibilityIdentifier("demo.generate")
        }
    }

    @ViewBuilder private var guide: some View {
        if !store.hasPlan {
            VStack(alignment: .leading, spacing: 14) {
                DemoPill(text: "SAV-E Guide", tint: DateTheme.coral)
                Text("先找到你們都想去的地方").font(.title3.bold())
                Text("Guide 會把共同選擇整理成時間線，出發前還能改時間和順序。")
                    .font(.subheadline).foregroundStyle(DateTheme.muted)
                DemoPrimaryButton(title: "回去一起挑") { transition(to: 1) }
            }
        } else {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SAV-E GUIDE").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.4).foregroundStyle(DateTheme.coral)
                    Text("把下午留給你們").font(.system(size: 23, weight: .bold, design: .rounded))
                }
                Spacer()
                Button { startEditor = true } label: {
                    HStack(spacing: 4) {
                        Text(DatePlanStore.clock(store.startsAtMinutes))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }.font(.system(size: 13, weight: .semibold)).padding(.horizontal, 11).frame(minHeight: 44)
                        .background(DateTheme.soft, in: Capsule())
                }.buttonStyle(.plain).disabled(store.started).accessibilityIdentifier("demo.editStart").accessibilityLabel("調整開始時間")
            }
            HStack(spacing: 6) {
                DemoPill(text: "\(store.timeline.count) 站")
                DemoPill(text: "\(DatePlanStore.clock(store.startsAtMinutes))–\(DatePlanStore.clock(store.timeline.last?.departureMinutes ?? store.startsAtMinutes))")
                DemoPill(text: "本地規劃示範")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(store.budget.isComplete
                     ? "兩人 NT$\(store.budget.minimumForTwo)–\(store.budget.maximumForTwo)"
                     : "預算待確認")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityIdentifier("demo.budgetTotal")
                Text("示範預算 · 未含交通與服務費，非真實報價")
                    .font(.system(size: 10)).foregroundStyle(DateTheme.muted)
            }
            if store.isPlanStale {
                Button {
                    _ = store.generatePlan()
                } label: {
                    Label("共同選擇已變更，點此重新安排", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(DateTheme.coral)
                    .background(DateTheme.coral.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .disabled(store.sharedIDs.isEmpty).accessibilityIdentifier("demo.regenerate")
            }
            if store.started { nextStop }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(store.timeline.enumerated()), id: \.element.id) { index, stop in
                        if let place = store.place(stop.placeID) {
                            timelineRow(place: place, stop: stop, index: index)
                        }
                    }
                    Text(store.started ? "出發後時間與順序已鎖定；需要調整時，回到一起挑重新安排。"
                         : "移動時間為示範估算；地圖連線表示順序，非導航路線。")
                        .font(.system(size: 10)).foregroundStyle(DateTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }.scrollIndicators(.hidden).accessibilityIdentifier("demo.timeline")
            if !store.started {
                DemoPrimaryButton(title: "開始照行程走", enabled: !store.isPlanStale) { store.startDate() }
                    .accessibilityIdentifier("demo.startDate")
            }
        }
    }

    @ViewBuilder private var nextStop: some View {
        if store.currentStopIndex < store.timeline.count {
            let stop = store.timeline[store.currentStopIndex]
            if let place = store.place(stop.placeID) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("接下來 · \(DatePlanStore.clock(stop.arrivalMinutes))").font(.system(size: 10, weight: .semibold)).foregroundStyle(DateTheme.muted)
                        Text(place.name).font(.system(size: 16, weight: .bold))
                    }
                    Spacer()
                    Button { store.advanceStop() } label: {
                        Text("下一站").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 13).frame(minHeight: 44)
                            .foregroundStyle(.white).background(DateTheme.ink, in: Capsule())
                    }.buttonStyle(.plain).disabled(store.isPlanStale).accessibilityIdentifier("demo.nextStop")
                }.padding(12).background(DateTheme.soft, in: RoundedRectangle(cornerRadius: 16))
            }
        } else {
            Label("今天的安排走完了", systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(DateTheme.green)
                .accessibilityIdentifier("demo.finished")
        }
    }

    private func timelineRow(place: DemoPlace, stop: DemoStop, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if index > 0 {
                Text("步行約 \(stop.travelMinutes) 分 · 示範估算")
                    .font(.system(size: 10)).foregroundStyle(DateTheme.muted).padding(.leading, 54)
            }
            HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 5) {
                Text(DatePlanStore.clock(stop.arrivalMinutes)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("\(index + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22).background(DateTheme.coral, in: Circle())
                Rectangle().fill(DateTheme.coral.opacity(0.15)).frame(width: 2, height: 40)
            }.frame(width: 42)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(place.emoji).font(.system(size: 25))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name).font(.system(size: 16, weight: .semibold))
                        Text("停留 \(stop.departureMinutes - stop.arrivalMinutes) 分鐘")
                            .font(.system(size: 11)).foregroundStyle(DateTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button("往前移", systemImage: "arrow.up") { store.moveStop(place.id, offset: -1) }.disabled(index == 0)
                        Button("往後移", systemImage: "arrow.down") { store.moveStop(place.id, offset: 1) }
                            .disabled(index == store.timeline.count - 1)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }.disabled(store.started).accessibilityLabel("調整\(place.name)順序").accessibilityIdentifier("demo.order.\(place.id)")
                }
                Text(place.isOutdoor ? "散散步。下雨時，可回去挑室內候選替換。" : place.note)
                    .font(.system(size: 12)).foregroundStyle(DateTheme.muted).lineLimit(2)
                Text("\(DatePlanStore.clock(stop.departureMinutes)) 離開")
                    .font(.system(size: 10)).foregroundStyle(DateTheme.muted)
                Button { selectedPlace = place.id } label: {
                    Label("吃玩・交通・預算", systemImage: "text.book.closed")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(DateTheme.ink)
                    .accessibilityLabel("查看\(place.name)行前卡")
                    .accessibilityIdentifier("demo.brief.\(place.id)")
            }.padding(12).background(DateTheme.soft.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
            }
        }.padding(.bottom, 12)
    }

    private func transition(to next: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) { step = next }
    }
}

@MainActor
struct DemoSavedScreen: View {
    let store: DatePlanStore
    let openPlace: (String) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("你的口袋名單").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("收藏留在這裡，一起挑的候選另外整理。")
                    .font(.subheadline).foregroundStyle(DateTheme.muted)
                ForEach(store.places.filter { store.savedIDs.contains($0.id) }) { place in
                    Button { openPlace(place.id) } label: {
                        HStack(spacing: 12) {
                            DemoPlaceIcon(place: place)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(place.name).font(.headline)
                                Text("已收藏 · 示範地點").font(.caption).foregroundStyle(DateTheme.green)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold())
                        }.frame(maxWidth: .infinity, minHeight: 64).demoCard()
                    }.buttonStyle(.plain).accessibilityIdentifier("demo.saved.\(place.id)")
                }
                Text("\(store.savedIDs.count) 個收藏").font(.caption).foregroundStyle(DateTheme.muted)
                    .accessibilityIdentifier("demo.savedCount")
            }.padding(.horizontal, 4).padding(.top, 24).padding(.bottom, 24)
        }.scrollIndicators(.hidden).frame(maxHeight: .infinity)
    }
}

@MainActor
struct DemoPassportScreen: View {
    let store: DatePlanStore
    let openPlan: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    DemoAvatar(person: .you, size: 68)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("你的 Passport").font(.system(size: 25, weight: .bold, design: .rounded))
                        DemoPill(text: "示範帳號 · 僅本地")
                    }
                }.padding(.top, 24)
                HStack(spacing: 12) {
                    stat("\(store.savedIDs.count)", "收藏")
                    stat(store.hasPlan ? "1" : "0", "共同計畫")
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("這次，把想去變成出發").font(.title3.bold())
                    Text(store.hasPlan ? "週六 · 和小安 · \(store.timeline.count) 站" : "先一起挑幾個地點，Guide 就能幫你們排半天。")
                        .font(.subheadline).foregroundStyle(DateTheme.muted)
                    DemoPrimaryButton(title: store.hasPlan ? "查看這次的時間線" : "打開 Guide") { openPlan() }
                }.demoCard()
                Label("尚未記錄到訪", systemImage: "bookmark")
                    .font(.subheadline).foregroundStyle(DateTheme.muted)
                Text("計畫與收藏不會自動變成到訪紀錄。")
                    .font(.caption).foregroundStyle(DateTheme.muted)
            }.padding(.horizontal, 4).padding(.bottom, 24)
        }.scrollIndicators(.hidden).frame(maxHeight: .infinity)
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(.system(size: 34, weight: .bold, design: .rounded))
            Text(label).font(.subheadline).foregroundStyle(DateTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).demoCard()
    }
}

@MainActor
struct DemoSearchScreen: View {
    let store: DatePlanStore
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.places.filter { query.isEmpty || ($0.name + $0.category + $0.detail).localizedCaseInsensitiveContains(query) }) { place in
                    NavigationLink {
                        DemoPlaceDetail(store: store, place: place)
                    } label: {
                        HStack(spacing: 12) {
                            DemoPlaceIcon(place: place, size: 42)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(place.name).font(.headline)
                                Text(place.category + " · 示範地點").font(.caption).foregroundStyle(DateTheme.muted)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("demo.searchResult.\(place.id)")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜尋地點、咖啡或公園")
            .navigationTitle("搜尋").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { dismiss() }.accessibilityIdentifier("demo.closeSearch")
            } }
        }
    }
}

@MainActor
struct DemoPlaceDetail: View {
    let store: DatePlanStore
    let place: DemoPlace
    @State private var confirmSave = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                DemoPlaceIcon(place: place, size: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(place.name).font(.title2.bold())
                    DemoPill(text: store.savedIDs.contains(place.id) ? "已收藏 · 示範" : "候選地點 · 示範",
                             tint: store.savedIDs.contains(place.id) ? DateTheme.green : DateTheme.coral)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("關閉行前卡")
                    .accessibilityIdentifier("demo.closeBrief")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("示範內容，非查證店家資料。店名、座標與價格均為本地測試資料。")
                        .font(.caption).foregroundStyle(DateTheme.muted)
                    if let brief = DemoGuideBrief.fixture(place.id) {
                        Text(brief.purpose).font(.headline)
                        info("吃什麼・玩什麼", symbol: "fork.knife", text: brief.foodOrActivity)
                        info("怎麼抵達", symbol: "figure.walk", text: arrivalContext + "\n" + brief.arrival)
                        info("時間提醒", symbol: "clock", text: brief.timing)
                        info("示範預算", symbol: "creditcard", text: brief.perPersonBudget.map {
                            "NT$\($0.lowerBound)–\($0.upperBound)／人；兩人 NT$\($0.lowerBound * 2)–\($0.upperBound * 2)。未含交通與服務費，實際價格待確認。"
                        } ?? "價格待確認，尚未計入總預算。")
                        info("如果不順利", symbol: "arrow.triangle.branch", text: brief.backup)
                    } else {
                        Text("吃玩、交通、時間與預算尚待補齊。")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden).accessibilityIdentifier("demo.placeInfo")
            DemoPrimaryButton(title: store.candidateIDs.contains(place.id) ? "移出這次候選" : "加入這次候選") {
                store.toggleCandidate(place.id)
            }
            if !store.savedIDs.contains(place.id) {
                Button("收藏這個示範地點") { confirmSave = true }
                    .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("demo.savePlace")
            }
        }.padding(24)
            .confirmationDialog("將這個地點加入本地示範收藏？", isPresented: $confirmSave, titleVisibility: .visible) {
                Button("確認收藏") { store.setSaved(place.id, true) }
                Button("取消", role: .cancel) {}
            }
    }

    private func info(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 14)).foregroundStyle(DateTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var arrivalContext: String {
        guard let index = store.timeline.firstIndex(where: { $0.placeID == place.id }) else {
            return "尚未加入這次時間線；確定順序後再安排抵達方式。"
        }
        guard index > 0 else { return "這次行程第一站 · 自行前往集合。" }
        let previous = store.timeline[index - 1]
        let name = store.place(previous.placeID)?.name ?? "上一站"
        return "由\(name)出發 · 步行約 \(store.timeline[index].travelMinutes) 分（示範估算）。"
    }
}

#endif
