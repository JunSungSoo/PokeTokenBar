import XCTest
@testable import PokeTokenBar

@MainActor final class BattleTargetlessMoveTests:XCTestCase {
    private struct Case:Decodable {let before:BattleFrame;let frames:[BattleFrame]}
    func testRealSelfKOAndTargetlessRecordsCannotPlayMovesOrSoundsIncludingOldPeerFrames()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process=Process(),output=Pipe();process.executableURL=root.appendingPathComponent("BattleEngine/runtime/node")
        process.arguments=[root.appendingPathComponent("BattleEngine/tests/fixtures/targetless-moves.cjs").path];process.standardOutput=output
        try process.run();let data=output.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit();XCTAssertEqual(process.terminationStatus,0)
        let cases=try JSONDecoder().decode([String:Case].self,from:data)
        XCTAssertEqual(cases.count,12)
        for (key,value) in cases {
            for (player,original) in value.frames.enumerated() {
                // Reconstruct the effect produced by the released 3.0.3 sender, using the
                // real notarget record. This is reachable when a peer hasn't updated yet.
                let index=original.log.firstIndex{$0.hasPrefix("|move|p1a:") && $0.contains("[notarget]")}
                for legacy in [false,true] {
                    var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
                    if legacy,let index {
                        var effects=(json["effects"] as? [[String:Any]]) ?? []
                        effects.append(["id":(original.logOffset ?? 0)+index,"move":"Thunderbolt","moveID":"thunderbolt","type":"Electric","category":"Special","phase":"move","source":["own":player==0,"slot":0],"targets":[["position":["own":player==0,"slot":0],"hit":true]]])
                        json["effects"]=effects
                    }
                    let frame=try JSONDecoder().decode(BattleFrame.self,from:JSONSerialization.data(withJSONObject:json))
                    for language in AppLanguage.allCases {
                        let presentation=BattlePresentationEvents(frame:frame,language:language,ownPlayer:player)
                        if let index {
                            let id=(frame.logOffset ?? 0)+index
                            XCTAssertNil(presentation.messages[id],key)
                            XCTAssertEqual(presentation.events.first{$0.id==id}?.phase,"state",key)
                            XCTAssertNil(BattleLogText.describe(frame.log[index],language:language,ownPlayer:player))
                            XCTAssertFalse(presentation.events.contains{$0.id==id && !($0.moveID ?? $0.move).isEmpty},"No renderer/audio event for \(key)")
                        }
                        if key.hasSuffix("-retarget") {XCTAssertTrue(presentation.events.contains{$0.moveID=="thunderbolt"})}
                        if key.hasSuffix("-recover") {XCTAssertTrue(presentation.events.contains{$0.moveID=="recover"})}
                        if key.hasSuffix("-ko") {XCTAssertFalse(presentation.events.contains{$0.moveID=="thunderbolt"})}
                    }
                }
            }
        }
    }
}
