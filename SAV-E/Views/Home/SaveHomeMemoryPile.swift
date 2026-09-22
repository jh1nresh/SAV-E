import SpriteKit
import SwiftUI

/// SpriteKit owns physical positions and gestures; native SwiftUI renders each Map Stamp.
/// The accessible result list remains the unbounded canonical collection.
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
                    .accessibilityHidden(true)
                ForEach(scene.visiblePlaces) { place in
                    if let pose = scene.poses[place.id] {
                        postage(place, loadsPhoto: pose.lifted)
                            .frame(width: 96, height: 122)
                            .scaleEffect(pose.scale)
                            .rotationEffect(.radians(-pose.rotation))
                            .position(x: pose.x, y: geometry.size.height - pose.y)
                            .zIndex(pose.zIndex)
                            // SpriteKit receives native drag/tap input and resolves the exact ID.
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            .clipped()
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

    private func postage(_ place: Place, loadsPhoto: Bool) -> some View {
        VStack(spacing: 5) {
            SaveHomeMemoryPhoto(place: place, loadsPhoto: loadsPhoto)
                .frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(place.name)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(SaveAtlasPalette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
            Text(loadsPhoto ? place.shareAreaLabel : place.category.displayName(language: language.language))
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(SaveAtlasPalette.muted)
                .lineLimit(1)
        }
        .padding(7)
        .frame(width: 96, height: 122)
        .background(SaveAtlasPalette.paper, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(SaveAtlasPalette.line.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        .shadow(color: SaveAtlasPalette.ink.opacity(0.1), radius: 5, x: 1, y: 4)
    }

    private func synchronize(size: CGSize) {
        guard scenePhase == .active else { scene.pause(); return }
        scene.onOpenPlace = { id in
            guard let place = places.first(where: { $0.id == id }) else { return }
            onOpenPlace(place)
        }
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
        let zIndex: Double
    }

    @Published private(set) var isAnimating = true
    @Published private(set) var poses: [UUID: Pose] = [:]
    @Published private(set) var visiblePlaces: [Place] = []
    var onOpenPlace: ((UUID) -> Void)?

    private var stamps: [UUID: SKNode] = [:]
    private var lifted: [UUID] = []
    private var restingIDs: Set<UUID> = []
    private var restingOrder: [UUID] = []
    private let walls = SKNode()
    private var draggingID: UUID?
    private var tappedLiftedID: UUID?
    private var dragStart: CGPoint?
    private var didDrag = false
    private var lastInteraction: TimeInterval = 0
    private var currentTime: TimeInterval = 0
    private var wasSearching = false

    private let stampSize = CGSize(width: 96, height: 122)
    private let simulationCap = 48

    override init() {
        super.init(size: CGSize(width: 358, height: 250))
        scaleMode = .resizeFill
        backgroundColor = .clear
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.5)
        addChild(walls)
    }

    required init?(coder aDecoder: NSCoder) { nil }

    func configure(places: [Place], liftedIDs: [UUID], size: CGSize, searching: Bool) {
        guard size.width > 0, size.height > 0 else { return }
        let oldLifted = lifted
        let resized = self.size != size
        let searchChanged = wasSearching != searching
        self.size = size
        wasSearching = searching
        if draggingID != nil || tappedLiftedID != nil { cancelInteraction() }

        let inventory = Set(places.map(\.id))
        lifted = Array(liftedIDs.filter { inventory.contains($0) }.prefix(3))
        if let draggingID, lifted.contains(draggingID) { cancelDrag() }

        // Only the animated world is capped. Search and the accessible list use all places.
        restingOrder = Array(places.prefix(simulationCap).map(\.id))
        restingIDs = Set(restingOrder)
        let visibleIDs = restingIDs.union(lifted).union(oldLifted)
        visiblePlaces = places.filter { visibleIDs.contains($0.id) }
        let retained = Set(visiblePlaces.map(\.id))
        for id in Array(stamps.keys) where !retained.contains(id) {
            if draggingID == id { cancelDrag() }
            if tappedLiftedID == id {
                tappedLiftedID = nil
                dragStart = nil
                didDrag = false
            }
            stamps.removeValue(forKey: id)?.removeFromParent()
        }

        walls.physicsBody = SKPhysicsBody(edgeLoopFrom: worldBounds)
        walls.physicsBody?.restitution = 0.18
        let restingScale = restingScale(for: restingOrder.count)

        for (visibleIndex, place) in visiblePlaces.enumerated() {
            let id = place.id
            let restingIndex = restingOrder.firstIndex(of: id) ?? visibleIndex
            let isNew = stamps[id] == nil
            let node: SKNode
            if let existing = stamps[id] {
                node = existing
            } else {
                node = makeStampNode(id: id, index: restingIndex, scale: restingScale)
                stamps[id] = node
                addChild(node)
            }

            if let slot = lifted.firstIndex(of: id) {
                let movedToSlot = oldLifted.firstIndex(of: id) != slot
                if isNew || resized || movedToSlot || node.action(forKey: "transition") == nil {
                    lift(node, to: liftedPosition(slot: slot), slot: slot, animated: true)
                }
            } else if oldLifted.contains(id) {
                drop(node, id: id, index: restingIndex, scale: restingScale, keepInPile: restingIDs.contains(id))
            } else if draggingID != id {
                // A resized keyboard/world must not leave an old physics position behind
                // the retrieval row. Re-seat only settled resting records; lifted and
                // transitioning stamps retain their causal motion and identity.
                if !node.hasActions() && (resized || searchChanged || !lowerCollectionContains(node.position, scale: restingScale)) {
                    node.position = restingPosition(index: restingIndex, scale: restingScale)
                    node.setScale(restingScale)
                    restoreRestingPhysics(for: node, index: restingIndex)
                } else if !node.hasActions() {
                    node.setScale(restingScale)
                    node.zPosition = CGFloat(restingIndex)
                }
            }
        }

        wake()
        publishPoses()
    }

#if os(iOS)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        beginDrag(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        moveDrag(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { endDrag() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelInteraction() }
#endif

    /// Shared by SpriteKit touch handling and deterministic scene tests.
    func beginDrag(at point: CGPoint) {
        guard let (id, node) = stamp(at: point) else { return }
        if lifted.contains(id) {
            tappedLiftedID = id
            dragStart = point
            didDrag = false
            wake()
            return
        }
        draggingID = id
        dragStart = point
        didDrag = false
        node.removeAction(forKey: "transition")
        node.physicsBody?.isDynamic = false
        node.physicsBody?.velocity = .zero
        node.physicsBody?.angularVelocity = 0
        node.zPosition = 90
        wake()
        publishPoses()
    }

    /// Shared by SpriteKit touch handling and deterministic scene tests.
    func moveDrag(to point: CGPoint) {
        if tappedLiftedID != nil, let dragStart {
            if hypot(point.x - dragStart.x, point.y - dragStart.y) > 5 {
                tappedLiftedID = nil
                self.dragStart = nil
            }
            wake()
            return
        }
        guard let id = draggingID, let node = stamps[id], let dragStart else { return }
        if hypot(point.x - dragStart.x, point.y - dragStart.y) > 5 { didDrag = true }
        node.position = bounded(point)
        node.zRotation *= 0.82
        wake()
        publishPoses()
    }

    /// Shared by SpriteKit touch handling and deterministic scene tests.
    func endDrag() {
        guard let id = draggingID, let node = stamps[id] else {
            if let tappedLiftedID { onOpenPlace?(tappedLiftedID) }
            tappedLiftedID = nil
            dragStart = nil
            didDrag = false
            return
        }
        let opened = !didDrag
        draggingID = nil
        dragStart = nil
        didDrag = false
        restoreRestingPhysics(for: node, index: restingOrder.firstIndex(of: id) ?? 0)
        if opened { onOpenPlace?(id) }
        wake()
        publishPoses()
    }

    override func update(_ currentTime: TimeInterval) {
        self.currentTime = currentTime
        if lastInteraction == 0 { lastInteraction = currentTime }
    }

    override func didSimulatePhysics() {
        confineRestingNodesToCollectionRegion()
        publishPoses()
        // Bound dense-pile solver work, but never cancel a held stamp or a lift.
        if draggingID == nil, tappedLiftedID == nil,
           currentTime - lastInteraction > 4.5,
           stamps.values.allSatisfy({ !$0.hasActions() }) { pause() }
    }

    func pause() {
        cancelInteraction()
        isPaused = true
        isAnimating = false
    }

    private func makeStampNode(id: UUID, index: Int, scale: CGFloat) -> SKNode {
        let node = SKNode()
        node.name = id.uuidString
        node.setScale(scale)
        node.position = restingPosition(index: index, scale: scale)
        node.zRotation = restingRotation(index: index)
        node.zPosition = CGFloat(index)
        // Circular proxies let the rectangular native stamps retain their varied angles
        // and tumble into an overlapping heap instead of solving into an upright row.
        let body = SKPhysicsBody(circleOfRadius: stampSize.width * 0.29)
        body.restitution = 0.14
        body.friction = 0.72
        body.linearDamping = 1.1
        body.angularDamping = 2.2
        node.physicsBody = body
        return node
    }

    private func lift(_ node: SKNode, to target: CGPoint, slot: Int, animated: Bool) {
        node.removeAction(forKey: "transition")
        node.physicsBody?.isDynamic = false
        node.physicsBody?.collisionBitMask = 0
        node.physicsBody?.velocity = .zero
        node.physicsBody?.angularVelocity = 0
        node.zPosition = CGFloat(100 + slot)
        let targetScale = liftedScale
        guard animated else {
            node.position = target
            node.setScale(targetScale)
            node.zRotation = 0
            return
        }
        let transition = SKAction.group([
            .move(to: target, duration: 0.42),
            .scale(to: targetScale, duration: 0.42),
            .rotate(toAngle: 0, duration: 0.42, shortestUnitArc: true),
        ])
        transition.timingMode = .easeInEaseOut
        node.run(transition, withKey: "transition")
    }

    private func drop(_ node: SKNode, id: UUID, index: Int, scale: CGFloat, keepInPile: Bool) {
        node.removeAction(forKey: "transition")
        let transition = SKAction.group([
            .move(to: restingPosition(index: index, scale: scale), duration: 0.3),
            .scale(to: scale, duration: 0.3),
            .rotate(toAngle: restingRotation(index: index), duration: 0.3, shortestUnitArc: true),
        ])
        transition.timingMode = .easeIn
        node.run(.sequence([transition, .run { [weak self, weak node] in
            guard let self, let node, self.stamps[id] === node, !self.lifted.contains(id) else { return }
            if keepInPile, self.restingIDs.contains(id) {
                self.restoreRestingPhysics(for: node, index: index)
            } else {
                node.removeFromParent()
                self.stamps.removeValue(forKey: id)
                self.visiblePlaces.removeAll { $0.id == id }
                self.poses.removeValue(forKey: id)
            }
        }]), withKey: "transition")
    }

    private func restoreRestingPhysics(for node: SKNode, index: Int) {
        node.physicsBody?.isDynamic = true
        node.physicsBody?.collisionBitMask = UInt32.max
        node.physicsBody?.velocity = .zero
        node.physicsBody?.angularVelocity = 0
        node.zPosition = CGFloat(index)
    }

    private func cancelDrag() {
        guard let id = draggingID, let node = stamps[id] else {
            draggingID = nil
            tappedLiftedID = nil
            dragStart = nil
            didDrag = false
            return
        }
        restoreRestingPhysics(for: node, index: restingOrder.firstIndex(of: id) ?? 0)
        draggingID = nil
        tappedLiftedID = nil
        dragStart = nil
        didDrag = false
    }

    /// Cancelling is a state cleanup boundary, never a navigation event.
    func cancelInteraction() {
        cancelDrag()
        tappedLiftedID = nil
        dragStart = nil
        didDrag = false
        publishPoses()
    }

    private func stamp(at point: CGPoint) -> (UUID, SKNode)? {
        stamps
            .compactMap { id, node -> (UUID, SKNode)? in
                let localPoint = node.convert(point, from: self)
                let localFrame = CGRect(
                    x: -stampSize.width / 2,
                    y: -stampSize.height / 2,
                    width: stampSize.width,
                    height: stampSize.height
                )
                guard localFrame.contains(localPoint) else { return nil }
                return (id, node)
            }
            .max { $0.1.zPosition < $1.1.zPosition }
    }

    private var worldBounds: CGRect {
        let horizontal = min(stampSize.width * 0.42, max(18, size.width / 7))
        let vertical = min(18, max(10, size.height / 20))
        return CGRect(
            x: horizontal,
            y: vertical,
            width: max(1, size.width - horizontal * 2),
            height: max(1, size.height - vertical * 2)
        )
    }

    private func bounded(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, worldBounds.minX), worldBounds.maxX),
            y: min(max(point.y, worldBounds.minY), worldBounds.maxY)
        )
    }

    private func restingPosition(index: Int, scale: CGFloat) -> CGPoint {
        let columns = restingOrder.count <= 6 ? 3 : max(3, min(7, Int(size.width / 64)))
        let column = index % columns
        let row = index / columns
        let span = max(1, worldBounds.width - stampSize.width * 0.2)
        let x = worldBounds.minX + stampSize.width * 0.1 + span * CGFloat(column) / CGFloat(max(1, columns - 1))
        let y = min(
            lowerCollectionCeiling(for: scale),
            worldBounds.minY + stampSize.height * scale / 2 + 6 + CGFloat(row % 5) * 17
        )
        return bounded(CGPoint(x: x, y: y))
    }

    private func lowerCollectionContains(_ point: CGPoint, scale: CGFloat) -> Bool {
        point.y >= worldBounds.minY && point.y <= lowerCollectionCeiling(for: scale)
    }

    private func lowerCollectionCeiling(for scale: CGFloat) -> CGFloat {
        let cardCenterFloor = worldBounds.minY + stampSize.height * scale / 2
        let belowComposer = size.height * 0.52 - stampSize.height * scale / 2 - 6
        return max(cardCenterFloor, min(worldBounds.maxY, size.height * 0.42, belowComposer))
    }

    private func confineRestingNodesToCollectionRegion() {
        let scale = restingScale(for: restingOrder.count)
        for (id, node) in stamps where !lifted.contains(id) && draggingID != id && !node.hasActions() {
            guard !lowerCollectionContains(node.position, scale: scale) else { continue }
            let index = restingOrder.firstIndex(of: id) ?? 0
            node.position = restingPosition(index: index, scale: scale)
            node.setScale(scale)
            restoreRestingPhysics(for: node, index: index)
        }
    }

    private func liftedPosition(slot: Int) -> CGPoint {
        let displayY = min(74, size.height * 0.22)
        return CGPoint(x: size.width * CGFloat(slot * 2 + 1) / 6, y: size.height - displayY)
    }

    private var liftedScale: CGFloat {
        let normal = min(1.08, max(0.92, (size.width / 3 - 14) / stampSize.width))
        guard size.height < 360 else { return normal }
        return min(normal, max(0.7, size.height * 0.32 / stampSize.height))
    }

    private func restingScale(for count: Int) -> CGFloat {
        switch count {
        case ...6: return 0.95
        case ...20: return 0.74
        default: return 0.58
        }
    }

    private func restingRotation(index: Int) -> CGFloat {
        CGFloat((index * 7) % 11 - 5) * 0.045
    }

    private func wake() {
        lastInteraction = currentTime
        isPaused = false
        isAnimating = true
    }

    private func publishPoses() {
        poses = stamps.mapValues { node in
            Pose(
                x: node.position.x,
                y: node.position.y,
                scale: node.xScale,
                rotation: node.zRotation,
                lifted: node.name.flatMap(UUID.init(uuidString:)).map(lifted.contains) ?? false,
                zIndex: Double(node.zPosition)
            )
        }
    }
}
