import SwiftUI

struct PlaceBottomSheet: View {
    let place: Place
    var onDelete: (() async throws -> Void)?
    var onPlanAround: (() -> Void)?
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
                    Text(place.status.memoryCardLabel.uppercased())
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
                    ShareLink(item: place.saveShareURL ?? place.appleMapsURL ?? URL(string: "https://wanderly.app")!, subject: Text(place.shareSubject), message: Text(place.shareText)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    if let sourceURL = place.primarySourceURL {
                        Button {
                            openURL(sourceURL)
                        } label: {
                            Label("View source", systemImage: "link")
                        }
                    }

                    if onDelete != nil {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.black))
                        .foregroundColor(.saveInk)
                        .frame(width: 36, height: 36)
                        .background(Color.saveNotebookPage.opacity(0.62))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1.4))
                }
            }

            PlaceBusinessPhotoCarousel(imageURLs: place.businessPhotoURLStrings)

            PlaceBasicInfoPanel(place: place)
            PlaceInsightSummaryPanel(place: place, fallbackSummary: memorySummary)

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
                    Text("Recommended")
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
                    NavigationService.navigate(to: place.coordinate, name: place.name)
                } label: {
                    PlaceDetailActionLabel(title: "Maps", systemImage: "map.fill", fill: .saveHoney)
                }

                ShareLink(item: place.saveShareURL ?? place.appleMapsURL ?? URL(string: "https://wanderly.app")!, subject: Text(place.shareSubject), message: Text(place.shareText)) {
                    PlaceDetailActionLabel(title: "Share", systemImage: "square.and.arrow.up", fill: Color.saveMint.opacity(0.36))
                }

                if let sourceURL = place.primarySourceURL {
                    Button {
                        openURL(sourceURL)
                    } label: {
                        PlaceDetailActionLabel(title: "Source", systemImage: "link", fill: Color.saveSky.opacity(0.22))
                    }
                } else {
                    Button {
                        onPlanAround?()
                    } label: {
                        PlaceDetailActionLabel(title: "Plan", systemImage: "sparkles", fill: Color.saveNotebookPage)
                    }
                    .disabled(onPlanAround == nil)
                    .opacity(onPlanAround == nil ? 0.55 : 1)
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
            "Delete \(place.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Place", role: .destructive) {
                Task { await deletePlace() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the Map Stamp from SAV-E.")
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
        place.sourceConfirmationLabel
    }

    private var verificationChips: [PlaceVerificationChip] {
        place.verificationChips(sourceLabel: sourceConfirmationLabel)
    }

    private var areaLabel: String? {
        let parts = place.address
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.count >= 2 { return parts[parts.count - 2] }
        return parts.first
    }

    private var memorySummary: String {
        if let areaLabel {
            return "Map verified for \(place.name) in \(areaLabel). Address confirmed for this SAV-E memory."
        }
        return "Map verified and address confirmed for this SAV-E memory."
    }

}

private struct PlaceDetailGlassBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.16) : Color.saveNotebookPage.opacity(0.46))
            )
    }
}

