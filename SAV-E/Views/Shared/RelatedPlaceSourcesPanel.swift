import SwiftUI

enum RelatedPlaceSourcesLoadState: Equatable {
    case idle
    case loading
    case loaded(RelatedPlaceSourcePack)
    case failed(RelatedPlaceSourcesDisplayError)
}

enum RelatedPlaceSourcesDisplayError: Equatable {
    case signInRequired
    case mapStampUnavailable
    case publicVenueRequired
    case googleConfirmationRequired
    case rateLimited
    case temporarilyUnavailable
    case network
    case invalidResponse

    static func classify(_ error: Error) -> RelatedPlaceSourcesDisplayError {
        guard let error = error as? SupabaseError else {
            if error is RelatedPlaceSourcesClientError {
                return .invalidResponse
            }
            return .temporarilyUnavailable
        }

        switch error {
        case .notAuthenticated:
            return .signInRequired
        case .recordNotFound:
            return .mapStampUnavailable
        case .notConfigured:
            return .temporarilyUnavailable
        case .networkError:
            return .network
        case .invalidResponse:
            return .invalidResponse
        case .apiError(let statusCode, _):
            switch statusCode {
            case 400: return .publicVenueRequired
            case 401, 403: return .signInRequired
            case 404: return .mapStampUnavailable
            case 409: return .googleConfirmationRequired
            case 429: return .rateLimited
            case 503: return .temporarilyUnavailable
            default: return .temporarilyUnavailable
            }
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .signInRequired:
            return language.localized(english: "Account required", traditionalChinese: "需要登入帳號")
        case .mapStampUnavailable:
            return language.localized(english: "Map Stamp unavailable", traditionalChinese: "找不到這個地圖章")
        case .publicVenueRequired:
            return language.localized(english: "Public venues only", traditionalChinese: "僅支援公開場所")
        case .googleConfirmationRequired:
            return language.localized(english: "Confirm the exact place first", traditionalChinese: "請先確認正確地點")
        case .rateLimited:
            return language.localized(english: "Search limit reached", traditionalChinese: "已達搜尋次數上限")
        case .temporarilyUnavailable:
            return language.localized(english: "Search unavailable", traditionalChinese: "目前無法搜尋")
        case .network:
            return language.localized(english: "Connection interrupted", traditionalChinese: "網路連線中斷")
        case .invalidResponse:
            return language.localized(english: "Receipt unavailable", traditionalChinese: "無法讀取搜尋收據")
        }
    }

    func message(language: AppLanguage) -> String {
        switch self {
        case .signInRequired:
            return language.localized(
                english: "Sign in with your SAV-E account to search sources for this private Map Stamp.",
                traditionalChinese: "請登入 SAV-E 帳號，才能為這個私人地圖章搜尋來源。"
            )
        case .mapStampUnavailable:
            return language.localized(
                english: "This Map Stamp may not be synced to your account yet.",
                traditionalChinese: "這個地圖章可能還沒有同步到你的帳號。"
            )
        case .publicVenueRequired:
            return language.localized(
                english: "Related-source discovery is limited to verified public venues.",
                traditionalChinese: "相關來源搜尋僅支援已驗證的公開場所。"
            )
        case .googleConfirmationRequired:
            return language.localized(
                english: "Confirm this Map Stamp with an exact Google place before searching public sources.",
                traditionalChinese: "請先用正確的 Google 地點確認這個地圖章，再搜尋公開來源。"
            )
        case .rateLimited:
            return language.localized(
                english: "Wait a few minutes before searching this account again.",
                traditionalChinese: "請稍候幾分鐘，再使用這個帳號搜尋。"
            )
        case .temporarilyUnavailable:
            return language.localized(
                english: "Public venue verification or search is temporarily unavailable. Try again later.",
                traditionalChinese: "公開場所驗證或搜尋暫時無法使用，請稍後再試。"
            )
        case .network:
            return language.localized(
                english: "Check your connection and try again.",
                traditionalChinese: "請檢查網路連線後再試一次。"
            )
        case .invalidResponse:
            return language.localized(
                english: "SAV-E did not receive a valid source receipt. Nothing was saved.",
                traditionalChinese: "SAV-E 沒有收到有效的來源收據，也沒有儲存任何內容。"
            )
        }
    }
}

