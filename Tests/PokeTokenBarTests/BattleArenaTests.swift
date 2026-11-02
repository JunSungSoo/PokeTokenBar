import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleArenaTests: XCTestCase {
    func testEveryTypeUsesFixedOriginalArenaAndMixedTiesIgnoreTeamOrder() {
        XCTAssertEqual(BattleArena.allCases.count,16)
        XCTAssertEqual(Set(BattleArena.typeArenas.keys),Set(BattleArena.typeOrder))
        for type in BattleArena.typeOrder {
            XCTAssertEqual(BattleArena.forTypes([type]),BattleArena.typeArenas[type])
            XCTAssertEqual(BattleArena.forTypes([type,type,"unknown"]),BattleArena.typeArenas[type])
        }
        XCTAssertEqual(BattleArena.forTypes([]),.plains)
        XCTAssertEqual(BattleArena.forTypes(["unknown"]),.plains)
        XCTAssertEqual(BattleArena.forTypes(["fire","flying","fire","water"]),.volcano)
        XCTAssertEqual(BattleArena.forTypes(["water","fire"]),.volcano)
        XCTAssertEqual(BattleArena.forTypes(["fire","water"]),.volcano)
    }
    func testAllChallengeArenasFollowFixedOpponentRostersIncludingDualTypes()throws {
        let catalog=try ChallengeEncounterCatalog.load()
        let arenas=Dictionary(uniqueKeysWithValues:catalog.encounters.map{($0.id,BattleArena.forOpponent($0.team.map(BattleRosterMember.init)))})
        XCTAssertEqual(arenas["brock"],.mountain)
        XCTAssertEqual(arenas["falkner"],.mountain)
        XCTAssertEqual(arenas["misty"],.lake)
        XCTAssertEqual(arenas["bugsy"],.forest)
        XCTAssertEqual(arenas["blaine"],.volcano)
        for encounter in catalog.encounters {
            XCTAssertEqual(BattleArena.forOpponent(encounter.team.reversed().map(BattleRosterMember.init)),arenas[encounter.id])
        }
    }

    func testOnlyRedOverridesTypeArenaWithOriginalEternatusEndBackground()throws {
        let encounters=try ChallengeEncounterCatalog.load().encounters
        for e in encounters {
            let roster=e.team.map(BattleRosterMember.init)
            XCTAssertEqual(BattleArena.forChallenge(encounterID:e.id,roster:roster),e.id=="red" ? .end:BattleArena.forOpponent(roster))
        }
        XCTAssertFalse(BattleArena.typeArenas.values.contains(.end))
        XCTAssertEqual(BattleArena.forChallenge(encounterID:"red",roster:[]),.end)
        XCTAssertEqual(BattleArena.end.backgroundPath,"images/arenas/end_bg.png")
    }
    func testBundledOriginalsMatchManifestAndCoverBothBattleSizes() throws {
        let directory = PokeRogueOriginalCatalog.directory
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as? [String:Any])
        let hashes = try XCTUnwrap(manifest["sha256"] as? [String:String])
        let groups = try XCTUnwrap(manifest["arenas"] as? [String:[String]])
        XCTAssertEqual(groups, Dictionary(grouping: BattleArena.allCases, by: \.group).mapValues { $0.map(\.rawValue) })
        for arena in BattleArena.allCases {
            let data = try Data(contentsOf: directory.appendingPathComponent(arena.backgroundPath))
            XCTAssertEqual(SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined(), hashes[arena.backgroundPath])
            let original = try XCTUnwrap(NSBitmapImageRep(data:data))
            XCTAssertEqual(original.pixelsWide,320); XCTAssertEqual(original.pixelsHigh,180)
            for size in [CGSize(width:660,height:310), CGSize(width:680,height:260)] {
                let renderer = ImageRenderer(content:PokeRogueArena(arena:arena).frame(width:size.width,height:size.height).clipped())
                let image = try XCTUnwrap(renderer.nsImage)
                let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                XCTAssertEqual(bitmap.pixelsWide,Int(size.width)); XCTAssertEqual(bitmap.pixelsHigh,Int(size.height))
                for (x,y) in [(0,0),(bitmap.pixelsWide-1,bitmap.pixelsHigh-1),(bitmap.pixelsWide/2,bitmap.pixelsHigh/2)] {
                    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x:x,y:y)).alphaComponent,0.99,"\(arena): background must fill the viewport")
                }
            }
        }
    }
}
