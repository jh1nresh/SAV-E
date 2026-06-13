import SwiftUI
import MapKit

struct PlaceDetailView: View {
    let place: Place
    var onDelete: (() async throws -> Void)?
    var onUpdateVisibility: ((PlaceVisibility) async throws -> Void)?
    @Environment(\.appLanguageSettings) private var languageSettings
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var enrichedPlace: Place?
    @State private var localVisibility: PlaceVisibility?
    @State private var maatAnalysis: MaatPlaceAnalysisResponse?
    @State private var maatAnalysisError: String?
    @State private var isLoadingMaatAnalysis = false

    private var detailPlace: Place {
        var value = enrichedPlace?.id == place.id ? enrichedPlace ?? place : place
        if let localVisibility {
            value.visibility = localVisibility
        }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                memoryHeader

                PlaceBusinessPhotoCarousel(imageURLs: detailPlace.businessPhotoURLStrings)
                    .padding(.horizontal)

                PlaceBasicInfoPanel(place: detailPlace)
                    .padding(.horizontal)

                PlaceInsightSummaryPanel(place: detailPlace, fallbackSummary: memorySummary)
                    .padding(.horizontal)

                SavePlaceInsightsPanel(
                    place: detailPlace,
                    analysis: maatAnalysis,
                    isLoading: isLoadingMaatAnalysis,
                    error: maatAnalysisError,
                    languageSettings: languageSettings
                ) {
                    Task { await loadMaatAnalysis(force: true) }
                }
                .padding(.horizontal)

                // Mini map
                Map(position: .constant(.region(MKCoordinateRegion(
                    center: detailPlace.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )))) {
                    Marker(detailPlace.name, coordinate: detailPlace.coordinate)
                        .tint(Color.categoryColor(for: detailPlace.category))
                }
                .frame(height: 160)
                .cornerRadius(16)
                .padding(.horizontal)

                HStack(spacing: 8) {
                    Button(action: { openInMaps() }) {
                        PlaceDetailActionLabel(
                            title: languageSettings.localized(english: "Maps", traditionalChinese: "地圖"),
                            systemImage: "map.fill",
                            fill: .saveHoney
                        )
                    }

                    SavePlaceShareButton(content: .place(detailPlace)) {
                        PlaceDetailActionLabel(
                            title: languageSettings.localized(english: "Share", traditionalChinese: "分享"),
                            systemImage: "square.and.arrow.up",
                            fill: Color.saveMint.opacity(0.36)
                        )
                    }

                    if let url = detailPlace.primarySourceURL {
                        Button(action: { openURL(url) }) {
                            PlaceDetailActionLabel(
                                title: languageSettings.localized(english: "Source", traditionalChinese: "來源"),
                                systemImage: "link",
                                fill: Color.saveSky.opacity(0.22)
                            )
                        }
                    }
                }
                .padding(.horizontal)

                if let deleteError {
                    Text(deleteError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 32)
        }
        .background(SaveDottedBackground())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: place.id) {
            await enrichBusinessDetails()
            await loadMaatAnalysis()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SavePlaceShareButton(content: .place(detailPlace)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }

            if onDelete != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .confirmationDialog(
            languageSettings.localized(english: "Delete \(detailPlace.name)?", traditionalChinese: "刪除「\(detailPlace.name)」？"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(languageSettings.localized(english: "Delete Place", traditionalChinese: "刪除地點"), role: .destructive) {
                Task { await deletePlace() }
            }
            Button(languageSettings.text(.cancel), role: .cancel) {}
        } message: {
            Text(languageSettings.localized(english: "This removes the Map Stamp from SAV-E.", traditionalChinese: "這會從 SAV-E 移除這個地圖章。"))
        }
    }

    private var memoryHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                SaveMemoryBadge(state: .saved(detailPlace.category), size: 62)

                VStack(alignment: .leading, spacing: 6) {
                    Text(detailPlace.status.memoryCardLabel(language: languageSettings.language).uppercased())
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveCocoa)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(detailPlace.status == .visited ? Color.saveMint : Color.saveHoney.opacity(0.56))
                        .clipShape(Capsule())

                    Text(detailPlace.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.saveInk)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        PlatformIcon(platform: detailPlace.sourcePlatform, size: 14)
                        Text(detailPlace.sourceConfirmationLabel(language: languageSettings.language))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.saveCocoa)
                    }

                    FlowLayout(spacing: 8) {
                        CategoryPill(category: detailPlace.category, isSelected: true)
                        ForEach(detailPlace.verificationChips(language: languageSettings.language), id: \.text) { chip in
                            InfoChip(icon: chip.icon, text: chip.text, color: .saveCocoa)
                        }
                    }
                }
            }

            Text(memorySummary)
                .font(.subheadline)
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(detailPlace.address)
                .font(.subheadline)
                .foregroundColor(.saveMutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.saveNotebookPage
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.88), lineWidth: 1.2)
        )
        .padding(.horizontal)
    }

    private func openInMaps() {
        SaveHaptics.tap()
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: detailPlace.coordinate))
        mapItem.name = detailPlace.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func updateVisibility(_ visibility: PlaceVisibility) async throws {
        try await onUpdateVisibility?(visibility)
        localVisibility = visibility
    }

    private var memorySummary: String {
        detailPlace.memorySummary(language: languageSettings.language)
    }

    private func enrichBusinessDetails() async {
        guard detailPlace.businessPhotoURLStrings.count < 2 ||
                detailPlace.googleRating == nil ||
                detailPlace.priceRange == nil ||
                detailPlace.openingHours == nil
        else { return }
        guard let update = await businessDetails(for: detailPlace) else { return }
        guard place.id == detailPlace.id else { return }

        var updatedPlace = detailPlace
        if !update.photoURLs.isEmpty {
            let urls = update.photoURLs.map(\.absoluteString)
            updatedPlace.sourceImageUrl = updatedPlace.sourceImageUrl ?? urls.first
            updatedPlace.businessPhotoUrls = urls
        }
        updatedPlace.googleRating = updatedPlace.googleRating ?? update.rating
        updatedPlace.priceRange = updatedPlace.priceRange ?? update.priceRange
        updatedPlace.openingHours = updatedPlace.openingHours ?? update.openingHours
        enrichedPlace = updatedPlace
    }

    private func loadMaatAnalysis(force: Bool = false) async {
        guard force || maatAnalysis == nil else { return }
        isLoadingMaatAnalysis = true
        maatAnalysisError = nil
        defer { isLoadingMaatAnalysis = false }

        do {
            maatAnalysis = try await SupabaseService.shared.fetchPlaceMaatAnalysis(
                for: detailPlace.id,
                includePrivateEvidence: false
            )
        } catch SupabaseError.notConfigured {
            maatAnalysis = nil
        } catch {
            maatAnalysisError = error.localizedDescription
        }
    }

    private func businessDetails(for place: Place) async -> (photoURLs: [URL], rating: Double?, priceRange: String?, openingHours: String?)? {
        let service = GooglePlacesService.shared
        let details: GooglePlaceDetails?
        let fallbackMatch: GooglePlaceMatch?
        if let googlePlaceId = place.googlePlaceId {
            details = try? await service.getPlaceDetails(placeId: googlePlaceId)
            fallbackMatch = nil
        } else {
            guard let match = await bestGoogleMatch(for: place, service: service) else { return nil }
            details = try? await service.getPlaceDetails(placeId: match.id)
            fallbackMatch = match
        }

        let photoReferences = details?.photoReferences?.isEmpty == false
            ? details?.photoReferences ?? []
            : [fallbackMatch?.photoReference].compactMap { $0 }
        let photoURLs = photoReferences
            .prefix(6)
            .compactMap { service.photoURL(reference: $0, maxWidth: 900) }
        let priceLevel = details?.priceLevel ?? fallbackMatch?.priceLevel
        let hasDetails = !photoURLs.isEmpty ||
            details?.rating != nil ||
            fallbackMatch?.rating != nil ||
            priceLevel != nil ||
            details?.openingHours?.isEmpty == false
        guard hasDetails else { return nil }

        return (
            photoURLs,
            details?.rating ?? fallbackMatch?.rating,
            priceLevel.map { String(repeating: "$", count: max(1, $0)) },
            details?.openingHours?.first
        )
    }

    private func bestGoogleMatch(for place: Place, service: GooglePlacesServiceProtocol) async -> GooglePlaceMatch? {
        do {
            let matches = try await service.searchPlace(
                query: "\(place.name) \(place.address)",
                near: place.coordinate
            )
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            return matches.first { match in
                let matchLocation = CLLocation(latitude: match.latitude, longitude: match.longitude)
                let sameArea = placeLocation.distance(from: matchLocation) < 250
                let sameName = match.name.localizedCaseInsensitiveContains(place.name) ||
                    place.name.localizedCaseInsensitiveContains(match.name)
                return sameArea || sameName
            }
        } catch {
            return nil
        }
    }

    private func deletePlace() async {
        guard let onDelete else { return }
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }

        do {
            try await onDelete()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

// MARK: - SAV-E Place Insights

struct SavePlaceInsightsPanel: View {
    let place: Place
    let analysis: MaatPlaceAnalysisResponse?
    let isLoading: Bool
    let error: String?
    let languageSettings: AppLanguageSettings
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundColor(.saveCocoa)
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageSettings.localized(english: "SAV-E place details", traditionalChinese: "SAV-E 地點詳情"))
                        .font(.headline.weight(.bold))
                        .foregroundColor(.saveInk)
                    Text(scopeSubtitle)
                    .font(.caption)
                    .foregroundColor(.saveMutedText)
                }
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                }
                .disabled(isLoading)
            }

            Text(summaryText)
                .font(.subheadline)
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)

            if let analysis {
                FlowLayout(spacing: 8) {
                    InfoChip(icon: "checkmark.seal", text: analysis.verdict.replacingOccurrences(of: "_", with: " "), color: .saveCocoa)
                    InfoChip(icon: "scope", text: analysis.analysisReceipt.inputScope.replacingOccurrences(of: "_", with: " "), color: .saveCocoa)
                    InfoChip(icon: "quote.bubble", text: "\(analysis.analysisReceipt.citedClaimCount) cited", color: .saveCocoa)
                }
            }

            SaveRestaurantDetailsView(
                place: place,
                details: analysis?.restaurantDetails,
                citedEvidence: analysis?.citedEvidence ?? [],
                languageSettings: languageSettings
            )

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if let analysis, !analysis.warnings.isEmpty {
                Text(analysis.warnings.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.saveMutedText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.saveNotebookPage.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.72), lineWidth: 1)
        )
    }

    private var summaryText: String {
        if let analysis {
            return analysis.summary
        }
        if isLoading {
            return languageSettings.localized(
                english: "SAV-E is checking saved evidence and public place context. Showing what is already known.",
                traditionalChinese: "SAV-E 正在檢查已保存證據與公開地點資訊。先顯示目前已知內容。"
            )
        }
        return languageSettings.localized(
            english: "SAV-E can still show saved place details here, and will mark missing fields as evidence gaps.",
            traditionalChinese: "SAV-E 會先顯示已保存的地點詳情，缺少的欄位會標成證據缺口。"
        )
    }

    private var scopeSubtitle: String {
        if analysis?.analysisReceipt.publicWebUsed == true {
            return languageSettings.localized(
                english: "Saved place + public web evidence",
                traditionalChinese: "保存地點 + 公開網路證據"
            )
        }

        return languageSettings.localized(
            english: "Saved place evidence first",
            traditionalChinese: "優先使用此地點保存證據"
        )
    }
}

