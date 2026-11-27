import SwiftUI

/// Isolated local gallery host. Fixture photos never enter a Savvy account.
@main
struct GalleryPreviewApp: App {
    var body: some Scene { WindowGroup { GalleryPreviewHome() } }
}

private struct PhotoFixture: Decodable {
    let name: String
    let file: String
    let detail: String
    let credit: String
    let commonsFile: String
    let width: Int
    let height: Int
}

@MainActor
private struct GalleryPreviewHome: View {
    @State private var query = ""
    @State private var lightsOn = true
    @State private var selected: SavedGalleryItem?
    @State private var largeText = CommandLine.arguments.contains("--large-text")
    private let items: [SavedGalleryItem] = {
        guard let url = Bundle.main.url(forResource: "place-photo-data", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let json = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .dropFirst("export default ".count).dropLast()
        let rows = (try? JSONDecoder().decode([PhotoFixture].self, from: Data(json.utf8))) ?? []
        return rows.enumerated().map { index, row in
            var source = URLComponents(string: "https://commons.wikimedia.org")!
            source.path = "/wiki/File:" + row.commonsFile
            return SavedGalleryItem(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                title: row.name, location: row.detail, symbol: "fork.knife",
                photoURL: Bundle.main.url(forResource: row.file, withExtension: nil),
                aspectRatio: CGFloat(row.width) / CGFloat(row.height), photoCredit: row.credit,
                photoSource: source.url)
        } + [SavedGalleryItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
                              title: "無照片測試地點", location: "本地測試 · 不會寫入收藏", symbol: "mappin",
                              photoURL: nil, aspectRatio: 1, photoCredit: nil, photoSource: nil)]
    }()
    private var filtered: [SavedGalleryItem] {
        items.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.location.localizedStandardContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved").font(.headline)
                Spacer()
                Menu {
                    Toggle("大字體驗證", isOn: $largeText)
                } label: {
                    Image(systemName: "textformat.size").frame(width: 44, height: 44)
                }.accessibilityLabel("Preview text size")
            }
            SavedGalleryWall(items: filtered,
                palette: SavedGalleryPalette(canvas: SaveBrandUI.canvas, surface: SaveBrandUI.surface,
                    ink: SaveBrandUI.ink, muted: SaveBrandUI.muted, accent: SaveBrandUI.accent, pink: SaveBrandUI.soft),
                chinese: true, lightsOn: $lightsOn, onOpen: { id in selected = items.first { $0.id == id } },
                photo: { item in
                    if let url = item.photoURL, let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                })
            if filtered.isEmpty { Text("沒有符合的地點").accessibilityIdentifier("preview.empty") }
            TextField("搜尋收藏", text: $query)
                .padding(16).background(SaveBrandUI.surface, in: Capsule())
                .accessibilityIdentifier("preview.search")
        }
        .padding(.horizontal, 20).padding(.bottom, 8)
        .background(SaveBrandUI.canvas.ignoresSafeArea())
        .foregroundStyle(SaveBrandUI.ink).tint(SaveBrandUI.accent)
        .preferredColorScheme(lightsOn ? nil : .dark)
        .dynamicTypeSize(largeText ? .accessibility2 : .large)
        .sheet(item: $selected) { item in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let url = item.photoURL, let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image).resizable().scaledToFit()
                        }
                        Text(item.title).font(.title2.bold())
                        Text(item.location)
                        if let credit = item.photoCredit, let source = item.photoSource {
                            Link(credit, destination: source).font(.caption)
                        }
                        Text("本地範例；打開照片不會儲存、分享或標記去過。")
                            .font(.caption).foregroundStyle(SaveBrandUI.muted)
                    }.padding()
                }
                .background(SaveBrandUI.canvas).foregroundStyle(SaveBrandUI.ink)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { selected = nil }.accessibilityIdentifier("preview.close")
                    }
                }
            }.presentationDetents([.medium, .large])
        }
    }
}
