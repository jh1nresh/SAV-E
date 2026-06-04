import SwiftUI
import MapKit

struct PlaceDetailView: View {
    let place: Place
    var onDelete: (() async throws -> Void)?
    var onUpdateVisibility: ((PlaceVisibility) async throws -> Void)?
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var enrichedPlace: Place?
    @State private var localVisibility: PlaceVisibility?

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

                PlaceVisibilityControl(
                    visibility: detailPlace.effectiveVisibility,
                    onChange: onUpdateVisibility == nil ? nil : updateVisibility
                )
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
    .environmentObject(AppLanguageSettings())
}
