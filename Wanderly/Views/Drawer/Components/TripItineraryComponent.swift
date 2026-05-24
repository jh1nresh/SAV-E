import SwiftUI

struct TripItineraryComponent: View {
    let title: String
    let days: [ItineraryDay]
    let aiMessage: String?
    var places: [Place] = []
    @State private var showShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PLAN READY")
                        .font(.caption2.weight(.black))
                        .foregroundColor(.saveInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.saveSky.opacity(0.48))
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

                Button(action: { showShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.weight(.black))
                        .foregroundColor(.saveInk)
                        .frame(width: 34, height: 34)
                        .background(Color.saveMint.opacity(0.74))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showShareSheet) {
                    if let url = buildShareURL() {
                        ShareSheet(items: [url])
                    }
                }

                Label("\(days.count) days", systemImage: "calendar")
                    .font(.caption.weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.saveHoney)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 1.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(days) { day in
                    DaySection(day: day)
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

    private func buildShareURL() -> URL? {
        let tripData = SharedTripData.from(title: title, city: "", days: days, places: places)
        return tripData.toURL()
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Day Section

private struct DaySection: View {
    let day: ItineraryDay

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(day.label ?? "Day \(day.dayNumber)")
                .font(.subheadline)
                .fontWeight(.black)
                .foregroundColor(.saveInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.saveHoney.opacity(0.66))
                .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                .clipShape(Capsule())
                .padding(.bottom, 12)

            ForEach(Array(day.stops.enumerated()), id: \.element.id) { index, stop in
                HStack(alignment: .top, spacing: 12) {
                    // Timeline
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.saveHoney)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.saveNotebookLine, lineWidth: 1))
                            .padding(.top, 5)
                        if index < day.stops.count - 1 {
                            Rectangle()
                                .fill(Color.saveNotebookLine.opacity(0.22))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 8)

                    // Content
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(stop.placeName)
                                .font(.subheadline)
                                .fontWeight(.black)
                                .foregroundColor(.saveInk)
                                .lineLimit(2)
                            Spacer()
                            if let time = stop.time {
                                Text(time)
                                    .font(.caption2.weight(.black))
                                    .foregroundColor(.saveInk)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.saveMint.opacity(0.74))
                                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                                    .clipShape(Capsule())
                            }
                        }
                        if let duration = stop.duration {
                            Text("\(duration) min")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.saveInk.opacity(0.76))
                        }
                        if let note = stop.note {
                            Text(note)
                                .font(.caption)
                                .foregroundColor(.saveInk.opacity(0.78))
                                .padding(.top, 1)
                        }
                    }
                    .padding(.bottom, 14)
                }
            }
        }
        .padding(14)
        .background(Color.saveHoney.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
