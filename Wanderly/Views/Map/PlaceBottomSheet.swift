import SwiftUI

struct PlaceBottomSheet: View {
    let place: Place
    var onDelete: (() async throws -> Void)?
    var onPlanAround: (() -> Void)?
    @Environment(\.openURL) private var openURL
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
                    if let normalizedSourceURL {
                        Button {
                            openURL(normalizedSourceURL)
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
                        .background(Color.saveNotebookPage)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1.4))
                }
            }

            Text(memorySummary)
                .font(.subheadline)
                .foregroundColor(.saveInk)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                CategoryPill(category: place.category, isSelected: true)
                if let rating = place.googleRating {
                    PlaceMemoryChip(icon: "star.fill", text: String(format: "%.1f", rating))
                }
                if let priceRange = place.priceRange {
                    PlaceMemoryChip(icon: "tag.fill", text: priceRange)
                }
                PlaceMemoryChip(icon: "link", text: sourceChipLabel)
                PlaceMemoryChip(icon: "mappin.and.ellipse", text: "Map confirmed")
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

            // Note
            if let note = cleanUserNote {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Why SAV-E saved this")
                        .font(.caption)
                        .fontWeight(.black)
                        .foregroundColor(.saveCocoa)
                    Text(note)
                        .font(.subheadline)
                        .foregroundColor(.saveInk)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Evidence receipt")
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveCocoa)
                FlowLayout(spacing: 8) {
                    PlaceMemoryChip(icon: "link", text: sourceChipLabel)
                    PlaceMemoryChip(icon: "mappin", text: "Address saved")
                    PlaceMemoryChip(icon: "checkmark.seal.fill", text: "Map ready")
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    NavigationService.navigate(to: place.coordinate, name: place.name)
                }) {
                    Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline)
                        .fontWeight(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.saveHoney)
                        .foregroundColor(.saveInk)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 2)
                        )
                }

                Button {
                    onPlanAround?()
                } label: {
                    Label("Plan around this", systemImage: "sparkles")
                        .font(.subheadline)
                        .fontWeight(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.saveNotebookPage)
                        .foregroundColor(.saveInk)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 2)
                        )
                }
                .disabled(onPlanAround == nil)
            }

            if let normalizedSourceURL {
                Button {
                    openURL(normalizedSourceURL)
                } label: {
                    Label("View source", systemImage: "link")
                        .font(.caption.weight(.black))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.saveSky.opacity(0.20))
                        .foregroundColor(.saveInk)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.saveNotebookLine.opacity(0.72), lineWidth: 1.4)
                        )
                }
            }

            if let deleteError {
                Text(deleteError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(SaveDottedBackground())
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

    private var sourceChipLabel: String {
        place.sourcePlatform == .other ? "Source saved" : "\(place.sourcePlatform.displayName) source"
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

    private var normalizedSourceURL: URL? {
        guard let raw = place.sourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }

        if let url = URL(string: raw), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(raw)")
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
        .background(Color.saveNotebookPage)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.saveNotebookLine.opacity(0.34), lineWidth: 1))
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

#Preview {
    PlaceBottomSheet(place: .mock)
}
