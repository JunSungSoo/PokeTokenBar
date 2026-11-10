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

    func testDoublesReplaysTwoCommandsAndCarriesHPAndPPIntoNextEncounter() async throws {
        let helper = ChallengeRunTests()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let singles = ChallengeRunStore(url: directory.appendingPathComponent("challenge-run-v1.json"))
        try singles.start(team: helper.team(), catalogVersion: "legacy-singles")
        let singlesBytes = try Data(contentsOf: singles.url)
        XCTAssertNil(singles.run?.mode)
        let wrongMode = ChallengeRunStore(url: singles.url, mode: .doubles)
        XCTAssertFalse(wrongMode.canWrite)
        XCTAssertEqual(try Data(contentsOf: singles.url), singlesBytes)

        let doubles = ChallengeRunStore(url: directory.appendingPathComponent("challenge-doubles-run-v1.json"),
                                        mode: .doubles, roll: { .attack })
        var team = helper.team(), opponent = helper.team("b")
        for index in team.indices {
            team[index].moves = ["splash"]
            opponent[index].moves = ["tackle"]
        }
        let catalog = ChallengeEncounterCatalog(version: "doubles-fixture", encounters: [
            .init(id: "brock", index: 0, nameKo: "웅", phase: "gym", team: opponent),
            .init(id: "misty", index: 1, nameKo: "이슬", phase: "gym", team: opponent)
        ], mode: .doubles)
        let session = try ChallengeBattleSession(save: doubles, catalog: catalog, testControlsEnabled: true)
        defer { session.stop() }
        try doubles.start(team: team, catalogVersion: catalog.version, encounterCount: 2)
        try doubles.beginEncounter(opponent: opponent, seed: [1, 2, 3, 4],
                                   policyRevision: ChallengeEncounterCatalog.policyRevision(mode: .doubles))
        try session.resume()
        let opening = try await wait(session)
        XCTAssertEqual(opening.own.filter(\.active).map(\.id), ["a0", "a1"])
        XCTAssertEqual(opening.own.count, 6)
        XCTAssertEqual(opening.foeTeamStatus?.selected, 6)
        let splash = BattleAction(kind: "move", index: 1, target: 0)
        XCTAssertThrowsError(try session.choose(.init(decisionID: opening.decisionID, actions: [splash], order: [])))
        XCTAssertNil(doubles.run?.checkpoint?.pendingDecision)
        try session.choose(.init(decisionID: opening.decisionID, actions: [splash, splash], order: []))
        let played = try await wait(session, after: opening.decisionID)
        let carried = try XCTUnwrap(played.resources)
        XCTAssertTrue(carried.prefix(2).allSatisfy { $0.moves[0].pp == $0.moves[0].maxPP - 1 })
        XCTAssertTrue(carried.prefix(2).contains { $0.hp < 500 })
        session.stop()

        let loaded = ChallengeRunStore(url: doubles.url, mode: .doubles, roll: { .attack })
        let resumed = try ChallengeBattleSession(save: loaded, catalog: catalog, testControlsEnabled: true)
        defer { resumed.stop() }
        try resumed.resume()
        let replay = try await wait(resumed)
        XCTAssertEqual(replay.decisionID, played.decisionID)
        XCTAssertEqual(replay.resources, carried)
        XCTAssertEqual(loaded.run?.checkpoint?.decisions.first?.actions.count, 2)
        resumed.completePresentation()
        try resumed.winForTesting()
        let victory = try await wait(resumed, after: replay.decisionID)
        XCTAssertTrue(victory.ended)
        resumed.completePresentation()
        try resumed.applyReward(.buff(.attack))
        try resumed.startEncounter()
        let next = try await wait(resumed, after: victory.decisionID)
        XCTAssertEqual(next.resources, Array(carried.prefix(4)))
        XCTAssertEqual(loaded.run?.resources,carried)
        XCTAssertEqual(loaded.run?.encounterIndex, 1)
        XCTAssertEqual(try Data(contentsOf: singles.url), singlesBytes)
        XCTAssertEqual(ChallengeRunStore(url: singles.url).run?.battleMode, .singles)
    }

    func testDoublesCatalogUsesKantoRouteAndSinglesLevels() throws {
        let catalog = try ChallengeEncounterCatalog.load(mode: .doubles)
        XCTAssertEqual(catalog.encounters.map(\.id), [
            "brock", "misty", "ltsurge", "erika", "koga1", "sabrina", "blaine", "giovanni",
            "lorelei", "bruno1", "agatha", "lance1", "blue", "red"
        ])
        XCTAssertTrue(catalog.encounters.enumerated().allSatisfy { index, encounter in
            encounter.index == index && encounter.team.count == 6
                && encounter.team.allSatisfy { $0.level == (index < 12 ? 95 : 100) }
        })
        let singles = try ChallengeEncounterCatalog.load()
        XCTAssertNotEqual(catalog.version, singles.version)
        XCTAssertEqual(catalog.encounters[0].team.prefix(2).map(\.species), ["Aerodactyl", "Golem"])
        XCTAssertEqual(singles.encounters[0].team.prefix(2).map(\.species), ["Geodude", "Onix"])
        XCTAssertEqual(catalog.encounters.last?.team.prefix(2).map(\.species), ["Charizard", "Venusaur"])
    }

    func testPreviousDoublesCheckpointKeepsItsOpponentAndPolicyAfterCatalogUpgrade() async throws {
        let catalog = try ChallengeEncounterCatalog.load(mode: .doubles)
        let previousVersion = try XCTUnwrap(catalog.compatiblePreviousVersions?.first)
        let oldOpponent = try ChallengeEncounterCatalog.load().encounters[0].team
        let temp = try ChallengeRunTests().store()
        defer { try? FileManager.default.removeItem(at: temp.url.deletingLastPathComponent()) }
        let save = ChallengeRunStore(url: temp.url, mode: .doubles)
        try save.start(team: ChallengeRunTests().team(), catalogVersion: previousVersion, encounterCount: 14)
        try save.beginEncounter(opponent: oldOpponent, seed: [1, 2, 3, 4], policyRevision: "ptb-challenge-doubles-v1")
        let session = try ChallengeBattleSession(save: save, catalog: catalog)
        defer { session.stop() }
        try session.resume()
        let opening = try await wait(session)
        XCTAssertEqual(save.run?.catalogVersion, catalog.version)
        XCTAssertEqual(save.run?.checkpoint?.opponent, oldOpponent)
        XCTAssertEqual(save.run?.checkpoint?.policyRevision, "ptb-challenge-doubles-v1")
        XCTAssertEqual(opening.foe.map(\.name), ["Geodude", "Onix"])
    }
    func testNextEncounterClearsOnlySleepAndMidbattleSleepSurvivesResume()async throws {
        let helper=ChallengeRunTests(),temporary=try helper.store()
        let save=ChallengeRunStore(url:temporary.url,roll:{.attack})
        var own=helper.team();own[0].moves=["rest","protect"]
        var foe=helper.team("b");for i in foe.indices{foe[i].moves=["splash"]}
        let catalog=ChallengeEncounterCatalog(version:"sleep-boundary",encounters:[
            .init(id:"brock",index:0,nameKo:"웅",phase:"gym",team:foe),
            .init(id:"falkner",index:1,nameKo:"비상",phase:"gym",team:foe)])
        try save.start(team:own,catalogVersion:catalog.version,encounterCount:2)
        try save.beginEncounter(opponent:foe,seed:[1,2,3,4],policyRevision:ChallengeEncounterCatalog.policyRevision())
        var state=save.run!.resources
        for (i,status) in ["psn","brn","par","frz","slp","tox"].enumerated(){state[i].status=status}
        state[0].hp=100;state[4].sleepStart=3;state[4].sleepRemaining=2
        try save.accept(resources:state,decision:nil,winner:0);try save.apply(.buff(.attack))
        XCTAssertEqual(ChallengeRunStore(url:save.url).run?.resources,state,"Reward/reopen does not clear ailments")
        let session=try ChallengeBattleSession(save:save,catalog:catalog);defer{session.stop()}
        try session.startEncounter();let opening=try await wait(session)
        let expected=["psn","brn","par","frz","","tox"]
        XCTAssertEqual(save.run?.checkpoint?.initialResources.map(\.status),expected)
        XCTAssertEqual(opening.resources?.map(\.status),expected)
        XCTAssertNil(save.run?.resources[4].sleepStart);XCTAssertNil(save.run?.resources[4].sleepRemaining)
        try session.choose(.init(decisionID:opening.decisionID,actions:[.init(kind:"move",index:1,target:0)],order:[]))
        let asleep=try await wait(session,after:opening.decisionID)
        XCTAssertEqual(asleep.resources?.first?.status,"slp","Rest creates real in-battle sleep")
        session.stop()
        let loaded=ChallengeRunStore(url:save.url),resumed=try ChallengeBattleSession(save:loaded,catalog:catalog)
        defer{resumed.stop()};try resumed.resume();let restored=try await wait(resumed)
        XCTAssertEqual(restored.resources,asleep.resources,"Resume must not wake or reroll sleep duration")
        XCTAssertEqual(restored.resources?.first?.status,"slp")
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
        let target=try XCTUnwrap(save.run?.resources.firstIndex{$0.hp>0 && $0.moves[0].pp<$0.moves[0].maxPP})
        let resource=save.run!.resources[target],before=resource.moves[0].pp
        try session.applyReward(.pp(resource.id,0));XCTAssertEqual(save.run?.resources[target].moves[0].pp,min(resource.moves[0].maxPP,before+3))
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
    func testTestTraversalVisitsEveryTrainerAndRedWithoutRefillingOrClearing()async throws {
        let helper=ChallengeRunTests(),save=try helper.store(),catalog=try ChallengeEncounterCatalog.load()
        defer{try? FileManager.default.removeItem(at:save.url.deletingLastPathComponent())}
        let session=try ChallengeBattleSession(save:save,catalog:catalog,testControlsEnabled:true)
        defer{session.stop()}
        try session.start(team:helper.team());var frame=try await wait(session)
        // Spend PP in a real turn before exercising QA traversal.
        try session.choose(action(frame));frame=try await wait(session,after:frame.decisionID)
        session.completePresentation()
        let carried=try XCTUnwrap(save.run?.resources)
        XCTAssertLessThan(carried[0].moves[0].pp,15)
        let disabled=try ChallengeBattleSession(save:save,catalog:catalog,testControlsEnabled:false)
        XCTAssertThrowsError(try disabled.nextTrainerForTesting())
        XCTAssertEqual(save.run?.encounterIndex,0)
        for index in 1..<catalog.encounters.count {
            try session.nextTrainerForTesting()
            frame=try await wait(session)
            session.completePresentation()
            XCTAssertEqual(save.run?.encounterIndex,index)
            XCTAssertEqual(save.run?.checkpoint?.opponent.map(\.id),catalog.encounters[index].team.map(\.id))
            XCTAssertEqual(save.run?.checkpoint?.initialResources,carried)
            XCTAssertEqual(save.run?.phase,.battling)
        }
        XCTAssertEqual(catalog.encounters[try XCTUnwrap(save.run?.encounterIndex)].id,"red")
        XCTAssertThrowsError(try session.nextTrainerForTesting())
        try session.winForTesting();frame=try await wait(session,after:frame.decisionID)
        XCTAssertTrue(frame.ended);XCTAssertEqual(save.run?.phase,.cleared)
    }
    func testTestNextTrainerCannotLeaveUnclaimedVictoryReward()async throws {
        let helper=ChallengeRunTests(),save=try helper.store(),session=try ChallengeBattleSession(save:save,catalog:ChallengeEncounterCatalog.load(),testControlsEnabled:true)
        defer{session.stop();try? FileManager.default.removeItem(at:save.url.deletingLastPathComponent())}
        try session.start(team:helper.team());let first=try await wait(session)
        session.completePresentation();try session.winForTesting()
        _ = try await wait(session,after:first.decisionID);session.completePresentation()
        XCTAssertEqual(save.run?.phase,.reward)
        let carried=save.run?.resources
        XCTAssertThrowsError(try session.nextTrainerForTesting());XCTAssertEqual(save.run?.phase,.reward)
        XCTAssertThrowsError(try session.startEncounter());XCTAssertEqual(save.run?.encounterIndex,0)
        try session.applyReward(.buff(try XCTUnwrap(save.run?.rewardRoll)))
        try session.startEncounter();_ = try await wait(session)
        XCTAssertEqual(save.run?.encounterIndex,1);XCTAssertEqual(save.run?.checkpoint?.initialResources,carried)
    }
    func testActualTeamBuffPayloadStackAndReplayPreserveThreeBattleDuration()async throws {
        let helper=ChallengeRunTests(),temporary=try helper.store(),save=ChallengeRunStore(url:temporary.url,roll:{.attack})
        let catalog=try ChallengeEncounterCatalog.load(),session=try ChallengeBattleSession(save:save,catalog:catalog,testControlsEnabled:true)
        defer{session.stop()}
        try session.start(team:helper.team());var f=try await wait(session)
        session.completePresentation();try session.winForTesting();f=try await wait(session,after:f.decisionID);session.completePresentation()
        try session.applyReward(.buff(.attack));try session.startEncounter();f=try await wait(session)
        XCTAssertTrue(f.own.allSatisfy{$0.boosts?["atk"]==1 && $0.stats?["atk"]==120})
        XCTAssertEqual(save.run?.teamBuffs?.map(\.remaining),[3])
        let old=f.decisionID;try session.choose(action(f));f=try await wait(session,after:old)
        let resources=f.resources,decision=f.decisionID
        session.stop();try session.resume();f=try await wait(session)
        XCTAssertEqual(f.decisionID,decision);XCTAssertEqual(f.resources,resources)
        XCTAssertEqual(save.run?.teamBuffs?.map(\.remaining),[3]);XCTAssertEqual(f.own.first?.boosts?["atk"],1)
        session.completePresentation();try session.winForTesting();f=try await wait(session,after:f.decisionID);session.completePresentation()
        try session.applyReward(.buff(.attack));try session.startEncounter();f=try await wait(session)
        XCTAssertTrue(f.own.allSatisfy{$0.boosts?["atk"]==2});XCTAssertEqual(save.run?.teamBuffs?.map(\.remaining),[2,3])
        session.completePresentation();try session.winForTesting();f=try await wait(session,after:f.decisionID);session.completePresentation()
        try session.applyReward(.allHeal);try session.startEncounter();f=try await wait(session)
        XCTAssertTrue(f.own.allSatisfy{$0.boosts?["atk"]==2});XCTAssertEqual(save.run?.teamBuffs?.map(\.remaining),[1,2])
    }
    func testVersionTwoCombinedBuffCheckpointResumesWithoutExtendingLegacyDuration()async throws {
        let helper=ChallengeRunTests(),save=try helper.store(),catalog=try ChallengeEncounterCatalog.load()
        try save.start(team:helper.team(),catalogVersion:catalog.version)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
        json["teamBuffs"]=[["id":"legacy","kind":"power","remaining":2]]
        try JSONSerialization.data(withJSONObject:json).write(to:save.url)
        let session=try ChallengeBattleSession(save:ChallengeRunStore(url:save.url),catalog:catalog)
        try session.startEncounter();var f=try await wait(session)
        try session.choose(action(f));f=try await wait(session,after:f.decisionID);session.stop()
        json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
        var checkpoint=try XCTUnwrap(json["checkpoint"] as? [String:Any]);checkpoint["engineRevision"]=BattleEngineProcess.previousRewardRevision;json["checkpoint"]=checkpoint
        try JSONSerialization.data(withJSONObject:json).write(to:save.url)
        let restored=try ChallengeBattleSession(save:ChallengeRunStore(url:save.url),catalog:catalog,testControlsEnabled:true);defer{restored.stop()}
        try restored.resume();let replay=try await wait(restored)
        XCTAssertEqual(replay.decisionID,f.decisionID);XCTAssertEqual(replay.resources,f.resources)
        XCTAssertEqual(replay.own.first?.boosts?["atk"],1);XCTAssertEqual(replay.own.first?.boosts?["spa"],1)
        XCTAssertEqual(restored.save.run?.teamBuffs?.map(\.remaining),[2])
        restored.completePresentation();try restored.winForTesting();_ = try await wait(restored,after:replay.decisionID)
        XCTAssertEqual(restored.save.run?.teamBuffs?.map(\.remaining),[1])
        XCTAssertTrue(ChallengeBuffKind.allCases.contains(try XCTUnwrap(restored.save.run?.rewardRoll)))
    }
    func testPreviousEngineCheckpointWithoutBuffsStillResumesDeterministically()async throws {
        let helper=ChallengeRunTests(),save=try helper.store(),catalog=try ChallengeEncounterCatalog.load()
        let session=try ChallengeBattleSession(save:save,catalog:catalog);defer{session.stop()}
        try session.start(team:helper.team());let f=try await wait(session);session.stop()
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
        var checkpoint=try XCTUnwrap(json["checkpoint"] as? [String:Any]);checkpoint["engineRevision"]=BattleEngineProcess.previousChallengeRevision;checkpoint.removeValue(forKey:"initialBuffs");json["checkpoint"]=checkpoint
        try JSONSerialization.data(withJSONObject:json).write(to:save.url)
        let restored=try ChallengeBattleSession(save:ChallengeRunStore(url:save.url),catalog:catalog);defer{restored.stop()}
        try restored.resume();let actual=try await wait(restored)
        XCTAssertEqual(actual.decisionID,f.decisionID);XCTAssertEqual(actual.resources,f.resources)
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
