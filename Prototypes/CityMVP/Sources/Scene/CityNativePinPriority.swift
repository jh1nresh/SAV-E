#if SAVVY_CITY_MVP
import SwiftUI
import MapKit
import UIKit

/// Give the selected native annotation the same foreground priority as the
/// selected scene sprite. Uses public MapKit properties, never its delegate.
struct CityNativePinPriority: UIViewRepresentable {
    func makeUIView(context: Context) -> CityNativePinPriorityHost {
        CityNativePinPriorityHost(frame: .zero)
    }
    func updateUIView(_ view: CityNativePinPriorityHost, context: Context) {
        view.synchronize()
    }
    static func dismantleUIView(_ view: CityNativePinPriorityHost, coordinator: ()) {
        view.restore()
    }
}

final class CityNativePinPriorityHost: UIView {
    private final class Lease {
        let display: MKFeatureDisplayPriority
        let z: MKAnnotationViewZPriority
        let selectedZ: MKAnnotationViewZPriority
        var owners = 0
        init(_ view: MKAnnotationView) {
            display = view.displayPriority; z = view.zPriority; selectedZ = view.selectedZPriority
        }
    }
    private static let leases = NSMapTable<MKAnnotationView, Lease>.weakToStrongObjects()
    private weak var annotationView: MKAnnotationView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { nil }
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        synchronize()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        synchronize()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        synchronize()
    }
    func synchronize() {
        var ancestor = superview
        while let view = ancestor, !(view is MKAnnotationView) { ancestor = view.superview }
        let next = ancestor as? MKAnnotationView
        guard next !== annotationView else { return }
        restore()
        guard let next else { return }
        annotationView = next
        let lease = Self.leases.object(forKey: next) ?? Lease(next)
        lease.owners += 1
        Self.leases.setObject(lease, forKey: next)
        next.displayPriority = .required
        next.zPriority = .max
        next.selectedZPriority = .max
    }
    func restore() {
        if let view = annotationView, let original = Self.leases.object(forKey: view) {
            original.owners -= 1
            guard original.owners == 0 else { annotationView = nil; return }
            Self.leases.removeObject(forKey: view)
            // Leave a subsequent owner's explicit changes alone.
            if view.displayPriority == .required { view.displayPriority = original.display }
            if view.zPriority == .max { view.zPriority = original.z }
            if view.selectedZPriority == .max { view.selectedZPriority = original.selectedZ }
        }
        annotationView = nil
    }
}
#endif
