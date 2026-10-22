import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleEffectCatalogTests: XCTestCase {
    func testShowmotionRegistryOnlyClaimsItsNineOriginalMoves() {
        XCTAssertEqual(ShowmotionPlayer.moveIDs.count,9)
        func event(_ id: String,hit: Bool = true,phase: String? = nil) -> BattleVisualEvent {
            BattleVisualEvent(id:1,move:id,type:"Water",category:"Special",source:BattleEffectPosition(own:true,slot:0),
                targets:[BattleEffectTarget(position:BattleEffectPosition(own:false,slot:0),hit:hit)],moveID:id,phase:phase)
        }
        for id in ShowmotionPlayer.moveIDs { XCTAssertTrue(ShowmotionPlayer.supports(event(id))) }
        XCTAssertFalse(ShowmotionPlayer.supports(event("thunderbolt")))
        XCTAssertFalse(ShowmotionPlayer.supports(event("hydropump",hit:false)))
        XCTAssertFalse(ShowmotionPlayer.supports(event("solarbeam",phase:"charge")))
    }
    func testEveryCurrentMoveAndAliasHasAnOfflineEffectWithFiniteTimelines() throws {
        let catalog=BattleEffectCatalog.shared
        XCTAssertEqual(catalog.aliases.count,560)
        XCTAssertEqual(Set(catalog.aliases.values).count,559)
        XCTAssertGreaterThan(catalog.recipes.count,559,"Later-generation matching effects must not be excluded")
        for key in BattleTextCatalog.shared.moves.keys {
            let recipe=try XCTUnwrap(catalog.recipe(for:key),key)
            XCTAssertTrue(recipe.duration > 0 && recipe.duration <= 2.5,key)
        }
        XCTAssertEqual(catalog.aliases["vicegrip"],"visegrip")
        XCTAssertEqual(catalog.recipe(for:"Vice Grip")?.source,catalog.recipe(for:"Vise Grip")?.source)
        XCTAssertNotNil(catalog.recipe(for:"Will-O-Wisp"))
        XCTAssertEqual(catalog.recipe(for:"Solar Beam",phase:"charge")?.scope,"self")
        XCTAssertFalse(try XCTUnwrap(catalog.recipe(for:"Solar Beam",phase:"charge")).operations.isEmpty)
        XCTAssertNil(catalog.recipe(for:"unknown future move"))
        for (key,recipe) in catalog.recipes {
            XCTAssertNil(recipe.generation,"The common source does not claim a specific game generation: \(key)")
            XCTAssertLessThanOrEqual(recipe.operations.count,64)
            for operation in recipe.operations {
                for point in [operation.start,operation.end] {
                    XCTAssertTrue([point.x,point.y,point.z,point.scaleX,point.scaleY,point.opacity].allSatisfy(\.isFinite),key)
                }
                XCTAssertGreaterThanOrEqual(operation.finish,operation.begin,key)
            }
        }
        let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:BattleEffectCatalog.resourceDirectory.appendingPathComponent("source-sha256.json"))) as! [String:Any]
        let textures=try XCTUnwrap(manifest["textures"] as? [String:String])
        XCTAssertFalse(textures.isEmpty)
        for (name,hash) in textures {
            let file=BattleEffectCatalog.resourceDirectory.appendingPathComponent("textures/"+name)
            XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:file)).map { String(format:"%02x",$0) }.joined(),hash)
            XCTAssertNotNil(NSImage(contentsOf:file),name)
        }
        for recipe in catalog.recipes.values { for op in recipe.operations {
            if let texture=op.texture { XCTAssertNotNil(textures[texture],texture) }
        } }
        for excluded in ["lightning.png","icicle.png","bone.png","rocks.png","rock1.png","rock2.png"] {
            XCTAssertNil(textures[excluded])
        }
    }
    func testGenerationPriorityIsFiveThenNineDownwardBeforeCommonEffects() throws {
        func recipe(_ generation: Int?) -> BattleEffectRecipe {
            BattleEffectRecipe(generation:generation,source:"fixture",duration:0.7,timeScale:1,
                category:"Special",type:"Water",scope:"target",operations:[])
        }
        let catalog=BattleEffectCatalog(aliases:[:],recipes:["surf":recipe(nil)],
            variants:["surf":[recipe(3),recipe(8),recipe(5),recipe(9)]])
        XCTAssertEqual(catalog.recipe(for:"Surf")?.generation,5)
        XCTAssertEqual(BattleEffectCatalog.select([recipe(nil),recipe(8),recipe(9)])?.generation,9)
        XCTAssertEqual(BattleEffectCatalog.select([recipe(4),recipe(2),recipe(6),recipe(nil)])?.generation,6)
        XCTAssertEqual(BattleEffectCatalog.select([recipe(1),recipe(3),recipe(4)])?.generation,4)
        XCTAssertNil(BattleEffectCatalog.select([recipe(nil)])?.generation)
        XCTAssertNil(BattleEffectCatalog.select([]))
        XCTAssertEqual(BattleEffectCatalog.generationPriority,[5,9,8,7,6,4,3,2,1])
    }
    func testEveryCurrentCanonicalMoveProducesVisiblePixelsWithoutMovingPokemonViews() throws {
        let catalog=BattleEffectCatalog.shared
        let rects=["own-0":CGRect(x:35,y:180,width:120,height:100),"foe-0":CGRect(x:480,y:25,width:120,height:100)]
        for key in Set(catalog.aliases.values).sorted() {
            let recipe=try XCTUnwrap(catalog.recipe(for:key))
            let event=BattleVisualEvent(id:1,move:key,type:recipe.type,category:recipe.category,
                source:BattleEffectPosition(own:true,slot:0),targets:[BattleEffectTarget(position:BattleEffectPosition(own:false,slot:0),hit:true)],moveID:key)
            var visible=false
            // Some moves deliberately wait for a late strike; sample their actual operation windows.
            let times=[0.25,0.5,0.75]+recipe.operations.map { ($0.begin+$0.finish)/2*recipe.timeScale/(recipe.duration*1000) }
            for progress in times {
                let image=try XCTUnwrap(ImageRenderer(content:BattleEffectCanvas(event:event,rects:rects,progress:progress)
                    .frame(width:640,height:320)).cgImage)
                let rep=NSBitmapImageRep(cgImage:image)
                for y in stride(from:0,to:rep.pixelsHigh,by:5) { for x in stride(from:0,to:rep.pixelsWide,by:5) {
                    if (rep.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0.01 { visible=true;break }
                };if visible { break } }
                if visible { break }
            }
            XCTAssertTrue(visible,"Move must have visible effect pixels: \(key)")
        }
    }
    func testDoublesAndReversePerspectiveRespectEachTargetAndReducedMotion() throws {
        let rects=["own-0":CGRect(x:20,y:240,width:110,height:100),"own-1":CGRect(x:180,y:240,width:110,height:100),
                   "foe-0":CGRect(x:360,y:20,width:110,height:100),"foe-1":CGRect(x:520,y:20,width:110,height:100)]
        func bitmap(_ event: BattleVisualEvent,reduced: Bool = false) throws -> NSBitmapImageRep {
            let image=try XCTUnwrap(ImageRenderer(content:BattleEffectCanvas(event:event,rects:rects,progress:0.8,reducedMotion:reduced)
                .frame(width:660,height:360)).cgImage)
            return NSBitmapImageRep(cgImage:image)
        }
        func alpha(_ bitmap: NSBitmapImageRep,_ rect: CGRect) -> Double {
            var value=0.0
            for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) {
                value += Double(bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)
            } }
            return value
        }
        var event=BattleVisualEvent(id:1,move:"Thunderbolt",type:"Electric",category:"Special",
            source:BattleEffectPosition(own:true,slot:0),targets:[
                BattleEffectTarget(position:BattleEffectPosition(own:false,slot:0),hit:true),
                BattleEffectTarget(position:BattleEffectPosition(own:false,slot:1),hit:false),
                BattleEffectTarget(position:BattleEffectPosition(own:true,slot:1),hit:true)],moveID:"thunderbolt")
        let spread=try bitmap(event)
        XCTAssertGreaterThan(alpha(spread,CGRect(x:340,y:0,width:150,height:150)),10)
        XCTAssertEqual(alpha(spread,CGRect(x:510,y:0,width:150,height:150)),0,accuracy:0.01)
        XCTAssertGreaterThan(alpha(spread,CGRect(x:160,y:170,width:150,height:170)),10)
        event=BattleVisualEvent(id:2,move:"Thunderbolt",type:"Electric",category:"Special",
            source:BattleEffectPosition(own:false,slot:0),targets:[BattleEffectTarget(position:BattleEffectPosition(own:true,slot:0),hit:true)],moveID:"thunderbolt")
        XCTAssertGreaterThan(alpha(try bitmap(event),CGRect(x:0,y:170,width:150,height:170)),10)
        event=BattleVisualEvent(id:3,move:"Protect",type:"Normal",category:"Status",
            source:BattleEffectPosition(own:true,slot:0),targets:[BattleEffectTarget(position:BattleEffectPosition(own:true,slot:0),hit:false)],moveID:"protect")
        for reduced in [false,true] {
            XCTAssertEqual(alpha(try bitmap(event,reduced:reduced),CGRect(x:0,y:0,width:660,height:360)),0,accuracy:0.01)
        }
    }
    func testRepresentativeEffectGallery() throws {
        guard let output=ProcessInfo.processInfo.environment["PTB_EFFECT_GALLERY_DIR"] else { return }
        try FileManager.default.createDirectory(atPath:output,withIntermediateDirectories:true)
        let ids=["thunderbolt","protect","quickattack","voltswitch","hydropump","swordsdance","shadowball","psychic","gunkshot","willowisp","flamethrower","icebeam","surf","moonblast","flowertrick","growl"]
        for id in ids {
            let recipe=try XCTUnwrap(BattleEffectCatalog.shared.recipe(for:id))
            let event=BattleVisualEvent(id:1,move:id,type:recipe.type,category:recipe.category,
                source:BattleEffectPosition(own:true,slot:0),targets:[BattleEffectTarget(position:BattleEffectPosition(own:false,slot:0),hit:true)],moveID:id)
            for progress in [0.4,0.8] {
                let cg=try XCTUnwrap(ImageRenderer(content:BattleEffectCanvas(event:event,
                    rects:["own-0":CGRect(x:60,y:160,width:120,height:100),"foe-0":CGRect(x:440,y:35,width:120,height:100)],progress:progress)
                    .frame(width:640,height:320).background(Color(red:0.12,green:0.15,blue:0.2))).cgImage)
                try XCTUnwrap(NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]))
                    .write(to:URL(fileURLWithPath:output).appendingPathComponent("\(id)-\(progress).png"))
            }
        }
    }
    func testChargePhasesStayAtTheCasterWithImportedOrNativePreparation() throws {
        for move in ["solarbeam","fly"] {
            let event=BattleVisualEvent(id:1,move:move,type:"Grass",category:"Special",
                source:BattleEffectPosition(own:true,slot:0),targets:[BattleEffectTarget(position:BattleEffectPosition(own:false,slot:0),hit:true)],
                moveID:move,phase:"charge")
            let cg=try XCTUnwrap(ImageRenderer(content:BattleEffectCanvas(event:event,
                rects:["own-0":CGRect(x:50,y:160,width:120,height:100),"foe-0":CGRect(x:440,y:30,width:120,height:100)],progress:0.5)
                .frame(width:640,height:320)).cgImage)
            let bitmap=NSBitmapImageRep(cgImage:cg)
            var source=0.0,target=0.0
            for y in 0..<320 { for x in 0..<640 {
                let alpha=Double(bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)
                if x<250 { source += alpha } else if x>350 { target += alpha }
            } }
            XCTAssertGreaterThan(source,10,move)
            XCTAssertEqual(target,0,accuracy:0.01,move)
        }
    }
}
