import SwiftUI

/// Presentation only: illuminating a frame never marks a place visited or saves it.
struct SavedGalleryItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let location: String
    let symbol: String
    let photoURL: URL?
    let aspectRatio: CGFloat
    let photoCredit: String?
    let photoSource: URL?
    var markedVisited = false
}

struct SavedGalleryPalette {
    let canvas: Color
    let surface: Color
    let ink: Color
    let muted: Color
    let accent: Color
    let pink: Color
}

@MainActor
struct SavedGalleryWall<Photo: View>: View {
    let items: [SavedGalleryItem]
    let palette: SavedGalleryPalette
    let chinese: Bool
    @Binding var lightsOn: Bool
    let onOpen: (UUID) -> Void
    @ViewBuilder let photo: (SavedGalleryItem) -> Photo
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var revealed = Set<UUID>()
    @State private var spotlight: CGPoint?
    @State private var activeFrame: UUID?
    @State private var cordDrag = CGSize.zero
    @State private var bounds: [UUID: CGRect] = [:]

    private var singleColumn: Bool { typeSize.isAccessibilitySize || voiceOver }
    private var spotlightTitle: String? {
        guard let spotlight else { return nil }
        return items.first { bounds[$0.id]?.contains(spotlight) == true }?.title
    }
    private var spring: Animation? { reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.64) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                Spacer()
                Button(action: toggleLights) {
                    Text(lightsOn ? (chinese ? "燈亮著" : "Lights on") : (chinese ? "夜間探索" : "After hours"))
                        .font(.caption.weight(.medium)).padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(palette.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("gallery.lights")
                .accessibilityLabel(chinese ? "切換收藏館燈光" : "Toggle gallery lighting")
                .accessibilityValue(lightsOn ? "On" : "Off")
                Spacer()
                bulbControl
            }
            .foregroundStyle(palette.ink)
            .padding(.bottom, 12)
            .zIndex(2)

            ScrollView {
            HStack(alignment: .top, spacing: 22) {
                ForEach(0..<(singleColumn ? 1 : 2), id: \.self) { column in
                    LazyVStack(spacing: 14) {
                        ForEach(Array(items.enumerated()).filter { singleColumn || $0.offset % 2 == column }, id: \.element.id) { index, item in
                            frame(item, index: index)
                        }
                    }.frame(maxWidth: .infinity)
                    .padding(.top, column == 1 ? 18 : 0)
                }
            }
            .padding(.horizontal, 12).padding(.trailing, singleColumn ? 0 : 30)
            .padding(.top, 4).padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .top) {
                LinearGradient(colors: [palette.canvas, palette.canvas.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16).allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [palette.canvas.opacity(0), palette.canvas], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16).allowsHitTesting(false)
            }

            HStack(spacing: 12) {
                torchControl
                Text(spotlightTitle ?? (lightsOn
                    ? (chinese ? "你的私人收藏館" : "Your private collection")
                    : (chinese ? "用光，找回想去的地方" : "A little light. A place to go.")))
                    .font(.caption).foregroundStyle(palette.ink)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(palette.surface, in: Capsule())
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
            }.padding(.top, 8).padding(.bottom, 4)

        }
        .background(palette.canvas)
        .environment(\.colorScheme, lightsOn ? systemScheme : .dark)
        .coordinateSpace(name: "saved.gallery")
        .onPreferenceChange(GalleryFrameBounds.self) { bounds = $0 }
        .overlay { if !lightsOn, let spotlight, !reduceMotion { beam(to: spotlight).allowsHitTesting(false) } }
        .onChange(of: items.map(\.id)) { _, ids in
            revealed.formIntersection(ids)
            bounds = bounds.filter { ids.contains($0.key) }
            spotlight = nil
            activeFrame = nil
        }
    }

    private func frame(_ item: SavedGalleryItem, index: Int) -> some View {
        let illuminated = lightsOn || revealed.contains(item.id)
        let ratio: CGFloat = index % 5 == 4 ? 1.35 : (index % 2 == 0 ? 0.76 : 0.84)
        return Button { onOpen(item.id) } label: {
            VStack(spacing: 5) {
                GalleryPictureLight(lit: illuminated, palette: palette)
                    .frame(width: 38, height: 12).accessibilityHidden(true)
                Color.clear.aspectRatio(ratio, contentMode: .fit)
                    .overlay {
                        if item.photoURL != nil {
                            photo(item).saturation(illuminated ? 1 : 0).opacity(illuminated ? 1 : 0.4)
                                .overlay {
                                    if !illuminated, let spotlight {
                                        GeometryReader { geometry in
                                            let rect = geometry.frame(in: .named("saved.gallery"))
                                            photo(item).frame(width: geometry.size.width, height: geometry.size.height)
                                                .mask {
                                                    Circle().fill(.white).frame(width: 110, height: 110)
                                                        .blur(radius: reduceMotion ? 0 : 12)
                                                        .position(x: spotlight.x - rect.minX, y: spotlight.y - rect.minY)
                                                }
                                        }
                                    }
                                }
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: item.symbol).font(.title3)
                                Text(chinese ? "尚無照片" : "No photo yet").font(.caption)
                            }.foregroundStyle(palette.muted)
                        }
                    }
                    .clipped()
                    .padding(10)
                    .background(palette.surface)
                    .overlay { GalleryFrame(style: index % 3, palette: palette).allowsHitTesting(false) }
                    .shadow(color: palette.ink.opacity(0.12), radius: 2, x: 1, y: 2)
                Text(item.title).font(.caption2.weight(.medium))
                    .foregroundStyle(palette.ink).lineLimit(singleColumn ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if singleColumn {
                    Text(item.location).font(.caption).foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if item.markedVisited {
                    Text(chinese ? "標記去過" : "Marked visited").font(.caption2).foregroundStyle(palette.muted)
                }
            }
            .frame(maxWidth: singleColumn ? 220 : .infinity)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: GalleryFrameBounds.self,
                                       value: [item.id: geometry.frame(in: .named("saved.gallery"))])
            })
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: illuminated)
            .contentShape(Rectangle())
        }
        .buttonStyle(GalleryPressStyle(reduceMotion: reduceMotion))
        .accessibilityIdentifier("live.library.place.\(item.id.uuidString)")
        .accessibilityLabel(item.title + ", " + item.location + (item.markedVisited ? (chinese ? "，標記去過" : ", marked visited") : ""))
        .accessibilityValue(illuminated ? "Illuminated" : "Dim")
        .accessibilityHint(chinese ? "開啟地點詳細資訊" : "Open place details")
        .contextMenu {
            if let credit = item.photoCredit, let source = item.photoSource { Link(credit, destination: source) }
        }
    }

    private var bulbControl: some View {
        Button(action: toggleLights) {
            Image(systemName: lightsOn ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(palette.accent)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chinese ? "拉燈開關" : "Gallery light switch")
        .accessibilityIdentifier("gallery.bulb")
        .overlay(alignment: .top) {
            cord.allowsHitTesting(false)
            Image(systemName: "drop.fill")
                .font(.system(size: 13)).foregroundStyle(palette.pink)
                .shadow(color: palette.accent.opacity(0.3), radius: 3)
                .frame(width: 44, height: 44).contentShape(Rectangle())
                .offset(x: cordDrag.width, y: 90 + cordDrag.height)
                .rotationEffect(.degrees(Double(cordDrag.width) * 0.15), anchor: .top)
                .gesture(DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        cordDrag = CGSize(width: max(-70, min(40, value.translation.width)),
                                          height: max(-10, min(90, value.translation.height)))
                    }
                    .onEnded { value in
                        if value.translation.height > 28 { toggleLights() }
                        withAnimation(spring) { cordDrag = .zero }
                    })
                .accessibilityHidden(true)
        }
    }
    private var cord: some View {
        GalleryCord(displacement: cordDrag)
        .stroke(palette.muted.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .accessibilityHidden(true)
    }
    private var torchControl: some View {
        Image(systemName: "flashlight.on.fill")
            .font(.system(size: 28)).rotationEffect(.degrees(32))
            .foregroundStyle(palette.accent).frame(width: 56, height: 64)

            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("saved.gallery"))
                .onChanged { value in
                    guard !lightsOn else { return }
                    spotlight = value.location
                    let hit = items.first { bounds[$0.id]?.contains(value.location) == true }?.id
                    if activeFrame != hit {
                        if let activeFrame { revealed.insert(activeFrame) }
                        activeFrame = hit
                    }
                }
                .onEnded { _ in
                    withAnimation(spring) {
                        if let activeFrame { revealed.insert(activeFrame) }
                        activeFrame = nil
                        spotlight = nil
                    }
                })
            .accessibilityLabel(chinese ? "探索收藏" : "Rediscover saved places")
            .accessibilityHint(chinese ? "點兩下照亮下一個地方" : "Double tap to illuminate the next place")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if lightsOn { toggleLights() }
                if let next = items.first(where: { !revealed.contains($0.id) }) { revealed.insert(next.id) }
            }
            .accessibilityIdentifier("gallery.torch")
    }
    private func beam(to point: CGPoint) -> some View {
        GeometryReader { geometry in
            let source = CGPoint(x: 28, y: geometry.size.height - 40)
            Canvas { context, _ in
                var path = Path()
                path.move(to: source)
                path.addLine(to: CGPoint(x: point.x - 40, y: point.y))
                path.addQuadCurve(to: CGPoint(x: point.x + 40, y: point.y), control: CGPoint(x: point.x, y: point.y - 24))
                path.closeSubpath()
                context.fill(path, with: .linearGradient(Gradient(colors: [.clear, palette.pink.opacity(0.24)]),
                                                         startPoint: source, endPoint: point))
                context.fill(Path(ellipseIn: CGRect(x: point.x - 40, y: point.y - 40, width: 80, height: 80)),
                             with: .radialGradient(Gradient(colors: [.white.opacity(0.22), .clear]),
                                                   center: point, startRadius: 5, endRadius: 40))
            }
        }.accessibilityHidden(true)
    }
    private func toggleLights() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            lightsOn.toggle()
            revealed.removeAll()
            spotlight = nil
            activeFrame = nil
        }
    }
}

