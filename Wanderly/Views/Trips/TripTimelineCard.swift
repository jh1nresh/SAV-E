import SwiftUI

struct TripTimelineCard: View {
    let stop: TripStop

    var body: some View {
        HStack(spacing: 12) {
            // Timeline indicator
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.wanderlyTerracotta)
                    .frame(width: 10, height: 10)
                Rectangle()
                    .fill(Color.wanderlyTerracotta.opacity(0.3))
                    .frame(width: 2)
            }
            .frame(width: 10)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(stop.placeName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.wanderlyCharcoal)

                HStack(spacing: 12) {
                    if let time = stop.startTime {
                        Label(time, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let duration = stop.duration {
                        Label(formatDuration(duration), systemImage: "hourglass")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("Day \(stop.day)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.wanderlyTerracotta)
                }

                if let note = stop.note {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining > 0 ? "\(hours)h \(remaining)m" : "\(hours)h"
    }
}

#Preview {
    List {
        ForEach(TripStop.mockList) { stop in
            TripTimelineCard(stop: stop)
        }
    }
}