private struct SaveRestaurantDetailsView: View {
    let place: Place
    let details: MaatRestaurantDetails?
    let citedEvidence: [String]
    let languageSettings: AppLanguageSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailSection(
                title: languageSettings.localized(english: "What to order", traditionalChinese: "推薦餐點"),
                icon: "fork.knife",
                rows: recommendationRows
            )

            detailSection(
                title: languageSettings.localized(english: "Cost and score", traditionalChinese: "消費與評分"),
                icon: "tag.fill",
                rows: costRows
            )

            detailSection(
                title: languageSettings.localized(english: "Logistics", traditionalChinese: "停車與訂位"),
                icon: "car.fill",
                rows: [
                    MaatDetailRow(
                        title: languageSettings.localized(english: "Parking", traditionalChinese: "停車"),
                        value: cleaned(details?.parking) ?? missingEvidenceText
                    ),
                    MaatDetailRow(
                        title: languageSettings.localized(english: "Reservation", traditionalChinese: "訂位"),
                        value: cleaned(details?.reservationTips) ?? missingEvidenceText
                    )
                ]
            )

            detailSection(
                title: languageSettings.localized(english: "Experience", traditionalChinese: "用餐體驗"),
                icon: "sparkles",
                rows: experienceRows
            )

            detailSection(
                title: languageSettings.localized(english: "Watch-outs", traditionalChinese: "注意事項"),
                icon: "exclamationmark.triangle.fill",
                rows: watchOutRows
            )

