import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleTeamPreviewTests: XCTestCase {
    private func member(_ id:Int,_ key:String)->BattleRosterMember {
        BattleRosterMember(BattlePokemon(id:key,speciesID:id,species:"",displayName:"",level:50,
            ability:"",nature:"hardy",gender:"",shiny:false,form:nil,ivs:[:],stats:[:],moves:[]))
    }
    func testRosterMatchupsRespectDualTypesImmunityAndBW2SteelResistance() {
        let electric=member(26,"electric")
        let strong=BattleRosterMatchup.evaluate(electric,against:member(130,"gyarados"))
        XCTAssertEqual(strong.outgoing,4);XCTAssertEqual(strong.advantage,.strong)
        let weak=BattleRosterMatchup.evaluate(electric,against:member(260,"swampert"))
        XCTAssertEqual(weak.outgoing,0);XCTAssertEqual(weak.incoming,2);XCTAssertEqual(weak.advantage,.weak)
        XCTAssertEqual(BattleRosterMatchup.evaluate(member(128,"tauros"),against:member(143,"snorlax")).advantage,.neutral)
        XCTAssertEqual(BattleRosterMatchup.evaluate(member(445,"garchomp"),against:member(149,"dragonite")).advantage,.neutral)
        let gen5=BattleRosterMatchup.evaluate(member(94,"gengar"),against:member(376,"metagross"))
        XCTAssertEqual(gen5.outgoing,1);XCTAssertEqual(gen5.advantage,.weak)
    }
    func testLastSelectedMemberUpdatesOpponentBorderAndClearingRestoresIt() throws {
        let own=[member(6,"fire"),member(26,"electric")]
        let foe=[member(130,"foe")]
        func border(_ selected:[String]) throws -> (green:Int,red:Int) {
            let view=BattleTeamPreview(own:own,opponent:foe,selected:selected,mode:.singles,language:.ko,enabled:true,onSelect:{_ in})
            let image=try XCTUnwrap(ImageRenderer(content:view.frame(width:320)).cgImage)
            let bitmap=NSBitmapImageRep(cgImage:image)
            var green=0,red=0
            for y in (bitmap.pixelsHigh-82)..<(bitmap.pixelsHigh-10) {
                let color=try XCTUnwrap(bitmap.colorAt(x:1,y:y)?.usingColorSpace(.deviceRGB))
                if color.greenComponent>color.redComponent*1.5 && color.greenComponent>color.blueComponent*1.5 {green+=1}
                if color.redComponent>color.greenComponent*1.5 && color.redComponent>color.blueComponent*1.5 {red+=1}
            }
            return(green,red)
        }
        XCTAssertGreaterThan(try border(["fire","electric"]).green,10)
        XCTAssertGreaterThan(try border(["electric","fire"]).red,10)
        let empty=try border([])
        XCTAssertEqual(empty.green,0);XCTAssertEqual(empty.red,0)
    }
    func testRosterTypesUseBW2AndFormsInTheSelectedLanguage() {
        let catalog=BattleTextCatalog.shared
        XCTAssertEqual(catalog.speciesTypeNames(130,form:nil,language:.ko),"물 / 비행")
        XCTAssertEqual(catalog.speciesTypeNames(36,form:nil,language:.ko),"노말")
        XCTAssertEqual(catalog.speciesTypeNames(479,form:PokemonForm("wash"),language:.ko),"전기 / 물")
        XCTAssertEqual(catalog.speciesTypeNames(479,form:nil,language:.en),"Electric / Ghost")
        XCTAssertEqual(catalog.speciesTypeNames(413,form:PokemonForm("sandy"),language:.ko),"벌레 / 땅")
        for language in AppLanguage.allCases {
            for id in 1...649 { XCTAssertFalse(catalog.speciesTypeNames(id,form:nil,language:language).isEmpty) }
        }
    }
    func testBothSixMemberRostersRenderTogetherWithinTheLobbyInEveryLanguage() throws {
        func roster(_ prefix: String, _ ids: [Int]) -> [BattleRosterMember] {
            ids.enumerated().map { index, id in
                BattleRosterMember(BattlePokemon(id: prefix + String(index), speciesID: id, species: "", displayName: "", level: 50,
                    ability: "", nature: "hardy", gender: "", shiny: false, form: nil, ivs: [:], stats: [:], moves: []))
            }
        }
        let own = roster("a", [26,181,310,101,587,618]), foe = roster("b", [130,80,59,134,212,143])
        for language in AppLanguage.allCases {
            for mode in BattleMode.allCases {
                let view = BattleTeamPreview(own: own, opponent: foe, selected: Array(own.prefix(mode.battleSize)).map(\.id),
                    mode: mode, language: language, enabled: true, onSelect: { _ in })
                let image = try XCTUnwrap(ImageRenderer(content: view.frame(width: 320)).cgImage)
                XCTAssertLessThanOrEqual(image.height, 240, "Both rosters must be visible together: \(language) \(mode)")
                XCTAssertGreaterThan(image.height, 150)
                XCTAssertFalse(L(language).battleWaitingForRoster.isEmpty)
            }
        }
    }
}
