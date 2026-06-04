import SwiftUI

struct PlaceBottomSheet: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let place: Place
    var onDelete: (() async throws -> Void)?
    var onPlanAround: (() -> Void)?
    var onUpdateVisibility: ((PlaceVisibility) async throws -> Void)?
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                SaveMemoryBadge(state: .saved(place.category), size: 52)

                VStack(alignment: .leading, spacing: 6) {
                    Text(place.status.memoryCardLabel(language: languageSettings.language).uppercased())
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveCocoa)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(place.status == .visited ? Color.saveMint : Color.saveHoney.opacity(0.64))
                        .clipShape(Capsule())

                    Text(place.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.saveInk)

                    Text(place.address)
                        .font(.subheadline)
                        .foregroundColor(.saveMutedText)
                }

                Spacer()

                Menu {
                    SavePlaceShareButton(content: .place(place)) {
                        Label(languageSettings.localized(english: "Share", traditionalChinese: "分享"), systemImage: "square.and.arrow.up")
                    }

                    if let sourceURL = place.primarySourceURL {
                        Button {
                            openURL(sourceURL)
                        } label: {
                            Label(languageSettings.localized(english: "View source", traditionalChinese: "查看來源"), systemImage: "link")
                        }
                    }

                    if onDelete != nil {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label(languageSettings.localized(english: "Delete", traditionalChinese: "刪除"), systemImage: "trash")
                        }
                    }
                } label: {
                    SaveIconTile(
                        systemName: "ellipsis",
                        size: 36,
                        fill: Color.saveNotebookPage.opacity(0.72),
                        foreground: .saveInk,
                        strokeOpacity: 0.62,
                        cornerRadius: 12
                    )
                }
            }

            PlaceBusinessPhotoCarousel(imageURLs: place.businessPhotoURLStrings)

            PlaceBasicInfoPanel(place: place)
            PlaceInsightSummaryPanel(place: place, fallbackSummary: memorySummary)
            PlaceVisibilityControl(
                visibility: place.effectiveVisibility,
                onChange: onUpdateVisibility
            )
            PlaceProofPlaceholderCard()

            FlowLayout(spacing: 8) {
                CategoryPill(category: place.category, isSelected: true)
                if let rating = place.googleRating {
                    PlaceMemoryChip(icon: "star.fill", text: String(format: "%.1f", rating))
                }
                if let priceRange = place.priceRange {
                    PlaceMemoryChip(icon: "tag.fill", text: priceRange)
                }
                ForEach(verificationChips, id: \.text) { chip in
                    PlaceMemoryChip(icon: chip.icon, text: chip.text)
                }
            }

            // Dishes
            if let dishes = place.extractedDishes, !dishes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(languageSettings.localized(english: "Recommended", traditionalChinese: "推薦"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.saveMutedText)

                    FlowLayout(spacing: 6) {
                        ForEach(dishes, id: \.self) { dish in
                            Text(dish)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .foregroundColor(.saveInk)
                                .background(Color.saveHoney.opacity(0.30))
                                .cornerRadius(12)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    onPlanAround?()
                } label: {
                    PlaceDetailActionLabel(
                        title: languageSettings.localized(english: "Order?", traditionalChinese: "點餐？"),
                        systemImage: "fork.knife",
                        fill: .saveHoney
                    )
                }
                .disabled(onPlanAround == nil)
                .opacity(onPlanAround == nil ? 0.55 : 1)

                Button {
                    NavigationService.navigate(to: place.coordinate, name: place.name)
                } label: {
                    PlaceDetailActionLabel(
                        title: languageSettings.localized(english: "Maps", traditionalChinese: "地圖"),
                        systemImage: "map.fill",
                        fill: Color.saveMint.opacity(0.36)
                    )
                }

                SavePlaceShareButton(content: .place(place)) {
                    PlaceDetailActionLabel(
                        title: languageSettings.localized(english: "Share", traditionalChinese: "分享"),
                        systemImage: "square.and.arrow.up",
                        fill: Color.saveNotebookPage
                    )
                }

                if let sourceURL = place.primarySourceURL {
                    Button {
                        openURL(sourceURL)
                    } label: {
                        PlaceDetailActionLabel(
                            title: languageSettings.localized(english: "Source", traditionalChinese: "來源"),
                            systemImage: "link",
                            fill: Color.saveSky.opacity(0.22)
                        )
                    }
                }
            }

            if let deleteError {
                Text(deleteError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(PlaceDetailGlassBackground(colorScheme: colorScheme))
        .confirmationDialog(
            languageSettings.localized(english: "Delete \(place.name)?", traditionalChinese: "刪除「\(place.name)」？"),
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

    private func deletePlace() async {
        guard let onDelete else { return }
        isDeleting = true
        deleteError = nil
        defer { isDeleting = false }

        do {
            try await onDelete()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private var sourceConfirmationLabel: String {
        place.sourceConfirmationLabel(language: languageSettings.language)
    }

    private var verificationChips: [PlaceVerificationChip] {
        place.verificationChips(language: languageSettings.language, sourceLabel: sourceConfirmationLabel)
    }

    private var memorySummary: String {
        place.memorySummary(language: languageSettings.language)
    }

}

struct PlaceVisibilityControl: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let visibility: PlaceVisibility
    var onChange: ((PlaceVisibility) async throws -> Void)?
    @State private var selectedVisibility: PlaceVisibility
    @State private var isUpdating = false
    @State private var errorMessage: String?

    init(
        visibility: PlaceVisibility,
        onChange: ((PlaceVisibility) async throws -> Void)? = nil
    ) {
        self.visibility = visibility
        self.onChange = onChange
        _selectedVisibility = State(initialValue: visibility)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.caption.weight(.black))
                Text(languageSettings.localized(english: "Social visibility", traditionalChinese: "社交可見度"))
                    .font(.caption.weight(.black))
                Spacer()
                if isUpdating {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .foregroundColor(.saveCocoa)

            VStack(spacing: 7) {
                ForEach(PlaceVisibility.allCases, id: \.self) { option in
                    Button {
                        Task { await update(option) }
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: option.systemImage)
                                .font(.caption.weight(.black))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName(language: languageSettings.language))
                                    .font(.caption.weight(.black))
                                Text(option.detailText(language: languageSettings.language))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.saveCocoa.opacity(0.72))
                                    .lineLimit(2)
                            }
                            Spacer()
                            if selectedVisibility == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.saveSignal)
                            }
                        }
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(selectedVisibility == option ? Color.saveHoney.opacity(0.34) : Color.saveNotebookPage.opacity(0.44))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.saveNotebookLine.opacity(selectedVisibility == option ? 0.62 : 0.28), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(onChange == nil || isUpdating)
                    .opacity(onChange == nil ? 0.62 : 1)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.red)
            }
        }
        .padding(10)
        .saveNotebookSurface(cornerRadius: 12, fill: .saveNotebookPage, opacity: 0.64)
        .onChange(of: visibility) { _, value in
            selectedVisibility = value
        }
    }

    private func update(_ option: PlaceVisibility) async {
        guard option != selectedVisibility, let onChange else { return }
        let previous = selectedVisibility
        selectedVisibility = option
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }

        do {
            try await onChange(option)
        } catch {
            selectedVisibility = previous
            errorMessage = error.localizedDescription
        }
    }
}

