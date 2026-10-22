import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleSpriteSizingTests:XCTestCase {
    func testPinnedCatalogCoversEverySpeciesAndSupportedFormInBothDirections() {
        let catalog=PokeRogueSpriteSizes.shared
        XCTAssertEqual(catalog.assetRevision,PokeRogueOriginalCatalog.shared.manifest.assetRevision)
        for id in 1...649 {
            let forms=PokemonForm.forms(speciesID:id)
            for form in forms.isEmpty ? [nil]:forms.map(Optional.some) {
                for back in [false,true] {
                    let prefix=back ? "back/":"",base=prefix+String(id)
                    let resolved=PokemonForm.resolved(speciesID:id,form:form)
                    let key=resolved.map{base+"-"+$0.rawValue} ?? base
                    XCTAssertNotNil(catalog.records[key] ?? catalog.records[base],"Missing \(key)")
                    if let record=catalog.records[key] ?? catalog.records[base] {
                        XCTAssertEqual(catalog.size(speciesID:id,form:form,back:back),CGSize(width:record.width,height:record.height),"Original bounds for \(key)")
                    }
                }
            }
        }
        XCTAssertEqual(catalog.size(speciesID:25,form:nil,back:false),CGSize(width:50,height:46))
        XCTAssertEqual(catalog.size(speciesID:25,form:nil,back:true),CGSize(width:41,height:47))
        XCTAssertEqual(catalog.size(speciesID:321,form:nil,back:true),CGSize(width:111,height:70))
    }
    func testSharedCameraPreservesRelativeSizesAndFitsBothModes() {
        let small=PokeRogueSpriteSizes.shared.size(speciesID:25,form:nil,back:true)
        let large=PokeRogueSpriteSizes.shared.size(speciesID:321,form:nil,back:true)
        for mode in BattleMode.allCases {
            let sizing=BattleSpriteSizing.make(mode:mode,sizes:[small,large])
            XCTAssertEqual((large.width*sizing.pixelScale)/(small.width*sizing.pixelScale),111/41.0,accuracy:0.0001)
            XCTAssertLessThanOrEqual(sizing.stageWidth,mode == .singles ? 192:130)
            XCTAssertLessThanOrEqual(sizing.stageHeight,mode == .singles ? 166:126)
            XCTAssertGreaterThan(sizing.pixelScale,0)
        }
    }
    func testNativeStageUsesOriginalSizesAndKeepsFeetAboveShadow() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore()
        defer{try? FileManager.default.removeItem(at:directory)}
        let original=directory.appendingPathComponent("back-25-a.gif")
        try FileManager.default.copyItem(at:original,to:directory.appendingPathComponent("back-321-a.gif"))
        let sizing=BattleSpriteSizing.make(mode:.singles,sizes:[CGSize(width:41,height:47),CGSize(width:111,height:70)])
        var heights:[Double]=[]
        for id in [25,321] {
            let pokemon=BattleCombatant(id:String(id),speciesID:id,name:"",level:50,shiny:false,active:true,form:nil,fainted:false,hp:100,maxHP:100,status:"",stats:nil)
            let host=NSHostingController(rootView:BattlePokemonStage(pokemon:pokemon,back:true,stageSize:108,sizing:sizing,spriteStore:store))
            let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:sizing.stageWidth,height:sizing.stageHeight),styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentViewController=host;window.setContentSize(NSSize(width:sizing.stageWidth,height:sizing.stageHeight));window.orderFront(nil)
            defer{window.orderOut(nil);window.contentViewController=nil}
            var top=Int.max,bottom = -1,rasterScale=1.0
            for _ in 0..<40 {
                try await Task.sleep(for:.milliseconds(25));host.view.layoutSubtreeIfNeeded()
                let bitmap=try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
                host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
                rasterScale=Double(bitmap.pixelsHigh)/host.view.bounds.height
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        guard let color=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else{continue}
                        if color.redComponent>0.8 && color.blueComponent<0.3 {top=min(top,y);bottom=max(bottom,y)}
                    }
                }
                if bottom>=0 {break}
            }
            XCTAssertGreaterThanOrEqual(bottom,0,"Actual GIF must render")
            let height=Double(bottom-top+1)/rasterScale
            let target=PokeRogueSpriteSizes.shared.size(speciesID:id,form:nil,back:true)
            let expected=SpriteFit.size(for:CGSize(width:48,height:52),width:target.width,height:target.height).height*sizing.pixelScale
            XCTAssertEqual(height,expected,accuracy:2)
            XCTAssertEqual(host.view.bounds.height-Double(bottom+1)/rasterScale,BattleSpriteGeometry.footInset,accuracy:1.5)
            heights.append(height)
        }
        XCTAssertGreaterThan(heights[1],heights[0]*1.4,"Native display must not normalize both species to the same square")
    }
    func testActualGIFsKeepDifferentNativeSizesDuringOriginalMoveAndEntry() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore()
        defer{try? FileManager.default.removeItem(at:directory)}
        // Use the same cached animated fixture for both species, isolating size metadata.
        for back in [false,true] {
            let original=directory.appendingPathComponent(SpriteStore.cacheKey(speciesID:25,animated:true,shiny:false,back:back)+".gif")
            let target=directory.appendingPathComponent(SpriteStore.cacheKey(speciesID:321,animated:true,shiny:false,back:back)+".gif")
            try FileManager.default.copyItem(at:original,to:target)
        }
        func pokemon(_ id:Int)->BattleCombatant {BattleCombatant(id:String(id),speciesID:id,name:"",level:50,shiny:false,active:true,form:nil,fainted:false,hp:100,maxHP:100,status:"",stats:nil)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).frame(width:680,height:350))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:680,height:350),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        for mode in BattleMode.allCases {
            let scale=BattleSpriteSizing.make(mode:mode,sizes:[CGSize(width:41,height:47),CGSize(width:103,height:88)]).pixelScale
            let actors=[PokeRogueActor(pokemon:pokemon(25),position:.init(own:true,slot:0),rect:CGRect(x:20,y:160,width:140,height:160),pixelScale:scale),
                        PokeRogueActor(pokemon:pokemon(321),position:.init(own:false,slot:0),rect:CGRect(x:480,y:20,width:140,height:160),pixelScale:scale)]
            for phase in [nil,"entry"] as [String?] {
                let event=BattleVisualEvent(id:1,move:"thunderbolt",type:"electric",category:"Special",source:.init(own:true,slot:0),targets:[.init(position:.init(own:false,slot:0),hit:true)],moveID:"thunderbolt",phase:phase)
                let task=Task {await player.play(event,actors:actors,size:CGSize(width:680,height:350))}
                let end=Date().addingTimeInterval(10)
                while !player.isPlaying,player.error==nil,Date()<end {try await Task.sleep(for:.milliseconds(25))}
                let state=try await player.inspect()
                let rendered=try XCTUnwrap(state["actors"] as? [[String:Any]])
                let own=try XCTUnwrap(rendered.first{$0["key"] as? String=="own-0"})
                let foe=try XCTUnwrap(rendered.first{$0["key"] as? String=="foe-0"})
                XCTAssertEqual(own["height"] as? Double,47)
                XCTAssertEqual(foe["height"] as? Double,88)
                XCTAssertEqual(own["pixelScale"] as? Double,Double(scale))
                XCTAssertGreaterThan(foe["width"] as? Double ?? 0,own["width"] as? Double ?? 0)
                let completed=await task.value;XCTAssertTrue(completed)
            }
        }
    }
}
