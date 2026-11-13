#if SAVVY_CITY_MVP
import SwiftUI
import UIKit
import MapKit

struct CityNativeBuildingSettingRecord: Equatable {
    let bound: Bool
    let bindingGeneration: Int
    let hostGeneration: Int
    let invalidated: Bool
    let original: Bool?
    let requested: Bool?
    let actual: Bool?
    let requestOff: Bool
    let revision: Int
    let configuration: String
    let elevation: String
    let emphasis: String
    let discovery: String
    let offApplications: Int
    let restorations: Int

    var fields: [String: Any] {
        ["bound": bound, "bindingGeneration": bindingGeneration, "hostGeneration": hostGeneration, "event": invalidated ? "invalidation" : "readback", "original": original.map { $0 as Any } ?? NSNull(),
         "requested": requested.map { $0 as Any } ?? NSNull(), "actual": actual.map { $0 as Any } ?? NSNull(),
         "requestOff": requestOff, "revision": revision, "configuration": configuration,
         "elevation": elevation, "emphasis": emphasis, "discovery": discovery,
         "offApplications": offApplications, "restorations": restorations]
    }
}

/// Isolated public-API experiment; never owns the map configuration, camera,
/// delegate or gestures. Repeated updates may observe an overwrite, not repair it.
struct CityNativeBuildingSettingProbe: UIViewRepresentable {
    let off: Bool
    let cameraReady: Bool
    let revision: Int
    let onRecord: (CityNativeBuildingSettingRecord) -> Void

    func makeUIView(context: Context) -> CityNativeBuildingSettingHost {
        CityNativeBuildingSettingHost(frame: .zero)
    }
    func updateUIView(_ host: CityNativeBuildingSettingHost, context: Context) {
        host.configure(off: off, cameraReady: cameraReady, revision: revision, onRecord: onRecord)
    }
    static func dismantleUIView(_ host: CityNativeBuildingSettingHost, coordinator: ()) {
        host.detach()
    }
}

@MainActor
final class CityNativeBuildingSettingHost: UIView {
    private static var nextGeneration = 0
    private static func allocateGeneration() -> Int {
        nextGeneration += 1
        return nextGeneration
    }
    // Host order also rejects an old host's LATER detach callback, whose
    // binding-generation allocation can legitimately follow a newer host.
    private let hostGeneration = CityNativeBuildingSettingHost.allocateGeneration()
    private weak var map: MKMapView?
    private var bindingGeneration = 0
    private let originals = NSMapTable<MKMapView, NSNumber>.weakToStrongObjects()
    private var original: Bool?
    private var offApplied = false
    private var off = false
    private var cameraReady = false
    private var revision = 0
    private var onRecord: (CityNativeBuildingSettingRecord) -> Void = { _ in }
    private var lastPublished: CityNativeBuildingSettingRecord?
    private var discovery = "missing"
    private var fallbackScheduled = false
    private var readbackScheduled = false
    private var offApplications = 0
    private var restorations = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { nil }