private struct PlaceDetailGlassBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(colorScheme == .dark ? Color.saveNotebookPage.opacity(0.88) : Color.saveNotebookPage.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.saveNotebookLine.opacity(colorScheme == .dark ? 0.42 : 0.52), lineWidth: 1.2)
            )
    }
}

struct PlaceBasicInfoPanel: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption.weight(.black))
                Text(languageSettings.localized(english: "Basic info", traditionalChinese: "基本資訊"))
                    .font(.caption.weight(.black))
                Spacer()
            }
            .foregroundColor(.saveCocoa)

            VStack(spacing: 7) {
                PlaceInfoRow(icon: "star", title: languageSettings.localized(english: "Rating", traditionalChinese: "評分"), value: ratingText)
                if let reviewCountText {
                    PlaceInfoRow(icon: "text.bubble", title: languageSettings.localized(english: "Reviews", traditionalChinese: "評論"), value: reviewCountText)
                }
                PlaceInfoRow(icon: place.category.detailIconName, title: languageSettings.localized(english: "Category", traditionalChinese: "分類"), value: place.category.displayName(language: languageSettings.language))
                PlaceInfoRow(icon: "mappin", title: languageSettings.localized(english: "Address", traditionalChinese: "地址"), value: place.address.isEmpty ? languageSettings.localized(english: "No address saved", traditionalChinese: "尚未保存地址") : place.address)
                PlaceInfoRow(icon: "link", title: languageSettings.localized(english: "Source", traditionalChinese: "來源"), value: place.sourceConfirmationLabel(language: languageSettings.language))
                if let priceRange = place.priceRange {
                    PlaceInfoRow(icon: "tag", title: languageSettings.localized(english: "Price", traditionalChinese: "價格"), value: priceRange)
                }
                if let openingHours = place.openingHours?.trimmingCharacters(in: .whitespacesAndNewlines), !openingHours.isEmpty {
                    PlaceInfoRow(icon: "clock", title: languageSettings.localized(english: "Hours", traditionalChinese: "營業時間"), value: openingHours)
                }
            }
        }
        .padding(10)
        .saveNotebookSurface(cornerRadius: 12, fill: .saveNotebookPage, opacity: 0.64)
    }

    private var ratingText: String {
        if let rating = place.googleRating ?? place.rating {
            return String(format: "%.1f", rating)
        }
        return languageSettings.localized(english: "No rating yet", traditionalChinese: "尚無評分")
    }

    private var reviewCountText: String? {
        for line in place.sourceEvidence {
            let prefix = "External reviews:"
            guard line.localizedCaseInsensitiveContains(prefix) else { continue }
            let value = line
                .replacingOccurrences(of: prefix, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            return languageSettings.localized(english: "\(value) reviews", traditionalChinese: "\(value) 則評論")
        }
        return nil
    }
}

