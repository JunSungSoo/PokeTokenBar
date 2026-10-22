import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleOwnStatsTests: XCTestCase {
    private func pokemon(_ boosts: [String:Int]) -> BattleCombatant {
        BattleCombatant(id:"own",speciesID:130,name:"Gyarados",level:37,shiny:false,active:true,form:nil,fainted:false,
            hp:143,maxHP:143,status:"",stats:["hp":143,"atk":91,"def":87,"spa":96,"spd":89,"spe":107],boosts:boosts)
    }
    func testCurrentAbilityRendersAndChangesWithoutShowingOldAbilityHistory() throws {
        for language in AppLanguage.allCases {
            var mon = pokemon(["atk": -1])
            mon.ability = "Intimidate"
            let before = try XCTUnwrap(ImageRenderer(content:BattleOwnStats(pokemon:mon,language:language).frame(width:240)).cgImage)
            mon.ability = "Immunity" // e.g. Skill Swap / Trace changes the engine's current ability.
            let after = try XCTUnwrap(ImageRenderer(content:BattleOwnStats(pokemon:mon,language:language).frame(width:240)).cgImage)
            XCTAssertNotEqual(NSBitmapImageRep(cgImage:before).tiffRepresentation,NSBitmapImageRep(cgImage:after).tiffRepresentation)
        }
    }
    func testReadoutsUseOnlyStagesAndRestoreNeutralWithoutExposingNumericalStats() throws {
        let lowered = try XCTUnwrap(BattleStatReadout.items(pokemon(["atk":-1,"spe":2,"evasion":1])).first { $0.id == "atk" })
        XCTAssertEqual(lowered.number,"-1")
        XCTAssertEqual(lowered.color,.blue)
        let raised = try XCTUnwrap(BattleStatReadout.items(pokemon(["atk":1])).first { $0.id == "atk" })
        XCTAssertEqual(raised.number,"+1")
        XCTAssertEqual(raised.color,.red)
        let neutral = try XCTUnwrap(BattleStatReadout.items(pokemon(["atk":0])).first { $0.id == "atk" })
        XCTAssertEqual(neutral.number,"0")
        XCTAssertEqual(neutral.color,.primary)
        XCTAssertEqual(BattleStatReadout.items(pokemon(["evasion":1])).last?.number,"+1")
        XCTAssertEqual(BattleStatReadout.items(pokemon([:])).last?.number,"0")
    }
    func testProductionReadoutActuallyRendersBlueAndRedNumbersInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            func render(_ boosts: [String:Int]) throws -> NSBitmapImageRep {
                let view=BattleOwnStats(pokemon:pokemon(boosts),language:language)
                    .frame(width:760).padding(4).background(Color.black).environment(\.colorScheme,.dark)
                return NSBitmapImageRep(cgImage:try XCTUnwrap(ImageRenderer(content:view).cgImage))
            }
            let changed=try render(["atk":-1,"spe":2]), neutral=try render([:])
            XCTAssertEqual(changed.pixelsWide,neutral.pixelsWide)
            XCTAssertEqual(changed.pixelsHigh,neutral.pixelsHigh)
            func counts(_ image:NSBitmapImageRep) -> (blue:Int,red:Int) {
                var b=0,r=0
                for y in 0..<image.pixelsHigh { for x in 0..<image.pixelsWide {
                    guard let c=image.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB) else { continue }
                    if c.blueComponent>0.4 && c.blueComponent>c.redComponent*1.4 { b += 1 }
                    if c.redComponent>0.4 && c.redComponent>c.blueComponent*1.4 { r += 1 }
                } }
                return (b,r)
            }
            let colored=counts(changed),plain=counts(neutral)
            XCTAssertGreaterThan(colored.blue,plain.blue+5,"negative stages must draw blue pixels: \(language)")
            XCTAssertGreaterThan(colored.red,plain.red+5,"positive stages must draw red pixels: \(language)")
        }
    }
}
