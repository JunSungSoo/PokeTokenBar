import AppKit
import CryptoKit
import XCTest
@testable import PokeTokenBar

@MainActor
final class PokeRoguePreviewTests: XCTestCase {
    private func catalog() throws -> PokeRoguePreviewCatalog {
        try PokeRoguePreviewCatalog(directory:XCTUnwrap(Bundle.module.url(forResource:"PokeRoguePreview",withExtension:nil)))
    }
    func testPinned48DefinitionsAndTheirOriginalHashes() throws {
        let catalog=try catalog()
        XCTAssertEqual(catalog.manifest.revision,"009cac30c39d3615c7b2c320c3984af368871031")
        let counts=Dictionary(grouping:catalog.manifest.moves,by:\.classification).mapValues(\.count)
        XCTAssertEqual(counts,["background-without-effect-graphics":15,"motion-without-effect-graphics":30,"empty":3])
        for (path,hash) in catalog.manifest.sha256 {
            let data=try Data(contentsOf:catalog.directory.appendingPathComponent(path))
            XCTAssertEqual(SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined(),hash,path)
        }
        for move in catalog.manifest.moves {
            for opponent in [false,true] {
                let animation=try XCTUnwrap(catalog.animation(move.id,opponent:opponent))
                XCTAssertTrue(animation.duration.isFinite)
                for time in stride(from:0.0,to:animation.length,by:0.5) {
                    if let bg=animation.background(at:time) {
                        XCTAssertTrue(bg.x.isFinite && bg.y.isFinite && (0...1).contains(bg.opacity),move.id)
                        if !bg.name.isEmpty { XCTAssertNotNil(catalog.backgroundImage(bg.name),bg.name) }
                    }
                    for own in [true,false] {
                        let poses=animation.poses(at:time,sourceOwn:own,selfTarget:BattleEffectCatalog.shared.recipe(for:move.id)?.scope == "self",
                            rects:["own-0":CGRect(x:45,y:177,width:128,height:128),"foe-0":CGRect(x:405,y:25,width:128,height:128)])
                        for pose in poses { XCTAssertTrue([pose.x,pose.y,pose.scaleX,pose.scaleY,pose.angle,pose.opacity].allSatisfy(\.isFinite),move.id) }
                    }
                }
                XCTAssertNil(animation.background(at:animation.length))
            }
        }
    }
    func testSurfBackgroundFadesAndScrollsAndEmptyMovesStayEmpty() throws {
        let catalog=try catalog(),surf=try XCTUnwrap(catalog.animation("surf"))
        let start=try XCTUnwrap(surf.background(at:0)),middle=try XCTUnwrap(surf.background(at:10)),later=try XCTUnwrap(surf.background(at:25))
        XCTAssertEqual(start.opacity,0)
        XCTAssertGreaterThan(middle.opacity,0.5)
        XCTAssertNotEqual(middle.x,later.x)
        XCTAssertEqual(middle.name,"PRAS- Surf FG")
        for id in ["naturepower","rest","secretpower"] {
            let animation=try XCTUnwrap(catalog.animation(id))
            XCTAssertTrue(animation.frames.isEmpty,id)
            XCTAssertNil(animation.background(at:0),id)
            XCTAssertEqual(animation.length,0,id)
        }
    }
    func testDoubleTeamClonesSelfAndTailWhipKeepsSourceAnchorForEitherSide() throws {
        let catalog=try catalog(),double=try XCTUnwrap(catalog.animation("doubleteam"))
        let rects=["own-0":CGRect(x:45,y:177,width:128,height:128),"foe-0":CGRect(x:405,y:25,width:128,height:128)]
        for own in [true,false] {
            let poses=double.poses(at:11,sourceOwn:own,selfTarget:true,rects:rects)
            XCTAssertEqual(poses.count,3,"A self move must not render a second USER copy over its TARGET copies")
            XCTAssertTrue(poses.allSatisfy { $0.own == own })
            XCTAssertGreaterThan(try XCTUnwrap(poses.map(\.x).max())-XCTUnwrap(poses.map(\.x).min()),90)
            let tail=try XCTUnwrap(catalog.animation("tailwhip")),source=try XCTUnwrap(rects[own ? "own-0" : "foe-0"])
            let pose=try XCTUnwrap(tail.poses(at:0,sourceOwn:own,selfTarget:false,rects:rects).first { $0.own == own })
            XCTAssertEqual(pose.x-source.midX,own ? 6.5 : -6.5,accuracy:0.01)
            XCTAssertEqual(pose.y,source.midY)
        }
        XCTAssertTrue(double.poses(at:Double(double.frames.count),sourceOwn:true,selfTarget:true,rects:rects).isEmpty)
    }
}
