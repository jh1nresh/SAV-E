import SpriteKit
import SwiftUI

/// SpriteKit owns only motion. The postcards remain native SwiftUI views with cached photos.
/// A separate, unbounded result list is the canonical accessible collection.
struct SaveHomeMemoryPile: View {
    let places: [Place]
    let liftedIDs: [UUID]
    let isSearching: Bool
    let onOpenPlace: (Place) -> Void
    @StateObject private var scene = SaveHomeMemoryScene()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appLanguageSettings) private var language

    private var input: Input { Input(places: places, liftedIDs: liftedIDs, isSearching: isSearching) }
    private struct Input: Equatable {
        let places: [Place]
        let liftedIDs: [UUID]
        let isSearching: Bool
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                SpriteView(scene: scene, isPaused: !scene.isAnimating, preferredFramesPerSecond: 30, options: [.allowsTransparency])
                    .allowsHitTesting(false)
                ForEach(scene.visiblePlaces) { place in
                    if let pose = scene.poses[place.id] {
                        Button { onOpenPlace(place) } label: {
                            postage(place)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 76, height: 92)
                        .scaleEffect(pose.scale)
                        .rotationEffect(.radians(-pose.rotation))
                        .position(x: pose.x, y: geometry.size.height - pose.y)
                        .zIndex(pose.lifted ? 100 : 0)
                    }
                }
            }
            .clipped()
            // Moving targets are decorative for assistive technology; every place is also
            // a full-size accessible button in the result list immediately after this view.
            .accessibilityHidden(true)
            .onAppear { synchronize(size: geometry.size) }
            .onChange(of: geometry.size) { _, size in synchronize(size: size) }
            .onChange(of: input) { _, _ in synchronize(size: geometry.size) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { synchronize(size: geometry.size) }
                else { scene.pause() }
            }
            .onDisappear { scene.pause() }
        }
    }

    private func postage(_ place: Place) -> some View {
        VStack(spacing: 4) {
            SaveHomeMemoryPhoto(place: place)
                .frame(height: 49)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(place.name)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(SaveAtlasPalette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 25, alignment: .top)
        }
        .padding(6)
        .frame(width: 76, height: 92)
        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(SaveAtlasPalette.line.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.1), radius: 3, y: 2)
    }

    private func synchronize(size: CGSize) {
        guard scenePhase == .active else { scene.pause(); return }
        scene.configure(places: places, liftedIDs: liftedIDs, size: size, searching: isSearching)
    }
}

@MainActor
final class SaveHomeMemoryScene: SKScene, ObservableObject {
    struct Pose {
        let x: CGFloat
        let y: CGFloat
        let scale: CGFloat
        let rotation: CGFloat
        let lifted: Bool
    }

    @Published private(set) var isAnimating = true
    @Published private(set) var poses: [UUID: Pose] = [:]
    @Published private(set) var visiblePlaces: [Place] = []
    private var stamps: [UUID: SKNode] = [:]
    private var lifted: [UUID] = []
    private var restingIDs: Set<UUID> = []
    private let walls = SKNode()
    private var lastInteraction: TimeInterval = 0
    private var currentTime: TimeInterval = 0
    private var searching = false
    private let restingScale: CGFloat = 0.62

    override init() {
        super.init(size: CGSize(width: 358, height: 168))
        scaleMode = .resizeFill
        backgroundColor = .clear
        physicsWorld.gravity = CGVector(dx: 0, dy: -8)
        addChild(walls)
    }

    required init?(coder aDecoder: NSCoder) { return nil }

