import SwiftUI
import MapKit

struct PlaceDetailView: View {
    let place: Place
    var onDelete: (() async throws -> Void)?
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                memoryHeader

                // Info grid
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        if let rating = place.googleRating {
                            InfoChip(icon: "star.fill", text: String(format: "%.1f", rating), color: .saveCocoa)
                        }
                        if let priceRange = place.priceRange {
                            InfoChip(icon: "dollarsign.circle", text: priceRange, color: .saveSignal)
                        }
                        InfoChip(icon: place.status == .visited ? "checkmark.circle.fill" : "clock",
                                 text: place.status.memoryCardLabel,
                                 color: place.status == .visited ? .saveSignal : .saveCocoa)
                    }

                    // Source
                    HStack {
                        PlatformIcon(platform: place.sourcePlatform)
                        Text("Saved from \(place.sourcePlatform.displayName)")
                            .font(.subheadline)
                            .foregroundColor(.saveMutedText)

                        if let recommender = place.recommender {
                            Text("via \(recommender)")
                                .font(.caption)
                                .foregroundColor(.saveCocoa)
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal)

                if !place.sourceEvidence.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Evidence receipt", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.saveInk)
                        EvidenceLinkList(evidence: place.sourceEvidence, maxItems: 4)
                    }
                    .padding(.horizontal)
                }

                // Opening hours
                if let hours = place.openingHours {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Opening Hours", systemImage: "clock")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.saveInk)
                        Text(hours)
                            .font(.subheadline)
                            .foregroundColor(.saveMutedText)
                    }
                    .padding(.horizontal)
                }

                // Dishes
                if let dishes = place.extractedDishes, !dishes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Must-Try Dishes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.saveInk)

                        FlowLayout(spacing: 8) {
                            ForEach(dishes, id: \.self) { dish in
                                HStack(spacing: 4) {
                                    Image(systemName: "fork.knife")
                                        .font(.caption2)
                                    Text(dish)
                                        .font(.subheadline)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.saveHoney.opacity(0.30))
                                .foregroundColor(.saveInk)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.saveNotebookLine.opacity(0.30), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Notes
                if let note = cleanUserNote {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Why SAV-E saved this", systemImage: "sparkles")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.saveInk)
                        Text(note)
                            .font(.subheadline)
                            .foregroundColor(.saveInk)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.saveNotebookPage)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.saveNotebookLine.opacity(0.32), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal)
                }

                // Mini map
                Map(position: .constant(.region(MKCoordinateRegion(
                    center: place.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )))) {
                    Marker(place.name, coordinate: place.coordinate)
                        .tint(Color.categoryColor(for: place.category))
                }
                .frame(height: 160)
                .cornerRadius(16)
                .padding(.horizontal)

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: { openInMaps() }) {
                        Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.subheadline)
                            .fontWeight(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.saveHoney)
                            .foregroundColor(.saveInk)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 1.6)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    ShareLink(item: place.saveShareURL ?? place.appleMapsURL ?? URL(string: "https://wanderly.app")!, subject: Text(place.shareSubject), message: Text(place.shareText)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                            .fontWeight(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.saveMint.opacity(0.42))
                            .foregroundColor(.saveInk)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 1.6)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if let url = place.primarySourceURL {
                        Button(action: { openURL(url) }) {
                            Label("Source", systemImage: "link")
                                .font(.subheadline)
                                .fontWeight(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.saveNotebookPage)
                                .foregroundColor(.saveInk)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.saveNotebookLine, lineWidth: 1.6)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: place.saveShareURL ?? place.appleMapsURL ?? URL(string: "https://wanderly.app")!, subject: Text(place.shareSubject), message: Text(place.shareText)) {
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

    private var memoryHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                SaveMemoryBadge(state: .saved(place.category), size: 62)

                VStack(alignment: .leading, spacing: 6) {
                    Text(place.status.memoryCardLabel.uppercased())
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveCocoa)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(place.status == .visited ? Color.saveMint : Color.saveHoney.opacity(0.56))
                        .clipShape(Capsule())

                    Text(place.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.saveInk)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        PlatformIcon(platform: place.sourcePlatform, size: 14)
                        Text("Saved from \(place.sourcePlatform.displayName)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.saveCocoa)
                    }

                    HStack(spacing: 8) {
                        CategoryPill(category: place.category, isSelected: true)
                        if let priceRange = place.priceRange {
                            InfoChip(icon: "tag.fill", text: priceRange, color: .saveCocoa)
                        }
                    }
                }
            }

            Text(memorySummary)
                .font(.subheadline)
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(place.address)
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
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        mapItem.name = place.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
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
        if let areaLabel, place.sourcePlatform != .other {
            return "Saved from \(place.sourcePlatform.displayName). SAV-E matched it to \(place.name) in \(areaLabel)."
        }
        if place.sourcePlatform != .other {
            return "Saved from \(place.sourcePlatform.displayName). SAV-E matched the source to this confirmed place."
        }
        return "Saved as a confirmed place memory in SAV-E."
    }

    private var cleanUserNote: String? {
        guard let note = place.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty,
              !note.localizedCaseInsensitiveContains("Source URL:"),
              !note.localizedCaseInsensitiveContains("Analysis pipeline:"),
              !note.localizedCaseInsensitiveContains("Evidence tier:")
        else { return nil }
        return note
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
}
