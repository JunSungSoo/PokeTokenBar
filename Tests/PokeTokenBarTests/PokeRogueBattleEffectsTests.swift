import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class PokeRogueBattleEffectsTests: XCTestCase {
    let rects=["own-0":CGRect(x:45,y:177,width:128,height:128),"own-1":CGRect(x:190,y:177,width:100,height:100),"foe-0":CGRect(x:405,y:25,width:128,height:128),"foe-1":CGRect(x:270,y:15,width:100,height:100)]
    private func event(_ id: String,own: Bool=true,hit: Bool=true,slot: Int=0,charge: Bool=false) -> BattleVisualEvent {
        let recipe=BattleEffectCatalog.shared.recipe(for:id)
        let selfMove=recipe?.scope == "self"
        return .init(id:1,move:id,type:recipe?.type ?? "Normal",category:recipe?.category ?? "Special",source:.init(own:own,slot:slot),
            targets:[.init(position:.init(own:selfMove ? own : !own,slot:slot),hit:hit)],moveID:id,phase:charge ? "charge" : "move")
    }
    private func render(_ event: BattleVisualEvent,_ p: Double) throws -> NSBitmapImageRep {
        NSBitmapImageRep(cgImage:try XCTUnwrap(ImageRenderer(content:ZStack {
            PokeRogueBattleCanvas(event:event,rects:rects,progress:p,behind:true)
            PokeRogueBattleEffects(event:event,rects:rects,progress:p)
        }.frame(width:570,height:320)).cgImage))
    }
    private func alpha(_ rep: NSBitmapImageRep,in region: CGRect=CGRect(x:0,y:0,width:570,height:320)) -> Double {
        var sum=0.0
        for y in stride(from:Int(region.minY),to:Int(region.maxY),by:7) { for x in stride(from:Int(region.minX),to:Int(region.maxX),by:7) {
            sum+=Double(rep.colorAt(x:x,y:y)?.alphaComponent ?? 0)
        } }
        return sum
    }
    func testEveryCurrentMoveAndChargeTimelineActuallyDrawsPixels() throws {
        let catalog=PokeRogueBattleCatalog.shared
        XCTAssertEqual(Set(catalog.catalog.aliases.values).count,559)
        var blank=[String]()
        for (id,entry) in catalog.catalog.entries.sorted(by:{$0.key<$1.key}) {
            let parts=id.split(separator:":"),move=String(parts[0]),e=event(move,charge:parts.count>1)
            let animation=try XCTUnwrap(catalog.animation(e),id)
            var samples=[0.24,0.5,0.76]
            let indices=animation.frames.indices.filter { !animation.frames[$0].isEmpty }
            if !indices.isEmpty { for i in [0,indices.count/2,indices.count-1] { samples.append((Double(indices[i])+0.5)/max(1,entry.length)) } }
            var visible=false
            for p in samples where p>0 && p<1 {
                if alpha(try render(e,p))>1 { visible=true;break }
            }
            if !visible { blank.append(id) }
        }
        XCTAssertEqual(blank,[],"Each matched ID must actually render, including original-empty, motion-only and invalid-frame fallbacks")
    }
    func testPokeRogueTakesPriorityOverExistingCustomEffectsForEveryMatchedMove() {
        let catalog = PokeRogueBattleCatalog.shared
        for id in catalog.catalog.entries.keys {
            let parts = id.split(separator: ":")
            let move = event(String(parts[0]), charge: parts.count > 1)
            XCTAssertEqual(BattleMoveEffectRenderer.resolve(move), .pokeRogue, id)
        }
        for id in ["thunderbolt", "quickattack", "protect", "voltswitch"] {
            let move = event(id)
            XCTAssertNotNil(PikachuMoveProfile.resolve(move), id)
            XCTAssertEqual(BattleMoveEffectRenderer.resolve(move), .pokeRogue, id)
            XCTAssertEqual(BattleMoveEffectRenderer.resolve(move, reducedMotion: true), .standard)
        }
    }
    func testMissEndDirectionAndDoublesAnchors() throws {
        for id in ["thunderbolt","psychic","surf","protect","rest","doubleteam","bravebird"] {
            XCTAssertEqual(alpha(try render(event(id,hit:false),0.6)),0,id)
            XCTAssertEqual(alpha(try render(event(id),1)),0,id)
        }
        for own in [true,false] {
            let e=event("psychic",own:own,slot:1)
            let rep=try render(e,0.68)
            XCTAssertGreaterThan(alpha(rep,in:rects[own ? "foe-1" : "own-1"]!),10)
        }
        var alias=event("vice-grip");alias.moveID="vicegrip"
        XCTAssertNotNil(PokeRogueBattleCatalog.shared.entry(alias))
        XCTAssertNotEqual(PokeRogueBattleCatalog.shared.key(event("solarbeam")),PokeRogueBattleCatalog.shared.key(event("solarbeam",charge:true)))
        let charge=try render(event("solarbeam",charge:true),0.5)
        XCTAssertGreaterThan(alpha(charge,in:rects["own-0"]!),1,"Charge effects must stay with the caster")
    }
    func testScopeOfBackgroundAndForegroundDoesNotRequirePokemonTransforms() throws {
        let catalog=PokeRogueBattleCatalog.shared
        let e=event("surf"),animation=try XCTUnwrap(catalog.animation(e))
        XCTAssertTrue(animation.frames.flatMap{$0}.allSatisfy{$0.target==2})
        let frame=try XCTUnwrap(ImageRenderer(content:PokeRogueBattleCanvas(event:e,rects:rects,progress:0.4,behind:true).frame(width:570,height:320)).cgImage)
        XCTAssertGreaterThan(alpha(NSBitmapImageRep(cgImage:frame)),100)
        XCTAssertEqual(BattleEffectPlayback.duration(e),catalog.entry(e)?.duration)
    }
}
