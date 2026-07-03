import SwiftUI

struct StatsView: View {
    @Environment(\.appLanguageSettings) private var languageSettings
    let stats: PassportStats

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ], spacing: 8) {
            StatItem(value: "\(stats.savedCount)", label: languageSettings.text(.memoryCards), color: .saveCocoa, icon: "rectangle.stack")
            StatItem(value: "\(stats.visitedCount)", label: languageSettings.text(.visited), color: .saveSuccess, icon: "figure.walk")
            StatItem(value: "\(stats.citiesCount)", label: languageSettings.text(.cities), color: .saveHoney, icon: "building.2")
            StatItem(value: "\(stats.waitingClues)", label: languageSettings.text(.waitingClues), color: .saveSignal, icon: "circle.hexagongrid")
        }
        .padding(12)
        .saveNotebookSurface(cornerRadius: 18)
        .padding(.horizontal)
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.saveCocoa)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.saveNotebookLine.opacity(0.7), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                Spacer()
                Text(value)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundColor(.saveInk)
            }
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.saveMutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .saveNotebookSurface(cornerRadius: 10, fill: color, opacity: 0.10)
    }
}

#Preview {
    StatsView(stats: PassportStats(profile: .mock, savedPlaces: Place.mockList, waitingClues: 2))
        .environment(\.appLanguageSettings, AppLanguageSettings())
        .padding()
        .background(SaveDottedBackground())
}
