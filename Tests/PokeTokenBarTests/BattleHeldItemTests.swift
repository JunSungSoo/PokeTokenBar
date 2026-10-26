import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleHeldItemTests:XCTestCase {
    func testCatalogAndNativeMenusAreLocalizedAndSpeciesBound() throws {
        XCTAssertEqual(BattleHeldItems.all.count,100)
        XCTAssertEqual(BattleHeldItems.all.filter{$0.mega != nil}.count,64)
        XCTAssertEqual(BattleHeldItems.choices(speciesID:25,form:nil).count,36)
        XCTAssertEqual(Set(BattleHeldItems.choices(speciesID:6,form:nil).compactMap{$0.mega == nil ? nil:$0.id}),["charizarditex","charizarditey"])
        XCTAssertTrue(BattleHeldItems.sizingForms(speciesID:479).contains(PokemonForm("wash")))
        XCTAssertEqual(BattleHeldItems.sizingForms(speciesID:479).count,6)
        XCTAssertNil(BattleHeldItems.item("fairyfeather"));XCTAssertNil(BattleHeldItems.item("mewtwonitex"))
        _ = NSApplication.shared
        for language in AppLanguage.allCases {
            let button=NSPopUpButton(frame:.zero,pullsDown:true),coordinator=PokemonLoadoutPicker.Coordinator{_ in}
            let choices=BattleHeldItems.all.map{PokemonLoadoutChoice(id:$0.id,title:$0.name(language),tooltip:$0.tooltip(language),selected:$0.id=="sitrusberry")}
            PokemonLoadoutPicker.configure(button,title:L(language).battleHeldItem,tooltip:"",choices:choices,target:coordinator,action:#selector(PokemonLoadoutPicker.Coordinator.select(_:)))
            for (index,choice) in choices.enumerated(){
                let item=try XCTUnwrap(button.menu?.item(at:index+1));XCTAssertEqual(item.title,choice.title)
                XCTAssertEqual(item.toolTip,choice.tooltip);XCTAssertFalse(choice.tooltip.isEmpty)
                XCTAssertEqual(item.state,choice.id=="sitrusberry" ? .on:.off)
            }
            for mega in BattleHeldItems.all.compactMap(\.mega) {
                XCTAssertNotEqual(BattleTextCatalog.shared.abilityName(mega.ability,language:language),L(language).battleAbility)
                XCTAssertNotEqual(BattleTextCatalog.shared.abilityDescription(mega.ability,language:language),L(language).battleDescriptionUnavailable)
                for type in mega.types {XCTAssertNotEqual(BattleTextCatalog.shared.typeName(type,language:language),L(language).battleUnknownType)}
            }
        }
    }
    func testEngineFramesExposeMegaControlsAndLocalizeItemNoticesPrivately() throws {
        let frames=try frames();XCTAssertEqual(frames.count,6)
        XCTAssertTrue(frames[0].slots[0].canMegaEvo==true)
        XCTAssertEqual(frames[0].own[0].item,"charizarditex");XCTAssertNil(frames[0].foe[0].item)
        XCTAssertEqual(frames[1].own[0].form?.rawValue,"mega-x");XCTAssertEqual(frames[1].own[0].maxHP,500)
        XCTAssertTrue(frames[1].slots.allSatisfy{$0.canMegaEvo != true});XCTAssertNil(frames[2].foe[0].item)
        XCTAssertTrue(frames[4].field!.conditions.contains("electricterrain"))
        XCTAssertEqual(frames[4].field!.conditionTimings?["electricterrain"]?.maximum,5)
        let terrainEvents=BattlePresentationEvents(frame:frames[4],language:.ko,ownPlayer:0).events.filter{$0.moveID=="electricterrain"}
        XCTAssertEqual(terrainEvents.count,1)
        XCTAssertTrue(terrainEvents.allSatisfy{BattleFieldEffects.isGlobal($0) && PokeRogueOriginalCatalog.shared.entry($0) != nil})
        for language in AppLanguage.allCases {
            for frame in frames {
                let p=BattlePresentationEvents(frame:frame,language:language,ownPlayer:0)
                for (index,line) in frame.log.enumerated() where line.hasPrefix("|-mega|") {
                    let id=index+(frame.logOffset ?? 0)
                    XCTAssertTrue(p.messages[id]?.contains(L(language).battleMegaEvolution)==true)
                    XCTAssertNotNil(p.events.first{$0.id==id})
                }
            }
            for code in ["-item","-enditem"] {
                XCTAssertTrue(BattleLogText.describe("|\(code)|p1a: Charizard|Normal Gem",language:language)!.contains(BattleHeldItems.item("normalgem")!.name(language)))
            }
            XCTAssertTrue(BattleLogText.describe("|-heal|p1a: Charizard|100/200|[from] item: Leftovers",language:language)!.contains(BattleHeldItems.item("leftovers")!.name(language)))
            XCTAssertNotNil(L(language).battleFieldDescription("electricterrain"))
        }
    }
    func testEveryMegaHasCorrectOfflineArtworkWithoutChangingCollectionForms() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
        let store=SpriteStore(directory:directory)
        for mega in BattleHeldItems.all.compactMap(\.mega) {
            let form=PokemonForm(mega.form)
            XCTAssertFalse(PokemonForm.forms(speciesID:mega.baseID).contains(form))
            XCTAssertTrue(BattleHeldItems.sizingForms(speciesID:mega.baseID).contains(form),"Camera must fit Mega forms before evolution")
            XCTAssertEqual(PokemonForm.assetName(speciesID:mega.baseID,form:form),"\(mega.baseID)-\(mega.form)")
            for back in [false,true] { for shiny in [false,true] {
                let record=try XCTUnwrap(BattleMegaSprites.record(speciesID:mega.baseID,form:form,back:back,shiny:shiny))
                let data=await store.data(speciesID:mega.baseID,animated:false,shiny:shiny,form:form,back:back)
                let bytes=try XCTUnwrap(data)
                XCTAssertNotNil(NSImage(data:bytes),mega.species)
                XCTAssertEqual(SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined(),record.sha256)
                let frames=await SpriteLoader.animationFrames(speciesID:mega.baseID,shiny:shiny,store:store,form:form,back:back)
                XCTAssertEqual(frames.isEmpty,!record.animated)
                if record.animated {XCTAssertTrue(frames.allSatisfy{abs($0.delay-0.1)<0.001})}
            }}
        }
    }
    func testMegaArtworkCacheRejectsLegacyProviderImagesWithoutChangingNormalKeys() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:directory)}
        let form=PokemonForm("mega-x")
        let oldGIF=try Data(contentsOf:BattleMegaSprites.directory.appendingPathComponent("248-mega.gif"))
        try oldGIF.write(to:directory.appendingPathComponent("6-mega-x-a.gif"))
        try oldGIF.write(to:directory.appendingPathComponent("6-mega-x-s.png"))
        XCTAssertTrue(SpriteLoader.cachedFrames(speciesID:6,shiny:false,directory:directory,form:form).isEmpty)
        XCTAssertNil(SpriteLoader.cachedImage(speciesID:6,animated:false,shiny:false,directory:directory,form:form))
        let record=try XCTUnwrap(BattleMegaSprites.record(speciesID:6,form:form,back:false,shiny:false))
        XCTAssertTrue(SpriteStore.cacheKey(speciesID:6,animated:false,shiny:false,form:form).hasSuffix("-rogue-"+String(record.sha256.prefix(12))))
        XCTAssertEqual(SpriteStore.cacheKey(speciesID:25,animated:true,shiny:false),"25-a")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID:25,animated:true,shiny:true,back:true),"back-25-sha")
        let store=SpriteStore(directory:directory)
        let data=await store.data(speciesID:6,animated:false,form:form)
        XCTAssertEqual(data,try Data(contentsOf:BattleMegaSprites.directory.appendingPathComponent(record.file)))
    }
    func testMegaGIFAndStaticFormWorkInOriginalMovePlayerOffscreen() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
        let store=SpriteStore(directory:directory),player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).frame(width:660,height:310))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:310),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        let own=BattleEffectPosition(own:true,slot:0),foe=BattleEffectPosition(own:false,slot:0)
        func pokemon(_ id:Int,_ name:String,_ form:String)->BattleCombatant{
            .init(id:name,speciesID:id,name:name,level:50,shiny:false,active:true,form:PokemonForm(form),fainted:false,hp:100,maxHP:100,status:"",stats:nil,mega:true)
        }
        let actors=[PokeRogueActor(pokemon:pokemon(248,"Tyranitar-Mega","mega"),position:own,rect:CGRect(x:70,y:170,width:100,height:110)),PokeRogueActor(pokemon:pokemon(26,"Raichu-Mega-X","mega-x"),position:foe,rect:CGRect(x:480,y:30,width:100,height:110))]
        var done=false,played=false,gifs=Set<Int>()
        let task=Task{played=await player.play(.init(id:1,move:"Thunderbolt",type:"electric",category:"Special",source:own,targets:[.init(position:foe,hit:true)],moveID:"thunderbolt"),actors:actors,size:CGSize(width:660,height:310));done=true}
        let deadline=Date().addingTimeInterval(15)
        while !done,Date()<deadline {
            if player.isPlaying {
                let state=try await player.inspect()
                if let actor=(state["actors"] as? [[String:Any]])?.first,let gif=actor["gif"] as? Int {gifs.insert(gif)}
            }
            try await Task.sleep(for:.milliseconds(20))
        }
        if !done {task.cancel()};await task.value
        XCTAssertTrue(played,player.error ?? "Original player timeout");XCTAssertGreaterThan(gifs.count,1)
        XCTAssertNil(player.error)
    }
    func testMegaSelectionBuildsOnlyOneLegalEvolutionActionAndCanBeCancelled() throws {
        var selection=BattleMegaSelection()
        let move=BattleAction(kind:"move",index:1,target:1)
        XCTAssertNil(selection.applying(to:move,slot:0,canMega:true).mega)
        selection.set(true,slot:0)
        XCTAssertEqual(selection.applying(to:move,slot:0,canMega:true).mega,true)
        selection.set(true,slot:1)
        let actions=(0...1).map{selection.applying(to:move,slot:$0,canMega:true)}
        XCTAssertEqual(actions.filter{$0.mega==true}.count,1);XCTAssertEqual(actions[1].mega,true)
        let decision=BattleDecision(decisionID:"current",actions:actions,order:[])
        let wire=try JSONDecoder().decode(BattleDecision.self,from:JSONEncoder().encode(decision))
        XCTAssertEqual(wire.actions,actions)
        XCTAssertNil(selection.applying(to:move,slot:1,canMega:false).mega)
        XCTAssertNil(selection.applying(to:.init(kind:"switch",index:2,target:0),slot:1,canMega:true).mega)
        selection.set(false,slot:0);XCTAssertEqual(selection.slot,1)
        selection.set(false,slot:1);XCTAssertNil(selection.applying(to:move,slot:1,canMega:true).mega)
    }
    func frames() throws->[BattleFrame]{
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let child=Process(),output=Pipe();child.executableURL=root.appendingPathComponent("BattleEngine/runtime/node")
        child.arguments=[root.appendingPathComponent("BattleEngine/tests/fixtures/held-items.cjs").path];child.standardOutput=output;try child.run()
        let data=output.fileHandleForReading.readDataToEndOfFile();child.waitUntilExit();XCTAssertEqual(child.terminationStatus,0)
        return try JSONDecoder().decode([BattleFrame].self,from:data)
    }
}