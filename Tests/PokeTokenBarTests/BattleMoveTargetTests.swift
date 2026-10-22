import XCTest
@testable import PokeTokenBar

final class BattleMoveTargetTests: XCTestCase {
    private func move(_ scope:String?, allies:Bool=false) -> BattleMove {
        BattleMove(index:1,name:"Surf",apiName:"surf",pp:15,maxPP:15,disabled:false,type:"Water",power:95,
            category:"Special",description:nil,matchups:[],targetRequired:allies,
            targets:allies ? [.init(location:1,name:"Foe"),.init(location:-2,name:"Ally")] : [],targetScope:scope)
    }
    func testTargetsDistinguishSpreadSidesTeamsAndSelfInEveryLanguage() {
        let cases:[String:String] = ["all":"모두","allAdjacent":"모두 (자신 제외)","allAdjacentFoes":"상대 모두",
            "self":"자신","adjacentAlly":"아군 단일","adjacentAllyOrSelf":"자신 또는 아군 단일",
            "allyTeam":"아군 모두 (대기 포함)","allySide":"아군 모두 (진영)","foeSide":"상대 진영",
            "randomNormal":"상대 단일 (무작위)","scripted":"반격 대상 (자동)","normal":"상대 단일","any":"상대 단일","adjacentFoe":"상대 단일"]
        for (scope,korean) in cases {
            XCTAssertEqual(L(.ko).battleMoveTarget(move(scope)),korean)
            for language in AppLanguage.allCases {
                let text=L(language).battleMoveTarget(move(scope))
                XCTAssertFalse(text.isEmpty)
                XCTAssertNotEqual(text,"—","\(language) \(scope)")
                if language != .ko { XCTAssertNotEqual(text,korean) }
            }
        }
    }
    func testSingleTargetsIncludeSelectableAlliesOnlyWhenRuntimeAllowsThem() {
        for scope in ["normal","any"] {
            XCTAssertEqual(L(.ko).battleMoveTarget(move(scope,allies:true)),"상대 또는 아군 단일")
            XCTAssertEqual(L(.ko).battleMoveTarget(move(scope)),"상대 단일")
        }
        XCTAssertEqual(L(.ko).battleMoveTarget(move("self",allies:true)),"자신")
        XCTAssertEqual(L(.ko).battleMoveTarget(move(nil)),"—")
    }
}
