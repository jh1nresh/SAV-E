import XCTest
import SwiftUI
import MapKit
#if canImport(SAVE)
@testable import SAVE
#else
@testable import SavvyCityMVP
#endif

@MainActor
final class CityContextLabelTests: XCTestCase {
    private func label(_ id: Int64, x: CGFloat, y: CGFloat, category: CityContextPlace.Category = .food) -> CityContextLabel {
        .init(place: .init(type: .node, osmID: id, originalName: "同名分店", englishName: nil,
             latitude: 25.034, longitude: 121.564, category: category, positionKind: .sourceNode),
              bounds: CGRect(x: x, y: y, width: 60, height: 44))
    }
    func testCollisionPriorityAndChromeClearancePreserveSourceIdentities() {
        let entries = [label(1,x:20,y:150),label(2,x:20,y:150,category:.transit),
                       label(3,x:150,y:150),label(4,x:150,y:300)]
        let output = CityContextLabels.declutter(entries,viewport:.init(width:393,height:852),
                                                reserved:[CGRect(x:0,y:280,width:393,height:80)])
        XCTAssertEqual(output.map(\.id),["node/2","node/3"])
        XCTAssertEqual(output[0].place.originalName,output[1].place.originalName)
        XCTAssertNotEqual(output[0].place.sourceURL,output[1].place.sourceURL)
        XCTAssertEqual(output[0].bounds,entries[1].bounds)
    }
    func testViewportLimitsCountAndRejectsOffscreenTargets() {
        var entries: [CityContextLabel] = []
        for number in 1...100 {
            let x = CGFloat((number-1) % 10) * 75 + 15
            let y = CGFloat((number-1) / 10) * 60 + 15
            entries.append(label(Int64(number), x: x, y: y))
        }
        let viewport=CGSize(width:800,height:800)
        let output=CityContextLabels.declutter(entries,viewport:viewport,reserved:[])
        XCTAssertEqual(output.count,24)
        XCTAssertTrue(output.allSatisfy { CGRect(origin:.zero,size:viewport).contains($0.bounds) })
        XCTAssertEqual(output.map(\.id), CityContextLabels.declutter(Array(entries.reversed()),viewport:viewport,reserved:[]).map(\.id))
        XCTAssertTrue(CityContextLabels.declutter([label(101,x:-50,y:150)],viewport:viewport,reserved:[]).isEmpty)
    }
    func testCandidateRetainsNodeIdentityAndOriginalNameWithoutInventingAddress() throws {
        let source=try XCTUnwrap(CityContextPlace.catalogue?.records.first { $0.type == .node && $0.englishName != nil })
        let candidate=CityMVPPlaceBridge.candidate(for:source)
        XCTAssertEqual(candidate.id,"city-mvp:"+source.id)
        XCTAssertEqual(candidate.sourceURL,source.sourceURL.absoluteString)
        XCTAssertEqual(candidate.latitude,source.latitude)
        XCTAssertEqual(candidate.longitude,source.longitude)
        XCTAssertTrue(candidate.subtitle.contains(source.originalName))
        XCTAssertTrue(candidate.subtitle.contains("street address not supplied"))
        XCTAssertTrue(candidate.evidence.contains { $0.contains("not saved") })
        XCTAssertTrue(candidate.evidence.contains { $0.contains("Source node") })
    }
    func testContextRasterUsesOriginalCJKAndEnglishInBothPalettes() throws {
        let place=try XCTUnwrap(CityContextPlace.catalogue?.records.first { $0.id == "node/253385544" })
        let label=CityContextLabel(place:place,bounds:CGRect(x:0,y:0,width:156,height:52))
        for night in [false,true] {
            let image=CityContextLabels.image(label,night:night)
            XCTAssertEqual(image.size,label.bounds.size)
            let attachment=XCTAttachment(image:image)
            attachment.name="context-raster-" + (night ? "night" : "day")
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testExtendedPolicyRestoresNativeBeforeTheContextProjectionEnds() {
        let registration=CityDistrictRegistration(latitudeOffset:0,longitudeOffset:0)
        func mode(_ current:CityNativeLabelPolicy,x:Double,distance:Double) -> CityNativeLabelPolicy {
            current.updated(camera:MapCamera(centerCoordinate:CityDistrictCamera.coordinate(x:x,z:0),distance:distance),
                registration:registration,style:.city,sceneReady:true,projectionAvailable:true,settled:true,contextLabels:true)
        }
        XCTAssertEqual(mode(.native,x:1000,distance:5000),.district)
        XCTAssertEqual(mode(.district,x:1499,distance:5000),.district)
        XCTAssertEqual(mode(.district,x:1501,distance:5000),.native)
        // At near street scale the renderer's geographic reach is smaller.
        XCTAssertEqual(mode(.district,x:1100,distance:500),.native)
    }
}
