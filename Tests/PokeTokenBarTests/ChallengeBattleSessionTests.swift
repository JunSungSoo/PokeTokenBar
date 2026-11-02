import XCTest
@testable import PokeTokenBar

@MainActor final class ChallengeBattleSessionTests:XCTestCase {
    private func wait(_ session:ChallengeBattleSession,after:String?=nil)async throws->BattleFrame {
        let end=Date().addingTimeInterval(8)
        while Date()<end {
            if let error=session.error {XCTFail(error);throw ChallengeFailure.invalidState}
            if let f=session.frame,!session.submitted,after==nil || f.decisionID != after {return f}
            try await Task.sleep(for:.milliseconds(15))
        }
        XCTFail("Local CPU did not return a decision");throw ChallengeFailure.invalidState
    }
    private func action(_ f:BattleFrame)->BattleDecision {
        let slot=f.slots[0]
        let a:BattleAction
        if slot.mustSwitch {a=BattleAction(kind:"switch",index:f.own.firstIndex(where:{!$0.active && !$0.fainted})!+1,target:0)}
        else {a=BattleAction(kind:"move",index:slot.moves.first(where:{!$0.disabled && $0.pp>0})!.index,target:0)}
        return BattleDecision(decisionID:f.decisionID,actions:[a],order:[])
    }
    func testRealProcessSixVsSixAutomaticCPUAndDeterministicResume()async throws {
        let helper=ChallengeRunTests(),save=try helper.store(),catalog=try ChallengeEncounterCatalog.load()
        defer{try? FileManager.default.removeItem(at:save.url.deletingLastPathComponent())}
        let session=try ChallengeBattleSession(save:save,catalog:catalog)
        try session.start(team:helper.team())
        var f=try await wait(session);XCTAssertEqual(f.own.count,6);XCTAssertEqual(f.own.first?.stats?["spa"],1000)
        XCTAssertEqual(f.resources?.first?.moves[0].pp,15)
        for _ in 0..<2 {let old=f.decisionID;try session.choose(action(f));f=try await wait(session,after:old)}
        let state=try XCTUnwrap(f.resources),id=f.decisionID
        XCTAssertLessThan(state.first?.moves[0].pp ?? 15,15)
        session.stop()
        let loaded=ChallengeRunStore(url:save.url),resumed=try ChallengeBattleSession(save:loaded,catalog:catalog)
        defer{resumed.stop()}
        try resumed.resume();let restored=try await wait(resumed)
        XCTAssertEqual(restored.decisionID,id);XCTAssertEqual(restored.resources,state)
        XCTAssertEqual(loaded.run?.checkpoint?.decisions.count,2)
    }
    func testActualWinRewardAndNextOpponentKeepPPInsteadOfRefilling()async throws {
        let helper=ChallengeRunTests(),save=try helper.store(),session=try ChallengeBattleSession(save:save,catalog:ChallengeEncounterCatalog.load())
        defer{session.stop();try? FileManager.default.removeItem(at:save.url.deletingLastPathComponent())}
        try session.start(team:helper.team());var f=try await wait(session)
        for _ in 0..<100 {
            if f.ended {break}
            let old=f.decisionID;try session.choose(action(f));f=try await wait(session,after:old)
        }
        XCTAssertTrue(f.ended);XCTAssertEqual(f.winner,0);XCTAssertEqual(save.run?.phase,.reward)
        session.completePresentation()
        let before=try XCTUnwrap(save.run).resources[0].moves[0].pp
        try session.applyReward(.pp("a0",0));XCTAssertEqual(save.run?.resources[0].moves[0].pp,min(15,before+3))
        let carried=try XCTUnwrap(save.run).resources
        try session.startEncounter();let next=try await wait(session,after:f.decisionID)
        XCTAssertEqual(save.run?.encounterIndex,1)
        XCTAssertEqual(next.resources,carried)
    }
    func testRejectedHumanCommandClearsSavedIntentAndSurrenderTerminatesTheRun()async throws {
        let helper=ChallengeRunTests(),save=try helper.store(),session=try ChallengeBattleSession(save:save,catalog:ChallengeEncounterCatalog.load())
        defer{session.stop();try? FileManager.default.removeItem(at:save.url.deletingLastPathComponent())}
        try session.start(team:helper.team());let f=try await wait(session)
        try session.choose(BattleDecision(decisionID:f.decisionID,actions:[BattleAction(kind:"move",index:4,target:0)],order:[]))
        let end=Date().addingTimeInterval(5)
        while session.error==nil && Date()<end {try await Task.sleep(for:.milliseconds(15))}
        XCTAssertNotNil(session.error);XCTAssertFalse(session.submitted)
        XCTAssertNil(save.run?.checkpoint?.pendingDecision);XCTAssertEqual(save.run?.checkpoint?.decisions.count,0)
        try session.choose(action(f));_ = try await wait(session,after:f.decisionID)
        XCTAssertNil(session.error);XCTAssertEqual(save.run?.checkpoint?.decisions.count,1)
        try session.surrender();XCTAssertEqual(ChallengeRunStore(url:save.url).run?.phase,.lost)
        XCTAssertThrowsError(try session.choose(action(f)))
    }
    func testResumeRejectsAnUpdatedPolicyWithoutChangingTheSavedRun()async throws {
        let helper=ChallengeRunTests(),save=try helper.store(),catalog=try ChallengeEncounterCatalog.load(),session=try ChallengeBattleSession(save:save,catalog:catalog)
        defer{session.stop();try? FileManager.default.removeItem(at:save.url.deletingLastPathComponent())}
        try session.start(team:helper.team());_ = try await wait(session);session.stop()
        var data=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
        var checkpoint=try XCTUnwrap(data["checkpoint"] as? [String:Any]);checkpoint["policyRevision"]="previous-trained-model";data["checkpoint"]=checkpoint
        try JSONSerialization.data(withJSONObject:data).write(to:save.url)
        let bytes=try Data(contentsOf:save.url),loaded=ChallengeRunStore(url:save.url),resumed=try ChallengeBattleSession(save:loaded,catalog:catalog)
        XCTAssertThrowsError(try resumed.resume());XCTAssertEqual(try Data(contentsOf:save.url),bytes)
    }

