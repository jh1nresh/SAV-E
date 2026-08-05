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
                .background(SaveAtlasPalette.canvas)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(SaveAtlasPalette.line.opacity(0.35), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(spacing: 7) {
                Text("ROUTE READY")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.saveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SaveAtlasPalette.kraft.opacity(0.58))
                    .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                    .clipShape(Capsule())

                Text(place.name)
                    .font(.title3.weight(.bold))
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
                .background(SaveAtlasPalette.canvas)
                .overlay(Capsule().stroke(SaveAtlasPalette.line, lineWidth: 1))
                .clipShape(Capsule())

            Button(action: openInMaps) {
                // Postage-coral primary CTA (spec P2 follow-up).
                Label("Start Navigation", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(SaveAtlasPalette.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(SaveAtlasPalette.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SaveAtlasPalette.line.opacity(0.35), lineWidth: 1)
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