private struct PlaceInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SaveIconTile(
                systemName: icon,
                size: 22,
                iconSize: 10,
                fill: Color.saveCream.opacity(0.74),
                foreground: .saveCocoa,
                strokeOpacity: 0.54
            )
            .padding(.top, 1)

            Text(title)
                .font(.caption2.weight(.black))
                .foregroundColor(.saveCocoa)
                .frame(width: 58, alignment: .leading)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

private struct PlaceProofPlaceholderCard: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal")
                    .font(.caption.weight(.black))
                Text(languageSettings.localized(english: "Real-world proof", traditionalChinese: "真實憑證"))
                    .font(.caption.weight(.black))
                Spacer()
            }
            .foregroundColor(.saveCocoa)

            Text(languageSettings.localized(
                english: "Proof-backed visits will require a receipt, original photo, or location evidence attached by you. Public map details and self-marked Visited status do not count as proof.",
                traditionalChinese: "有憑證的去過紀錄會需要你附上的收據、原始照片或定位證據。公開地圖資料和自行標記的去過不算憑證。"
            ))
                .font(.caption2.weight(.semibold))
                .foregroundColor(.saveCocoa.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)

            Button {} label: {
                Label(languageSettings.localized(english: "Add proof", traditionalChinese: "新增憑證"), systemImage: "plus.circle")
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveCocoa.opacity(0.74))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.saveNotebookPage.opacity(0.48))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.saveNotebookLine.opacity(0.46), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityHint(languageSettings.localized(english: "Proof attachments are not available yet.", traditionalChinese: "憑證附件功能尚未開放。"))
        }
        .padding(10)
        .saveNotebookSurface(cornerRadius: 12, fill: .saveNotebookPage, opacity: 0.56)
    }
}