struct RelatedPlaceSourcesPanel: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.openURL) private var openURL

    let place: Place
    let discover: (Place, Bool) async throws -> RelatedPlaceSourcePack

    @State private var state: RelatedPlaceSourcesLoadState = .idle
    @State private var loadRequestID: UUID?
    @State private var requestedForceRefresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            stateContent
        }
        .padding(14)
        .saveAtlasPaper(radius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer.saved.relatedSources")
        .task(id: loadRequestID) {
            guard let requestID = loadRequestID else { return }
            await loadSources(requestID: requestID)
        }
        .onChange(of: place.id) { _, _ in
            loadRequestID = nil
            requestedForceRefresh = false
            state = .idle
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.title3)
                .foregroundColor(.saveCocoa)

            VStack(alignment: .leading, spacing: 3) {
                Text(languageSettings.localized(
                    english: "Related public sources",
                    traditionalChinese: "相關公開來源"
                ))
                .font(.subheadline.weight(.bold))
                .foregroundColor(.saveInk)

                Text(languageSettings.localized(
                    english: "Public-index candidates; verify before using.",
                    traditionalChinese: "這些是公開索引候選，使用前請再次確認。"
                ))
                .font(.caption)
                .foregroundColor(.saveCocoa.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .idle:
            VStack(alignment: .leading, spacing: 10) {
                Text(languageSettings.localized(
                    english: "Search seven supported platforms for this confirmed place. Results will not change your Map Stamp or Trip.",
                    traditionalChinese: "在七個支援平台搜尋這個已確認地點；結果不會改動地圖章或行程。"
                ))
                .font(.caption)
                .foregroundColor(.saveMutedText)
                .fixedSize(horizontal: false, vertical: true)

                findButton(
                    title: languageSettings.localized(
                        english: "Find related sources",
                        traditionalChinese: "尋找相關來源"
                    ),
                    systemImage: "sparkle.magnifyingglass",
                    forceRefresh: false
                )
            }

        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.saveCocoa)
                Text(languageSettings.localized(
                    english: "Searching supported public sources…",
                    traditionalChinese: "正在搜尋支援的公開來源…"
                ))
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveCocoa)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .accessibilityIdentifier("drawer.saved.relatedSources.loading")

        case .loaded(let pack):
            loadedContent(pack)

        case .failed(let error):
            failedContent(error)
        }
    }

    private func loadedContent(_ pack: RelatedPlaceSourcePack) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let storage = pack.storage, storage.isStale {
                staleNotice(storage)
            }

            if pack.sources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(emptyStateTitle(pack))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.saveInk)

                    Text(emptyStateMessage(pack))
                    .font(.caption)
                    .foregroundColor(.saveMutedText)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("drawer.saved.relatedSources.empty")
            } else {
                ForEach(Array(pack.sources.enumerated()), id: \.element.id) { index, source in
                    RelatedPlaceSourceRow(source: source) {
                        openURL(source.url)
                    }
                    .accessibilityIdentifier(
                        "drawer.saved.relatedSources.result.\(source.platform.rawValue).\(index)"
                    )
                }
            }

            coverageView(pack)

            Button {
                startDiscovery(forceRefresh: true)
            } label: {
                Label(
                    languageSettings.localized(
                        english: "Refresh public sources",
                        traditionalChinese: "重新搜尋公開來源"
                    ),
                    systemImage: "arrow.clockwise"
                )
                .saveOutlinedButton(fill: SaveAtlasPalette.paper)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("drawer.saved.relatedSources.refresh")
        }
    }

    private func coverageView(_ pack: RelatedPlaceSourcePack) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageSettings.localized(
                english: "Coverage receipt",
                traditionalChinese: "搜尋範圍收據"
            ))
            .font(.caption.weight(.bold))
            .foregroundColor(.saveCocoa)

            FlowLayout(spacing: 6) {
                ForEach(pack.coverage) { entry in
                    RelatedSourceCoverageChip(entry: entry)
                }
            }

            Text(receiptSummary(pack))
                .font(.caption2.weight(.medium))
                .foregroundColor(.saveMutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .saveAtlasPaper(radius: 12)
        .accessibilityIdentifier("drawer.saved.relatedSources.coverage")
    }

    private func failedContent(_ error: RelatedPlaceSourcesDisplayError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(error.title(language: languageSettings.language))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.subheadline.weight(.bold))
            .foregroundColor(.saveError)

            Text(error.message(language: languageSettings.language))
                .font(.caption)
                .foregroundColor(.saveMutedText)
                .fixedSize(horizontal: false, vertical: true)

            findButton(
                title: languageSettings.localized(english: "Try again", traditionalChinese: "再試一次"),
                systemImage: "arrow.clockwise",
                forceRefresh: true
            )
        }
        .accessibilityIdentifier("drawer.saved.relatedSources.error")
    }

    private func findButton(title: String, systemImage: String, forceRefresh: Bool) -> some View {
        Button {
            startDiscovery(forceRefresh: forceRefresh)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(SaveBrandPrimaryButtonStyle(fill: SaveAtlasPalette.coral, foreground: .white))
        .disabled(state == .loading)
        .accessibilityIdentifier("drawer.saved.relatedSources.find")
    }

    private func startDiscovery(forceRefresh: Bool) {
        SaveHaptics.tap()
        state = .loading
        requestedForceRefresh = forceRefresh
        loadRequestID = UUID()
    }

    private func loadSources(requestID: UUID) async {
        let requestedPlaceID = place.id
        do {
            let pack = try await discover(place, requestedForceRefresh)
            try Task.checkCancellation()
            guard loadRequestID == requestID,
                  place.id == requestedPlaceID
            else { return }
            state = .loaded(pack)
        } catch is CancellationError {
            return
        } catch {
            guard loadRequestID == requestID,
                  place.id == requestedPlaceID
            else { return }
            state = .failed(RelatedPlaceSourcesDisplayError.classify(error))
        }
    }

    @ViewBuilder
    private func staleNotice(_ storage: RelatedSourcesStorage) -> some View {
        Label {
            Text(languageSettings.localized(
                english: "Saved result may be out of date · Last checked \(staleAgeDays(storage.fetchedAt)) days ago.",
                traditionalChinese: "已儲存的結果可能已過期 · 上次檢查是 \(staleAgeDays(storage.fetchedAt)) 天前。"
            ))
        } icon: {
            Image(systemName: "clock.badge.exclamationmark")
        }
        .font(.caption.weight(.semibold))
        .foregroundColor(.saveCocoa)
        .accessibilityIdentifier("drawer.saved.relatedSources.stale")
    }

    private func emptyStateTitle(_ pack: RelatedPlaceSourcePack) -> String {
        if pack.coverage.contains(where: { $0.status != .searched }) {
            return languageSettings.localized(
                english: "Search coverage incomplete",
                traditionalChinese: "搜尋範圍不完整"
            )
        }
        return languageSettings.localized(
            english: "No useful public candidates found",
            traditionalChinese: "沒有找到可用的公開候選"
        )
    }

    private func emptyStateMessage(_ pack: RelatedPlaceSourcePack) -> String {
        if pack.coverage.contains(where: { $0.status != .searched }) {
            return languageSettings.localized(
                english: "Some requested platforms failed or returned partial coverage. Use the receipt below before drawing any conclusion.",
                traditionalChinese: "部分指定平台搜尋失敗或只取得部分範圍；請先查看下方收據再判斷。"
            )
        }
        return languageSettings.localized(
            english: "The searched platforms are listed below. This does not mean no post exists.",
            traditionalChinese: "下方列出已搜尋的平台；這不代表網路上完全沒有相關貼文。"
        )
    }

    private func staleAgeDays(_ fetchedAt: String) -> Int {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractionalFormatter.date(from: fetchedAt)
            ?? ISO8601DateFormatter().date(from: fetchedAt)
        guard let date else { return 7 }
        return max(7, Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 7)
    }

    private func receiptSummary(_ pack: RelatedPlaceSourcePack) -> String {
        let failedCount = pack.coverage.filter { $0.status == .failed }.count
        let candidateCount = pack.sources.count
        if failedCount > 0 {
            return languageSettings.localized(
                english: "\(candidateCount) candidates · \(pack.receipt.searchedPlatforms.count) platforms searched · \(failedCount) unavailable. Public-index coverage, not every post.",
                traditionalChinese: "\(candidateCount) 個候選 · 已搜尋 \(pack.receipt.searchedPlatforms.count) 個平台 · \(failedCount) 個無法使用。這是公開索引範圍，不是所有貼文。"
            )
        }
        return languageSettings.localized(
            english: "\(candidateCount) candidates · \(pack.receipt.searchedPlatforms.count) platforms searched. Public-index coverage, not every post.",
            traditionalChinese: "\(candidateCount) 個候選 · 已搜尋 \(pack.receipt.searchedPlatforms.count) 個平台。這是公開索引範圍，不是所有貼文。"
        )
    }
}

