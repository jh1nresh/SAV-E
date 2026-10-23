import StoreKit
import SwiftUI
import UIKit

enum ClipPreviewFailure: String {
    case expired
    case offline
    case server
    case malformed
    case empty

    var titleKey: String.LocalizationValue {
        switch self {
        case .expired: return "clip.error.expired.title"
        case .offline: return "clip.error.offline.title"
        case .server: return "clip.error.server.title"
        case .malformed: return "clip.error.malformed.title"
        case .empty: return "clip.empty.title"
        }
    }

    var bodyKey: String.LocalizationValue {
        switch self {
        case .expired: return "clip.error.expired.body"
        case .offline: return "clip.error.offline.body"
        case .server: return "clip.error.server.body"
        case .malformed: return "clip.error.malformed.body"
        case .empty: return "clip.empty.body"
        }
    }

    var sticker: ClipStickerKind {
        switch self {
        case .expired, .malformed: return .lantern
        case .server: return .coffee
        case .offline, .empty: return .place
        }
    }

    var badge: String {
        switch self {
        case .expired: return "✕"
        case .offline: return "!"
        case .server: return "…"
        case .malformed: return "?"
        case .empty: return ""
        }
    }

    var showsRetry: Bool {
        self == .offline || self == .server
    }
}

enum ClipSurface: Equatable {
    case preview
    case signIn(ClipSignInKind)
    case saved(String)
    case listSaved(ClipListSaveCounts)
    case capReached
    case duplicate
    case saveFailed
}

