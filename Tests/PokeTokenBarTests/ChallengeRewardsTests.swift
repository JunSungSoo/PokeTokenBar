import XCTest
@testable import PokeTokenBar

@MainActor final class ChallengeRewardsTests:XCTestCase {
    private func make(_ kind:ChallengeBuffKind = .attack)throws->ChallengeRunStore {
        let helper=ChallengeRunTests(),temp=try helper.store()
        let save=ChallengeRunStore(url:temp.url,roll:{kind})
        var team=helper.team();team[0].item="leftovers";team[0].moves=["surf","protect","tackle","rest"]
        try save.start(team:team,catalogVersion:"rewards-test")
        return save
    }
    private func win(_ save:ChallengeRunStore,damage:Bool=true)throws {
        try save.beginEncounter(opponent:ChallengeRunTests().team("b"),seed:[1,2,3,4],policyRevision:"test")
        var r=try XCTUnwrap(save.run?.resources)
        if damage {r[0].item="";r[0].hp=0;r[1].hp=123;r[1].status="tox";r[2].status="slp";r[2].sleepStart=3;r[2].sleepRemaining=2;for i in r.indices{for j in r[i].moves.indices{r[i].moves[j].pp=0}}}
        try save.accept(resources:r,decision:nil,winner:0)
    }
    func testAllTwentySixRewardsUseMilestonesAndEnhancedBoundaryAndCannotSkip()throws {
        let save=try make()
        for index in 0..<26 {
            try win(save)
            XCTAssertEqual(save.run?.milestoneReward,(index+1)%3==0)
            XCTAssertEqual(save.run?.enhancedReward,index>=15)
            XCTAssertEqual(save.run?.rewardRoll,.attack)
            XCTAssertThrowsError(try save.advance());XCTAssertThrowsError(try save.skipUnavailableReward(eligible:[]))
            XCTAssertThrowsError(try save.apply(.buff(.speed)),"Only the offered random effect can be chosen")
            let restored=ChallengeRunStore(url:save.url,roll:{.speed})
            XCTAssertEqual(restored.run?.rewardRoll,.attack,"Reloading cannot reroll a committed reward")
            if (index+1)%3==0 {
                XCTAssertThrowsError(try save.apply(.heal("a0")));XCTAssertThrowsError(try save.apply(.pp("a0",0)))
                try save.apply(.allHeal)
                XCTAssertEqual(save.run?.resources[0].item,"","Full recovery cannot recreate a consumed item")
                for r in try XCTUnwrap(save.run?.resources){
                    XCTAssertEqual(r.hp,500);XCTAssertEqual(r.status,"");XCTAssertNil(r.sleepStart);XCTAssertNil(r.sleepRemaining)
                    XCTAssertTrue(r.moves.allSatisfy{$0.pp==$0.maxPP})
                }
            }else{
                XCTAssertThrowsError(try save.apply(.allHeal))
                try save.apply(.buff(.attack))
            }
            XCTAssertEqual(save.run?.phase,.intermission)
            XCTAssertThrowsError(try save.apply(.buff(.attack)))
            try save.advance()
        }
        XCTAssertEqual(save.run?.encounterIndex,26,"The final reward prepares Red, not a 28th encounter")
    }
    func testEnhancedHealingRevivesFullyAndPPRecoversEverySlotOnlyOnChosenIndividual()throws {
        for pp in [false,true] {
            let save=try make(.speed)
            for _ in 0..<15 {try win(save,damage:false);try save.apply(.buff(.speed));try save.advance()}
            try win(save)
            if pp {
                try save.apply(.pp("a0",0))
                XCTAssertTrue(save.run!.resources[0].moves.allSatisfy{$0.pp==$0.maxPP})
                XCTAssertTrue(save.run!.resources[1].moves.allSatisfy{$0.pp==0})
                XCTAssertEqual(save.run?.resources[0].hp,0)
            }else{
                try save.apply(.heal("a0"));XCTAssertEqual(save.run?.resources[0].hp,500)
                XCTAssertEqual(save.run?.resources[1].hp,123)
            }
        }
    }
    func testStackedBuffsExpireIndependentlyAfterExactlyThreeCompletedBattlesAndResumeSnapshot()throws {
        let save=try make()
        try win(save);try save.apply(.buff(.attack));try save.advance()
        XCTAssertEqual(save.run?.teamBuffs?.map(\.remaining),[3])
        try win(save);try save.apply(.buff(.attack));try save.advance()
        XCTAssertEqual(save.run?.teamBuffs?.map(\.remaining),[2,3])
        XCTAssertEqual(ChallengeTeamBuff.stages(save.run!.teamBuffs!) ,["atk":2])
        try save.beginEncounter(opponent:ChallengeRunTests().team("b"),seed:[1,2,3,4],policyRevision:"test")
        try save.accept(resources:save.run!.resources,decision:nil,winner:nil)
        let resumed=ChallengeRunStore(url:save.url)
        XCTAssertEqual(resumed.run?.teamBuffs?.map(\.remaining),[2,3])
        XCTAssertEqual(resumed.run?.checkpoint?.initialBuffs?.map(\.remaining),[2,3])
        try resumed.accept(resources:resumed.run!.resources,decision:nil,winner:0)
        XCTAssertEqual(resumed.run?.teamBuffs?.map(\.remaining),[1,2])
        XCTAssertThrowsError(try resumed.accept(resources:resumed.run!.resources,decision:nil,winner:0))
        try resumed.apply(.allHeal);try resumed.advance()
        try win(resumed);XCTAssertEqual(resumed.run?.teamBuffs?.map(\.remaining),[1])
        try resumed.apply(.heal("a0"));try resumed.advance()
        XCTAssertEqual(ChallengeTeamBuff.stages(resumed.run?.teamBuffs ?? []),["atk":1])
        try win(resumed);XCTAssertEqual(resumed.run?.teamBuffs,[])
    }
    func testReplacementKeepsTeamWideRewardAndRetiresOutgoingIndividual()throws {
        let save=try make();try win(save,damage:false);try save.apply(.buff(.attack));try save.advance();try win(save)
        let buffs=save.run?.teamBuffs
        let entry=DexEntry(id:"incoming",baseID:143,finalID:143,chainOrder:[143],rarity:.common,caughtAt:Date(),profile:PokemonProfile.generate(seed:7))
        let sample=save.run!.team[0]
        let incoming=BattlePokemon(id:"incoming",speciesID:143,species:"Snorlax",displayName:"Snorlax",level:100,ability:"Thick Fat",nature:"Hardy",gender:"",shiny:false,form:nil,ivs:sample.ivs,stats:sample.stats,moves:["rest","bodyslam"])
        try save.apply(.replace("a0",incoming),eligible:[entry])
        XCTAssertEqual(save.run?.teamBuffs,buffs);XCTAssertEqual(save.run?.team.first?.id,"incoming")
        XCTAssertTrue(save.run!.retiredIDs.contains("a0"));try save.advance()
        try save.beginEncounter(opponent:ChallengeRunTests().team("b"),seed:[1,2,3,4],policyRevision:"test")
        XCTAssertEqual(ChallengeTeamBuff.stages(save.run?.checkpoint?.initialBuffs ?? []),["atk":1])
    }
    func testOnlyFiveIndependentStatsAreOfferedAndEveryNewInstanceLastsThreeBattles()throws {
        XCTAssertEqual(ChallengeBuffKind.allCases,[.attack,.specialAttack,.speed,.defense,.specialDefense])
        for kind in ChallengeBuffKind.allCases {
            let save=try make(kind);try win(save);try save.apply(.buff(kind))
            XCTAssertEqual(save.run?.teamBuffs?.map(\.remaining),[3])
            XCTAssertEqual(ChallengeTeamBuff.stages(save.run?.teamBuffs ?? []),kind.stages)
            XCTAssertEqual(kind.stages.count,1);XCTAssertNil(kind.stages["hp"])
            for language in AppLanguage.allCases{XCTAssertFalse(L(language).challengeBuffReward(kind).isEmpty)}
        }
    }
    func testOldCombinedOfferMigratesButActiveLegacyInstanceKeepsItsRemainingBattles()throws {
        let save=try make();try win(save)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
        json["rewardRoll"]="power";json["teamBuffs"]=[["id":"legacy-power","kind":"power","remaining":2]]
        try JSONSerialization.data(withJSONObject:json).write(to:save.url)
        let migrated=ChallengeRunStore(url:save.url,roll:{.specialDefense})
        XCTAssertEqual(migrated.run?.rewardRoll,.specialDefense)
        XCTAssertEqual(migrated.run?.teamBuffs?.first?.kind,.power);XCTAssertEqual(migrated.run?.teamBuffs?.first?.remaining,2)
        XCTAssertThrowsError(try migrated.apply(.buff(.power)))
        try migrated.apply(.buff(.specialDefense))
        XCTAssertEqual(migrated.run?.teamBuffs?.map(\.remaining),[2,3])
        XCTAssertEqual(ChallengeTeamBuff.stages(migrated.run?.teamBuffs ?? []),["atk":1,"spa":1,"spd":1])
    }
    func testLegacyRewardMigratesToOnePersistedOffer()throws {
        let save=try make();try win(save)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
        json.removeValue(forKey:"rewardRoll");json.removeValue(forKey:"teamBuffs")
        try JSONSerialization.data(withJSONObject:json).write(to:save.url)
        let migrated=ChallengeRunStore(url:save.url,roll:{.speed})
        XCTAssertEqual(migrated.run?.rewardRoll,.speed)
        XCTAssertEqual(ChallengeRunStore(url:save.url,roll:{.attack}).run?.rewardRoll,.speed)
        try migrated.apply(.buff(.speed))
        XCTAssertEqual(migrated.run?.teamBuffs?.map(\.remaining),[3])
        XCTAssertEqual(ChallengeTeamBuff.stages(migrated.run?.teamBuffs ?? []),["spe":1])
    }
}