private struct RelatedPlaceSourceRow: View {
    @Environment(\.appLanguageSettings) private var languageSettings

    let source: RelatedPlaceSource
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(source.platform.displayName)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(SaveAtlasPalette.kraft.opacity(0.55))
                        .clipShape(Capsule())

                    Text(relationLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.saveCocoa)

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.saveCocoa)
                }

                Text(source.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                if let snippet = source.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.caption)
                        .foregroundColor(.saveMutedText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .saveAtlasPaper(radius: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(source.platform.displayName), \(source.title), \(relationLabel)")
        .accessibilityHint(languageSettings.localized(
            english: "Opens the public source. It will not save or change this Map Stamp.",
            traditionalChinese: "開啟公開來源，不會儲存或改動這個地圖章。"
        ))
    }

    private var relationLabel: String {
        switch source.relation {
        case .samePlace:
            return languageSettings.localized(
                english: "Likely same venue · Candidate",
                traditionalChinese: "可能是同一地點 · 候選"
            )
        case .mentionsPlace:
            return languageSettings.localized(
                english: "Mentions venue · Candidate",
                traditionalChinese: "提到此地點 · 候選"
            )
        }
    }
}

private struct RelatedSourceCoverageChip: View {
    let entry: RelatedSourceCoverage

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption2.weight(.bold))
            Text("\(entry.platform.displayName) \(entry.resultCount)")
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(.saveInk)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.64))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.platform.displayName), \(entry.status.rawValue), \(entry.resultCount) results")
    }

    private var statusIcon: String {
        switch entry.status {
        case .searched: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .searched: return SaveAtlasPalette.mint
        case .partial: return SaveAtlasPalette.honey
        case .failed: return .saveError.opacity(0.38)
        }
    }
}