/// The curve participates in the same spring as the pull handle; a raw Path
/// would snap back while the handle animates.
nonisolated private struct GalleryCord: Shape {
    var displacement: CGSize
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(displacement.width, displacement.height) }
        set { displacement = CGSize(width: newValue.first, height: newValue.second) }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 22, y: 35))
        path.addQuadCurve(to: CGPoint(x: 22 + displacement.width, y: 104 + displacement.height),
                         control: CGPoint(x: 22 + displacement.width * 0.15, y: 80))
        return path
    }
}

nonisolated private struct GalleryFrameBounds: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct GalleryPressStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

private struct GalleryFrame: View {
    let style: Int
    let palette: SavedGalleryPalette
    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            ZStack {
                Rectangle().strokeBorder(palette.ink.opacity(0.9), lineWidth: 1)
                Rectangle().inset(by: 2).strokeBorder(style == 1 ? palette.accent : palette.pink, lineWidth: 5)
                Rectangle().inset(by: 6).strokeBorder(palette.ink.opacity(0.8), lineWidth: 1)
                Rectangle().inset(by: 8).strokeBorder(palette.accent.opacity(0.45), lineWidth: 1)
                if style == 0 {
                    Path { path in
                        for x in stride(from: CGFloat(4), to: rect.width - 4, by: 4) {
                            path.addEllipse(in: CGRect(x: x, y: 3, width: 1.5, height: 1.5))
                            path.addEllipse(in: CGRect(x: x, y: rect.height - 4.5, width: 1.5, height: 1.5))
                        }
                        for y in stride(from: CGFloat(7), to: rect.height - 6, by: 4) {
                            path.addEllipse(in: CGRect(x: 3, y: y, width: 1.5, height: 1.5))
                            path.addEllipse(in: CGRect(x: rect.width - 4.5, y: y, width: 1.5, height: 1.5))
                        }
                    }.fill(palette.accent)
                } else if style == 1 {
                    Path { path in
                        for y in stride(from: CGFloat(9), to: rect.height - 6, by: 12) {
                            path.move(to: CGPoint(x: 0, y: y - 5))
                            path.addLine(to: CGPoint(x: -4, y: y))
                            path.addLine(to: CGPoint(x: 0, y: y + 5))
                            path.move(to: CGPoint(x: rect.width, y: y - 5))
                            path.addLine(to: CGPoint(x: rect.width + 4, y: y))
                            path.addLine(to: CGPoint(x: rect.width, y: y + 5))
                        }
                    }.fill(palette.accent)
                }
            }
        }

    }
}

private struct GalleryPictureLight: View {
    let lit: Bool
    let palette: SavedGalleryPalette
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(palette.accent.opacity(0.7)).frame(width: 2, height: 12)
            Capsule().fill(lit ? palette.pink : palette.muted.opacity(0.4)).frame(height: 5)
                .overlay(Capsule().stroke(palette.accent, lineWidth: 1.2))
                .shadow(color: lit ? palette.pink.opacity(0.65) : .clear, radius: 5, y: 3)
        }
    }
}