private extension PlaceCategory {
    var detailIconName: String {
        switch self {
        case .food: return "fork.knife"
        case .cafe: return "cup.and.saucer"
        case .bar: return "wineglass"
        case .attraction: return "star"
        case .stay: return "bed.double"
        case .shopping: return "bag"
        }
    }
}

private struct PlaceMemoryChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.black))
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundColor(.saveCocoa)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.saveNotebookPage.opacity(0.50))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.34), lineWidth: 1))
    }
}

struct PlaceVerificationChip: Hashable {
    let icon: String
    let text: String
}

extension Place {
    var sourceConfirmationLabel: String {
        if primarySourceURL?.host(percentEncoded: false)?.localizedCaseInsensitiveContains("maps.apple.com") == true {
            return "Found on Apple Maps"
        }
        if primarySourceURL?.host(percentEncoded: false)?.localizedCaseInsensitiveContains("google") == true ||
            sourcePlatform == .googleMaps {
            return googlePlaceId == nil ? "Found on Google Maps" : "Google Places details"
        }
        if sourcePlatform != .other {
            return "Found on \(sourcePlatform.displayName)"
        }
        if googlePlaceId != nil {
            return "Google Places details"
        }
        return "Source saved"
    }

    func sourceConfirmationLabel(language: AppLanguage) -> String {
        if primarySourceURL?.host(percentEncoded: false)?.localizedCaseInsensitiveContains("maps.apple.com") == true {
            return language.localized(english: "Found on Apple Maps", traditionalChinese: "來自 Apple Maps")
        }
        if primarySourceURL?.host(percentEncoded: false)?.localizedCaseInsensitiveContains("google") == true ||
            sourcePlatform == .googleMaps {
            return googlePlaceId == nil
                ? language.localized(english: "Found on Google Maps", traditionalChinese: "來自 Google Maps")
                : language.localized(english: "Google Places details", traditionalChinese: "Google Places 詳細資料")
        }
        if sourcePlatform != .other {
            return language.localized(english: "Found on \(sourcePlatform.displayName)", traditionalChinese: "來自 \(sourcePlatform.displayName)")
        }
        if googlePlaceId != nil {
            return language.localized(english: "Google Places details", traditionalChinese: "Google Places 詳細資料")
        }
        return language.localized(english: "Source saved", traditionalChinese: "已保存來源")
    }