    func testInstantWinIsTestOnlyAndUsesRealEngineRewardsWithoutSpendingResources()async throws {
        let helper=ChallengeRunTests(),save=try helper.store(),catalog=try ChallengeEncounterCatalog.load()
        defer{try? FileManager.default.removeItem(at:save.url.deletingLastPathComponent())}
        let disabled=try ChallengeBattleSession(save:save,catalog:catalog,testControlsEnabled:false)
        XCTAssertThrowsError(try disabled.winForTesting())
        let session=try ChallengeBattleSession(save:save,catalog:catalog,testControlsEnabled:true)
        defer{session.stop()};try session.start(team:helper.team())
        let before=try await wait(session);session.completePresentation();try session.winForTesting()
        let won=try await wait(session,after:before.decisionID)
        XCTAssertTrue(won.ended);XCTAssertEqual(won.winner,0);XCTAssertEqual(save.run?.phase,.reward)
        XCTAssertEqual(won.resources,before.resources)
        XCTAssertThrowsError(try session.winForTesting())
    }
    func testSketchPersistsItsLearnedMoveAndReplaysFromTheOriginalTeam()async throws {
        let helper=ChallengeRunTests(),save=try helper.store()
        var own=helper.team();let p=own[0];var stats=p.stats;stats["spe"]=1
        own[0]=BattlePokemon(id:p.id,speciesID:p.speciesID,species:p.species,displayName:p.displayName,level:p.level,ability:p.ability,nature:p.nature,gender:p.gender,shiny:p.shiny,form:p.form,ivs:p.ivs,stats:stats,moves:["sketch","protect"])
        let foe=helper.team("b").map { p in
            var stats=p.stats;stats["atk"]=1;stats["spa"]=1
            return BattlePokemon(id:p.id,speciesID:p.speciesID,species:p.species,displayName:p.displayName,level:p.level,ability:p.ability,nature:p.nature,gender:p.gender,shiny:p.shiny,form:p.form,ivs:p.ivs,stats:stats,moves:["tackle"])
        }
        let catalog=ChallengeEncounterCatalog(version:"sketch-test",encounters:[.init(id:"sketch",index:0,nameKo:"검증",phase:"test",team:foe)])
        let session=try ChallengeBattleSession(save:save,catalog:catalog)
        defer{session.stop();try? FileManager.default.removeItem(at:save.url.deletingLastPathComponent())}
        try session.start(team:own);let first=try await wait(session)
        try session.choose(BattleDecision(decisionID:first.decisionID,actions:[.init(kind:"move",index:1,target:0)],order:[]))
        let changed=try await wait(session,after:first.decisionID)
        XCTAssertEqual(changed.resources?.first?.moves.first?.id,"tackle")
        XCTAssertEqual(save.run?.team.first?.moves.first,"tackle")
        XCTAssertEqual(save.run?.checkpoint?.initialTeam.first?.moves.first,"sketch")
        session.stop()
        let resumed=try ChallengeBattleSession(save:ChallengeRunStore(url:save.url),catalog:catalog)
        defer{resumed.stop()};try resumed.resume()
        let restored=try await wait(resumed)
        XCTAssertEqual(restored.resources,changed.resources)
    }

}
