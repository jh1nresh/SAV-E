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

                PlaceMaatAnalysisPanel(
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

// MARK: - Ma'at Analysis

private struct PlaceMaatAnalysisPanel: View {
    let analysis: MaatPlaceAnalysisResponse?
    let isLoading: Bool
    let error: String?
    let languageSettings: AppLanguageSettings
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "scalemass.fill")
                    .foregroundColor(.saveCocoa)
                VStack(alignment: .leading, spacing: 2) {
                    Text(languageSettings.localized(english: "Ma'at analysis", traditionalChinese: "Ma'at 分析"))
                        .font(.headline.weight(.bold))
                        .foregroundColor(.saveInk)
                    Text(languageSettings.localized(
                        english: "Selected-place evidence only",
                        traditionalChinese: "只使用此地點的可引用證據"
                    ))
                    .font(.caption)
                    .foregroundColor(.saveMutedText)
                }
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                }
                .disabled(isLoading)
            }

            if let analysis {
                Text(analysis.summary)
                    .font(.subheadline)
                    .foregroundColor(.saveInk)
                    .fixedSize(horizontal: false, vertical: true)

                FlowLayout(spacing: 8) {
                    InfoChip(icon: "checkmark.seal", text: analysis.verdict.replacingOccurrences(of: "_", with: " "), color: .saveCocoa)
                    InfoChip(icon: "scope", text: analysis.analysisReceipt.inputScope.replacingOccurrences(of: "_", with: " "), color: .saveCocoa)
                    InfoChip(icon: "quote.bubble", text: "\(analysis.analysisReceipt.citedClaimCount) cited", color: .saveCocoa)
                }

                if let details = analysis.restaurantDetails {
                    MaatRestaurantDetailsView(details: details, languageSettings: languageSettings)
                }

                if !analysis.warnings.isEmpty {
                    Text(analysis.warnings.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.saveMutedText)
                }
            } else if let error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Text(languageSettings.localized(
                    english: "No server analysis loaded yet. Refresh after this place has notes, claims, source evidence, or receipts.",
                    traditionalChinese: "尚未載入伺服器分析。此地點有筆記、claims、來源或收據後可重新整理。"
                ))
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
}

private struct MaatRestaurantDetailsView: View {
    let details: MaatRestaurantDetails
    let languageSettings: AppLanguageSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !details.mustTry.isEmpty {
                detailSection(
                    title: languageSettings.localized(english: "What to order", traditionalChinese: "推薦餐點"),
                    icon: "fork.knife",
                    rows: details.mustTry.prefix(4).map { item in
                        MaatDetailRow(
                            title: item.name,
                            value: [item.price, item.description].compactMap(cleaned).joined(separator: " · ")
                        )
                    }
                )
            }

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
                        value: details.parking
                    ),
                    MaatDetailRow(
                        title: languageSettings.localized(english: "Reservation", traditionalChinese: "訂位"),
                        value: details.reservationTips
                    )
                ]
            )

            detailSection(
                title: languageSettings.localized(english: "Experience", traditionalChinese: "用餐體驗"),
                icon: "sparkles",
                rows: experienceRows
            )

            if !details.criticalReviews.isEmpty {
                detailSection(
                    title: languageSettings.localized(english: "Watch-outs", traditionalChinese: "注意事項"),
                    icon: "exclamationmark.triangle.fill",
                    rows: details.criticalReviews.prefix(3).map { review in
                        MaatDetailRow(
                            title: review.source ?? languageSettings.localized(english: "Saved evidence", traditionalChinese: "保存證據"),
                            value: review.issue
                        )
                    }
                )
            }

            if !details.evidenceGaps.isEmpty {
                Text(languageSettings.localized(
                    english: "Needs more evidence: \(details.evidenceGaps.map(gapLabel).joined(separator: ", "))",
                    traditionalChinese: "還需要更多證據：\(details.evidenceGaps.map(gapLabel).joined(separator: "、"))"
                ))
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveMutedText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var costRows: [MaatDetailRow] {
        var rows: [MaatDetailRow] = []
        if let priceRange = cleaned(details.priceRange) {
            rows.append(MaatDetailRow(title: languageSettings.localized(english: "Price", traditionalChinese: "價格"), value: priceRange))
        }
        if let avgCost = cleaned(details.avgCost) {
            rows.append(MaatDetailRow(title: languageSettings.localized(english: "Average", traditionalChinese: "人均"), value: avgCost))
        }
        rows += details.platformScores.prefix(2).map { score in
            MaatDetailRow(title: score.platform, value: String(format: "%.1f", score.score))
        }
        return rows
    }

    private var experienceRows: [MaatDetailRow] {
        var rows: [MaatDetailRow] = []
        if let ambiance = cleaned(details.ambiance) {
            rows.append(MaatDetailRow(title: languageSettings.localized(english: "Ambiance", traditionalChinese: "氛圍"), value: ambiance))
        }
        if let service = cleaned(details.serviceRating) {
            rows.append(MaatDetailRow(title: languageSettings.localized(english: "Service", traditionalChinese: "服務"), value: service))
        }
        if !details.bestFor.isEmpty {
            rows.append(MaatDetailRow(
                title: languageSettings.localized(english: "Best for", traditionalChinese: "適合"),
                value: details.bestFor.joined(separator: " · ")
            ))
        }
        return rows
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
