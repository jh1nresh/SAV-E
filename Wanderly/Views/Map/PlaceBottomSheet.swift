import SwiftUI

struct PlaceBottomSheet: View {
    let place: Place
    var onDelete: (() async throws -> Void)?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                SaveMemoryBadge(state: .saved(place.category), size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MEMORY CARD")
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveCocoa)

                    Text(place.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.saveInk)

                    Text(place.address)
                        .font(.subheadline)
                        .foregroundColor(.saveMutedText)
                }

                Spacer()

                CategoryPill(category: place.category, isSelected: true)
            }

            Divider()

            // Info row
            HStack(spacing: 16) {
                if let rating = place.googleRating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundColor(.saveCocoa)
                }

                if let priceRange = place.priceRange {
                    Text(priceRange)
                        .font(.subheadline)
                        .foregroundColor(.saveMutedText)
                }

                HStack(spacing: 4) {
                    PlatformIcon(platform: place.sourcePlatform, size: 14)
                    Text(place.sourcePlatform.displayName)
                        .font(.caption)
                        .foregroundColor(.saveMutedText)
                }

                Spacer()

                Text(place.status.memoryCardLabel)
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(place.status == .visited ? Color.saveMint : Color.saveHoney.opacity(0.64))
                    .cornerRadius(8)
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
            if let note = place.note {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Note")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.saveMutedText)
                    Text(note)
                        .font(.subheadline)
                        .foregroundColor(.saveInk)
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

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(isDeleting ? "Deleting..." : "Delete", systemImage: "trash")
                        .font(.subheadline)
                        .fontWeight(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.saveNotebookPage)
                        .foregroundColor(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 2)
                        )
                }
                .disabled(isDeleting || onDelete == nil)
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
