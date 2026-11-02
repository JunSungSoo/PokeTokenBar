import XCTest
@testable import PokeTokenBar

@MainActor final class ChallengeTestDataTests:XCTestCase {
    func testQASnapshotPreservesOwnedIDsAndNeverOverwritesClaimedRewardsOrProduction()throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let source=folder.appendingPathComponent("source.json"),qa=folder.appendingPathComponent("qa.json")
        var state=CompanionState();state.dex=[DexEntry(id:"real-owned",baseID:6,finalID:6,chainOrder:[6],rarity:.common,caughtAt:nil)]
        let original=try JSONEncoder().encode(state);try original.write(to:source)
        XCTAssertEqual(try ChallengeTestData.snapshot(source:source,destination:qa),qa)
        var copy=try JSONDecoder().decode(CompanionState.self,from:Data(contentsOf:qa));XCTAssertEqual(copy.dex[0].id,"real-owned")
        copy.dex[0].isShiny=true;copy.challengeShinyClaims=["run":"real-owned"]
        let changed=try JSONEncoder().encode(copy);try changed.write(to:qa)
        _ = try ChallengeTestData.snapshot(source:source,destination:qa)
        XCTAssertEqual(try Data(contentsOf:qa),changed);XCTAssertEqual(try Data(contentsOf:source),original)
    }
}
