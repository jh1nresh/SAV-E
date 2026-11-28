#if DEBUG && SAVVY_MAIN_APP && SAVVY_DATE_PLAN_PHONE_PREVIEW
import SwiftUI

@MainActor
struct LivePlanningLibraryView: View {
    let places: [Place]
    let isLoading: Bool
    let onOpen: (Place) -> Void
    let onCapture: () -> Void
    let reviewCandidates: [PlaceReviewCandidate]
    let reviewBatchIDs: [UUID]?
    let onOpenReview: (UUID) -> Void
    let onClearReviewBatch: () -> Void
    let sharedQuery: Binding<String>?
    let galleryLights: Binding<Bool>
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var query = ""
    @State private var regionID: String?
    @State private var category: PlaceCategory?
    @State private var reviewsExpanded = false

    init(places: [Place], isLoading: Bool, onOpen: @escaping (Place) -> Void,
         onCapture: @escaping () -> Void, reviewCandidates: [PlaceReviewCandidate] = [],
         reviewBatchIDs: [UUID]? = nil, onOpenReview: @escaping (UUID) -> Void = { _ in },
         onClearReviewBatch: @escaping () -> Void = {}, sharedQuery: Binding<String>? = nil, galleryLights: Binding<Bool> = .constant(true)) {
        self.places = places
        self.isLoading = isLoading
        self.onOpen = onOpen
        self.onCapture = onCapture
        self.reviewCandidates = reviewCandidates
        self.reviewBatchIDs = reviewBatchIDs
        self.onOpenReview = onOpenReview
        self.onClearReviewBatch = onClearReviewBatch
        self.sharedQuery = sharedQuery
        self.galleryLights = galleryLights
    }

    private var searchText: String { sharedQuery?.wrappedValue ?? query }

    private func clearSearch() {
        if let sharedQuery { sharedQuery.wrappedValue = "" }
        else { query = "" }
    }

    private var review: LiveLibraryReviewProjection {
        LiveLibraryReviewProjection(candidates: reviewCandidates, batchIDs: reviewBatchIDs, query: searchText)
    }

    var body: some View {
        let collection = LiveLibraryCollection(places: places, query: searchText, regionID: regionID, category: category)
        let pending = review
        VStack(spacing: 12) {
            if sharedQuery == nil {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(DateTheme.muted)
                    TextField(copy("Search name or address", "搜尋名稱或地址"), text: $query,
                              prompt: Text(copy("Search name or address", "搜尋名稱或地址"))
                        .foregroundColor(DateTheme.muted))
                        .font(.system(.body, design: .rounded))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.search).accessibilityIdentifier("live.library.search")
                        .savvyInputFeedback()
                    if !query.isEmpty {
                        Button(action: clearSearch) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(DateTheme.muted)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .savvyPressFeedback().accessibilityLabel(copy("Clear search", "清除搜尋"))
                    }
                }
                .padding(.leading, 16).padding(.trailing, 4).frame(minHeight: 52)
                .modifier(LiveLibraryCard())
            }

            VStack(alignment: .leading, spacing: 12) {
                if reviewBatchIDs != nil {
                    ScrollView { reviewSection(pending) }.frame(maxHeight: 180)
                } else if !pending.eligible.isEmpty {
                    Button { reviewsExpanded.toggle() } label: {
                        HStack(spacing: 8) {
                            Text(copy("To review · \(pending.eligible.count)", "待確認 · \(pending.eligible.count)"))
                            Spacer()
                            Image(systemName: reviewsExpanded ? "chevron.down" : "chevron.right")
                                .accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .savvyPressFeedback()
                    .accessibilityValue(reviewsExpanded ? copy("Expanded", "已展開") : copy("Collapsed", "已收合"))
                    .accessibilityIdentifier("live.library.review.disclosure")
                    if reviewsExpanded { ScrollView { reviewSection(pending) }.frame(maxHeight: 180) }
                }
                collectionHeader(collection)
                if isLoading {
                    ProgressView(copy("Loading saved places…", "載入收藏…"))
                        .font(.system(.subheadline, design: .rounded)).padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                }
                if collection.matches.isEmpty && !isLoading {
                    emptyState
                } else {
                    gallery(collection)
                }
            }.padding(.bottom, 8)

            if sharedQuery == nil {
                Button(action: onCapture) {
                    Label(dynamicTypeSize.isAccessibilitySize ? copy("Add", "新增") : copy("Add from a post or screenshot", "從貼文或截圖新增"),
                          systemImage: "plus")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 52)
                        .padding(.horizontal, 16).padding(.vertical, 4)
                        .foregroundStyle(DateTheme.actionInk).background(DateTheme.action, in: Capsule())
                }
                .savvyPressFeedback(prominent: true)
                .accessibilityLabel(copy("Add from a post or screenshot", "從貼文或截圖新增"))
                .accessibilityIdentifier("live.library.add")
            }
        }
        .foregroundStyle(DateTheme.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live.library")
    }