struct PlaceBasicInfoPanel: View {
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption.weight(.black))
                Text("Basic info")
                    .font(.caption.weight(.black))
                Spacer()
            }
            .foregroundColor(.saveCocoa)

            VStack(spacing: 7) {
                PlaceInfoRow(icon: "star.fill", title: "Rating", value: ratingText)
                if let reviewCountText {
                    PlaceInfoRow(icon: "text.bubble.fill", title: "Reviews", value: reviewCountText)
                }
                PlaceInfoRow(icon: place.category.iconName, title: "Category", value: place.category.displayName)
                PlaceInfoRow(icon: "mappin.and.ellipse", title: "Address", value: place.address.isEmpty ? "No address saved" : place.address)
                PlaceInfoRow(icon: "link", title: "Source", value: place.sourceConfirmationLabel)
                if let priceRange = place.priceRange {
                    PlaceInfoRow(icon: "tag.fill", title: "Price", value: priceRange)
                }
                if let openingHours = place.openingHours?.trimmingCharacters(in: .whitespacesAndNewlines), !openingHours.isEmpty {
                    PlaceInfoRow(icon: "clock.fill", title: "Hours", value: openingHours)
                }
            }
        }
        .padding(10)
        .background(Color.saveSky.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.56), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var ratingText: String {
        if let rating = place.googleRating ?? place.rating {
            return String(format: "%.1f", rating)
        }
        return "No rating yet"
    }

    private var reviewCountText: String? {
        for line in place.sourceEvidence {
            let prefix = "External reviews:"
            guard line.localizedCaseInsensitiveContains(prefix) else { continue }
            let value = line
                .replacingOccurrences(of: prefix, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            return "\(value) reviews"
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
            Image(systemName: icon)
                .font(.caption2.weight(.black))
                .foregroundColor(.saveInk)
                .frame(width: 16)
                .padding(.top, 2)

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

    var cleanMemoryNote: String? {
        guard let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return nil
        }
        let cleanedLines = note
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                !line.localizedCaseInsensitiveContains("Source URL:") &&
                !line.localizedCaseInsensitiveContains("Analysis pipeline:") &&
                !line.localizedCaseInsensitiveContains("Evidence tier:") &&
                !line.localizedCaseInsensitiveContains("Apple Maps POI") &&
                !line.localizedCaseInsensitiveContains("Apple Maps result") &&
                !line.localizedCaseInsensitiveContains("POI:") &&
                !line.localizedCaseInsensitiveContains("MKPOICategory") &&
                !line.localizedCaseInsensitiveContains("Business photo: Google Places") &&
                !line.localizedCaseInsensitiveContains("External reviews:")
            }
        guard !cleanedLines.isEmpty else { return nil }
        return cleanedLines.joined(separator: "\n")
    }

    func verificationChips(sourceLabel: String? = nil) -> [PlaceVerificationChip] {
        var chips = [
            PlaceVerificationChip(icon: "checkmark.seal.fill", text: "Map verified")
        ]
        if !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chips.append(PlaceVerificationChip(icon: "mappin.and.ellipse", text: "Address confirmed"))
        }
        chips.append(PlaceVerificationChip(icon: "link", text: sourceLabel ?? sourceConfirmationLabel))
        if googlePlaceId != nil || googleRating != nil || googlePriceLevel != nil || openingHours != nil {
            chips.append(PlaceVerificationChip(icon: "building.2.fill", text: "Google Places details"))
        }
        return chips
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
    let place: Place
    var fallbackSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.badge.checkmark")
                    .font(.caption.weight(.black))
                Text("Place summary")
                    .font(.caption.weight(.black))
                Spacer()
            }
            .foregroundColor(.saveCocoa)

            VStack(alignment: .leading, spacing: 7) {
                PlaceSummaryLine(icon: "sparkles", text: fallbackSummary)
                PlaceSummaryLine(icon: "clock.fill", text: practicalInfo)
                PlaceSummaryLine(icon: "star.fill", text: reviewSummary)
                PlaceSummaryLine(icon: "hand.thumbsup.fill", text: recommendationSummary)
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

    private var practicalInfo: String {
        var parts: [String] = []
        if let openingHours = cleaned(place.openingHours) {
            parts.append(openingHours)
        }
        if let priceRange = cleaned(place.priceRange) {
            parts.append(priceRange)
        }
        if parts.isEmpty {
            parts.append(place.address.isEmpty ? "Address not saved yet" : place.address)
        }
        return "Practical info: \(parts.joined(separator: " · "))"
    }

    private var reviewSummary: String {
        var parts: [String] = []
        if let rating = place.googleRating ?? place.rating {
            parts.append(String(format: "%.1f stars", rating))
        }
        if let reviewCountText = reviewCountText {
            parts.append(reviewCountText)
        }
        return parts.isEmpty ? "Reviews: no rating or review count saved yet" : "Reviews: \(parts.joined(separator: " · "))"
    }

    private var recommendationSummary: String {
        if let dishes = place.extractedDishes, !dishes.isEmpty {
            return "Recommended: \(dishes.prefix(4).joined(separator: ", "))"
        }
        if let recommender = cleaned(place.recommender) {
            return "Recommended by \(recommender)"
        }
        if let note = cleanMemoryNote {
            return "Memory note: \(note)"
        }
        return "Recommendation: no saved dish or personal note yet"
    }

    private var cleanMemoryNote: String? {
        guard let note = cleaned(place.note),
              !note.localizedCaseInsensitiveContains("Source URL:"),
              !note.localizedCaseInsensitiveContains("Analysis pipeline:"),
              !note.localizedCaseInsensitiveContains("Evidence tier:")
        else { return nil }
        return note
    }

    private var reviewCountText: String? {
        for line in place.sourceEvidence {
            let prefix = "External reviews:"
            guard line.localizedCaseInsensitiveContains(prefix) else { continue }
            let value = line
                .replacingOccurrences(of: prefix, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            return "\(value) reviews"
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
}
