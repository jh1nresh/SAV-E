import SwiftUI

struct PlaceListComponent: View {
    let title: String
    let places: [Place]
    let aiMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAP STAMP MATCHES")
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.saveMint.opacity(0.72))
                        .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                        .clipShape(Capsule())

                    Text(title)
                        .font(.title3.weight(.black))
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
                        PlaceCard(place: place)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.saveNotebookPage.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
