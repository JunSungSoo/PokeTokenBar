import AppKit
import SwiftUI
import XCTest
import Vision
@testable import PokeTokenBar

private struct ChallengeUIProvider:PokeProviding,PokemonDetailProviding {
    static let species:[Int:(String,String)]=[6:("charizard","blaze"),9:("blastoise","torrent"),3:("venusaur","overgrow"),94:("gengar","levitate"),143:("snorlax","immunity"),181:("ampharos","static"),65:("alakazam","synchronize")]
    func line(baseSpeciesID:Int)async throws->EvoLine{throw URLError(.notConnectedToInternet)}
    func baseSpeciesIndex()async throws->[BaseSpecies]{[]}
    func baseSpecies(id:Int)async throws->BaseSpecies?{nil}
    func pokemonDetails(speciesID:Int)async throws->PokemonDetails {
        let p=Self.species[speciesID]!
        return PokemonDetails(speciesID:speciesID,name:p.0,height:10,weight:100,baseExperience:100,genderRate:1,types:["normal"],
            baseStats:Dictionary(uniqueKeysWithValues:PokemonStatCalculator.order.map{($0,100)}),
            abilities:[.init(name:p.1,slot:1,isHidden:false)],moves:[.init(name:"return",learnMethods:[.init(method:"machine",level:0)]),.init(name:"protect",learnMethods:[.init(method:"machine",level:0)])])
    }
}

private struct IncomingOnlyProvider:PokemonDetailProviding {
    func pokemonDetails(speciesID:Int)async throws->PokemonDetails {
        guard speciesID==65 else{throw URLError(.notConnectedToInternet)}
        return try await ChallengeUIProvider().pokemonDetails(speciesID:speciesID)
    }
}