    func configure(places: [Place], liftedIDs: [UUID], size: CGSize, searching: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let oldLifted = lifted
        let resized = self.size != size
        self.size = size
        self.searching = searching
        let inventory = Set(places.map(\.id))
        lifted = Array(liftedIDs.filter { inventory.contains($0) }.prefix(3))
        // Only the visual simulation is capped. Search and the accessible list use all places.
        restingIDs = Set(places.prefix(24).map(\.id))
        let visibleIDs = restingIDs.union(lifted).union(oldLifted)
        visiblePlaces = places.filter { visibleIDs.contains($0.id) }
        let retained = Set(visiblePlaces.map(\.id))
        for id in Array(stamps.keys) where !retained.contains(id) {
            stamps.removeValue(forKey: id)?.removeFromParent()
        }
        walls.physicsBody = SKPhysicsBody(edgeLoopFrom: CGRect(x: 0, y: 0, width: size.width, height: pileHeight))
        walls.physicsBody?.restitution = 0.25

        for (index, place) in visiblePlaces.enumerated() {
            let isNew = stamps[place.id] == nil
            let node: SKNode
            if let existing = stamps[place.id] { node = existing }
            else {
                node = SKNode()
                node.name = place.id.uuidString
                node.setScale(restingScale)
                // Rounded collision bodies let the postage edges overlap like a real handful.
                let body = SKPhysicsBody(circleOfRadius: 28)
                body.restitution = 0.2
                body.friction = 0.7
                body.linearDamping = 0.9
                body.angularDamping = 1.8
                node.physicsBody = body
                let column = CGFloat(index % 7)
                node.position = CGPoint(x: 30 + column * (size.width - 60) / 6, y: 28 + CGFloat(index / 7) * 22)
                node.zRotation = CGFloat((index * 7) % 11 - 5) * 0.06
                stamps[place.id] = node
                addChild(node)
            }
            if let slot = lifted.firstIndex(of: place.id) {
                // A named action replaces an in-flight lift, starting at the current pose.
                // No delayed callback can resurrect a removed filter's old result.
                if isNew || resized || oldLifted.firstIndex(of: place.id) != slot {
                    node.removeAction(forKey: "lift")
                    node.physicsBody?.isDynamic = false
                    node.physicsBody?.collisionBitMask = 0
                    node.physicsBody?.velocity = .zero
                    node.physicsBody?.angularVelocity = 0
                    let target = CGPoint(x: size.width * CGFloat(slot * 2 + 1) / 6, y: size.height - 67)
                    let actions = SKAction.group([
                        .move(to: target, duration: 0.48),
                        .scale(to: min(1.22, (size.width / 3 - 10) / 76), duration: 0.48),
                        .rotate(toAngle: 0, duration: 0.48, shortestUnitArc: true),
                    ])
                    actions.timingMode = .easeInEaseOut
                    node.run(actions, withKey: "lift")
                }
            } else {
                if oldLifted.contains(place.id) {
                    node.removeAction(forKey: "lift")
                    let drop = SKAction.group([
                        .move(to: CGPoint(x: min(max(node.position.x, 28), size.width - 28), y: pileHeight - 28), duration: 0.28),
                        .scale(to: restingScale, duration: 0.28),
                        .rotate(toAngle: CGFloat((index * 7) % 11 - 5) * 0.06, duration: 0.28),
                    ])
                    drop.timingMode = .easeIn
                    node.run(.sequence([drop, .run { [weak self, weak node] in
                        guard let self, let node, self.stamps[place.id] === node,
                              !self.lifted.contains(place.id) else { return }
                        if self.restingIDs.contains(place.id) {
                            node.physicsBody?.isDynamic = true
                            node.physicsBody?.collisionBitMask = UInt32.max
                        } else {
                            node.removeFromParent()
                            self.stamps.removeValue(forKey: place.id)
                            self.visiblePlaces.removeAll { $0.id == place.id }
                            self.poses.removeValue(forKey: place.id)
                        }
                    }]), withKey: "lift")
                } else if resized {
                    node.position.x = min(max(node.position.x, 24), size.width - 24)
                    node.position.y = min(max(node.position.y, 24), pileHeight - 24)
                }
            }
        }
        lastInteraction = 0
        isPaused = false
        isAnimating = true
        publishPoses()
    }

    private var pileHeight: CGFloat { min(112, size.height - 12) }

    override func update(_ currentTime: TimeInterval) {
        self.currentTime = currentTime
        if lastInteraction == 0 { lastInteraction = currentTime }
    }

    override func didSimulatePhysics() {
        publishPoses()
        // Stop frame work once the collection has settled; every new input wakes it.
        if currentTime - lastInteraction > 5, stamps.values.allSatisfy({ !$0.hasActions() }) {
            pause()
        }
    }

    func pause() {
        isPaused = true
        isAnimating = false
    }

    private func publishPoses() {
        poses = stamps.mapValues { node in
            Pose(x: node.position.x, y: node.position.y, scale: node.xScale,
                 rotation: node.zRotation, lifted: node.name.flatMap(UUID.init(uuidString:)).map(lifted.contains) ?? false)
        }
    }
}