    func configure(off: Bool, cameraReady: Bool, revision: Int,
                   onRecord: @escaping (CityNativeBuildingSettingRecord) -> Void) {
        self.off = off
        self.cameraReady = cameraReady
        self.revision = revision
        self.onRecord = onRecord
        reconcileSetting()
        setNeedsLayout()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { detach(); return }
        discoverMap()
        setNeedsLayout()
        // Exactly one next-main-loop discovery fallback per host lifetime.
        // Later discovery happens only through normal UIKit lifecycle callbacks.
        if !fallbackScheduled {
            fallbackScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.discoverMap()
                self.setNeedsLayout()
            }
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard window != nil else { return }
        discoverMap()
        if cameraReady { scheduleReadback() }
    }
    func detach() {
        guard map != nil || original != nil || offApplied else { return }
        restore()
        map = nil
        original = nil
        discovery = "missing"
        bindingGeneration = Self.allocateGeneration()
        publishInvalidation()
    }
    private func discoverMap() {
        var ancestor = superview
        var found: MKMapView?
        var result = "missing"
        while let node = ancestor {
            let maps = Self.maps(in: node)
            if maps.count > 1 { result = "ambiguous"; break }
            if let only = maps.first { found = only; result = "bound"; break }
            ancestor = node.superview
        }
        discovery = result
        if found === map && !(found == nil && original != nil) {
            reconcileSetting()
            return
        }
        restore()
        map = found
        bindingGeneration = Self.allocateGeneration()
        // Invalidate the old binding before a replacement can supply a read.
        // This event is delivered even if the host has left its window.
        publishInvalidation()
        if let found {
            let saved = originals.object(forKey: found) ?? NSNumber(value: found.showsBuildings)
            originals.setObject(saved, forKey: found)
            original = saved.boolValue
        } else { original = nil }
        reconcileSetting()
    }
    private static func maps(in view: UIView) -> [MKMapView] {
        if let map = view as? MKMapView { return [map] }
        var result: [MKMapView] = []
        for child in view.subviews {
            result.append(contentsOf: maps(in: child))
            if result.count > 1 { break }
        }
        return result
    }
    private func reconcileSetting() {
        guard window != nil, let map else { return }
        if off && !offApplied {
            map.showsBuildings = false
            offApplied = true
            offApplications += 1
        } else if !off && offApplied { restore() }
    }
    private func restore() {
        guard offApplied else { return }
        if let map, let original {
            map.showsBuildings = original
            restorations += 1
        }
        offApplied = false
    }
    private func publishInvalidation() {
        let generation = bindingGeneration
        let record = CityNativeBuildingSettingRecord(
            bound: false, bindingGeneration: generation, hostGeneration: hostGeneration, invalidated: true,
            original: nil, requested: off ? false : nil, actual: nil,
            requestOff: off, revision: revision, configuration: "unbound", elevation: "unknown",
            emphasis: "unknown", discovery: discovery, offApplications: offApplications, restorations: restorations)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.bindingGeneration == generation else { return }
            guard record != self.lastPublished else { return }
            self.lastPublished = record
            self.onRecord(record)
        }
    }
    private func scheduleReadback() {
        guard !readbackScheduled else { return }
        readbackScheduled = true
        let layoutRevision = revision
        let layoutOff = off
        let layoutBinding = bindingGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.readbackScheduled = false
            guard self.window != nil, self.cameraReady else { return }
            guard self.bindingGeneration == layoutBinding, self.revision == layoutRevision, self.off == layoutOff else {
                self.setNeedsLayout()
                return
            }
            // Read only after a camera-ready layout. Any SwiftUI rewrite is
            // recorded verbatim; this path NEVER reapplies showsBuildings.
            let standard = self.map?.preferredConfiguration as? MKStandardMapConfiguration
            let elevation: String
            switch standard?.elevationStyle {
            case .flat?: elevation = "flat"
            case .realistic?: elevation = "realistic"
            default: elevation = "unknown"
            }
            let emphasis: String
            switch standard?.emphasisStyle {
            case .default?: emphasis = "default"
            case .muted?: emphasis = "muted"
            default: emphasis = "unknown"
            }
            let record = CityNativeBuildingSettingRecord(
                bound: self.map != nil, bindingGeneration: self.bindingGeneration, hostGeneration: self.hostGeneration, invalidated: false,
                original: self.original,
                requested: self.off ? false : self.original, actual: self.map?.showsBuildings,
                requestOff: self.off, revision: self.revision,
                configuration: standard == nil ? "non-standard-or-missing" : "standard",
                elevation: elevation, emphasis: emphasis, discovery: self.discovery,
                offApplications: self.offApplications, restorations: self.restorations)
            guard record != self.lastPublished else { return }
            self.lastPublished = record
            self.onRecord(record)
        }
    }
}
#endif