@MainActor final class ChallengeUITests:XCTestCase {
    private func fixture(testControls:Bool=false,rewardFixtures:Bool=false)throws->ChallengeUIModel {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("challenge-ui-\(UUID())")
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let suite="ChallengeUI.\(UUID())",defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        addTeardownBlock{try? FileManager.default.removeItem(at:dir);defaults.removePersistentDomain(forName:suite)}
        var state=CompanionState();state.installBaselineSet=true
        state.dex=[6,9,3,94,143,181,65].enumerated().map{i,id in
            var p=PokemonProfile.generate(seed:UInt64(i+1),instanceID:"instance-\(i)")
            p.level=100;p.gender = .male;p.abilityName=ChallengeUIProvider.species[id]!.1;p.abilitySlot=1
            p.moves=[.init(name:"return",learnedAtLevel:1)];p.hasCustomMoves=true
            return DexEntry(id:"owned-\(i)",baseID:id,finalID:id,chainOrder:[id],rarity:.common,caughtAt:Date(),nature:.adamant,profile:p)
        }
        var duplicate=state.dex[0];duplicate.id="duplicate";state.dex.append(duplicate)
        if rewardFixtures {
            var released=state.dex[0];released.id="released";released.releasedAt=Date();state.dex.append(released)
            var shiny=state.dex[1];shiny.id="already-shiny";shiny.isShiny=true;state.dex.append(shiny)
            var legacy=state.dex[0];legacy.id="legacy-graduate";legacy.profile=nil;state.dex.append(legacy)
        }
        let file=dir.appendingPathComponent("collection.json");try JSONEncoder().encode(state).write(to:file)
        let store=CompanionStore(provider:ChallengeUIProvider(),fileURL:file,defaults:defaults)
        let weak=ChallengeRunTests().team("foe").map{p in
            BattlePokemon(id:p.id,speciesID:p.speciesID,species:p.species,displayName:p.displayName,level:100,ability:p.ability,nature:p.nature,gender:p.gender,shiny:false,form:nil,ivs:p.ivs,
                stats:["hp":1,"atk":1,"def":1,"spa":1,"spd":1,"spe":1],moves:["splash"])
        }
        let catalog=ChallengeEncounterCatalog(version:"ui-test",encounters:[.init(id:"brock",index:0,nameKo:"웅",phase:"gym",team:weak),.init(id:"falkner",index:1,nameKo:"비상",phase:"gym",team:weak)])
        let session=try ChallengeBattleSession(save:ChallengeRunStore(url:dir.appendingPathComponent("run.json")),catalog:catalog,testControlsEnabled:testControls)
        let model=ChallengeUIModel(store:store,session:session,provider:ChallengeUIProvider(),itemMemory:BattlePokemonItemStore(defaults:defaults),itemUsage:BattleItemUsageStore(defaults:defaults))
        model.isOpen=true;addTeardownBlock{Task{@MainActor in model.close()}}
        return model
    }
    private func wait(_ m:ChallengeUIModel,after:String?=nil)async throws->BattleFrame {
        let end=Date().addingTimeInterval(8)
        while Date()<end {
            if let error=m.session.error{XCTFail(error);throw ChallengeFailure.invalidState}
            if let f=m.session.frame,!m.session.submitted,after==nil || f.decisionID != after{return f}
            try await Task.sleep(for:.milliseconds(15))
        }
        throw ChallengeFailure.invalidState
    }
    private func beginPrepared(_ m:ChallengeUIModel) {
        if m.preparationOrder.isEmpty {for p in m.run?.team ?? []{m.selectPrepared(p.id)}}
        m.beginPreparedEncounter()
    }
    private func win(_ m:ChallengeUIModel)async throws {
        var f=try await wait(m)
        for _ in 0..<30 {
            if f.ended{break}
            m.didFinishPresentation()
            let slot=try XCTUnwrap(f.slots.first),old=f.decisionID
            let a=slot.mustSwitch ? BattleAction(kind:"switch",index:try XCTUnwrap(f.own.firstIndex{!$0.active && !$0.fainted})+1,target:0):BattleAction(kind:"move",index:1,target:0)
            try m.session.choose(.init(decisionID:old,actions:[a],order:[]));f=try await wait(m,after:old)
        }
        XCTAssertTrue(f.ended);XCTAssertEqual(f.winner,0)
    }
    func testPreparationPreviewsBothTeamsAndOnlyChangesOrderAndItemsAcrossEncounters()async throws {
        let m=try fixture();defer{m.close()}
        for i in 0..<6{m.select("owned-\(i)")}
        await m.start()
        XCTAssertEqual(m.screen,.preparation);XCTAssertNil(m.session.frame)
        XCTAssertEqual(m.preparationOpponent?.id,"brock")
        XCTAssertEqual(m.preparationOpponent?.team.count,6)
        let frozen=try XCTUnwrap(m.run?.team)
        XCTAssertTrue(m.preparationOrder.isEmpty);XCTAssertFalse(m.canStartPrepared)
        m.beginPreparedEncounter();XCTAssertNil(m.session.frame)
        m.selectPrepared("owned-5");m.selectPrepared("owned-0");m.selectPrepared("owned-5")
        XCTAssertEqual(m.preparationOrder,["owned-0"],"Clicking a selected card removes it and renumbers the rest")
        m.selectPrepared("owned-0")
        for id in ["owned-5","owned-0","owned-1","owned-2","owned-3","owned-4"]{m.selectPrepared(id)}
        XCTAssertTrue(m.canStartPrepared)
        XCTAssertTrue(m.applyPreparedItem("leftovers",to:"owned-5"))
        XCTAssertFalse(m.applyPreparedItem("leftovers",to:"owned-0"))
        XCTAssertFalse(m.applyPreparedItem("charizarditex",to:"owned-5"))
        XCTAssertTrue(m.savePreparation())
        m.close();m.isOpen=true;m.resume()
        XCTAssertEqual(m.screen,.preparation)
        XCTAssertTrue(m.preparationOrder.isEmpty,"Every preparation uses explicit click order")
        for id in ["owned-5","owned-0","owned-1","owned-2","owned-3","owned-4"]{m.selectPrepared(id)}
        XCTAssertEqual(m.preparationItems["owned-5"],"leftovers")
        beginPrepared(m);let frame=try await wait(m)
        XCTAssertEqual(frame.own.first(where:{$0.active})?.id,"owned-5")
        XCTAssertEqual(m.run?.checkpoint?.initialTeam.first?.item,"leftovers")
        XCTAssertEqual(m.run?.team.map(\.stats).count,6)
        for p in frozen {
            let current=try XCTUnwrap(m.run?.team.first{$0.id==p.id})
            XCTAssertEqual(current.moves,p.moves);XCTAssertEqual(current.ability,p.ability);XCTAssertEqual(current.stats,p.stats)
        }
        try await win(m);m.didFinishPresentation()
        m.next();XCTAssertEqual(m.screen,.reward,"Mandatory reward cannot be bypassed")
        m.selectReward(.buff);await m.applyReward()
        let carried=try XCTUnwrap(m.run?.resources)
        m.next();XCTAssertEqual(m.screen,.preparation)
        XCTAssertEqual(m.preparationOpponent?.id,"falkner")
        XCTAssertEqual(m.run?.encounterIndex,0,"Preview does not advance the save before Start")
        for id in ["owned-0","owned-5","owned-1","owned-2","owned-3","owned-4"]{m.selectPrepared(id)}
        XCTAssertTrue(m.applyPreparedItem("",to:"owned-5"))
        XCTAssertTrue(m.applyPreparedItem("leftovers",to:"owned-0"))
        beginPrepared(m);_ = try await wait(m)
        XCTAssertEqual(m.run?.encounterIndex,1)
        for old in carried {
            let now=try XCTUnwrap(m.run?.checkpoint?.initialResources.first{$0.id==old.id})
            XCTAssertEqual(now.hp,old.hp);XCTAssertEqual(now.moves,old.moves);XCTAssertEqual(now.status,old.status)
        }
        XCTAssertEqual(m.run?.checkpoint?.initialResources.first{$0.id=="owned-0"}?.item,"leftovers")
        XCTAssertEqual(m.run?.checkpoint?.initialTeam.first?.id,"owned-0")
    }
    func testSelectionItemsActualBattleRewardSaveAndNext()async throws {
        let m=try fixture();defer{m.close()}
        m.select("owned-0");m.select("duplicate");XCTAssertEqual(m.selectedIDs,["owned-0"])
        for i in 1..<6{m.select("owned-\(i)")}
        XCTAssertTrue(m.applyItem("leftovers",to:"owned-0"));XCTAssertFalse(m.applyItem("leftovers",to:"owned-1"))
        await m.start();beginPrepared(m);XCTAssertFalse(m.problem);_ = try await wait(m)
        XCTAssertEqual(m.screen,.battle);XCTAssertEqual(m.run?.team.count,6);XCTAssertTrue(m.intro.active)
        XCTAssertEqual(m.run?.team[0].item,"leftovers")
        try await win(m)
        XCTAssertEqual(m.screen,.battle,"Final effects must finish before exposing rewards")
        m.didFinishPresentation();XCTAssertEqual(m.screen,.reward)
        m.selectReward(.pp);let id=m.rewardPokemonID,move=m.rewardMove
        let before=try XCTUnwrap(m.run?.resources.first{$0.id==id}).moves[move]
        await m.applyReward();XCTAssertFalse(m.problem);XCTAssertEqual(m.run?.phase,.intermission)
        XCTAssertEqual(m.run?.resources.first{$0.id==id}?.moves[move].pp,min(before.maxPP,before.pp+3))
        let carried=try XCTUnwrap(m.run?.resources)
        m.close()
        XCTAssertEqual(ChallengeRunStore(url:m.save.url).run?.resources,carried)
        m.isOpen=true;m.next();beginPrepared(m);let next=try await wait(m)
        XCTAssertEqual(m.run?.encounterIndex,1);XCTAssertEqual(next.resources,carried);XCTAssertTrue(m.intro.active)
    }
    func testCollectionLoadoutEditsCannotChangeStartedChallengeAfterResumeOrNextEncounter()async throws {
        let m=try fixture();defer{m.close()}
        for i in 0..<6{m.select("owned-\(i)")}
        await m.start();beginPrepared(m);let opening=try await wait(m)
        let registered=try XCTUnwrap(m.run?.team),checkpoint=try XCTUnwrap(m.run?.checkpoint)
        XCTAssertEqual(BattleTextCatalog.key(registered[0].ability),"blaze")
        XCTAssertEqual(registered[0].moves,["return"])

        // Exercise the same persisted edit APIs used by Collection and Pokédex details.
        await m.store.loadPokemonDetails(speciesID:6)
        XCTAssertTrue(m.store.setPokemonMove(entryID:"owned-0",slot:0,name:"protect"))
        XCTAssertTrue(m.store.setPokemonAbility(entryID:"owned-0",name:"Solar Power"))
        XCTAssertTrue(m.store.setPokemonBattleDefaultItem(entryID:"owned-0",itemID:"lifeorb"))
        let edited=try XCTUnwrap(m.store.state.dex.first{$0.id=="owned-0"})
        XCTAssertEqual(edited.profile?.moves.map(\.name),["protect"])
        XCTAssertEqual(edited.profile?.abilityName,"Solar Power")
        let disk=try JSONDecoder().decode(CompanionState.self,from:Data(contentsOf:m.save.url.deletingLastPathComponent().appendingPathComponent("collection.json")))
        XCTAssertEqual(disk.dex.first{$0.id=="owned-0"}?.profile?.moves.map(\.name),["protect"])
        m.reconcileSelection()
        XCTAssertEqual(m.run?.team,registered)
        XCTAssertEqual(m.run?.checkpoint?.initialTeam,checkpoint.initialTeam)
        XCTAssertEqual(BattleTextCatalog.key(opening.own.first{$0.active}?.ability ?? ""),"blaze")
        XCTAssertEqual(opening.slots.first?.moves.map{BattleTextCatalog.key($0.apiName ?? $0.name)},["return"])
        m.close()

        let loaded=ChallengeRunStore(url:m.save.url)
        XCTAssertEqual(loaded.run?.team,registered)
        let session=try ChallengeBattleSession(save:loaded,catalog:m.session.catalog)
        // Existing team members must never need to rebuild from mutable collection data.
        let resumed=ChallengeUIModel(store:m.store,session:session,provider:IncomingOnlyProvider())
        resumed.isOpen=true;defer{resumed.close()}
        resumed.resume();let replayed=try await wait(resumed)
        XCTAssertEqual(replayed.decisionID,opening.decisionID)
        XCTAssertEqual(session.save.run?.team,registered)
        XCTAssertEqual(BattleTextCatalog.key(replayed.own.first{$0.active}?.ability ?? ""),"blaze")
        XCTAssertEqual(replayed.slots.first?.moves.map{BattleTextCatalog.key($0.apiName ?? $0.name)},["return"])
        try await win(resumed);resumed.didFinishPresentation()
        let carried=try XCTUnwrap(resumed.run?.resources)
        XCTAssertLessThan(carried[0].moves[0].pp,checkpoint.initialResources[0].moves[0].pp)
        XCTAssertEqual(carried[0].moves[0].id,"return")
        resumed.selectReward(.buff);await resumed.applyReward();XCTAssertFalse(resumed.problem)
        resumed.next();beginPrepared(resumed);let next=try await wait(resumed)
        XCTAssertEqual(resumed.run?.encounterIndex,1)
        XCTAssertEqual(resumed.run?.team,registered)
        XCTAssertEqual(resumed.run?.checkpoint?.initialTeam,registered)
        XCTAssertEqual(next.resources,carried)
        XCTAssertEqual(BattleTextCatalog.key(next.own.first{$0.active}?.ability ?? ""),"blaze")
        XCTAssertEqual(next.slots.first?.moves.map{BattleTextCatalog.key($0.apiName ?? $0.name)},["return"])
        XCTAssertEqual(ChallengeRunStore(url:m.save.url).run?.team,registered)
    }
    func testPendingRewardReopensWithoutBattleFrameAndReplacementBuildsOnlyNewMember()async throws {
        let m=try fixture();defer{m.close()}
        for i in 0..<6{m.select("owned-\(i)")};await m.start();beginPrepared(m);try await win(m);m.didFinishPresentation();m.close()
        let loaded=try ChallengeBattleSession(save:ChallengeRunStore(url:m.save.url),catalog:m.session.catalog)
        let reopened=ChallengeUIModel(store:m.store,session:loaded,provider:IncomingOnlyProvider(),itemMemory:m.itemMemory,itemUsage:m.itemUsage)
        reopened.isOpen=true;defer{reopened.close()}
        XCTAssertEqual(reopened.screen,.reward);XCTAssertNil(loaded.frame)
        reopened.selectReward(.replace);reopened.rewardPokemonID="owned-0";reopened.incomingID="owned-6"
        XCTAssertTrue(reopened.canApplyReward);await reopened.applyReward()
        XCTAssertFalse(reopened.problem);XCTAssertEqual(reopened.run?.phase,.intermission)
        XCTAssertEqual(reopened.run?.team[0].id,"owned-6");XCTAssertEqual(reopened.run?.resources[0].moves[0].pp,20)
        XCTAssertTrue(reopened.run?.retiredIDs.contains("owned-0")==true)
        XCTAssertFalse(reopened.replacements.contains{$0.id=="owned-0"})
    }
    func testSavedVictoryHealingRevivesWithoutAReplayedBattle()async throws {
        let m=try fixture();defer{m.close()}
        let team=ChallengeRunTests().team()
        try m.save.start(team:team,catalogVersion:m.session.catalog.version,encounterCount:2)
        try m.save.beginEncounter(opponent:team,seed:[1,2,3,4],policyRevision:"test")
        var resources=try XCTUnwrap(m.run?.resources);resources[0].hp=0
        try m.save.accept(resources:resources,decision:nil,winner:0)
        XCTAssertNil(m.session.frame);XCTAssertEqual(m.screen,.reward)
        m.selectReward(.heal);XCTAssertTrue(m.canApplyReward)
        await m.applyReward();XCTAssertFalse(m.problem)
        XCTAssertEqual(m.run?.resources[0].hp,175);XCTAssertEqual(m.run?.phase,.intermission)
        await m.applyReward();XCTAssertEqual(m.run?.resources[0].hp,175,"A reward is claimed only once")
    }
    func testSingleReplacementValidationDoesNotWeakenSixMemberTeamContract()async throws {
        let m=try fixture();defer{m.close()}
        let one=try await BattleTeamBuilder.buildIndividual(id:"owned-6",entries:m.candidates,language:.ko,provider:ChallengeUIProvider())
        XCTAssertEqual(one.id,"owned-6")
        do {_ = try await BattleEngineProcess.validate(mode:.singles,team:[one]);XCTFail("Ordinary registration must still require six") }catch{}
        do {_ = try await BattleEngineProcess.validate(mode:.doubles,team:[one],memberOnly:true);XCTFail("Member-only API is singles-only") }catch{}
    }
    func testEveryTrainerHasOriginalAtlasAndLocalizedNameAndIntroWaitsForExit()async throws {
        let catalog=try ChallengeEncounterCatalog.load()
        XCTAssertEqual(Set(catalog.encounters.map{ChallengeTrainerCatalog.key($0.id)}).count,24)
        for e in catalog.encounters {
            let image=try XCTUnwrap(ChallengeTrainerCatalog.image(ChallengeTrainerCatalog.key(e.id)),e.id)
            XCTAssertGreaterThan(image.size.height,10)
            for lang in AppLanguage.allCases{XCTAssertNotEqual(ChallengeTrainerCatalog.name(e.id,language:lang),L(lang).challengeTitle)}
        }
        let intro=ChallengeTrainerIntro();intro.duration = .milliseconds(50);intro.reset(encounter:"lance2")
        let own=BattleVisualEvent(id:1,move:"",type:"",category:"",source:.init(own:true,slot:0),targets:[],phase:"entry")
        await intro.before(own);XCTAssertTrue(intro.active);XCTAssertTrue(intro.ownEntryStarted);XCTAssertFalse(intro.exiting)
        let foe=BattleVisualEvent(id:2,move:"",type:"",category:"",source:.init(own:false,slot:0),targets:[],phase:"entry")
        let exit=Task{await intro.before(foe)}
        try await Task.sleep(for:.milliseconds(10));XCTAssertTrue(intro.active);XCTAssertTrue(intro.exiting)
        await exit.value;XCTAssertFalse(intro.active)
    }
    func testProductionWindowRendersSelectionAndPlaysTrainerExitBeforeFoeEntry()async throws {
        let m=try fixture(),activity=ChallengeActivity()
        let controller=ChallengeWindowController(model:m,identity:.init(nickname:"Test",code:"test",nonce:"test"),allowsAudio:false,activity:activity)
        controller.show(present:false)
        defer{m.close();controller.window?.close()}
        for i in 0..<6{m.select("owned-\(i)")}
        func capture(_ name:String)throws {
            let view=try XCTUnwrap(controller.window?.contentView)
            view.layoutSubtreeIfNeeded()
            let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds))
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/ptb-challenge-\(name).png"))
        }
        try await Task.sleep(for:.milliseconds(400));try capture("selection")
        await m.start();try await Task.sleep(for:.milliseconds(200));try capture("preparation");beginPrepared(m);_ = try await wait(m)
        let opening=BattlePresentationEvents(frame:try XCTUnwrap(m.session.frame),language:.ko,ownPlayer:0).events.filter{$0.phase=="entry"}
        XCTAssertEqual(opening.map(\.source.own),[true,false],"Trainer timing relies on engine's ordered opening entries")
        try capture("trainer")
        let deadline=Date().addingTimeInterval(25)
        while m.intro.active,Date()<deadline{try await Task.sleep(for:.milliseconds(40))}
        XCTAssertTrue(m.intro.ownEntryStarted);XCTAssertFalse(m.intro.active,"Production effects must drive the trainer exit")
        try await Task.sleep(for:.seconds(4));try capture("battle")
        try await win(m);m.didFinishPresentation();m.configureRewardSelection()
        try await Task.sleep(for:.milliseconds(400));try capture("reward")
    }
    func testActualDefeatCannotResumeAfterReopenAndNewRunRestartsAtFirstGym()async throws {
        let fixture=try fixture(testControls:true)
        let save=ChallengeRunStore(url:fixture.save.url,roll:{.attack})
        let opponent=fixture.session.catalog.encounters[0].team.map{p in
            BattlePokemon(id:p.id,speciesID:p.speciesID,species:p.species,displayName:p.displayName,level:100,ability:p.ability,nature:p.nature,gender:p.gender,shiny:false,form:p.form,ivs:p.ivs,
                stats:["hp":500,"atk":500,"def":500,"spa":500,"spd":500,"spe":1000],moves:["dragonrage"])
        }
        let catalog=ChallengeEncounterCatalog(version:"actual-loss-test",encounters:["brock","falkner","misty"].enumerated().map{.init(id:$0.element,index:$0.offset,nameKo:"Test",phase:"gym",team:opponent)})
        let session=try ChallengeBattleSession(save:save,catalog:catalog,testControlsEnabled:true)
        let m=ChallengeUIModel(store:fixture.store,session:session,provider:fixture.provider)
        m.isOpen=true;defer{m.close()}
        let ids=(0..<6).map{"owned-\($0)"}
        let owned=try await BattleTeamBuilder.build(ids:ids,entries:m.candidates,mode:.singles,language:.ko,provider:fixture.provider)
        let weak=owned.map{p in
            BattlePokemon(id:p.id,speciesID:p.speciesID,species:p.species,displayName:p.displayName,level:p.level,ability:p.ability,nature:p.nature,gender:p.gender,shiny:p.shiny,form:p.form,ivs:p.ivs,
                stats:["hp":1,"atk":1,"def":1,"spa":1,"spd":1,"spe":1],moves:p.moves)
        }
        try session.start(team:weak);m.resume();var frame=try await wait(m)
        session.completePresentation();try session.winForTesting();frame=try await wait(m,after:frame.decisionID);m.didFinishPresentation()
        m.selectReward(.buff);await m.applyReward();m.next();beginPrepared(m);frame=try await wait(m)
        XCTAssertEqual(m.run?.encounterIndex,1);XCTAssertEqual(m.run?.teamBuffs?.first?.remaining,3)
        m.intro.finish();session.completePresentation()
        for _ in 0..<30 {
            if frame.ended{break}
            let slot=try XCTUnwrap(frame.slots.first)
            let action:BattleAction
            if slot.mustSwitch {
                action=BattleAction(kind:"switch",index:try XCTUnwrap(frame.own.firstIndex{!$0.active && !$0.fainted})+1,target:0)
            }else{
                action=BattleAction(kind:"move",index:try XCTUnwrap(slot.moves.first{!$0.disabled && $0.pp>0}).index,target:0)
            }
            try session.choose(BattleDecision(decisionID:frame.decisionID,actions:[action],order:[]))
            frame=try await wait(m,after:frame.decisionID);session.completePresentation()
        }
        XCTAssertTrue(frame.ended);XCTAssertEqual(frame.winner,1)
        XCTAssertTrue(frame.own.allSatisfy(\.fainted));m.didFinishPresentation()
        XCTAssertEqual(m.run?.phase,.lost);XCTAssertEqual(m.screen,.result)
        let oldID=try XCTUnwrap(m.run?.id);m.close()
        let restoredSession=try ChallengeBattleSession(save:ChallengeRunStore(url:save.url),catalog:catalog,testControlsEnabled:true)
        let restored=ChallengeUIModel(store:fixture.store,session:restoredSession,provider:fixture.provider)
        restored.isOpen=true;defer{restored.close()}
        XCTAssertEqual(restored.screen,.result);XCTAssertNil(restored.buffSummary)
        XCTAssertThrowsError(try restoredSession.resume());XCTAssertThrowsError(try restoredSession.startEncounter())
        XCTAssertThrowsError(try restoredSession.nextTrainerForTesting());XCTAssertThrowsError(try restored.save.advance())
        XCTAssertThrowsError(try restoredSession.applyReward(.buff(.attack)))
        restored.newChallenge();XCTAssertEqual(restored.screen,.setup);XCTAssertTrue(restored.selectedIDs.isEmpty)
        for id in ids{restored.select(id)};await restored.start();beginPrepared(restored);let fresh=try await wait(restored)
        XCTAssertNotEqual(restored.run?.id,oldID);XCTAssertEqual(restored.run?.encounterIndex,0)
        XCTAssertEqual(restored.encounter?.id,"brock");XCTAssertTrue((restored.run?.teamBuffs ?? []).isEmpty)
        XCTAssertTrue(restored.run!.retiredIDs.isEmpty)
        XCTAssertTrue(fresh.own.allSatisfy{$0.hp==$0.maxHP && $0.status.isEmpty})
        XCTAssertTrue(fresh.resources!.allSatisfy{$0.moves.allSatisfy{$0.pp==$0.maxPP}})
    }
    func testFinishedRealBattleUnlocksShopBeforeAndAfterMandatoryReward()async throws {
        for claimReward in [false,true] {
            let m=try fixture();defer{m.close()}
            for i in 0..<6{m.select("owned-\(i)")}
            await m.start();beginPrepared(m);_ = try await wait(m)
            XCTAssertFalse(m.canPurchase(.ppRecovery,targetID:"owned-0"))
            try await win(m)
            XCTAssertEqual(m.session.frame?.ended,true)
            // Real completion runs before the SwiftUI busy binding's deferred reset.
            m.effectsBusy=true
            XCTAssertFalse(m.canPurchase(.ppRecovery,targetID:"owned-0"),"The final battle presentation must finish first")
            m.didFinishPresentation()
            XCTAssertEqual(m.screen,.reward)
            m.playbackBusyChanged(true)
            XCTAssertFalse(m.effectsBusy,"The removed battle view must not retain a shop lock")
            if claimReward{m.selectReward(.buff);await m.applyReward()}
            XCTAssertEqual(m.run?.phase,claimReward ? .intermission:.reward)
            XCTAssertTrue(m.run?.canPurchase(.ppRecovery,targetID:"owned-0")==true)
            // A stale mirrored flag must never override settled authoritative presentation.
            m.effectsBusy=true
            XCTAssertTrue(m.canPurchase(.ppRecovery,targetID:"owned-0"))
            XCTAssertTrue(m.purchase(.ppRecovery,targetID:"owned-0"))
            XCTAssertEqual(m.shopBalance,70);XCTAssertEqual(m.shopPrice(.ppRecovery),35)
            let r=try XCTUnwrap(m.run?.resources.first{$0.id=="owned-0"})
            XCTAssertTrue(r.moves.allSatisfy{$0.pp==$0.maxPP})
            XCTAssertEqual(ChallengeRunStore(url:m.save.url).run?.pointBalance,70)
        }
    }
    func testMountedAnimatedVictoryLeavesShopTargetsPurchasable()async throws {
        let m=try fixture();defer{m.close()}
        let controller=ChallengeWindowController(model:m,identity:.init(nickname:"Test",code:"test",nonce:"test"),allowsAudio:false,activity:ChallengeActivity())
        controller.show(present:false);defer{controller.window?.close()}
        for i in 0..<6{m.select("owned-\(i)")}
        await m.start();beginPrepared(m)
        let deadline=Date().addingTimeInterval(65)
        var submitted=Set<String>()
        // Let the actual mounted renderer finish every entry/hit/HP/faint sequence.
        // No manual completePresentation/didFinishPresentation calls are allowed.
        while Date()<deadline,m.screen != .reward {
            if let error=m.session.error{XCTFail(error);break}
            if let frame=m.session.frame,!frame.ended,!m.session.submitted,!m.effectsBusy,
               !m.intro.active,!m.session.presentation.pending,!submitted.contains(frame.decisionID),
               let slot=frame.slots.first {
                submitted.insert(frame.decisionID)
                let action=BattleAction(kind:"move",index:try XCTUnwrap(slot.moves.first{!$0.disabled&&$0.pp>0}).index,target:0)
                try m.session.choose(.init(decisionID:frame.decisionID,actions:[action],order:[]))
            }
            try await Task.sleep(for:.milliseconds(30))
        }
        XCTAssertEqual(m.screen,.reward);XCTAssertEqual(m.session.frame?.ended,true)
        XCTAssertFalse(m.effectsBusy);XCTAssertFalse(m.session.presentation.pending)
        XCTAssertGreaterThan(submitted.count,0)
        m.selectReward(.buff);await m.applyReward()
        XCTAssertEqual(m.run?.phase,.intermission)
        XCTAssertTrue(m.canPurchase(.ppRecovery,targetID:"owned-0"))
        XCTAssertTrue(m.purchase(.ppRecovery,targetID:"owned-0"));XCTAssertEqual(m.shopBalance,70)
    }
    func testShopCardsRenderAndPurchaseCannotBypassRequiredVictoryReward()async throws {
        let m=try fixture();defer{m.close()}
        for i in 0..<6{m.select("owned-\(i)")};await m.start();beginPrepared(m);_ = try await wait(m)
        try await win(m);m.didFinishPresentation();m.configureRewardSelection()
        XCTAssertEqual(m.shopBalance,100)
        let controller=ChallengeWindowController(model:m,identity:.init(nickname:"Test",code:"test",nonce:"test"),allowsAudio:false,activity:ChallengeActivity())
        controller.show(present:false);defer{controller.window?.close()}
        try await Task.sleep(for:.milliseconds(200))
        let view=try XCTUnwrap(controller.window?.contentView);view.layoutSubtreeIfNeeded()
        let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/ptb-challenge-shop.png"))
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["ko-KR","en-US"]
        try VNImageRequestHandler(cgImage:try XCTUnwrap(bitmap.cgImage),options:[:]).perform([request])
        let text=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined().replacingOccurrences(of:" ",with:"")
        for label in ["챌린지상점","완전회복","PP전체회복","20%","40%","100포인트","30포인트","10포인트","20포인트"]{XCTAssertTrue(text.contains(label),"Missing card text: \(label) in \(text)")}
        XCTAssertTrue(m.canPurchase(.ppRecovery,targetID:"owned-0"))
        XCTAssertTrue(m.purchase(.ppRecovery,targetID:"owned-0"));XCTAssertEqual(m.shopBalance,70)
        XCTAssertEqual(m.run?.phase,.reward);m.next();XCTAssertEqual(m.run?.encounterIndex,0)
        m.selectReward(.buff);await m.applyReward();XCTAssertEqual(m.run?.phase,.intermission)
        m.next();beginPrepared(m);_ = try await wait(m);XCTAssertEqual(m.run?.encounterIndex,1)
        XCTAssertEqual(m.shopBalance,70,"Skipping further purchases must not block Next")
    }
    func testSevenProductShopRendersWithoutRevivalItemsAndHPRewardAllowsFainted()async throws {
        let m=try fixture();defer{m.close()}
        let team=ChallengeRunTests().team()
        try m.save.start(team:team,catalogVersion:m.session.catalog.version,encounterCount:2)
        try m.save.beginEncounter(opponent:team,seed:[1,2,3,4],policyRevision:"test")
        var resources=m.run!.resources;resources[0].hp=0;resources[1].hp=1
        try m.save.accept(resources:resources,decision:nil,winner:0)
        m.selectReward(.heal);XCTAssertEqual(m.rewardPokemonID,"a0");XCTAssertTrue(m.canApplyReward)
        m.rewardPokemonID="a1";XCTAssertTrue(m.canApplyReward)
        let controller=ChallengeWindowController(model:m,identity:.init(nickname:"Test",code:"test",nonce:"test"),allowsAudio:false,activity:ChallengeActivity())
        controller.show(present:false);defer{controller.window?.close()}
        try await Task.sleep(for:.milliseconds(200))
        let view=try XCTUnwrap(controller.window?.contentView);view.layoutSubtreeIfNeeded()
        let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/ptb-all-challenge-shop.png"))
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["ko-KR","en-US"]
        try VNImageRequestHandler(cgImage:try XCTUnwrap(bitmap.cgImage),options:[:]).perform([request])
        let text=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined().replacingOccurrences(of:" ",with:"")
        for label in ChallengeShopItem.allCases.map({m.store.l.challengeShopName($0).replacingOccurrences(of:" ",with:"")})+["10포인트","20포인트","30포인트","50포인트","100포인트"]{XCTAssertTrue(text.contains(label),"Missing card: \(label) in \(text)")}
        XCTAssertFalse(text.contains("기력의조각"));XCTAssertFalse(text.contains("기력의덩어리"))
    }
    func testMovePPSheetRendersSelectionAndUpdatedPriceAfterPurchase()async throws {
        let m=try fixture();defer{m.close()}
        let team=ChallengeRunTests().team()
        try m.save.start(team:team,catalogVersion:m.session.catalog.version,encounterCount:2)
        try m.save.beginEncounter(opponent:team,seed:[1,2,3,4],policyRevision:"test")
        var resources=m.run!.resources;resources[0].hp=0
        resources[0].moves[0].pp=0;resources[0].moves[1].pp=0
        try m.save.accept(resources:resources,decision:nil,winner:0)
        let host=NSHostingController(rootView:ChallengeShopPurchaseView(model:m,item:.ppMoveRecovery,onClose:{}).background(Color(nsColor:.windowBackgroundColor)).preferredColorScheme(.dark))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:560,height:580),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentViewController=host;window.appearance=NSAppearance(named:.darkAqua);host.view.appearance=window.appearance
        defer{window.contentViewController=nil;window.close()}
        try await Task.sleep(for:.milliseconds(250));host.view.layoutSubtreeIfNeeded()
        let bitmap=try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds));host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/ptb-selected-pp-shop.png"))
        let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["ko-KR","en-US"]
        try VNImageRequestHandler(cgImage:try XCTUnwrap(bitmap.cgImage),options:[:]).perform([request])
        let text=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined().replacingOccurrences(of:" ",with:"")
        for label in ["PP선택기술회복","파도타기","방어","0/15","0/10","10포인트"]{XCTAssertTrue(text.contains(label),"Missing move picker: \(label) in \(text)")}
        XCTAssertTrue(m.purchase(.ppMoveRecovery,targetID:"a0",moveIndex:1))
        XCTAssertEqual(m.run?.resources[0].moves.map(\.pp),[0,10]);XCTAssertEqual(m.run?.resources[0].hp,0)
        XCTAssertEqual(m.shopPrice(.ppMoveRecovery),15);XCTAssertEqual(m.shopPrice(.ppRecovery),30)
        XCTAssertEqual(m.shopBalance,90);XCTAssertEqual(m.run?.phase,.reward)
        try await Task.sleep(for:.milliseconds(150));host.view.layoutSubtreeIfNeeded()
        let updated=try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds));host.view.cacheDisplay(in:host.view.bounds,to:updated)
        try VNImageRequestHandler(cgImage:try XCTUnwrap(updated.cgImage),options:[:]).perform([request])
        let updatedText=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined().replacingOccurrences(of:" ",with:"")
        XCTAssertTrue(updatedText.contains("15포인트"),"Purchase button must show the inflated price: \(updatedText)")
    }
    func testRewardOptionsAndNextStayLockedUntilActualRewardApplication()async throws {
        let fixture=try fixture(testControls:true),save=ChallengeRunStore(url:fixture.save.url,roll:{.attack})
        let session=try ChallengeBattleSession(save:save,catalog:ChallengeEncounterCatalog.load(),testControlsEnabled:true)
        let m=ChallengeUIModel(store:fixture.store,session:session,provider:fixture.provider)
        m.isOpen=true;defer{m.close()}
        let team=try await BattleTeamBuilder.build(ids:(0..<6).map{"owned-\($0)"},entries:m.candidates,mode:.singles,language:.ko,provider:m.provider)
        try save.start(team:team,catalogVersion:session.catalog.version)
        for index in 0..<26 {
            try save.beginEncounter(opponent:team,seed:[1,2,3,4],policyRevision:"test")
            var resources=save.run!.resources
            resources[0].hp=0;resources[1].hp=1;resources[1].status="psn"
            for i in resources.indices{for j in resources[i].moves.indices{resources[i].moves[j].pp=0}}
            try save.accept(resources:resources,decision:nil,winner:0)
            m.configureRewardSelection()
            XCTAssertEqual(m.screen,.reward);XCTAssertFalse(m.canTestNextTrainer)
            XCTAssertEqual(m.rewardOptions,(index+1)%3==0 ? [.allHeal,.replace,.buff]:[.heal,.pp,.replace,.buff])
            m.next();m.nextTrainerForTesting();XCTAssertEqual(save.run?.encounterIndex,index)
            XCTAssertEqual(save.run?.phase,.reward)
            if index==2 {
                m.selectReward(.allHeal);XCTAssertTrue(m.canApplyReward);await m.applyReward()
                XCTAssertTrue(save.run!.resources.allSatisfy{$0.hp>0 && $0.status.isEmpty && $0.moves.allSatisfy{$0.pp==$0.maxPP}})
            }else if index==15 {
                m.selectReward(.pp);XCTAssertTrue(m.canApplyReward);await m.applyReward()
                XCTAssertTrue(save.run!.resources[0].moves.allSatisfy{$0.pp==$0.maxPP})
                XCTAssertTrue(save.run!.resources[1].moves.allSatisfy{$0.pp==0})
            }else{
                m.selectReward(.buff);XCTAssertTrue(m.canApplyReward);await m.applyReward()
            }
            XCTAssertEqual(save.run?.phase,.intermission)
            try save.advance()
        }
        try save.beginEncounter(opponent:team,seed:[1,2,3,4],policyRevision:"test")
        try save.accept(resources:save.run!.resources,decision:nil,winner:0)
        XCTAssertEqual(m.screen,.result);XCTAssertFalse((save.run?.teamBuffs ?? []).isEmpty)
        XCTAssertNil(m.buffSummary,"No future-battle counter should remain on the Champion finale")
    }
    func testNextTrainerResetsIntroAndAppliesArenaAndBattleMusic()async throws {
        let fixture=try fixture(testControls:true)
        let session=try ChallengeBattleSession(save:fixture.save,catalog:ChallengeEncounterCatalog.load(),testControlsEnabled:true)
        let m=ChallengeUIModel(store:fixture.store,session:session,provider:fixture.provider)
        m.isOpen=true;defer{m.close()}
        let controller=ChallengeWindowController(model:m,identity:.init(nickname:"Test",code:"test",nonce:"test"),allowsAudio:false,activity:ChallengeActivity())
        for i in 0..<6{m.select("owned-\(i)")};await m.start();beginPrepared(m);_ = try await wait(m)
        m.session.completePresentation();m.intro.finish()
        m.effectsBusy=true;m.nextTrainerForTesting();XCTAssertEqual(m.run?.encounterIndex,0)
        m.effectsBusy=false
        for (index,key,arena) in [(1,"falkner",BattleArena.mountain),(2,"misty",.lake)] {
            m.nextTrainerForTesting();_ = try await wait(m)
            XCTAssertEqual(m.run?.encounterIndex,index)
            XCTAssertEqual(m.intro.key,key);XCTAssertTrue(m.intro.active)
            XCTAssertFalse(m.intro.exiting);XCTAssertFalse(m.resuming)
            XCTAssertEqual(controller.battle.arena,arena);XCTAssertEqual(controller.resolvedMusicCue,.battle)
            m.session.completePresentation();m.intro.finish()
        }
    }
    func testProductionInstantVictoryWithNoNewEffectsShowsRewardFooter()async throws {
        let m=try fixture(testControls:true)
        // No manual presentation completion is allowed.
        let window=ChallengeWindowController(model:m,identity:.init(nickname:"Test",code:"test",nonce:"test"),allowsAudio:false,activity:ChallengeActivity())
        window.show(present:false);defer{m.close();window.window?.close()}
        for i in 0..<6{m.select("owned-\(i)")};await m.start();beginPrepared(m);_ = try await wait(m)
        let until=Date().addingTimeInterval(20)
        while (m.intro.active || m.effectsBusy),Date()<until{try await Task.sleep(for:.milliseconds(30))}
        XCTAssertFalse(m.intro.active);XCTAssertFalse(m.effectsBusy)
        let prior=m.session.frame?.effects
        try m.session.winForTesting();_ = try await wait(m,after:m.session.frame?.decisionID)
        let end=Date().addingTimeInterval(5)
        while m.screen != .reward,Date()<end{try await Task.sleep(for:.milliseconds(30))}
        XCTAssertEqual(m.session.frame?.effects,prior,"The regression must use an end-only frame")
        XCTAssertEqual(m.screen,.reward);m.selectReward(.pp)
        // No PP was spent, so take the replacement reward instead.
        m.selectReward(.replace);m.rewardPokemonID="owned-0";m.incomingID="owned-6";await m.applyReward()
        XCTAssertEqual(m.run?.phase,.intermission)
        try await Task.sleep(for:.milliseconds(250))
        let view=try XCTUnwrap(window.window?.contentView);view.layoutSubtreeIfNeeded()
        let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds));view.cacheDisplay(in:view.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/ptb-challenge-reward-fixed.png"))
    }
    func testRedUsesDistinctProvidedBattleAndVictoryMusic()async throws {
        let fixture=try fixture(testControls:true)
        let catalog=ChallengeEncounterCatalog(version:"red-music-test",encounters:[.init(id:"red",index:0,nameKo:"레드",phase:"최종 구간",team:fixture.session.catalog.encounters[0].team)])
        let session=try ChallengeBattleSession(save:fixture.save,catalog:catalog,testControlsEnabled:true)
        let m=ChallengeUIModel(store:fixture.store,session:session,provider:fixture.provider)
        m.isOpen=true;defer{m.close()}
        let controller=ChallengeWindowController(model:m,identity:.init(nickname:"Test",code:"test",nonce:"test"),allowsAudio:false,activity:ChallengeActivity())
        for i in 0..<6{m.select("owned-\(i)")};await m.start();beginPrepared(m);let frame=try await wait(m)
        XCTAssertEqual(m.run?.phase,.battling);XCTAssertEqual(controller.resolvedMusicCue,.championBattle)
        m.session.completePresentation();m.intro.finish()
        XCTAssertEqual(controller.resolvedMusicCue,.championBattle)
        try session.winForTesting();_ = try await wait(m,after:frame.decisionID)
        XCTAssertEqual(m.run?.phase,.cleared);XCTAssertEqual(controller.resolvedMusicCue,.championBattle)
        m.didFinishPresentation();XCTAssertEqual(controller.resolvedMusicCue,.championVictory)
        try m.offerChampionReward();XCTAssertNil(controller.resolvedMusicCue)
    }
    func testChampionAwardPersistsOnlyWinningIndividualsAndIsIdempotent()async throws {
        let m=try fixture();defer{m.close()}
        let ids=(0..<6).map{"owned-\($0)"}
        let team=try await BattleTeamBuilder.build(ids:ids,entries:m.candidates,mode:.singles,language:.ko,provider:m.provider)
        try m.save.start(team:team,catalogVersion:m.session.catalog.version,encounterCount:1)
        try m.save.beginEncounter(opponent:team,seed:[1,2,3,4],policyRevision:"test")
        try m.save.accept(resources:try XCTUnwrap(m.run?.resources),decision:nil,winner:0)
        m.synchronizeChampionAward();XCTAssertEqual(m.run?.phase,.cleared)
        let awards=m.store.state.dex.filter{$0.championAchievedAt != nil}
        XCTAssertEqual(Set(awards.map(\.id)),Set(ids))
        let first=awards.map(\.championAchievedAt)
        try m.store.markChallengeChampions(ids:Set(ids),date:Date().addingTimeInterval(999))
        XCTAssertEqual(m.store.state.dex.filter{$0.championAchievedAt != nil}.map(\.championAchievedAt),first)
        let saved=try JSONDecoder().decode(CompanionState.self,from:Data(contentsOf:m.save.url.deletingLastPathComponent().appendingPathComponent("collection.json")))
        XCTAssertEqual(Set(saved.dex.filter{$0.championAchievedAt != nil}.map(\.id)),Set(ids))
        XCTAssertNil(saved.dex.first{$0.id=="duplicate"}?.championAchievedAt)
        let controller=ChallengeWindowController(model:m,identity:.init(nickname:"Test",code:"test",nonce:"test"),allowsAudio:false,activity:ChallengeActivity())
        XCTAssertEqual(controller.resolvedMusicCue,.championVictory)
    }
    func testChampionAwardWriteFailureDoesNotPublishUnsavedTrophies()throws {
        let m=try fixture();defer{m.close()}
        let file=m.save.url.deletingLastPathComponent().appendingPathComponent("collection.json"),backup=file.appendingPathExtension("backup")
        try FileManager.default.moveItem(at:file,to:backup)
        try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
        defer{try? FileManager.default.removeItem(at:file);try? FileManager.default.moveItem(at:backup,to:file)}
        XCTAssertThrowsError(try m.store.markChallengeChampions(ids:["owned-0"]))
        XCTAssertTrue(m.store.state.dex.allSatisfy{$0.championAchievedAt==nil})
    }
    private func clearedRewardFixture()async throws->ChallengeUIModel {
        let m=try fixture(rewardFixtures:true)
        let team=try await BattleTeamBuilder.build(ids:(0..<6).map{"owned-\($0)"},entries:m.candidates,mode:.singles,language:.ko,provider:m.provider)
        try m.save.start(team:team,catalogVersion:m.session.catalog.version,encounterCount:1)
        try m.save.beginEncounter(opponent:team,seed:[1,2,3,4],policyRevision:"test")
        try m.save.accept(resources:try XCTUnwrap(m.run?.resources),decision:nil,winner:0)
        m.synchronizeChampionAward();return m
    }
    func testChampionCloseAndXOfferOneShinyChoiceThenPersistAcrossReopen()async throws {
        let m=try await clearedRewardFixture();defer{m.close()}
        let controller=ChallengeWindowController(model:m,identity:.init(nickname:"Test",code:"test",nonce:"test"),allowsAudio:false,activity:ChallengeActivity())
        controller.show(present:false);controller.window?.performClose(nil)
        XCTAssertNotNil(controller.window,"Champion Close and X share this native close handler")
        XCTAssertEqual(m.screen,.championReward);XCTAssertEqual(m.run?.championReward?.claimed,false)
        XCTAssertNil(controller.resolvedMusicCue)
        let pendingID=try XCTUnwrap(m.run?.id)
        XCTAssertThrowsError(try m.save.start(team:try XCTUnwrap(m.run?.team),catalogVersion:m.session.catalog.version))
        let targets=Set(m.store.championShinyTargets.map(\.id))
        XCTAssertFalse(targets.contains("released"));XCTAssertFalse(targets.contains("already-shiny"));XCTAssertTrue(targets.contains("legacy-graduate"))
        controller.window?.performClose(nil)
        XCTAssertNil(controller.window);XCTAssertEqual(ChallengeRunStore(url:m.save.url).run?.id,pendingID)
        controller.show(present:false);XCTAssertEqual(m.screen,.championReward)
        m.shinyRewardSelection="owned-6" // A graduate outside the six-member winning team is eligible.
        try await Task.sleep(for:.milliseconds(350))
        let view=try XCTUnwrap(controller.window?.contentView)
        view.layoutSubtreeIfNeeded()
        let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds))
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/ptb-champion-shiny-reward.png"))
        let before=try XCTUnwrap(m.store.state.dex.first{$0.id=="owned-6"})
        XCTAssertTrue(m.claimChampionShiny())
        XCTAssertEqual(m.store.state.dex.first{$0.id=="owned-6"}?.isShiny,true)
        XCTAssertEqual(m.store.state.dex.first{$0.id=="owned-6"}?.profile,before.profile)
        XCTAssertEqual(m.store.state.dex.filter{$0.isShiny}.map(\.id).sorted(),["already-shiny","owned-6"])
        XCTAssertEqual(m.store.state.challengeShinyClaims?[pendingID],"owned-6")
        XCTAssertEqual(ChallengeRunStore(url:m.save.url).run?.championReward?.claimed,true)
        XCTAssertFalse(m.claimChampionShiny());XCTAssertThrowsError(try m.store.claimChallengeShiny(runID:pendingID,entryID:"owned-0"))
        controller.window?.performClose(nil);XCTAssertNil(controller.window)
        controller.show(present:false);XCTAssertEqual(m.screen,.setup)
        controller.window?.close()
    }
    func testShinyClaimCrashBetweenCollectionAndRunCannotGrantSecondPokemon()async throws {
        let m=try await clearedRewardFixture();defer{m.close()};try m.offerChampionReward()
        let id=try XCTUnwrap(m.run?.id)
        try m.save.prepareChampionShinyReward(recipientID:"owned-0")
        try m.store.claimChallengeShiny(runID:id,entryID:"owned-0")
        // Simulate process exit before the separate run receipt is acknowledged.
        let collection=m.save.url.deletingLastPathComponent().appendingPathComponent("collection.json")
        let suite="ChampionReward.\(UUID())",defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer{defaults.removePersistentDomain(forName:suite)}
        let store=CompanionStore(provider:ChallengeUIProvider(),fileURL:collection,defaults:defaults)
        let session=try ChallengeBattleSession(save:ChallengeRunStore(url:m.save.url),catalog:m.session.catalog)
        let restored=ChallengeUIModel(store:store,session:session,provider:m.provider)
        XCTAssertEqual(restored.screen,.championReward);XCTAssertTrue(restored.canClaimChampionShiny)
        XCTAssertTrue(restored.claimChampionShiny())
        XCTAssertEqual(store.state.dex.filter{$0.isShiny}.map(\.id).sorted(),["already-shiny","owned-0"])
        XCTAssertEqual(session.save.run?.championReward?.recipientID,"owned-0");XCTAssertEqual(session.save.run?.championReward?.claimed,true)
    }
    func testShinyClaimFailedCollectionWriteKeepsEntitlementAndCanRetry()async throws {
        let m=try await clearedRewardFixture();defer{m.close()};try m.offerChampionReward()
        m.shinyRewardSelection="owned-6"
        let file=m.save.url.deletingLastPathComponent().appendingPathComponent("collection.json"),backup=file.appendingPathExtension("backup")
        try FileManager.default.moveItem(at:file,to:backup);try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
        XCTAssertFalse(m.claimChampionShiny())
        XCTAssertFalse(try XCTUnwrap(m.store.state.dex.first{$0.id=="owned-6"}).isShiny)
        XCTAssertNil(m.store.state.challengeShinyClaims);XCTAssertEqual(m.run?.championReward?.claimed,false)
        try FileManager.default.removeItem(at:file);try FileManager.default.moveItem(at:backup,to:file)
        XCTAssertTrue(m.claimChampionShiny());XCTAssertTrue(try XCTUnwrap(m.store.state.dex.first{$0.id=="owned-6"}).isShiny)
    }
    func testOffscreenWindowCloseReleasesHostingAndActivity()async throws {
        let m=try fixture(),activity=ChallengeActivity()
        let controller=ChallengeWindowController(model:m,identity:.init(nickname:"Test",code:"test",nonce:"test"),allowsAudio:false,activity:activity)
        controller.show(present:false)
        XCTAssertTrue(activity.isOpen);XCTAssertNotNil(controller.window?.contentViewController)
        controller.window?.close()
        XCTAssertFalse(activity.isOpen);XCTAssertNil(controller.window);XCTAssertFalse(m.isOpen);XCTAssertNil(controller.musicCue)
    }
}
