import SwiftUI

struct PlaceListComponent: View {
    let title: String
    let places: [Place]
    let aiMessage: String?
    let onSelect: (Place) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAP STAMP MATCHES")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.saveCream.opacity(0.72))
                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                        .clipShape(Capsule())

                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.saveInk)
                        .lineLimit(2)
                    if let msg = aiMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(.saveInk.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Text("\(places.count)")
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.saveHoney)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.saveNotebookLine, lineWidth: 1)
                    )
            }

            if places.isEmpty {
                Text("No matching Map Stamps yet.")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.saveInk.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(32)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(places) { place in
                        Button {
                            onSelect(place)
                        } label: {
                            PlaceListMatchRow(place: place)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(place.name), saved Map Stamp")
                        .accessibilityHint("Open place detail")
                    }
                }
            }
        }
        .padding(14)
        .background(Color.saveNotebookPage.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PlaceListMatchRow: View {
    let place: Place

    private var addressText: String {
        let address = place.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? "Selected on map" : address
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.category.iconName)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(iconFill)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(place.name)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.saveInk)
                    .lineLimit(1)

                Text(addressText)
                    .font(.subheadline)
                    .foregroundColor(.saveMutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("SAVED")
                .font(.caption2.weight(.bold))
                .foregroundColor(.saveInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.saveMint.opacity(0.64))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.saveNotebookLine.opacity(0.26), lineWidth: 1)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.saveNotebookPage.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.saveNotebookLine.opacity(0.16), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private var iconFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.saveStampColor(for: place.category).opacity(0.92),
                Color.saveStampColor(for: place.category).opacity(place.status == .visited ? 0.68 : 0.52)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