    var cleanMemoryNote: String? {
        guard let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return nil
        }
        let cleanedLines = note
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                let normalizedLine = line.normalizedSummaryText
                let metadataPrefixes = ["source:", "category:", "rating:", "reviews:", "hours:", "address:"]
                return !line.localizedCaseInsensitiveContains("Source URL:") &&
                !line.localizedCaseInsensitiveContains("Analysis pipeline:") &&
                !line.localizedCaseInsensitiveContains("Evidence tier:") &&
                !line.localizedCaseInsensitiveContains("Apple Maps POI") &&
                !line.localizedCaseInsensitiveContains("Apple Maps result") &&
                !line.localizedCaseInsensitiveContains("POI:") &&
                !line.localizedCaseInsensitiveContains("MKPOICategory") &&
                !line.localizedCaseInsensitiveContains("Business photo: Google Places") &&
                !line.localizedCaseInsensitiveContains("External reviews:") &&
                !line.localizedCaseInsensitiveContains("Venue name:") &&
                !line.localizedCaseInsensitiveContains("Address clue:") &&
                !line.localizedCaseInsensitiveContains("Source saved") &&
                !line.localizedCaseInsensitiveContains("citiesmemory") &&
                !line.localizedCaseInsensitiveContains("Public rating") &&
                !metadataPrefixes.contains { normalizedLine.hasPrefix($0) } &&
                normalizedLine != name.normalizedSummaryText &&
                normalizedLine != address.normalizedSummaryText
            }
        guard !cleanedLines.isEmpty else { return nil }
        return cleanedLines.joined(separator: "\n")
    }

    func verificationChips(sourceLabel: String? = nil) -> [PlaceVerificationChip] {
        var chips: [PlaceVerificationChip] = []
        if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chips.append(PlaceVerificationChip(icon: "mappin.and.ellipse", text: "Address saved"))
        }
        chips.append(PlaceVerificationChip(icon: "link", text: sourceLabel ?? sourceConfirmationLabel))
        if googlePlaceId != nil || googleRating != nil || googlePriceLevel != nil || openingHours != nil {
            chips.append(PlaceVerificationChip(icon: "building.2.fill", text: "Google Places details"))
        }
        return chips
    }

    func verificationChips(language: AppLanguage, sourceLabel: String? = nil) -> [PlaceVerificationChip] {
        var chips: [PlaceVerificationChip] = []
        if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chips.append(PlaceVerificationChip(
                icon: "mappin.and.ellipse",
                text: language.localized(english: "Address saved", traditionalChinese: "已保存地址")
            ))
        }
        chips.append(PlaceVerificationChip(icon: "link", text: sourceLabel ?? sourceConfirmationLabel(language: language)))
        if googlePlaceId != nil || googleRating != nil || googlePriceLevel != nil || openingHours != nil {
            chips.append(PlaceVerificationChip(
                icon: "building.2.fill",
                text: language.localized(english: "Google Places details", traditionalChinese: "Google Places 詳細資料")
            ))
        }
        return chips
    }

    var memorySummary: String {
        if let note = cleanMemoryNote {
            return note
        }
        if let dishes = extractedDishes, !dishes.isEmpty {
            return "Saved for \(dishes.prefix(3).joined(separator: ", "))."
        }
        if let recommender = recommender?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommender.isEmpty {
            return "Recommended by \(recommender)."
        }
        switch status {
        case .visited:
            return "Marked visited in SAV-E."
        case .wantToGo:
            return "Saved as a place to try."
        }
    }

    func memorySummary(language: AppLanguage) -> String {
        if let note = cleanMemoryNote {
            return note
        }
        if let dishes = extractedDishes, !dishes.isEmpty {
            return language.localized(
                english: "Saved for \(dishes.prefix(3).joined(separator: ", ")).",
                traditionalChinese: "為了 \(dishes.prefix(3).joined(separator: "、")) 存下。"
            )
        }
        if let recommender = recommender?.trimmingCharacters(in: .whitespacesAndNewlines),
           !recommender.isEmpty {
            return language.localized(english: "Recommended by \(recommender).", traditionalChinese: "\(recommender) 推薦。")
        }
        switch status {
        case .visited:
            return language.localized(english: "Marked visited in SAV-E.", traditionalChinese: "已在 SAV-E 標記為去過。")
        case .wantToGo:
            return language.localized(english: "Saved as a place to try.", traditionalChinese: "已存成想找時間去的地點。")
        }
    }
}

private extension String {
    var normalizedSummaryText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

// MARK: - Simple Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(subviews: subviews, proposal: proposal)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, proposal: proposal)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(subviews: Subviews, proposal: ProposedViewSize) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalHeight = y + rowHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}

struct PlaceDetailActionLabel: View {
    var title: String
    var systemImage: String
    var fill: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.black))
            .foregroundColor(.saveInk)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.saveNotebookLine, lineWidth: 1.4)
            )
    }
}

