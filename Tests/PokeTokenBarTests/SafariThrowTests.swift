import SwiftUI
import AppKit
import XCTest
@testable import PokeTokenBar

final class SafariThrowPathTests: XCTestCase {
    func testAllThrowsRiseAboveBothEndpointsThenDescend() {
        for path in [SafariThrowPath.ball,SafariThrowPath.item(width:632)] {
            XCTAssertEqual(path.point(at:0),path.start)
            XCTAssertEqual(path.point(at:1),path.end)
            XCTAssertEqual(path.point(at:-1),path.start)
            XCTAssertEqual(path.point(at:2),path.end)
            XCTAssertLessThan(path.point(at:0.5).y,min(path.start.y,path.end.y))
            XCTAssertLessThan(path.point(at:0.8).y,path.point(at:1).y)
            // Constant horizontal velocity and constant downward acceleration.
            let points = (0...4).map { path.point(at:Double($0)/4) }
            for i in 1...3 {
                XCTAssertEqual(points[i+1].x-2*points[i].x+points[i-1].x,0,accuracy:1e-9)
                XCTAssertEqual(points[i+1].y-2*points[i].y+points[i-1].y,path.height/2,accuracy:1e-9)
            }
        }
    }
    func testCaptureFlightJoinsOriginalOpeningWithoutJumpOrTimingChange() {
        let sequence = SafariCaptureSequence(caught:true)
        let before = sequence.frame(at:SafariCaptureSequence.impact-0.000001)
        let impact = sequence.frame(at:SafariCaptureSequence.impact)
        XCTAssertEqual(before.x,impact.x,accuracy:0.001)
        XCTAssertEqual(before.y,impact.y,accuracy:0.001)
        XCTAssertEqual(impact.phase,.absorb)
        XCTAssertEqual(sequence.sounds.first { $0.name == "pb_rel" }?.time,0.5)
        XCTAssertEqual(sequence.duration,7.29453125,accuracy:1e-9)
    }
}

@MainActor
final class SafariThrowRenderingTests: XCTestCase {
    func testCartoonRockIsHalfPreviousSizeAndRendersVisibleFacets() throws {
        let renderer = ImageRenderer(content:SafariThrownItem(action:.rock,progress:0))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.cgImage))
        XCTAssertEqual(bitmap.pixelsWide,28); XCTAssertEqual(bitmap.pixelsHigh,28)
        var opaque = 0, shades = Set<Int>()
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            if let color = bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB),color.alphaComponent > 0.9 {
                opaque += 1; shades.insert(Int(color.redComponent*10))
            }
        } }
        XCTAssertGreaterThan(opaque,150)
        XCTAssertGreaterThanOrEqual(shades.count,3,"Outline, facets and highlight must remain visible at 14pt")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-safari-throw")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try bitmap.representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent("rock.png"))
    }
    func testThrownItemsRenderAcrossTheWholeProductionArcWithoutWindow() throws {
        var session = SafariSession(area:.forest,seed:1,shinyDenominator:4096)
        try session.continueJourney(catalog:SafariCatalog.load())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-safari-throw")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for action in [SafariAction.rock,.bait] {
            for progress in [0.0,0.5,1.0] {
                let renderer = ImageRenderer(content:SafariBattlefield(session:session,language:.ko,
                    projectile:action,projectileProgress:progress).frame(width:632,height:280))
                renderer.scale = 2
                let bitmap = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.cgImage))
                XCTAssertEqual(bitmap.pixelsWide,1264); XCTAssertEqual(bitmap.pixelsHigh,560)
                try bitmap.representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent("\(action.rawValue)-\(progress).png"))
            }
        }
        XCTAssertNil(SafariWindowController.shared.window)
    }
}
