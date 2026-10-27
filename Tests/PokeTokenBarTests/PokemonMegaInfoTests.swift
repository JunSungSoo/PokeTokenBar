import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class PokemonMegaInfoTests:XCTestCase {
    func testSupportedFormsAreSpeciesBoundAndMultiFormsRemainDistinct() {
        let all=(1...649).flatMap{BattleHeldItems.megaStones(speciesID:$0)}
        XCTAssertEqual(all.count,64)
        XCTAssertEqual(Set(all.compactMap{$0.mega?.baseID}).count,59)
        XCTAssertTrue(BattleHeldItems.megaStones(speciesID:25).isEmpty)
        XCTAssertEqual(BattleHeldItems.megaStones(speciesID:6).compactMap{$0.mega?.form},["mega-x","mega-y"])
        for item in all {
            XCTAssertEqual(Set(item.mega!.stats.keys),Set(["hp","atk","def","spa","spd","spe"]))
            XCTAssertTrue(item.mega!.stats.values.allSatisfy{$0>0})
            XCTAssertTrue(BattleHeldItems.megaStones(speciesID:item.mega!.baseID).contains{$0.id==item.id})
        }
    }
    func testEveryMegaHasBundledArtworkAndLocalizedInformation() throws {
        let catalog=BattleTextCatalog.shared
        for item in BattleHeldItems.all where item.mega != nil {
            let mega=item.mega!
            for shiny in [false,true] {
                let record=try XCTUnwrap(BattleMegaSprites.record(speciesID:mega.baseID,form:PokemonForm(mega.form),back:false,shiny:shiny))
                let data=try Data(contentsOf:BattleMegaSprites.directory.appendingPathComponent(record.file))
                XCTAssertNotNil(NSImage(data:data),mega.species)
                XCTAssertEqual(SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),record.sha256)
            }
            for language in AppLanguage.allCases {
                let l=L(language)
                XCTAssertFalse(item.name(language).isEmpty)
                XCTAssertNotEqual(catalog.pokemonName(mega.species,language:language),l.battleUnknownPokemon)
                XCTAssertNotEqual(catalog.abilityDescription(mega.ability,language:language),l.battleDescriptionUnavailable)
                for type in mega.types {XCTAssertNotEqual(catalog.typeName(type,language:language),l.battleUnknownType)}
            }
        }
    }
    func testReadOnlyMegaInformationFitsOffscreen() async throws {
        _ = NSApplication.shared
        for id in [6,80] {
            let base=id==6 ? ["hp":78,"attack":84,"defense":78,"special-attack":109,"special-defense":85,"speed":100]:["hp":95,"attack":75,"defense":110,"special-attack":100,"special-defense":80,"speed":30]
            let view=PokemonMegaInfoView(speciesID:id,language:.ko,baseStats:base,onClose:{XCTFail("Rendering must not close or edit data")})
                .background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.dark)
            let host=NSHostingController(rootView:view)
            let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:440,height:590),styleMask:[.borderless],backing:.buffered,defer:false)
            window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.darkAqua)
            host.view.appearance=window.appearance;window.contentViewController=host;window.orderFront(nil)
            try await Task.sleep(for:.milliseconds(500));host.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.view.fittingSize.width,440,accuracy:1)
            XCTAssertEqual(host.view.fittingSize.height,590,accuracy:1)
            let bitmap=try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
            host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/ptb-mega-info-\(id).png"))
            window.orderOut(nil);window.contentViewController=nil
        }
    }
}
