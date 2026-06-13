import Messages
import MapKit
import SwiftUI
import UIKit

final class MessagesViewController: MSMessagesAppViewController {

    private var hostingController: UIHostingController<PlacePickerView>?

    // MARK: - Conversation lifecycle

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        presentPicker()
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        presentPicker()
    }

    // MARK: - SwiftUI hosting

    private func presentPicker() {
        let places = MessagesVaultReader.confirmedPlaces()

        let root = PlacePickerView(places: places) { [weak self] place in
            self?.insertCard(for: place)
        }

        if let hostingController {
            hostingController.rootView = root
            return
        }

        let controller = UIHostingController(rootView: root)
        controller.view.backgroundColor = .clear
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
        hostingController = controller

        // Show the full list when there is content to scroll through.
        if !places.isEmpty, presentationStyle == .compact {
            requestPresentationStyle(.expanded)
        }
    }

    // MARK: - Card insertion

    private func insertCard(for place: MessagesPlace) {
        guard let conversation = activeConversation else { return }

        let layout = MSMessageTemplateLayout()
        layout.caption = place.name
        layout.subcaption = subcaption(for: place)

        let message = MSMessage()
        message.layout = layout
        message.url = deepLinkURL(for: place)

        // Render a MapKit snapshot for the card image, then insert. Falls back to
        // a branded placeholder if the snapshot fails.
        renderSnapshot(for: place) { [weak self] image in
            layout.image = image
            conversation.insert(message) { error in
                if let error {
                    NSLog("[SAVEiMessage] insert failed: \(error.localizedDescription)")
                }
            }
            self?.requestPresentationStyle(.compact)
        }
    }

    private func subcaption(for place: MessagesPlace) -> String {
        var parts: [String] = []
        if !place.address.isEmpty { parts.append(place.address) }
        if let category = place.category, !category.isEmpty {
            parts.append(category.capitalized)
        }
        if let rating = place.rating {
            parts.append(String(format: "%.1f★", rating))
        }
        return parts.joined(separator: " · ")
    }

    /// A `wanderly://` deep link so tapping the card can open the place in SAV-E.
    private func deepLinkURL(for place: MessagesPlace) -> URL? {
        var components = URLComponents()
        components.scheme = "wanderly"
        components.host = "place"
        components.queryItems = [
            URLQueryItem(name: "id", value: place.id.uuidString),
            URLQueryItem(name: "name", value: place.name),
            URLQueryItem(name: "lat", value: String(place.latitude)),
            URLQueryItem(name: "lng", value: String(place.longitude))
        ]
        return components.url
    }

    private func renderSnapshot(for place: MessagesPlace, completion: @escaping (UIImage?) -> Void) {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            latitudinalMeters: 600,
            longitudinalMeters: 600
        )
        options.size = CGSize(width: 600, height: 360)
        options.showsBuildings = true

        let snapshotter = MKMapSnapshotter(options: options)
        snapshotter.start(with: .main) { snapshot, _ in
            guard let snapshot else {
                completion(Self.placeholderImage(for: place))
                return
            }

            let renderer = UIGraphicsImageRenderer(size: options.size)
            let image = renderer.image { _ in
                snapshot.image.draw(at: .zero)

                // Draw a pin at the place coordinate.
                let pin = "📍" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 36)
                ]
                let point = snapshot.point(for: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
                let textSize = pin.size(withAttributes: attributes)
                pin.draw(at: CGPoint(x: point.x - textSize.width / 2, y: point.y - textSize.height),
                         withAttributes: attributes)
            }
            completion(image)
        }
    }

    private static func placeholderImage(for place: MessagesPlace) -> UIImage {
        let size = CGSize(width: 600, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let pin = "📍" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 80)
            ]
            let textSize = pin.size(withAttributes: attributes)
            pin.draw(at: CGPoint(x: (size.width - textSize.width) / 2,
                                 y: (size.height - textSize.height) / 2),
                     withAttributes: attributes)
        }
    }
}
