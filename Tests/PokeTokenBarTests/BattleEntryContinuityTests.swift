import AppKit
import CryptoKit
import ImageIO
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleEntryContinuityTests:XCTestCase {
    func testOriginalCharizardVariantsUsePinnedAnimatedAssetsAndSeparateOldCache()async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=SpriteStore(directory:dir);defer{try? FileManager.default.removeItem(at:dir)}
        for back in [false,true] {for shiny in [false,true] {
            let asset=try XCTUnwrap(BattleOriginalSprites.asset(speciesID:6,form:nil,back:back,shiny:shiny))
            let oldKey=SpriteStore.cacheKey(speciesID:6,animated:true,shiny:shiny,back:back).components(separatedBy:"-rogue-")[0]
            try Data("legacy-provider-cache".utf8).write(to:dir.appendingPathComponent(oldKey+".gif"))
            let fetched=await store.data(speciesID:6,animated:true,shiny:shiny,back:back)
            let data=try XCTUnwrap(fetched)
            XCTAssertEqual(SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),asset.record.sha256)
            let source=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil));XCTAssertGreaterThan(CGImageSourceGetCount(source),1)
            XCTAssertTrue(SpriteStore.cacheKey(speciesID:6,animated:true,shiny:shiny,back:back).contains("-rogue-"))
        }}
        XCTAssertNotNil(BattleOriginalSprites.asset(speciesID:6,form:.init("mega-x"),back:true,shiny:false))
    }
    func testGiantReserveCannotMakeCharizardTinyAndHeightOrderingRemains() {
        let catalog=PokeRogueSpriteSizes.shared
        let sizes=[6,25,321,384].flatMap{id in BattleHeldItems.sizingForms(speciesID:id).flatMap{form in [false,true].map{catalog.battleSize(speciesID:id,form:form,back:$0)}}}
        let camera=BattleSpriteSizing.make(mode:.singles,sizes:sizes)
        let charizard=catalog.battleSize(speciesID:6,form:nil,back:true),pikachu=catalog.battleSize(speciesID:25,form:nil,back:true),wailord=catalog.battleSize(speciesID:321,form:nil,back:true)
        XCTAssertGreaterThanOrEqual(charizard.height*camera.pixelScale,85)
        XCTAssertGreaterThan(charizard.height,pikachu.height)
        XCTAssertGreaterThan(wailord.width,charizard.width)
        XCTAssertLessThanOrEqual(camera.stageHeight,166)
    }
    func testTrainerAnnouncementIsLocalizedOnlyForOpening() {
        let intro=ChallengeTrainerIntro();intro.reset(encounter:"brock")
        let event=BattleVisualEvent(id:7,move:"",type:"",category:"",source:.init(own:true,slot:0),targets:[],phase:"entry")
        XCTAssertEqual(intro.openingMessages(events:[event],messages:[:],language:.ko,enabled:true)[7],"적 웅이 등장했다.")
        XCTAssertEqual(intro.openingMessages(events:[event],messages:[7:"existing"],language:.ko,enabled:false)[7],"existing")
        for lang in AppLanguage.allCases{XCTAssertNotNil(intro.openingMessages(events:[event],messages:[:],language:lang,enabled:true)[7])}
    }
    func testEliteFourAndRedAppearWithEncounterSpecificTitles() {
        let intro=ChallengeTrainerIntro()
        let event=BattleVisualEvent(id:7,move:"",type:"",category:"",source:.init(own:true,slot:0),targets:[],phase:"entry")
        let expected=["lorelei":"사천왕 칸나가 등장했다.","bruno1":"사천왕 시바가 등장했다.","agatha":"사천왕 국화가 등장했다.","lance1":"사천왕 목호가 등장했다.","will":"사천왕 일목이 등장했다.","koga2":"사천왕 독수 (2세대)가 등장했다.","bruno2":"사천왕 시바 (2세대)가 등장했다.","karen":"사천왕 카렌이 등장했다.","red":"포켓몬 마스터 레드가 등장했다.","koga1":"적 독수가 등장했다.","lance2":"챔피언 목호 (2세대)가 등장했다.","blue":"챔피언 그린이 등장했다."]
        for (encounter,message) in expected {
            intro.reset(encounter:encounter)
            XCTAssertEqual(intro.openingMessages(events:[event],messages:[:],language:.ko,enabled:true)[7],message)
            XCTAssertEqual(intro.openingMessages(events:[event],messages:[7:"unchanged"],language:.ko,enabled:false)[7],"unchanged")
            for language in AppLanguage.allCases {
                let localized=intro.openingMessages(events:[event],messages:[:],language:language,enabled:true)[7]
                XCTAssertTrue(localized?.contains(ChallengeTrainerCatalog.name(encounter,language:language)) == true)
            }
        }
    }
    func testFoeBallAnimationNeverHidesAlreadyPresentOwnPokemon()async throws {
        let (store,dir)=try PokeRogueFaithfulTests().gifStore();defer{try? FileManager.default.removeItem(at:dir)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).frame(width:660,height:310))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:310),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        let own=BattleEffectPosition(own:true,slot:0),foe=BattleEffectPosition(own:false,slot:0)
        func actor(_ p:BattleEffectPosition)->PokeRogueActor {
            let pokemon=BattleCombatant(id:p.key,speciesID:25,name:"Pikachu",level:100,shiny:false,active:true,form:nil,fainted:false,hp:100,maxHP:100,status:"",stats:nil)
            return PokeRogueActor(pokemon:pokemon,position:p,rect:CGRect(x:p.own ? 40:450,y:p.own ? 160:30,width:100,height:110))
        }
        player.entryHiddenPositions=[foe.key]
        let event=BattleVisualEvent(id:2,move:"",type:"",category:"",source:foe,targets:[],phase:"entry")
        let task=Task{await player.play(event,actors:[actor(own),actor(foe)],size:CGSize(width:660,height:310),entrySources:[foe],beforeFinish:{player.entryHiddenPositions.remove(foe.key)})}
        let deadline=Date().addingTimeInterval(15);var samples=0
        while Date()<deadline {
            if player.isPlaying {
                samples+=1
                XCTAssertFalse(player.hidesNative(own),"The prior all-actor mask erased the stationary owner during the foe's ball flight")
                XCTAssertTrue(player.hidesNative(foe))
                let state=try await player.inspect()
                let a=(state["actors"] as? [[String:Any]])?.first{$0["key"] as? String==own.key}
                XCTAssertEqual(a?["visible"] as? Bool,false,"The unchanged owner stays native, without a duplicate WebKit actor")
            }
            if samples>0 && !player.isPlaying{break}
            try await Task.sleep(for:.milliseconds(40))
        }
        let success=await task.value
        XCTAssertTrue(success,player.error ?? "entry failed");XCTAssertGreaterThan(samples,10)
        XCTAssertFalse(player.hidesNative(own));XCTAssertFalse(player.hidesNative(foe))
    }
}
