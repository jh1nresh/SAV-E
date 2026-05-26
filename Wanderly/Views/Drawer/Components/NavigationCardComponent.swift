import SwiftUI
import MapKit

struct NavigationCardComponent: View {
    let place: Place
    let mode: SaveAIResponse.TransportMode

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: modeIcon)
                .font(.system(size: 26, weight: .black))
                .foregroundColor(.saveInk)
                .frame(width: 58, height: 58)
                .background(Color.saveSky.opacity(0.54))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.saveNotebookLine, lineWidth: 2)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 7) {
                Text("ROUTE READY")
                    .font(.caption2.weight(.black))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.saveHoney)
                    .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                    .clipShape(Capsule())

                Text(place.name)
                    .font(.title3.weight(.black))
                    .foregroundColor(.saveInk)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(place.address)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.saveInk.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(modeLabel, systemImage: modeIcon)
                .font(.caption)
                .fontWeight(.black)
                .foregroundColor(.saveInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.saveMint.opacity(0.74))
                .overlay(Capsule().stroke(Color.saveNotebookLine, lineWidth: 1))
                .clipShape(Capsule())

            Button(action: openInMaps) {
                Label("Start Navigation", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                    .foregroundColor(.saveInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.saveHoney)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.saveNotebookLine, lineWidth: 2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.saveNotebookPage.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.saveNotebookLine, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var modeIcon: String {
        switch mode {
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        case .driving: return "car.fill"
        }
    }

    private var modeLabel: String {
        switch mode {
        case .walking: return "Walking directions"
        case .transit: return "Transit directions"
        case .driving: return "Driving directions"
        }
    }

    private func openInMaps() {
        let navMode: NavigationService.Mode = switch mode {
        case .walking: .walking
        case .transit: .transit
        case .driving: .driving
        }
        NavigationService.navigate(to: place.coordinate, name: place.name, mode: navMode)
    }
}
