import SwiftUI
import MapKit

// Preview wrapper for ClipContentView (App Clip targets don't support previews)

private struct PreviewClipStop: Identifiable {
    let id = UUID()
    var name: String
    var address: String
    var coordinate: CLLocationCoordinate2D
}

#Preview("Clip Content") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 20) {
                let stops = [
                    PreviewClipStop(name: "Tartine Bakery", address: "600 Guerrero St, SF", coordinate: CLLocationCoordinate2D(latitude: 37.7614, longitude: -122.4241)),
                    PreviewClipStop(name: "Dolores Park", address: "Dolores St, SF", coordinate: CLLocationCoordinate2D(latitude: 37.7596, longitude: -122.4269)),
                    PreviewClipStop(name: "Bi-Rite Creamery", address: "3692 18th St, SF", coordinate: CLLocationCoordinate2D(latitude: 37.7618, longitude: -122.4256)),
                ]

                Map {
                    ForEach(stops) { stop in
                        Marker(stop.name, coordinate: stop.coordinate)
                            .tint(Color.saveCoral)
                    }
                }
                .frame(height: 200)
                .cornerRadius(16)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Shared Trip")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(Color.saveInk)
                    Text("\(stops.count) stops")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                VStack(spacing: 12) {
                    ForEach(stops) { stop in
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title3)
                                .foregroundColor(Color.saveCoral)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.saveInk)
                                Text(stop.address)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .saveNotebookPage(cornerRadius: 16)
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 12) {
                    Button(action: {}) {
                        Text("Open in SAV-E")
                            .font(.headline)
                            .foregroundColor(Color.saveInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.saveHoney)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.saveNotebookLine, lineWidth: 2)
                            )
                    }
                    Button(action: {}) {
                        Text("Get the Full App")
                            .font(.subheadline)
                            .foregroundColor(Color.saveInk)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .background(SaveDottedBackground())
        .navigationTitle("Trip Preview")
        .navigationBarTitleDisplayMode(.inline)
    }
}