            detailSection(
                title: languageSettings.localized(english: "Evidence gaps", traditionalChinese: "證據缺口"),
                icon: "questionmark.circle.fill",
                rows: evidenceGapRows
            )

            relatedReelsSection
        }
    }

    private var recommendationRows: [MaatDetailRow] {
        if let mustTry = details?.mustTry, !mustTry.isEmpty {
            return mustTry.prefix(4).map { item in
                MaatDetailRow(
                    title: item.name,
                    value: [item.price, item.description].compactMap(cleaned).joined(separator: " · ")
                )
            }
        }

        let savedItems = place.savedRecommendedItems
        if !savedItems.isEmpty {
            return savedItems.prefix(4).map { item in
                MaatDetailRow(title: item.name, value: cleaned(item.price))
            }
        }

        return [MaatDetailRow(
            title: languageSettings.localized(english: "Needs evidence", traditionalChinese: "需要證據"),
            value: missingEvidenceText
        )]
    }

    private var costRows: [MaatDetailRow] {
        var rows: [MaatDetailRow] = [
            MaatDetailRow(
                title: languageSettings.localized(english: "Price", traditionalChinese: "價格"),
                value: cleaned(details?.priceRange) ?? cleaned(place.priceRange) ?? missingEvidenceText
            )
        ]

        if let avgCost = cleaned(details?.avgCost) {
            rows.append(MaatDetailRow(title: languageSettings.localized(english: "Average", traditionalChinese: "人均"), value: avgCost))
        }

        rows += (details?.platformScores ?? []).prefix(2).map { score in
            MaatDetailRow(title: score.platform, value: String(format: "%.1f", score.score))
        }

        if let rating = place.googleRating ?? place.rating,
           !(details?.platformScores.contains(where: { $0.platform.localizedCaseInsensitiveContains("google") }) ?? false) {
            rows.append(MaatDetailRow(title: "Google", value: String(format: "%.1f", rating)))
        }

        return rows
    }

    private var experienceRows: [MaatDetailRow] {
        var rows: [MaatDetailRow] = []
        if let ambiance = cleaned(details?.ambiance) {
            rows.append(MaatDetailRow(title: languageSettings.localized(english: "Ambiance", traditionalChinese: "氛圍"), value: ambiance))
        }
        if let service = cleaned(details?.serviceRating) {
            rows.append(MaatDetailRow(title: languageSettings.localized(english: "Service", traditionalChinese: "服務"), value: service))
        }
        let bestFor = details?.bestFor ?? []
        if !bestFor.isEmpty {
            rows.append(MaatDetailRow(
                title: languageSettings.localized(english: "Best for", traditionalChinese: "適合"),
                value: bestFor.joined(separator: " · ")
            ))
        }
        if rows.isEmpty {
            rows.append(MaatDetailRow(
                title: languageSettings.localized(english: "Needs evidence", traditionalChinese: "需要證據"),
                value: missingEvidenceText
            ))
        }
        return rows
    }

    private var watchOutRows: [MaatDetailRow] {
        if let reviews = details?.criticalReviews, !reviews.isEmpty {
            return reviews.prefix(3).map { review in
                MaatDetailRow(
                    title: review.source ?? languageSettings.localized(english: "Saved evidence", traditionalChinese: "保存證據"),
                    value: review.issue
                )
            }
        }

        let warnings = details?.warnings ?? []
        if !warnings.isEmpty {
            return warnings.prefix(3).map { warning in
                MaatDetailRow(
                    title: languageSettings.localized(english: "Warning", traditionalChinese: "提醒"),
                    value: warning.replacingOccurrences(of: "_", with: " ")
                )
            }
        }

        return [MaatDetailRow(
            title: languageSettings.localized(english: "Needs evidence", traditionalChinese: "需要證據"),
            value: languageSettings.localized(english: "No wait, service, closure, or crowd warning evidence yet.", traditionalChinese: "尚未有等待、服務、停業或人潮注意事項證據。")
        )]
    }

    private var evidenceGapRows: [MaatDetailRow] {
        let gaps = computedEvidenceGaps
        guard !gaps.isEmpty else {
            return [MaatDetailRow(
                title: languageSettings.localized(english: "Ready", traditionalChinese: "已補齊"),
                value: languageSettings.localized(english: "SAV-E has enough detail evidence for this view.", traditionalChinese: "SAV-E 已有足夠地點詳情證據。")
            )]
        }
        return gaps.map { gap in
            MaatDetailRow(
                title: gapLabel(gap),
                value: languageSettings.localized(english: "Needs one more reliable source.", traditionalChinese: "需要再補一個可靠來源。")
            )
        }
    }

    private var computedEvidenceGaps: [String] {
        var gaps = details?.evidenceGaps ?? []
        if details?.mustTry.isEmpty != false && place.savedRecommendedItems.isEmpty {
            gaps.append("recommended_dishes")
        }
        if cleaned(details?.priceRange) == nil && cleaned(details?.avgCost) == nil && cleaned(place.priceRange) == nil {
            gaps.append("cost")
        }
        if cleaned(details?.parking) == nil {
            gaps.append("parking")
        }
        if cleaned(details?.reservationTips) == nil {
            gaps.append("reservation_tips")
        }
        if relatedReelLinks.isEmpty {
            gaps.append("related_reels")
        }
        var seen = Set<String>()
        return gaps.filter { seen.insert($0).inserted }
    }

    @ViewBuilder
    private var relatedReelsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(languageSettings.localized(english: "Related reels", traditionalChinese: "相關 Reels"), systemImage: "play.rectangle.fill")
                .font(.caption.weight(.black))
                .foregroundColor(.saveCocoa)

            if relatedReelLinks.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text(languageSettings.localized(english: "Needs evidence", traditionalChinese: "需要證據"))
                        .font(.caption.weight(.bold))
                        .foregroundColor(.saveInk)
                        .frame(width: 86, alignment: .leading)
                    Text(languageSettings.localized(english: "No Instagram Reel source is linked to this place yet.", traditionalChinese: "這個地點尚未連到 Instagram Reel 來源。"))
                        .font(.caption)
                        .foregroundColor(.saveMutedText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(relatedReelLinks) { link in
                        Link(destination: link.url) {
                            Label(link.title, systemImage: "play.rectangle.fill")
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.saveHoney.opacity(0.34))
                                .foregroundColor(.saveInk)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.56), lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.saveNotebookPage.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.42), lineWidth: 1)
        )
    }

    private var relatedReelLinks: [SaveRelatedReelLink] {
        SaveRelatedReelLink.extract(from: place.sourceEvidence + citedEvidence)
    }

    private var missingEvidenceText: String {
        languageSettings.localized(english: "Not enough saved or public evidence yet.", traditionalChinese: "目前保存或公開證據還不夠。")
    }

    private func detailSection(title: String, icon: String, rows: [MaatDetailRow]) -> some View {
        let visibleRows = rows.filter { cleaned($0.value) != nil }
        return Group {
            if !visibleRows.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Label(title, systemImage: icon)
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveCocoa)

                    ForEach(visibleRows) { row in
                        HStack(alignment: .top, spacing: 8) {
                            Text(row.title)
                                .font(.caption.weight(.bold))
                                .foregroundColor(.saveInk)
                                .frame(width: 86, alignment: .leading)
                            Text(row.value ?? "")
                                .font(.caption)
                                .foregroundColor(.saveMutedText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(10)
                .background(Color.saveNotebookPage.opacity(0.56))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.saveNotebookLine.opacity(0.42), lineWidth: 1)
                )
            }
        }
    }

    private func gapLabel(_ value: String) -> String {
        switch value {
        case "recommended_dishes":
            return languageSettings.localized(english: "recommended dishes", traditionalChinese: "推薦餐點")
        case "parking":
            return languageSettings.localized(english: "parking", traditionalChinese: "停車")
        case "reservation_tips":
            return languageSettings.localized(english: "reservation tips", traditionalChinese: "訂位建議")
        case "cost":
            return languageSettings.localized(english: "cost", traditionalChinese: "消費")
        case "related_reels":
            return languageSettings.localized(english: "related reels", traditionalChinese: "相關 Reels")
        default:
            return value.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func cleaned(_ value: String?) -> String? {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}

private struct MaatDetailRow: Identifiable {
    let id = UUID()
    let title: String
    let value: String?
}

private struct SaveRelatedReelLink: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL

    static func extract(from evidence: [String]) -> [SaveRelatedReelLink] {
        var links: [SaveRelatedReelLink] = []
        var seen = Set<String>()

        for text in evidence {
            for url in urls(in: text) where isInstagramReel(url) {
                let key = normalizedKey(url)
                guard seen.insert(key).inserted else { continue }
                links.append(SaveRelatedReelLink(
                    id: key,
                    title: "Instagram Reel",
                    url: url
                ))
            }
        }

        return Array(links.prefix(4))
    }

    private static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector
            .matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .filter { url in
                guard let scheme = url.scheme?.lowercased() else { return false }
                return scheme == "http" || scheme == "https"
            }
    }

    private static func isInstagramReel(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased(),
              host.hasSuffix("instagram.com")
        else { return false }
        let path = url.path(percentEncoded: false).lowercased()
        return path.contains("/reel/") || path.contains("/reels/")
    }

    private static func normalizedKey(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
}

// MARK: - Info Chip

struct InfoChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.saveNotebookPage)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.38), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        PlaceDetailView(place: .mock)
    }
    .environment(\.appLanguageSettings, AppLanguageSettings())
}
