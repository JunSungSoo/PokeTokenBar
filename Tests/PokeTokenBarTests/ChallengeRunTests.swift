import XCTest
@testable import PokeTokenBar

@MainActor final class ChallengeRunTests: XCTestCase {
    func team(_ prefix:String="a")->[BattlePokemon] {
        [(235,"Smeargle","Own Tempo"),(242,"Blissey","Natural Cure"),(26,"Raichu","Static"),(134,"Vaporeon","Water Absorb"),(212,"Scizor","Technician"),(80,"Slowbro","Own Tempo")].enumerated().map { i,p in
            BattlePokemon(id:prefix+String(i),speciesID:p.0,species:p.1,displayName:p.1,level:100,ability:p.2,nature:"Hardy",gender:"",shiny:false,form:nil,
                          ivs:["hp":31,"atk":31,"def":31,"spa":31,"spd":31,"spe":31],
                          stats:["hp":500,"atk":120,"def":150,"spa":1000,"spd":150,"spe":1000],moves:["surf","protect"])
        }
    }
    func store()throws->ChallengeRunStore {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock{try? FileManager.default.removeItem(at:dir)}
        return ChallengeRunStore(url:dir.appendingPathComponent("run.json"))
    }
    func victory(_ save:ChallengeRunStore,resources:[ChallengePokemonState]?=nil)throws {
        try save.beginEncounter(opponent:team("b"),seed:[1,2,3,4],policyRevision:"test")
        try save.accept(resources:resources ?? XCTUnwrap(save.run).resources,decision:nil,winner:0)
    }
    func testReviveAndPPRestoresExactlyOneMoveAcrossAtomicReloads()throws {
        let save=try store();try save.start(team:team(),catalogVersion:"test",encounterCount:3)
        var state=try XCTUnwrap(save.run).resources
        state[0].hp=0;state[1].hp=1;state[1].moves[0].pp=1;state[1].moves[1].pp=0
        try victory(save,resources:state)
        try save.apply(.heal("a0"))
        XCTAssertEqual(save.run?.resources[0].hp,175)
        XCTAssertEqual(save.run?.resources[1].hp,1)
        XCTAssertThrowsError(try save.apply(.heal("a1")),"One reward per encounter")
        let loaded=ChallengeRunStore(url:save.url);XCTAssertEqual(loaded.run?.phase,.intermission)
        try loaded.advance();try victory(loaded)
        try loaded.apply(.pp("a1",0))
        XCTAssertEqual(loaded.run?.resources[1].moves.map(\.pp),[4,0])
        XCTAssertEqual(loaded.run?.resources[0].hp,175,"No automatic between-battle healing")
        XCTAssertEqual(ChallengeRunStore(url:save.url).run?.encounterIndex,1)
    }
    func testRewardCapsAndOneHPRevival()throws {
        let save=try store();var own=team();var stats=own[0].stats;stats["hp"]=1
        let p=own[0];own[0]=BattlePokemon(id:p.id,speciesID:p.speciesID,species:p.species,displayName:p.displayName,level:p.level,ability:p.ability,nature:p.nature,gender:p.gender,shiny:p.shiny,form:p.form,ivs:p.ivs,stats:stats,moves:p.moves)
        try save.start(team:own,catalogVersion:"test",encounterCount:3)
        var r=try XCTUnwrap(save.run).resources;r[0].hp=0
        try victory(save,resources:r);try save.apply(.heal("a0"));XCTAssertEqual(save.run?.resources[0].hp,1)
        try save.advance();r=try XCTUnwrap(save.run).resources;r[1].moves[0].pp-=1
        try victory(save,resources:r);try save.apply(.pp("a1",0));XCTAssertEqual(save.run?.resources[1].moves[0].pp,15)
    }
    func testReplacementRetiresIndividualAndCannotMintAnItem()throws {
        let save=try store();try save.start(team:team(),catalogVersion:"test",encounterCount:4)
        let profile=PokemonProfile.generate(seed:42)
        let entry=DexEntry(id:"new",baseID:143,finalID:143,chainOrder:[143],rarity:.uncommon,caughtAt:Date(),profile:profile)
        var incoming=team()[0]
        incoming=BattlePokemon(id:entry.id,speciesID:143,species:"Snorlax",displayName:"Snorlax",level:100,ability:"Thick Fat",nature:"Hardy",gender:"",shiny:false,form:nil,ivs:incoming.ivs,stats:incoming.stats,moves:["tackle","protect"],item:"lifeorb")
        try victory(save)
        XCTAssertThrowsError(try save.apply(.replace("a0",incoming)))
        try save.apply(.replace("a0",incoming),eligible:[entry])
        XCTAssertTrue(save.run?.retiredIDs.contains("a0")==true)
        XCTAssertEqual(save.run?.team[0].id,"new");XCTAssertEqual(save.run?.resources.first?.item,"")
        XCTAssertEqual(save.run?.resources.first?.hp,500)
        try save.advance();try victory(save)
        XCTAssertThrowsError(try save.apply(.replace("a1",team()[0]),eligible:[]))
        XCTAssertTrue(ChallengeRunStore(url:save.url).run?.retiredIDs.contains("a0")==true)
    }
    func testPendingIntentSurvivesCrashAndOnlyAnAcknowledgedDecisionEntersTheLog()throws {
        let save=try store();try save.start(team:team(),catalogVersion:"test")
        try save.beginEncounter(opponent:team("b"),seed:[1,2,3,4],policyRevision:"policy")
        let decision=BattleDecision(decisionID:"1:move::10",actions:[BattleAction(kind:"move",index:1,target:0)],order:[])
        try save.queueIntent(decision)
        let loaded=ChallengeRunStore(url:save.url)
        XCTAssertEqual(loaded.run?.checkpoint?.pendingDecision?.decisionID,decision.decisionID)
        XCTAssertEqual(loaded.run?.checkpoint?.decisions.count,0)
        try loaded.accept(resources:try XCTUnwrap(loaded.run).resources,decision:decision,winner:nil)
        XCTAssertNil(loaded.run?.checkpoint?.pendingDecision);XCTAssertEqual(loaded.run?.checkpoint?.decisions.count,1)
        try loaded.forfeit();XCTAssertEqual(loaded.run?.phase,.lost)
        XCTAssertThrowsError(try loaded.advance());try loaded.start(team:team(),catalogVersion:"test")
        XCTAssertEqual(loaded.run?.encounterIndex,0)
    }
    func testCorruptSaveIsPreservedAndFailedWriteDoesNotAdvanceMemory()throws {
        let save=try store();try FileManager.default.createDirectory(at:save.url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let invalid=Data("{bad".utf8);try invalid.write(to:save.url)
        let loaded=ChallengeRunStore(url:save.url);XCTAssertNotNil(loaded.error)
        XCTAssertThrowsError(try loaded.start(team:team(),catalogVersion:"test"));XCTAssertEqual(try Data(contentsOf:save.url),invalid)
        let blocked=save.url.appendingPathComponent("child.json"),unwritable=ChallengeRunStore(url:blocked)
        XCTAssertThrowsError(try unwritable.start(team:team(),catalogVersion:"test"));XCTAssertNil(unwritable.run)
    }
    func testEveryVictoryRequiresARewardAndDuplicateInitialItemsCannot()throws {
        let save=try store();var own=team();own[0].item="leftovers";own[1].item="leftovers"
        XCTAssertThrowsError(try save.start(team:own,catalogVersion:"test"))
        try save.start(team:team(),catalogVersion:"test",encounterCount:3)
        try victory(save)
        XCTAssertThrowsError(try save.skipUnavailableReward(eligible:[]));XCTAssertThrowsError(try save.advance())
        try save.apply(.buff(try XCTUnwrap(save.run?.rewardRoll)));XCTAssertEqual(save.run?.phase,.intermission)
        try save.advance();var damaged=try XCTUnwrap(save.run).resources;damaged[0].hp-=1
        try victory(save,resources:damaged)
        XCTAssertThrowsError(try save.skipUnavailableReward(eligible:[]))
        try save.apply(.heal("a0"));XCTAssertEqual(save.run?.resources[0].hp,500)
    }
    func testFinalWinClearsAndDrawLosesWithoutAReward()throws {
        for winner in [0,-1,1] {
            let save=try store();try save.start(team:team(),catalogVersion:"test",encounterCount:1)
            try save.beginEncounter(opponent:team("b"),seed:[1,2,3,4],policyRevision:"test")
            try save.accept(resources:try XCTUnwrap(save.run).resources,decision:nil,winner:winner)
            XCTAssertEqual(save.run?.phase,winner==0 ? .cleared:.lost)
            XCTAssertThrowsError(try save.apply(.heal("a0")))
        }
    }
}