struct PlaceInsightSummaryPanel: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let place: Place
    var fallbackSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.badge.checkmark")
                    .font(.caption.weight(.black))
                Text(languageSettings.localized(english: "Memory summary", traditionalChinese: "記憶摘要"))
                    .font(.caption.weight(.black))
                Spacer()
            }
            .foregroundColor(.saveCocoa)

            VStack(alignment: .leading, spacing: 7) {
                PlaceSummaryLine(icon: "sparkles", text: condensedSummary)
            }
        }
        .padding(12)
        .background(Color.saveNotebookPage.opacity(0.50))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.7), lineWidth: 1.2)
        )
    }

    private var condensedSummary: String {
        let firstLine = fallbackSummary
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fallbackSummary
        let value = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 120 else { return value }
        return String(value.prefix(117)) + "..."
    }

    private var practicalInfo: String? {
        var parts: [String] = []
        if let openingHours = cleaned(place.openingHours) {
            parts.append(languageSettings.localized(english: "Hours: \(openingHours)", traditionalChinese: "營業時間：\(openingHours)"))
        }
        if let priceRange = cleaned(place.priceRange) {
            parts.append(languageSettings.localized(english: "Price: \(priceRange)", traditionalChinese: "價格：\(priceRange)"))
        }
        let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty {
            parts.append(languageSettings.localized(english: "Address: \(address)", traditionalChinese: "地址：\(address)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var reviewSummary: String? {
        var parts: [String] = []
        if let rating = place.googleRating ?? place.rating {
            let value = String(format: "%.1f", rating)
            parts.append(languageSettings.localized(english: "\(value) stars", traditionalChinese: "\(value) 星"))
        }
        if let reviewCountText = reviewCountText {
            parts.append(reviewCountText)
        }
        return parts.isEmpty ? nil : languageSettings.localized(english: "Reviews: \(parts.joined(separator: " · "))", traditionalChinese: "評論：\(parts.joined(separator: " · "))")
    }

    private var recommendationSummary: String? {
        if let dishes = place.extractedDishes, !dishes.isEmpty {
            return languageSettings.localized(
                english: "Saved for: \(dishes.prefix(4).joined(separator: ", "))",
                traditionalChinese: "為了這些存下：\(dishes.prefix(4).joined(separator: "、"))"
            )
        }
        if let recommender = cleaned(place.recommender) {
            return languageSettings.localized(english: "Recommended by: \(recommender)", traditionalChinese: "推薦人：\(recommender)")
        }
        return nil
    }

    private var reviewCountText: String? {
        for line in place.sourceEvidence {
            let prefix = "External reviews:"
            guard line.localizedCaseInsensitiveContains(prefix) else { continue }
            let value = line
                .replacingOccurrences(of: prefix, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            return languageSettings.localized(english: "\(value) reviews", traditionalChinese: "\(value) 則評論")
        }
        return nil
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}

private struct PlaceSummaryLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2.weight(.black))
                .foregroundColor(.saveCocoa)
                .frame(width: 16)
                .padding(.top, 2)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PlaceBusinessPhotoCarousel: View {
    var imageURLs: [String]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if photoURLs.isEmpty {
                fallbackVisual
                    .frame(height: 156)
            } else {
                TabView {
                    ForEach(Array(photoURLs.enumerated()), id: \.offset) { index, url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                fallbackVisual
                            case .empty:
                                ProgressView()
                                    .tint(.saveInk)
                            @unknown default:
                                fallbackVisual
                            }
                        }
                        .frame(height: 156)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: photoURLs.count > 1 ? .automatic : .never))
                .frame(height: 156)
            }

            HStack(spacing: 6) {
                Image(systemName: photoURLs.isEmpty ? "photo" : "camera.fill")
                    .font(.caption2.weight(.black))
                Text(photoURLs.isEmpty ? "Finding business photo" : photoLabel)
                    .font(.caption2.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundColor(.saveInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.saveNotebookPage.opacity(0.66))
            .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
            .clipShape(Capsule())
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.2)
        )
    }

    private var photoURLs: [URL] {
        imageURLs.compactMap(URL.init(string:))
    }

    private var photoLabel: String {
        photoURLs.count > 1 ? "\(photoURLs.count) business photos" : "Business photo"
    }

    private var fallbackVisual: some View {
        Rectangle()
            .fill(Color.saveNotebookPage.opacity(0.72))
            .overlay {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.saveCocoa.opacity(0.66))
            }
    }
}

#Preview {
    PlaceBottomSheet(place: .mock)
        .environmentObject(AppLanguageSettings())
}