    private func gallery(_ collection: LiveLibraryCollection) -> some View {
        let entries = Dictionary(collection.matches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = collection.matches.map { entry -> SavedGalleryItem in
            let source = LiveSavedPlaceCoverSource.resolve(entry.place)
            let bundled: LiveBundledBusinessPhoto?
            if case .business(.bundled(let local)) = source { bundled = local }
            else { bundled = nil }
            return SavedGalleryItem(
                id: entry.id,
                title: entry.place.name.isEmpty ? copy("Untitled saved place", "未命名收藏") : entry.place.name,
                location: entry.location.isEmpty ? copy("Location unavailable", "暫無位置資訊") : entry.location,
                symbol: entry.place.category.iconName, photoURL: source.url,
                aspectRatio: bundled?.aspectRatio ?? 1.08,
                photoCredit: bundled?.credit, photoSource: bundled?.original,
                markedVisited: entry.place.status == .visited,
                photoKindLabel: source.isSavedSource ? copy("Saved source image", "收藏來源圖片") : nil)
        }
        return SavedGalleryWall(items: items,
            palette: SavedGalleryPalette(canvas: SaveBrandUI.canvas, surface: SaveBrandUI.surface,
                                         ink: SaveBrandUI.ink, muted: SaveBrandUI.muted,
                                         accent: SaveBrandUI.accent, pink: SaveBrandUI.soft),
            chinese: copy("en", "zh") == "zh", lightsOn: galleryLights,
            onOpen: { id in
                // Resolve against the current account's collection before opening.
                if let entry = entries[id] { onOpen(entry.place) }
            }, photo: { item in
                if let entry = entries[item.id] { LiveSavedPlaceCover(place: entry.place) }
            })
    }

    private func collectionHeader(_ collection: LiveLibraryCollection) -> some View {
        let filtering = regionID != nil || category != nil
        return HStack(spacing: 8) {
            Text(copy("Everything", "全部收藏"))
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if !collection.regions.isEmpty || !collection.categories.isEmpty {
                Menu {
                    Picker(copy("Region", "地區"), selection: $regionID) {
                        Text(copy("All regions", "所有地區")).tag(nil as String?)
                        ForEach(collection.regions) { region in
                            Text(region.name).tag(Optional(region.id))
                        }
                    }
                    Picker(copy("Category", "類別"), selection: $category) {
                        Text(copy("All categories", "所有類別")).tag(nil as PlaceCategory?)
                        ForEach(collection.categories, id: \.self) { value in
                            Text(value.displayName(language: language.language)).tag(Optional(value))
                        }
                    }
                    if filtering {
                        Button(copy("Clear filters", "清除篩選"), action: clearFilters)
                    }
                } label: {
                    Image(systemName: filtering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(DateTheme.soft, in: Circle())
                }
                .tint(filtering ? DateTheme.blue : DateTheme.ink)
                .accessibilityLabel(copy("Filter saved places", "篩選收藏"))
                .accessibilityValue(filtering ? copy("Filters active", "已套用篩選") : copy("Showing everything", "顯示全部收藏"))
                .accessibilityIdentifier("live.library.filter")
            }
        }
    }

    private func reviewSection(_ projection: LiveLibraryReviewProjection) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            if reviewBatchIDs != nil {
                Text(copy("To review", "待確認"))
                    .font(.system(.headline, design: .rounded)).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("live.library.review.heading")
                VStack(alignment: .leading, spacing: 4) {
                    Label(copy("This capture · review before saving", "本次線索 · 確認後才會收藏"), systemImage: "magnifyingglass")
                        .font(.system(.subheadline, design: .rounded)).foregroundStyle(DateTheme.muted)
                    Button(copy("Show all to review", "顯示全部待確認")) {
                        reviewsExpanded = true
                        onClearReviewBatch()
                    }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(minHeight: 44).foregroundStyle(DateTheme.blue)
                        .accessibilityIdentifier("live.library.review.showAll")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("live.library.review.batch")
            }
            if projection.matches.isEmpty {
                Text(isLoading ? copy("Loading clues…", "載入線索…") : reviewEmptyCopy(projection.emptyState))
                    .font(.system(.subheadline, design: .rounded)).foregroundStyle(DateTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("live.library.review.empty")
                if projection.emptyState == .noSearchMatches {
                    Button(copy("Clear search", "清除搜尋"), action: clearSearch)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(minHeight: 44).foregroundStyle(DateTheme.blue)
                        .accessibilityIdentifier("live.library.review.clearSearch")
                }
            } else {
                ForEach(projection.matches) { candidate in
                    let id = candidate.id
                    Button { onOpenReview(id) } label: { LiveLibraryReviewRow(candidate: candidate) }
                        .savvyPressFeedback()
                        .accessibilityHint(copy("Open this clue to check it before saving", "打開線索，確認後才會收藏"))
                        .accessibilityIdentifier("live.library.review.\(id.uuidString)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live.library.review")
    }

    private func reviewEmptyCopy(_ state: LiveLibraryReviewProjection.EmptyState?) -> String {
        switch state {
        case .nonePending: copy("No clues waiting for review.", "目前沒有待確認的線索。")
        case .batchReviewed: copy("No clues from this capture are waiting for review.", "這次線索目前沒有待確認項目。")
        case .noSearchMatches: copy("No matching clues. Try another name or address.", "沒有符合的線索，試試其他名稱或地址。")
        case nil: ""
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: places.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(.title2, design: .rounded)).foregroundStyle(DateTheme.muted)
                .accessibilityHidden(true)
            Text(places.isEmpty
                 ? copy("Your collection starts here", "從第一個收藏開始")
                 : copy("No matching saved places", "沒有符合的收藏"))
                .font(.system(.headline, design: .rounded))
            Text(places.isEmpty
                 ? copy("Add a clue from a post or screenshot, then confirm the place.", "從貼文或截圖加入線索，再確認地點。")
                 : copy("Try another name, address or filter.", "試試其他名稱、地址或篩選。"))
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(DateTheme.muted)
            if !searchText.isEmpty || regionID != nil || category != nil {
                Button(copy("Clear filters", "清除篩選")) { clearSearch(); clearFilters() }
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .frame(minHeight: 44).foregroundStyle(DateTheme.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20).modifier(LiveLibraryCard())
    }

    private func clearFilters() {
        regionID = nil
        category = nil
    }

    private func copy(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

/// Read-only projection, shared with focused tests. Saved status filters never enter this path.
@MainActor
struct LiveLibraryReviewProjection {
    enum EmptyState: Equatable { case nonePending, batchReviewed, noSearchMatches }
    let eligible: [PlaceReviewCandidate]
    let matches: [PlaceReviewCandidate]
    let emptyState: EmptyState?

    init(candidates: [PlaceReviewCandidate], batchIDs: [UUID]?, query: String) {
        eligible = candidates.filter(Self.isPending).sorted(by: PlaceReviewCandidate.newestFirst)
        let ids = batchIDs.map { Set($0) }
        let scoped = eligible.filter { ids?.contains($0.id) ?? true }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        matches = scoped.filter {
            text.isEmpty || $0.name.localizedStandardContains(text) || $0.address.localizedStandardContains(text)
        }
        if scoped.isEmpty { emptyState = batchIDs == nil ? .nonePending : .batchReviewed }
        else { emptyState = matches.isEmpty ? .noSearchMatches : nil }
    }

    static func isPending(_ candidate: PlaceReviewCandidate) -> Bool {
        ["review", "needs_more_evidence", "source_only"].contains(candidate.status)
            && candidate.replacementCandidateIDs.isEmpty
    }
}

@MainActor
enum LiveLibraryReviewState: Equatable {
    case analysisPending, sourceClue, possiblePlace, unplaced

    init(_ candidate: PlaceReviewCandidate) {
        if candidate.isUnplacedInbox { self = .unplaced }
        else if candidate.isAnalysisPending { self = .analysisPending }
        else if candidate.status == "source_only" || !candidate.hasSavableLocation { self = .sourceClue }
        else { self = .possiblePlace }
    }

    var symbol: String {
        switch self {
        case .analysisPending: "clock"
        case .sourceClue: "link"
        case .possiblePlace: "mappin.and.ellipse"
        case .unplaced: "tray"
        }
    }

    @MainActor func title(_ language: AppLanguageSettings) -> String {
        switch self {
        case .analysisPending: language.localized(english: "Analysis pending", traditionalChinese: "分析待完成")
        case .sourceClue: language.localized(english: "Source clue · exact place needed", traditionalChinese: "來源線索 · 尚待找出地點")
        case .possiblePlace: language.localized(english: "Possible place · review before saving", traditionalChinese: "可能的地點 · 確認後才會收藏")
        case .unplaced: language.localized(english: "Unplaced · not on your map yet", traditionalChinese: "暫未放入 · 尚未加入你的地圖")
        }
    }
}

@MainActor
private struct LiveLibraryReviewRow: View {
    let candidate: PlaceReviewCandidate
    @Environment(\.appLanguageSettings) private var language
    private var state: LiveLibraryReviewState { LiveLibraryReviewState(candidate) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: state.symbol).font(.system(.title3, design: .rounded))
                .foregroundStyle(DateTheme.blue).frame(width: 44, height: 44)
                .background(DateTheme.soft, in: RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(candidate.name.isEmpty ? language.localized(english: "Untitled clue", traditionalChinese: "未命名線索") : candidate.name)
                    .font(.system(.headline, design: .rounded))
                Text(state.title(language)).font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(DateTheme.blue)
                if !candidate.address.isEmpty {
                    Text(candidate.address).font(.system(.subheadline, design: .rounded)).foregroundStyle(DateTheme.muted)
                }
                if let handle = SaveSourceHandle.resolved(candidate.sourceHandle) {
                    Text(handle).font(.system(.caption, design: .rounded)).foregroundStyle(DateTheme.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            Image(systemName: "chevron.right").font(.system(.caption, weight: .semibold))
                .foregroundStyle(DateTheme.muted).padding(.top, 4).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(16).modifier(LiveLibraryCard()).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct LivePlanningPassportView: View {
    let places: [Place]
    let onOpenLibrary: () -> Void
    let onOpenAccount: () -> Void
    @Environment(\.appLanguageSettings) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(places: [Place], onOpenLibrary: @escaping () -> Void, onOpenAccount: @escaping () -> Void) {
        self.places = places
        self.onOpenLibrary = onOpenLibrary
        self.onOpenAccount = onOpenAccount
    }

    private var visitedCount: Int { places.filter { $0.status == .visited }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "book.closed")
                        .font(.system(.largeTitle, design: .rounded)).foregroundStyle(DateTheme.blue)
                        .accessibilityHidden(true)
                    Text(copy("Your place archive", "你的地點檔案"))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(copy("Saved places, including the ones still on your list.", "已收藏的地方，包含還沒出發的那些。"))
                        .font(.system(.body, design: .rounded)).foregroundStyle(DateTheme.muted)
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 16) { counts }
                    } else {
                        HStack(alignment: .top, spacing: 16) { counts }
                    }
                    Text(copy("Visited counts reflect your saved status. Location is not verified here.",
                              "去過數量依收藏中的標記計算，未在此驗證到訪位置。"))
                        .font(.system(.caption, design: .rounded)).foregroundStyle(DateTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20).modifier(LiveLibraryCard())

                archiveLink(title: copy("Open saved places", "查看收藏"),
                            detail: copy("Browse every place in your collection", "查看你存下的每個地方"),
                            icon: "tray", action: onOpenLibrary)
                    .accessibilityIdentifier("live.passport.library")
                archiveLink(title: copy("Account settings", "帳號設定"),
                            detail: copy("Profile, sign out and account controls", "個人資料、登出與帳號管理"),
                            icon: "person.crop.circle", action: onOpenAccount)
                    .accessibilityIdentifier("live.passport.account")
            }.padding(.vertical, 8)
        }
        .scrollIndicators(.hidden).foregroundStyle(DateTheme.ink)
        .accessibilityIdentifier("live.passport")
    }

    @ViewBuilder private var counts: some View {
        archiveCount(places.count, title: copy("Saved places", "已收藏"))
        archiveCount(visitedCount, title: copy("Marked visited", "標記去過"))
    }

    private func archiveCount(_ count: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count, format: .number).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
            Text(title).font(.system(.subheadline, design: .rounded)).foregroundStyle(DateTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private func archiveLink(title: String, detail: String, icon: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(.title3, design: .rounded))
                    .foregroundStyle(DateTheme.blue).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.headline, design: .rounded))
                    Text(detail).font(.system(.subheadline, design: .rounded)).foregroundStyle(DateTheme.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DateTheme.muted).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(16).modifier(LiveLibraryCard()).contentShape(Rectangle())
        }.savvyPressFeedback()
    }

    private func copy(_ english: String, _ chinese: String) -> String {
        language.localized(english: english, traditionalChinese: chinese)
    }
}

struct LiveLibraryCollection {
    struct Region: Identifiable {
        let id: String
        let name: String
    }
    struct Entry: Identifiable {
        let id: UUID
        let place: Place
        let region: Region?
        let location: String

        @MainActor
        init(place: Place) {
            id = place.id
            self.place = place
            let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
            let taiwanAddress = address.replacingOccurrences(of: "臺", with: "台")
            if let municipality = Self.taiwanMunicipality(in: taiwanAddress) {
                let label = String(taiwanAddress[municipality])
                region = Region(id: SaveAddressLocality.resolve(label)?.cityID ?? label, name: label)
                location = Self.locationLabel(label, remainder: taiwanAddress[municipality.upperBound...])
            } else if let area = SaveAddressLocality.resolve(address),
               area.metroKey != nil || area.region != nil || area.country != nil
                || area.label.last.map({ "市縣县都".contains($0) }) == true {
                region = Region(id: area.cityID, name: area.label)
                if let city = address.range(of: area.label) {
                    location = Self.locationLabel(area.label, remainder: address[city.upperBound...])
                } else {
                    location = area.label
                }
            } else {
                region = nil
                location = address
            }
        }

        private static func taiwanMunicipality(in address: String) -> Range<String.Index>? {
            let prefix = address.range(of: #"^(?:\d{3,6}\s*)?(?:台灣|台湾)?\s*"#,
                                       options: .regularExpression)
            let remainder = address[(prefix?.upperBound ?? address.startIndex)...]
            return remainder.range(
                of: #"^(?:台北市|新北市|基隆市|桃園市|新竹[市縣]|苗栗縣|台中市|彰化縣|南投縣|雲林縣|嘉義[市縣]|台南市|高雄市|屏東縣|宜蘭縣|花蓮縣|台東縣|澎湖縣|金門縣|連江縣)"#,
                options: .regularExpression
            )
        }

        private static func locationLabel(_ city: String, remainder: Substring) -> String {
            guard let district = remainder.range(of: #"^\s*[\p{Han}]{1,5}?[區区鄉乡鎮镇市]"#,
                                                  options: .regularExpression) else { return city }
            return city + " · " + remainder[district].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    let regions: [Region]
    let categories: [PlaceCategory]
    let matches: [Entry]

    @MainActor
    init(places: [Place], query: String, regionID: String?, category: PlaceCategory?) {
        let entries = places.map(Entry.init)
        var seen = Set<String>()
        regions = entries.compactMap(\.region).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let presentCategories = Set(places.map(\.category))
        categories = PlaceCategory.allCases.filter(presentCategories.contains)
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        matches = entries.filter { entry in
            (regionID == nil || entry.region?.id == regionID)
                && (category == nil || entry.place.category == category)
                && (text.isEmpty || entry.place.name.localizedStandardContains(text)
                    || entry.place.address.localizedStandardContains(text)
                    || entry.location.localizedStandardContains(text))
        }
    }
}

private struct LiveLibraryCard: ViewModifier {
    func body(content: Content) -> some View {
        content.background(DateTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(DateTheme.ink.opacity(0.06)))
    }
}
#endif