struct ClipContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var placeReceipt: SharedPlaceReceipt?
    @State private var tripData: SharedTripData?
    @State private var listData: SharedListData?
    @State private var referralData: SharedReferralProfile?
    @State private var mySavesData: SharedMySavesData?
    @State private var mySavesSourceURL: URL?
    @State private var isLoading = true
    @State private var incomingURLTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?
    @State private var activeIncomingURLRequestID: UUID?
    @State private var activeSaveRequestID: UUID?
    @State private var lastIncomingURL: URL?
    @State private var failure: ClipPreviewFailure?
    @State private var surface: ClipSurface = .preview
    @State private var signInHint = false
    @State private var isSaving = false
    @State private var lastSaveWasList = false
    @State private var pendingSaveDraft: ClipPlaceDraft?
    @State private var pendingListDrafts: [ClipPlaceDraft]?
    @State private var pendingSaveListTitle: String?
    @State private var listPage = 0
    @State private var showListSwipeHint = !ClipListSwipeHint.isDismissed()
    @State private var presentsAppClipOverlay = false

    var body: some View {
        Group {
            if isLoading {
                loadingScreen
            } else if case .signIn(let kind) = surface {
                signInScreen(kind)
            } else if case .listSaved(let counts) = surface {
                listOutcomeScreen(counts)
            } else if case .saved(let name) = surface {
                outcomeScreen(
                    title: ClipCopy.string("clip.saved.title"),
                    bodyText: ClipCopy.format("clip.saved.body", name),
                    sticker: .place,
                    badge: "✓",
                    retry: nil,
                    back: nil,
                    identifier: "clip.saved"
                )
            } else if surface == .capReached {
                outcomeScreen(
                    title: ClipCopy.string("clip.cap50.title"),
                    bodyText: ClipCopy.string("clip.cap50.body"),
                    sticker: .place,
                    badge: "50",
                    retry: nil,
                    back: ClipCopy.string("clip.cap50.back"),
                    identifier: "clip.cap50",
                    savedLine: ClipCopy.string("clip.cap50.saved")
                )
            } else if surface == .duplicate {
                outcomeScreen(
                    title: ClipCopy.string("clip.duplicate.title"),
                    bodyText: ClipCopy.string("clip.duplicate.body"),
                    sticker: .place,
                    badge: "↺",
                    retry: nil,
                    back: ClipCopy.string("clip.cap50.back"),
                    identifier: "clip.duplicate"
                )
            } else if surface == .saveFailed {
                outcomeScreen(
                    title: ClipCopy.string("clip.saveFailed.title"),
                    bodyText: ClipCopy.string("clip.saveFailed.body"),
                    sticker: .place,
                    badge: "!",
                    retry: { Task { await retryLastSave() } },
                    back: nil,
                    identifier: "clip.saveFailed"
                )
            } else if let mySaves = mySavesData {
                leftoverContent(title: "My Savvy", rows: mySaves.places.map(\.name))
            } else if let referral = referralData {
                leftoverContent(
                    title: referral.displayName,
                    rows: [ClipCopy.format("clip.referral.invite", referral.handle)]
                )
            } else if let list = listData {
                listPages(list)
            } else if let receipt = placeReceipt {
                placePage(
                    draft: .from(place: receipt.payload, shareCode: receipt.code),
                    sender: receipt.verifiedSenderLabel,
                    photoURL: ClipOwnedPhotoPolicy.url(from: receipt.payload.photoURLs),
                    listTitle: nil,
                    pageIndex: 0,
                    pageCount: 1
                )
            } else if let trip = tripData {
                leftoverContent(title: trip.name, rows: trip.stops.map(\.name))
            } else {
                let reason = failure ?? .empty
                outcomeScreen(
                    title: ClipCopy.string(reason.titleKey),
                    bodyText: ClipCopy.string(reason.bodyKey),
                    sticker: reason.sticker,
                    badge: reason.badge,
                    retry: reason.showsRetry ? { handleIncomingURL(lastIncomingURL) } : nil,
                    back: nil,
                    identifier: "clip.error.\(reason.rawValue)"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClipDottedBackground().ignoresSafeArea())
        .background {
            ClipSKOverlayHost(isPresented: $presentsAppClipOverlay)
        }
        .overlay(alignment: .top) {
            if presentsAppClipOverlay {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("clip.skoverlay")
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            handleIncomingURL(activity.webpageURL)
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .task {
#if DEBUG
            if applyLaunchFixtureIfNeeded() {
                return
            }
            if activeIncomingURLRequestID == nil,
               let rawURL = ProcessInfo.processInfo.environment["_XCAppClipURL"],
               let localInvocationURL = URL(string: rawURL) {
                handleIncomingURL(localInvocationURL)
                return
            }
#endif
            try? await Task.sleep(for: .seconds(1))
            if activeIncomingURLRequestID == nil,
               placeReceipt == nil && tripData == nil && listData == nil && referralData == nil && mySavesData == nil {
                failure = .empty
                isLoading = false
            }
        }
        .onDisappear {
            incomingURLTask?.cancel()
            incomingURLTask = nil
            activeIncomingURLRequestID = nil
        }
    }

    private var loadingScreen: some View {
        VStack(spacing: 0) {
            hero(photoURL: nil, category: nil, sender: nil, listTitle: nil, pageIndex: 0, pageCount: 1)
                .overlay {
                    VStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ClipJournalPalette.cream.opacity(0.35))
                            .frame(width: 180, height: 18)
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ClipJournalPalette.cream.opacity(0.22))
                            .frame(width: 120, height: 14)
                        ClipLoadingDots(reduceMotion: reduceMotion)
                    }
                }
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityIdentifier("clip.loading")
        .accessibilityLabel(ClipCopy.string("clip.loading.title"))
    }

    private func listPages(_ list: SharedListData) -> some View {
        let items = list.items
        return GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        placePage(
                            draft: .from(item: item),
                            sender: ClipPreviewPolicy.senderLabel(list.ownerDisplayName),
                            photoURL: ClipOwnedPhotoPolicy.url(from: item.photoURLs),
                            listTitle: list.title,
                            pageIndex: index,
                            pageCount: items.count
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .background {
                            GeometryReader { itemProxy in
                                Color.clear.preference(
                                    key: ClipListPageKey.self,
                                    value: abs(itemProxy.frame(in: .named("clip.list")).minY) < 80 ? index : nil
                                )
                            }
                        }
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .coordinateSpace(name: "clip.list")
            .onPreferenceChange(ClipListPageKey.self) { incoming in
                let page = ClipListSavePlanner.visiblePage(current: listPage, incoming: incoming)
                if page > 0 {
                    ClipListSwipeHint.dismiss()
                    showListSwipeHint = false
                }
                listPage = page
            }
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityIdentifier("clip.list.preview")
    }

    private func placePage(
        draft: ClipPlaceDraft,
        sender: String?,
        photoURL: URL?,
        listTitle: String?,
        pageIndex: Int,
        pageCount: Int
    ) -> some View {
        VStack(spacing: 0) {
            hero(
                photoURL: photoURL,
                category: draft.category,
                sender: sender,
                listTitle: listTitle,
                pageIndex: pageIndex,
                pageCount: pageCount
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if signInHint {
                        Text(ClipCopy.string("clip.signin.hint"))
                            .font(ClipJournalType.system(13, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(ClipJournalPalette.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ClipJournalPalette.kraft, in: Capsule())
                            .accessibilityIdentifier("clip.signin.hint")
                    }
                    Text(draft.name)
                        .font(ClipDisplayType.placeName)
                        .foregroundStyle(ClipJournalPalette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    if let meta = areaCategoryLine(draft) {
                        Text(meta)
                            .font(ClipJournalType.system(15, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(ClipJournalPalette.muted)
                    }
                    if let note = draft.note, !note.isEmpty {
                        ClipWashiNote(text: note, attribution: sender)
                    }
                    ClipJournalPrimaryButton(
                        title: ClipCopy.string("clip.save"),
                        enabled: !isSaving
                    ) {
                        beginSave(draft: draft, listTitle: listTitle)
                    }
                    .accessibilityIdentifier(listTitle == nil ? "clip.place.open" : "clip.list.open")
                    .accessibilityHint(ClipCopy.format("clip.signin.reason", draft.name))
                    if listTitle != nil, pageCount > 0 {
                        ClipJournalSecondaryButton(
                            title: ClipCopy.format("clip.saveAll", pageCount),
                            enabled: !isSaving
                        ) {
                            beginSaveWholeList()
                        }
                        .accessibilityIdentifier("clip.list.saveAll")
                    }
                    if let maps = draft.mapsURL() {
                        ClipMapsTextLink(title: ClipCopy.string("clip.openMaps")) {
                            UIApplication.shared.open(maps)
                        }
                        .accessibilityIdentifier("clip.place.maps")
                    }
                    if listTitle != nil,
                       ClipListSwipeHint.shouldShow(
                           pageIndex: pageIndex,
                           pageCount: pageCount,
                           dismissed: !showListSwipeHint
                       ) {
                        Text("⌃ \(ClipCopy.string("clip.list.swipe"))")
                            .font(ClipJournalType.system(13, weight: .regular, relativeTo: .footnote))
                            .foregroundStyle(ClipJournalPalette.muted)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("clip.list.swipe")
                    }
                }
                .padding(.horizontal, ClipJournalLayout.screenMargin)
                .padding(.top, 16)
                .padding(.bottom, ClipJournalLayout.buttonGroupBottom)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier(listTitle == nil ? "clip.place.preview" : "clip.list.item.\(pageIndex)")
    }

    private func hero(
        photoURL: URL?,
        category: String?,
        sender: String?,
        listTitle: String?,
        pageIndex: Int,
        pageCount: Int
    ) -> some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: .bottom) {
                Group {
                    if let photoURL {
                        ClipOwnedPhoto(url: photoURL)
                            .accessibilityIdentifier("clip.place.photo")
                    } else {
                        ClipJournalPalette.coral
                        ClipHeroSticker(kind: .forHero(category))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(ClipTornPaperEdge())
                .overlay(alignment: .bottom) {
                    ClipTornPaperEdge()
                        .stroke(ClipJournalPalette.ink, lineWidth: ClipJournalPalette.strokeWidth)
                }
                .overlay(alignment: .top) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let sender {
                                ClipSharerChip(name: sender)
                            }
                            if let listTitle, !listTitle.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(listTitle)
                                        .font(ClipDisplayType.title(ClipJournalLayout.listTitlePoint, relativeTo: .title3))
                                        .foregroundStyle(ClipJournalPalette.cream)
                                        .lineLimit(2)
                                    Text(ClipCopy.format("clip.list.count", pageIndex + 1, pageCount))
                                        .font(ClipJournalType.system(13, weight: .semibold, relativeTo: .footnote))
                                        .foregroundStyle(ClipJournalPalette.cream.opacity(0.9))
                                }
                            }
                            if sender == nil && (listTitle == nil || listTitle?.isEmpty == true) {
                                Spacer(minLength: 0)
                            }
                        }
                        Spacer(minLength: 8)
                        ClipWordmarkPlate()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 54)
                }
                if pageCount > 1 {
                    ClipPageIndicator(count: pageCount, current: pageIndex)
                        .padding(.trailing, 10)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
            }
            .frame(width: proxy.size.width, height: height)
        }
        .frame(height: min(ClipJournalLayout.heroHeight, UIScreen.main.bounds.height * ClipJournalLayout.heroHeightRatio))
    }

    private func leftoverContent(title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ClipDisplayTitle(text: title, pointSize: 28, relativeTo: .title, alignment: .leading)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text(row)
                    .font(ClipJournalType.system(17, weight: .regular, relativeTo: .body))
                    .foregroundStyle(ClipJournalPalette.ink)
            }
            Spacer()
            ClipJournalPrimaryButton(title: ClipCopy.string("clip.trip.open"), action: openLeftover)
                .accessibilityIdentifier("clip.trip.open")
        }
        .padding(.horizontal, ClipJournalLayout.screenMargin)
        .padding(.bottom, ClipJournalLayout.buttonGroupBottom)
    }

    private func outcomeScreen(
        title: String,
        bodyText: String,
        sticker: ClipStickerKind,
        badge: String,
        retry: (() -> Void)?,
        back: String?,
        identifier: String,
        savedLine: String? = nil
    ) -> some View {
        VStack(spacing: ClipJournalLayout.stateTitleGap) {
            ClipWordmarkPlate()
                .accessibilityIdentifier("clip.wordmark")
            ClipStateIllustration(sticker: sticker, badge: badge)
            VStack(spacing: ClipJournalLayout.stateBodyGap) {
                ClipDisplayTitle(text: title, pointSize: 24, relativeTo: .title2)
                    .multilineTextAlignment(.center)
                if let savedLine {
                    Text(savedLine)
                        .font(ClipJournalType.system(17, weight: .semibold, relativeTo: .headline))
                        .foregroundStyle(ClipJournalPalette.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("clip.cap50.saved")
                }
                Text(bodyText)
                    .font(ClipJournalType.system(15, weight: .regular, relativeTo: .body))
                    .foregroundStyle(ClipJournalPalette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: ClipJournalLayout.stateBodyMaxWidth)
            }
            .accessibilityElement(children: .combine)
            if let retry {
                ClipJournalPrimaryButton(title: ClipCopy.string("clip.retry"), action: retry)
                    .accessibilityIdentifier("clip.error.retry")
                    .padding(.horizontal, ClipJournalLayout.screenMargin)
            }
            if let back {
                Button(back) {
                    surface = .preview
                    presentsAppClipOverlay = false
                }
                .font(ClipJournalType.system(15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(ClipJournalPalette.coral)
                .underline()
                .accessibilityIdentifier("clip.cap50.back")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, ClipJournalLayout.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func signInScreen(_ kind: ClipSignInKind) -> some View {
        let title = kind == .onePlace
            ? ClipCopy.string("clip.signin.saveOne")
            : ClipCopy.format("clip.signin.saveCount", kind.placeCount)
        return VStack(spacing: ClipJournalLayout.stateTitleGap) {
            ClipWordmarkPlate()
                .accessibilityIdentifier("clip.wordmark")
            ClipStateIllustration(sticker: .seal, badge: "")
            VStack(spacing: ClipJournalLayout.stateBodyGap) {
                ClipDisplayTitle(text: title, pointSize: 24, relativeTo: .title2)
                    .multilineTextAlignment(.center)
                Text(ClipCopy.string("clip.signin.hint"))
                    .font(ClipJournalType.system(15, weight: .regular, relativeTo: .body))
                    .foregroundStyle(ClipJournalPalette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: ClipJournalLayout.stateBodyMaxWidth)
            }
            ClipJournalPrimaryButton(title: title, enabled: !isSaving) {
                Task { await continueSignIn() }
            }
            .accessibilityIdentifier("clip.signin.continue")
            .padding(.horizontal, ClipJournalLayout.screenMargin)
            Button(ClipCopy.string("clip.cap50.back")) {
                surface = .preview
                signInHint = true
                presentsAppClipOverlay = false
            }
            .font(ClipJournalType.system(15, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(ClipJournalPalette.coral)
            .underline()
            .accessibilityIdentifier("clip.signin.back")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, ClipJournalLayout.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clip.signin")
    }

    private func listOutcomeScreen(_ counts: ClipListSaveCounts) -> some View {
        let partial = counts.overCap > 0
        let inSavvy = counts.newlySaved + counts.alreadySaved
        return VStack(spacing: ClipJournalLayout.stateTitleGap) {
            ClipWordmarkPlate()
                .accessibilityIdentifier("clip.wordmark")
            ClipStateIllustration(
                sticker: .seal,
                badge: partial ? "50" : "✓"
            )
            ClipDisplayTitle(
                text: partial
                    ? ClipCopy.string("clip.listPartial.title")
                    : ClipCopy.string("clip.listSaved.title"),
                pointSize: 24,
                relativeTo: .title2
            )
            .multilineTextAlignment(.center)
            ClipListSaveCountTable(counts: counts)
            Text(
                partial
                    ? ClipCopy.format("clip.listPartial.body", counts.overCap)
                    : ClipCopy.format("clip.listSaved.footer", inSavvy)
            )
            .font(ClipJournalType.system(15, weight: .regular, relativeTo: .body))
            .foregroundStyle(ClipJournalPalette.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: ClipJournalLayout.stateBodyMaxWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, ClipJournalLayout.screenMargin)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(partial ? "clip.list.partial" : "clip.list.saved")
    }

    private func areaCategoryLine(_ draft: ClipPlaceDraft) -> String? {
        let area = draft.address.split(separator: ",").first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if area.isEmpty && category.isEmpty { return nil }
        if area.isEmpty { return category }
        if category.isEmpty { return area }
        return ClipCopy.format("clip.meta.areaCategory", area, category)
    }

    private func saveCurrentPlace() async {
        if let draft = pendingOnePlaceDraft() {
            await save(draft: draft.draft, listTitle: draft.listTitle)
        }
    }

    /// SIWA / retry keep the tapped draft. `listPage` can drift while
    /// off-screen PreferenceKey children reduce last-writer-wins.
    private func pendingOnePlaceDraft() -> (draft: ClipPlaceDraft, listTitle: String?)? {
        if let draft = pendingSaveDraft {
            return (draft, pendingSaveListTitle)
        }
        if let receipt = placeReceipt {
            return (.from(place: receipt.payload, shareCode: receipt.code), nil)
        }
        guard let list = listData else { return nil }
        let pageItem = list.items.indices.contains(listPage)
            ? ClipPlaceDraft.from(item: list.items[listPage]).listSaveItem
            : nil
        guard let chosen = ClipListSavePlanner.onePlaceItem(pending: nil, pageItem: pageItem) else {
            return nil
        }
        if let match = list.items.first(where: {
            ClipPlaceDraft.from(item: $0).listSaveItem == chosen
        }) {
            return (.from(item: match), list.title)
        }
        return nil
    }

    private func retryLastSave() async {
        if lastSaveWasList {
            beginSaveWholeList()
        } else if let draft = pendingSaveDraft {
            beginSave(draft: draft, listTitle: pendingSaveListTitle)
        } else {
            await saveCurrentPlace()
        }
    }

    private func beginSave(draft: ClipPlaceDraft, listTitle: String?) {
        signInHint = false
        lastSaveWasList = false
        pendingSaveDraft = draft
        pendingSaveListTitle = listTitle
        if ClipFullApp.isInstalled {
            enqueueSave { await save(draft: draft, listTitle: listTitle) }
            return
        }
        surface = .signIn(.onePlace)
    }

    private func beginSaveWholeList() {
        guard let list = listData else { return }
        signInHint = false
        lastSaveWasList = true
        if pendingListDrafts == nil {
            pendingListDrafts = list.items.map(ClipPlaceDraft.from(item:))
        }
        if ClipFullApp.isInstalled {
            enqueueSave { await saveWholeList() }
            return
        }
        surface = .signIn(.wholeList(pendingListDrafts?.count ?? list.items.count))
    }

    private func continueSignIn() async {
        switch surface {
        case .signIn(.onePlace):
            await saveCurrentPlace()
        case .signIn(.wholeList):
            await saveWholeList()
        default:
            break
        }
    }

    private func enqueueSave(_ work: @escaping () async -> Void) {
        saveTask?.cancel()
        let saveID = UUID()
        activeSaveRequestID = saveID
        saveTask = Task { @MainActor in
            await work()
        }
    }

    private func saveWholeList() async {
        guard let drafts = pendingListDrafts, !drafts.isEmpty else { return }
        signInHint = false
        lastSaveWasList = true
        let saveID = activeSaveRequestID ?? UUID()
        activeSaveRequestID = saveID
        isSaving = true
        defer { if activeSaveRequestID == saveID { isSaving = false } }
        let url = lastIncomingURL ?? URL(string: "https://sav-e-app.vercel.app/list")!
        let shareCode = lastIncomingURL.flatMap(SharedListPayload.shareCode(from:))
        let outcome = await ClipSaveService.saveList(
            drafts: drafts,
            listId: listData?.id.uuidString,
            shareCode: shareCode,
            handoffURL: url,
            sender: listData?.ownerDisplayName.isEmpty == false ? listData?.ownerDisplayName : nil
        )
        guard !Task.isCancelled, activeSaveRequestID == saveID else { return }
        switch outcome {
        case .handedOff:
            return
        case .listSaved(let counts):
            surface = .listSaved(counts)
            presentsAppClipOverlay = counts.addedAnything
        case .listFailed:
            surface = .saveFailed
            presentsAppClipOverlay = false
        case .signInCancelled:
            surface = .preview
            signInHint = true
            presentsAppClipOverlay = false
        case .saved, .duplicate, .capReached, .failed:
            surface = .saveFailed
            presentsAppClipOverlay = false
        }
    }

    private func save(draft: ClipPlaceDraft, listTitle: String?) async {
        signInHint = false
        lastSaveWasList = false
        let saveID = activeSaveRequestID ?? UUID()
        activeSaveRequestID = saveID
        isSaving = true
        defer { if activeSaveRequestID == saveID { isSaving = false } }
        let url = handoffURL(for: draft, listTitle: listTitle)
        let sender = placeReceipt?.verifiedSenderLabel
            ?? (listData?.ownerDisplayName.isEmpty == false ? listData?.ownerDisplayName : nil)
        let outcome = await ClipSaveService.save(draft: draft, handoffURL: url, sender: sender)
        guard !Task.isCancelled, activeSaveRequestID == saveID else { return }
        switch outcome {
        case .handedOff:
            return
        case .saved:
            surface = .saved(draft.name)
            presentsAppClipOverlay = true
        case .duplicate:
            surface = .duplicate
            presentsAppClipOverlay = false
        case .capReached:
            surface = .capReached
            presentsAppClipOverlay = false
        case .signInCancelled:
            surface = .preview
            signInHint = true
            presentsAppClipOverlay = false
        case .failed, .listFailed:
            surface = .saveFailed
            presentsAppClipOverlay = false
        case .listSaved(let counts):
            surface = .listSaved(counts)
            presentsAppClipOverlay = counts.addedAnything
        }
    }

    private func handoffURL(for draft: ClipPlaceDraft, listTitle: String?) -> URL {
        _ = listTitle
        // Never return lastIncomingURL: /p links can embed the sender's note/rating.
        if let encoded = SharedPlaceData(
            id: draft.placeId ?? "",
            name: draft.name,
            address: draft.address,
            lat: draft.latitude,
            lng: draft.longitude,
            category: draft.category,
            rating: nil,
            reviewCount: nil,
            priceRange: nil,
            hours: nil,
            sourceLabel: "Savvy",
            sourceURL: draft.sourceURL,
            photoURLs: [],
            note: nil,
            coordinateSystem: draft.coordinateSystem,
            locationProvider: draft.locationProvider,
            providerMapUrl: draft.providerMapURL
        ).strippingSenderMemory().toURL() {
            return encoded
        }
        return URL(string: "https://sav-e-app.vercel.app/p")!
    }

    private func openLeftover() {
        let url = mySavesSourceURL
            ?? referralData?.fullAppURL()
            ?? tripData?.toURL(baseURL: "savvy://trip")
            ?? URL(string: "savvy://trip")
        if let url {
            UIApplication.shared.open(url)
        }
    }

    private func handleIncomingURL(_ url: URL?) {
        guard let url else { return }
        incomingURLTask?.cancel()
        incomingURLTask = nil
        saveTask?.cancel()
        saveTask = nil
        activeSaveRequestID = nil
        isSaving = false
        lastIncomingURL = url
        failure = nil
        surface = .preview
        signInHint = false
        lastSaveWasList = false
        presentsAppClipOverlay = false
        let requestID = UUID()
        activeIncomingURLRequestID = requestID

        if let referral = SharedReferralProfile.from(url: url) {
            apply(referral: referral)
            isLoading = false
            return
        }

        if SharedListPayload.isListLink(url) {
            if let payload = SharedListPayload.from(url: url) {
                apply(list: payload.list)
                isLoading = false
                return
            }
            guard SharedListPayload.shareCode(from: url) != nil else {
                presentFailure(.malformed)
                return
            }
            isLoading = true
            incomingURLTask = Task { @MainActor in
                do {
                    let payload = try await SharedListPayload.resolve(from: url)
                    guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                    apply(list: payload.list)
                    isLoading = false
                    incomingURLTask = nil
                } catch is CancellationError {
                    return
                } catch let error as SharedListPreviewError {
                    guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                    presentFailure(Self.failure(from: error))
                    incomingURLTask = nil
                } catch {
                    guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                    presentFailure(.server)
                    incomingURLTask = nil
                }
            }
            return
        }

        if SharedMySavesData.isMySavesLink(url) {
            isLoading = true
            incomingURLTask = Task { @MainActor in
                let resolved = await SharedMySavesData.resolve(from: url)
                guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                if let resolved {
                    apply(mySaves: resolved, url: url)
                } else {
                    presentFailure(.server)
                    return
                }
                isLoading = false
                incomingURLTask = nil
            }
            return
        }

        if isPlaceLink(url) {
            guard url.absoluteString.utf8.count <= ShareRoutePayloadLimits.pendingPlaceURLMaxBytes else {
                presentFailure(.malformed)
                return
            }
            clearContent()
            if let data = SharedPlaceData.from(url: url) {
                placeReceipt = .embedded(data)
                isLoading = false
                return
            } else if SharedPlaceData.shortCode(from: url) != nil {
                isLoading = true
                incomingURLTask = Task { @MainActor in
                    do {
                        let receipt = try await SharedPlaceReceipt.resolve(from: url)
                        guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                        placeReceipt = receipt
                        isLoading = false
                        if let code = receipt.code {
                            await SharedPlaceReceipt.recordPublicEvent(
                                code: code,
                                eventType: "friend_share_receipt_opened"
                            )
                        }
                        incomingURLTask = nil
                    } catch is CancellationError {
                        return
                    } catch let error as SharedPlaceReceiptError {
                        guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                        presentFailure(Self.failure(from: error))
                        if let code = SharedPlaceData.shortCode(from: url) {
                            await SharedPlaceReceipt.recordPublicEvent(
                                code: code,
                                eventType: "friend_share_open_failed",
                                reasonCode: error.eventFailureReason
                            )
                        }
                        incomingURLTask = nil
                    } catch {
                        guard !Task.isCancelled, activeIncomingURLRequestID == requestID else { return }
                        presentFailure(.server)
                        if let code = SharedPlaceData.shortCode(from: url) {
                            await SharedPlaceReceipt.recordPublicEvent(
                                code: code,
                                eventType: "friend_share_open_failed",
                                reasonCode: "unknown"
                            )
                        }
                        incomingURLTask = nil
                    }
                }
                return
            }
            presentFailure(.malformed)
            return
        }

        guard isTripLink(url) else {
            presentFailure(.malformed)
            return
        }

        if let data = SharedTripData.from(url: url) {
            apply(trip: data)
        } else {
            presentFailure(.malformed)
        }
        isLoading = false
    }

    private func presentFailure(_ reason: ClipPreviewFailure) {
        clearContent()
        failure = reason
        isLoading = false
    }

    private func clearContent() {
        placeReceipt = nil
        tripData = nil
        listData = nil
        referralData = nil
        mySavesData = nil
        mySavesSourceURL = nil
        listPage = 0
        pendingSaveDraft = nil
        pendingSaveListTitle = nil
        if !lastSaveWasList {
            pendingListDrafts = nil
        }
    }

    private func apply(list: SharedListData) {
        clearContent()
        guard !list.items.isEmpty else {
            presentFailure(.empty)
            return
        }
        listData = list
        showListSwipeHint = !ClipListSwipeHint.isDismissed()
        listPage = 0
    }

    private func apply(referral: SharedReferralProfile) {
        clearContent()
        referralData = referral
    }

    private func apply(trip: SharedTripData) {
        clearContent()
        tripData = trip
    }

    private func apply(mySaves: SharedMySavesData, url: URL) {
        clearContent()
        mySavesData = mySaves
        mySavesSourceURL = url
    }

    private static func failure(from error: SharedPlaceReceiptError) -> ClipPreviewFailure {
        switch error {
        case .missingOrExpired: return .expired
        case .networkUnavailable: return .offline
        case .serverUnavailable: return .server
        case .malformedOrUnconfigured, .invalidResponse: return .malformed
        }
    }

    private static func failure(from error: SharedListPreviewError) -> ClipPreviewFailure {
        switch error {
        case .notFound, .expired: return .expired
        case .network: return .offline
        case .invalidLink: return .malformed
        case .invalidResponse: return .server
        }
    }

    private func isPlaceLink(_ url: URL) -> Bool {
        if SAVEProductionConfig.supportsCustomURLScheme(url), url.host == "p" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app"].contains(url.host ?? "") else {
            return false
        }
        return url.path.split(separator: "/").first.map(String.init) == "p"
    }

    private func isTripLink(_ url: URL) -> Bool {
        if SAVEProductionConfig.supportsCustomURLScheme(url), url.host == "trip" {
            return true
        }
        guard url.scheme == "https",
              ["sav-e-app.vercel.app"].contains(url.host ?? "") else {
            return false
        }

        let pathParts = url.path.split(separator: "/")
        if pathParts.first.map(String.init) == "trip", pathParts.count >= 2 {
            return true
        }

        guard url.path == "/trip",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.queryItems?.contains { item in
            item.name == "d" && item.value?.isEmpty == false
        } == true
    }
}

private struct ClipListPageKey: PreferenceKey {
    static var defaultValue: Int? = nil
    static func reduce(value: inout Int?, nextValue: () -> Int?) {
        if let next = nextValue() {
            value = next
        }
    }
}

enum ClipOwnedPhotoPolicy {
    static func url(from values: [String]) -> URL? {
        for value in values {
            guard let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.user == nil,
                  url.password == nil,
                  !ShareRoutePhotoPolicy.isGooglePlacesPhotoURL(url),
                  !ShareRoutePhotoPolicy.looksLikeGooglePlacesPhotoReference(value)
            else { continue }
            return url
        }
        return nil
    }
}

/// System App Clip overlay. Unstyled — SKOverlay owns the chrome.
/// Present only after a successful backend save.
private struct ClipSKOverlayHost: UIViewControllerRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        let scene = activeScene()
        switch context.coordinator.presentation.update(requested: isPresented, hasScene: scene != nil) {
        case .none:
            break
        case .present:
            guard let scene else { return }
            context.coordinator.scene = scene
            let overlay = SKOverlay(configuration: SKOverlay.AppClipConfiguration(position: .bottom))
            overlay.present(in: scene)
        case .dismiss:
            if let presentedScene = context.coordinator.scene { SKOverlay.dismiss(in: presentedScene) }
            context.coordinator.scene = nil
        }
    }

    private func activeScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        if let scene = coordinator.scene { SKOverlay.dismiss(in: scene) }
        coordinator.scene = nil
        _ = coordinator.presentation.update(requested: false, hasScene: false)
    }

    final class Coordinator {
        var presentation = ClipOverlayPresentationState()
        weak var scene: UIWindowScene?
    }
}

#if DEBUG
extension ClipContentView {
    @discardableResult
    fileprivate func applyLaunchFixtureIfNeeded() -> Bool {
        guard let screen = ClipPreviewFixtures.requestedScreen() else { return false }
        isLoading = false
        failure = nil
        surface = .preview
        signInHint = false
        lastSaveWasList = false
        presentsAppClipOverlay = false
        clearContent()
        switch screen {
        case "place-sender":
            let place = ClipPreviewFixtures.samplePlace()
            placeReceipt = SharedPlaceReceipt(
                code: "AbC123_x",
                payload: place,
                sourcePlaceID: nil,
                expiresAt: nil,
                sender: SharedPlaceSender(displayName: "Mina", handle: "mina")
            )
        case "place-inline":
            placeReceipt = .embedded(ClipPreviewFixtures.samplePlace())
        case "skoverlay", "saved":
            placeReceipt = .embedded(ClipPreviewFixtures.samplePlace())
            surface = .saved(ClipPreviewFixtures.samplePlace().name)
            presentsAppClipOverlay = screen == "skoverlay"
        case "cap50":
            placeReceipt = .embedded(ClipPreviewFixtures.samplePlace())
            surface = .capReached
        case "duplicate":
            placeReceipt = .embedded(ClipPreviewFixtures.samplePlace())
            surface = .duplicate
        case "signin-fail":
            placeReceipt = .embedded(ClipPreviewFixtures.samplePlace())
            signInHint = true
        case "signin":
            placeReceipt = .embedded(ClipPreviewFixtures.samplePlace())
            surface = .signIn(.onePlace)
        case "signin-list":
            apply(list: ClipPreviewFixtures.sampleList())
            surface = .signIn(.wholeList(ClipPreviewFixtures.sampleList().items.count))
        case "save-fail":
            placeReceipt = .embedded(ClipPreviewFixtures.samplePlace())
            surface = .saveFailed
        case "list":
            ClipListSwipeHint.reset()
            apply(list: ClipPreviewFixtures.sampleList())
            showListSwipeHint = true
        case "list-empty", "list-placeholder-owner":
            let list = ClipPreviewFixtures.sampleList()
            apply(list: SharedListData(
                id: list.id, title: list.title, note: list.note,
                ownerDisplayName: screen == "list-placeholder-owner" ? "Shared list" : list.ownerDisplayName,
                viewerRole: list.viewerRole, items: screen == "list-empty" ? [] : list.items,
                createdAt: list.createdAt, updatedAt: list.updatedAt
            ))
        case "list-swiped":
            ClipListSwipeHint.dismiss()
            apply(list: ClipPreviewFixtures.sampleList())
            showListSwipeHint = false
        case "list-saved":
            apply(list: ClipPreviewFixtures.sampleList())
            surface = .listSaved(
                ClipListSaveCounts(newlySaved: 4, alreadySaved: 1, overCap: 0, remaining: 12, limit: 50)
            )
            presentsAppClipOverlay = true
        case "list-partial":
            apply(list: ClipPreviewFixtures.sampleList())
            surface = .listSaved(
                ClipListSaveCounts(newlySaved: 3, alreadySaved: 1, overCap: 1, remaining: 0, limit: 50)
            )
            presentsAppClipOverlay = true
        case "loading":
            isLoading = true
        case "expired":
            failure = .expired
        case "offline":
            lastIncomingURL = URL(string: "https://sav-e-app.vercel.app/p/AbC123_x")
            failure = .offline
        case "server":
            lastIncomingURL = URL(string: "https://sav-e-app.vercel.app/p/AbC123_x")
            failure = .server
        case "malformed":
            failure = .malformed
        default:
            failure = .empty
        }
        return true
    }
}
#endif
