import CryptoKit
import XCTest
@testable import PokeTokenBar

@MainActor
final class ChallengePolicyCompatibilityTests: XCTestCase {
    private func wait(_ session:ChallengeBattleSession,after:String?=nil) async throws -> BattleFrame {
        let deadline=Date().addingTimeInterval(12)
        while Date()<deadline {
            if let error=session.error {XCTFail(error);throw ChallengeFailure.invalidState}
            if let frame=session.frame,!session.submitted,after==nil || frame.decisionID != after {return frame}
            try await Task.sleep(for:.milliseconds(20))
        }
        throw ChallengeFailure.invalidState
    }
    func testLegacyPolicyCheckpointReplaysWithIdenticalDecisionsHPAndPP() async throws {
        let catalog=try ChallengeEncounterCatalog.load(),helper=ChallengeRunTests(),save=try helper.store()
        defer{try? FileManager.default.removeItem(at:save.url)}
        let bytes=try Data(contentsOf:BattleEngineProcess.resourceDirectory.appendingPathComponent("challenge-policy-v1.json"))
        let old=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
        XCTAssertTrue(try ChallengeEncounterCatalog.supportsPolicyRevision(old))
        XCTAssertNotEqual(old,try ChallengeEncounterCatalog.policyRevision())
        try save.start(team:helper.team(),catalogVersion:catalog.version)
        try save.beginEncounter(opponent:catalog.encounters[0].team,seed:[1,2,3,4],policyRevision:old)
        let first=try ChallengeBattleSession(save:save,catalog:catalog);defer{first.stop()}
        try first.resume();let initial=try await wait(first);first.completePresentation()
        let move=try XCTUnwrap(initial.slots[0].moves.first{!$0.disabled&&$0.pp>0})
        try first.choose(BattleDecision(decisionID:initial.decisionID,actions:[.init(kind:"move",index:move.index,target:0)],order:[]))
        let resolved=try await wait(first,after:initial.decisionID);first.completePresentation();first.stop()
        let restored=ChallengeRunStore(url:save.url),second=try ChallengeBattleSession(save:restored,catalog:catalog)
        defer{second.stop()}
        XCTAssertEqual(restored.run?.checkpoint?.policyRevision,old)
        try second.resume();let replayed=try await wait(second)
        XCTAssertEqual(replayed.decisionID,resolved.decisionID)
        XCTAssertEqual(replayed.own.map(\.hp),resolved.own.map(\.hp))
        XCTAssertEqual(replayed.foe.map(\.hp),resolved.foe.map(\.hp))
        XCTAssertEqual(replayed.resources,resolved.resources)
        // Wall-clock protocol stamps are intentionally different on a later replay.
        XCTAssertEqual(replayed.log.filter{!$0.hasPrefix("|t:|")},resolved.log.filter{!$0.hasPrefix("|t:|")})
    }
    func testUnknownPolicyCannotRewriteASavedChallenge() throws {
        let catalog=try ChallengeEncounterCatalog.load(),helper=ChallengeRunTests(),save=try helper.store()
        defer{try? FileManager.default.removeItem(at:save.url)}
        try save.start(team:helper.team(),catalogVersion:catalog.version)
        try save.beginEncounter(opponent:catalog.encounters[0].team,seed:[1,2,3,4],policyRevision:"unknown-policy")
        let original=try Data(contentsOf:save.url),session=try ChallengeBattleSession(save:save,catalog:catalog)
        XCTAssertThrowsError(try session.resume())
        XCTAssertEqual(try Data(contentsOf:save.url),original)
    }
}
