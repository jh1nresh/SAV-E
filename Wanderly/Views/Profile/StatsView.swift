import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    let profile: UserProfile
    var waitingClues: Int = 0

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ], spacing: 8) {
            StatItem(value: "\(profile.savedCount)", label: languageSettings.text(.memoryCards), color: .saveCocoa, icon: "rectangle.stack.fill")
            StatItem(value: "\(profile.visitedCount)", label: languageSettings.text(.verified), color: .saveSuccess, icon: "checkmark.seal.fill")
            StatItem(value: "\(profile.citiesCount)", label: languageSettings.text(.cities), color: .saveHoney, icon: "building.2.fill")
            StatItem(value: "\(waitingClues)", label: languageSettings.text(.waitingClues), color: .saveSignal, icon: "circle.hexagongrid.fill")
        }
        .padding(12)
        .saveNotebookPage(cornerRadius: 18)
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
                    .font(.caption.weight(.black))
                    .foregroundColor(color)
                Spacer()
                Text(value)
                    .font(.title3.monospacedDigit().weight(.black))
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
        .background(Color.saveNotebookPage.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 1.4)
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(color.opacity(0.42))
                .frame(width: 28, height: 28)
                .offset(x: -8, y: -8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    StatsView(profile: .mock)
        .environmentObject(AppLanguageSettings())
        .padding()
        .background(SaveDottedBackground())
}
