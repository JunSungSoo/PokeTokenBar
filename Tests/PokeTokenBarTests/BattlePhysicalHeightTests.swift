import XCTest
@testable import PokeTokenBar

@MainActor final class BattlePhysicalHeightTests:XCTestCase {
    func testPhysicalHeightsCoverSpeciesAndEveryMegaForm() {
        let heights=PokemonDisplayHeights.shared
        for id in 1...649 {XCTAssertGreaterThan(heights.records[String(id)]?.decimetres ?? 0,0)}
        for item in BattleHeldItems.all where item.mega != nil {
            let mega=item.mega!
            XCTAssertGreaterThan(heights.records["\(mega.baseID)-\(mega.form)"]?.decimetres ?? 0,0)
        }
        for (id,height) in [(25,0.4),(6,1.7),(143,2.1),(208,9.2),(321,14.5)] {
            XCTAssertEqual(heights.metres(speciesID:id,form:nil),height)
        }
        XCTAssertEqual(heights.metres(speciesID:3,form:PokemonForm(rawValue:"mega")),2.4)
    }
    func testHeightDeterminesExtentWithoutDistortingSpritesOrCamera() {
        let catalog=PokeRogueSpriteSizes.shared
        let ids=[25,6,143,208,321]
        let sizes=ids.map{id in [false,true].map{catalog.battleSize(speciesID:id,form:nil,back:$0)}}
        let extents=sizes.map{$0.map(\.height).max()!}
        for i in 1..<extents.count {XCTAssertGreaterThan(extents[i],extents[i-1])}
        XCTAssertGreaterThan(extents.last!/extents.first!,2.0)
        XCTAssertLessThan(extents.last!/extents.first!,3,"Compress metres so small Pokémon remain readable")
        for id in ids {for back in [false,true] {
            let raw=catalog.size(speciesID:id,form:nil,back:back),scaled=catalog.battleSize(speciesID:id,form:nil,back:back)
            XCTAssertEqual(scaled.width/scaled.height,raw.width/raw.height,accuracy:0.000001)
        }}
        for mode in BattleMode.allCases { for id in ids {
            func member(_ side:String)->BattleCombatant {
                BattleCombatant(id:side+String(id),speciesID:id,name:"",level:100,shiny:false,active:true,form:nil,fainted:false,hp:100,maxHP:100,status:"",stats:nil)
            }
            let camera=BattleSpriteSizing.forBattle(mode:mode,own:[member("own")],foe:[member("foe")])
            XCTAssertLessThanOrEqual(camera.stageWidth,mode == .singles ? 282:189)
            XCTAssertEqual(2*camera.stageHeight+BattleSpriteSizing.battlefieldTopInset+BattleSpriteSizing.battlefieldRowSpacing,
                           BattleSpriteSizing.battlefieldHeight(for:mode),accuracy:0.001)
            for back in [false,true] {
                let visible=catalog.battleSize(speciesID:id,form:nil,back:back)
                XCTAssertLessThanOrEqual(visible.width*camera.pixelScale,camera.stageWidth-12+0.001)
                XCTAssertLessThanOrEqual(visible.height*camera.pixelScale+BattleSpriteGeometry.footInset,camera.stageHeight+0.001)
            }
        }}
        let base=catalog.battleSize(speciesID:3,form:nil,back:false),mega=catalog.battleSize(speciesID:3,form:PokemonForm(rawValue:"mega"),back:false)
        XCTAssertGreaterThan(max(mega.width,mega.height),max(base.width,base.height))
    }
    func testEveryHeightMatchesItsOriginalPokeAPIPokemonRecord() throws {
        let url=PokeRogueOriginalCatalog.directory.appendingPathComponent("original/physical/pokemon.csv")
        let lines=try String(contentsOf:url,encoding:.utf8).split(separator:"\n").dropFirst()
        let originals=Dictionary(uniqueKeysWithValues:lines.map {line -> (Int,Int) in
            let columns=line.split(separator:",",omittingEmptySubsequences:false)
            return (Int(columns[0])!,Int(columns[3])!)
        })
        for (key,record) in PokemonDisplayHeights.shared.records {
            XCTAssertEqual(record.decimetres,originals[record.pokemonID],key)
        }
    }
}
