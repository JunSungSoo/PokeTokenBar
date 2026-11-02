import AppKit
import SwiftUI
import XCTest
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
            abilities:[.init(name:p.1,slot:1,isHidden:false)],moves:[.init(name:"return",learnMethods:[.init(method:"machine",level:0)])])
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
    func testSelectionItemsActualBattleRewardSaveAndNext()async throws {
        let m=try fixture();defer{m.close()}
        m.select("owned-0");m.select("duplicate");XCTAssertEqual(m.selectedIDs,["owned-0"])
        for i in 1..<6{m.select("owned-\(i)")}
        XCTAssertTrue(m.applyItem("leftovers",to:"owned-0"));XCTAssertFalse(m.applyItem("leftovers",to:"owned-1"))
        await m.start();XCTAssertFalse(m.problem);_ = try await wait(m)
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
        m.isOpen=true;m.next();let next=try await wait(m)
        XCTAssertEqual(m.run?.encounterIndex,1);XCTAssertEqual(next.resources,carried);XCTAssertTrue(m.intro.active)
    }
    func testPendingRewardReopensWithoutBattleFrameAndReplacementBuildsOnlyNewMember()async throws {
        let m=try fixture();defer{m.close()}
        for i in 0..<6{m.select("owned-\(i)")};await m.start();try await win(m);m.didFinishPresentation();m.close()
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
        await m.start();_ = try await wait(m)
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
    func testProductionInstantVictoryWithNoNewEffectsShowsRewardFooter()async throws {
        let m=try fixture(testControls:true)
        // No manual presentation completion is allowed.
        let window=ChallengeWindowController(model:m,identity:.init(nickname:"Test",code:"test",nonce:"test"),allowsAudio:false,activity:ChallengeActivity())
        window.show(present:false);defer{m.close();window.window?.close()}
        for i in 0..<6{m.select("owned-\(i)")};await m.start();_ = try await wait(m)
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
