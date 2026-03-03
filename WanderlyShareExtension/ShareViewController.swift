import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(rootView: ShareExtensionView(
            extensionContext: extensionContext
        ))
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hostingController.didMove(toParent: self)
    }
}

// MARK: - Share Extension SwiftUI View

struct ShareExtensionView: View {
    weak var extensionContext: NSExtensionContext?
    @State private var sharedURL: String = ""
    @State private var parsedResult: String = "Analyzing..."
    @State private var isParsing = true
    @State private var isSaved = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if isParsing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(Color(hex: "C75B39"))

                        Text("AI is parsing the shared content...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if isSaved {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(Color(hex: "A8B5A0"))

                        Text("Saved to Wanderly!")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(hex: "2C2C2E"))

                        Text("Open the app to see it on your map.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        // Parsed place preview
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Detected Place")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                Image(systemName: "fork.knife")
                                    .foregroundColor(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Color(hex: "C75B39"))
                                    .cornerRadius(10)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tartine Bakery")
                                        .font(.headline)
                                        .foregroundColor(Color(hex: "2C2C2E"))
                                    Text("600 Guerrero St, San Francisco")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(hex: "FFF8F0"))
                        .cornerRadius(16)

                        // Category selector placeholder
                        Text("Category")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["Food", "Cafe", "Bar", "Attraction", "Stay", "Shopping"], id: \.self) { cat in
                                    Text(cat)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(cat == "Food" ? Color(hex: "C75B39") : Color(hex: "C75B39").opacity(0.1))
                                        .foregroundColor(cat == "Food" ? .white : Color(hex: "C75B39"))
                                        .cornerRadius(16)
                                }
                            }
                        }

                        Spacer()

                        // Save button
                        Button(action: {
                            isSaved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                extensionContext?.completeRequest(returningItems: nil)
                            }
                        }) {
                            Text("Save to Map")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "C75B39"))
                                .cornerRadius(16)
                        }
                    }
                    .padding()
                }
            }
            .background(Color(hex: "FFF8F0"))
            .navigationTitle("Save Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        extensionContext?.cancelRequest(withError: NSError(domain: "com.wanderly", code: 0))
                    }
                }
            }
        }
        .task {
            await extractSharedContent()
        }
    }

    private func extractSharedContent() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            isParsing = false
            return
        }

        for item in items {
            guard let attachments = item.attachments else { continue }
            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await attachment.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                        sharedURL = url.absoluteString
                    }
                }
            }
        }

        // Simulate AI parsing delay
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        isParsing = false
    }
}
