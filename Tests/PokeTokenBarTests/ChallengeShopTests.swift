import XCTest
@testable import PokeTokenBar

@MainActor final class ChallengeShopTests:XCTestCase {
    private func ready(wins:Int=1,stock:[ChallengeShopItem]=Array(ChallengeShopItem.allCases.prefix(4)))throws->ChallengeRunStore {
        let helper=ChallengeRunTests(),temporary=try helper.store(),save=ChallengeRunStore(url:temporary.url,roll:{.attack},shopRoll:{stock})
        var team=helper.team();team[0].item="leftovers"
        try save.start(team:team,catalogVersion:"shop-test")
        for index in 0..<wins {
            try save.beginEncounter(opponent:helper.team("b"),seed:[1,2,3,4],policyRevision:"test")
            var r=save.run!.resources
            r[0].hp=0;r[0].item="";r[1].hp=1;r[1].status="psn";r[2].hp=0;r[3].hp=1
            for i in r.indices{for j in r[i].moves.indices{r[i].moves[j].pp=0}}
            try save.accept(resources:r,decision:nil,winner:0)
            if index+1<wins{try save.apply(.buff(.attack));try save.advance()}
        }
        return save
    }
    func testOneHundredPointsPerActualWinNoDoubleAwardAndNewRunResets()throws {
        let save=try ready();XCTAssertEqual(save.run?.pointBalance,100)
        XCTAssertThrowsError(try save.accept(resources:save.run!.resources,decision:nil,winner:0))
        XCTAssertEqual(save.run?.pointBalance,100)
        try save.apply(.buff(.attack));try save.advance()
        XCTAssertThrowsError(try save.purchase(.heal20,targetID:"a0"))
        try save.beginEncounter(opponent:ChallengeRunTests().team("b"),seed:[1,2,3,4],policyRevision:"test")
        XCTAssertThrowsError(try save.purchase(.heal20,targetID:"a0"))
        try save.skipEncounterForTesting();XCTAssertEqual(save.run?.pointBalance,100,"QA skip is not a victory")
        try save.beginEncounter(opponent:ChallengeRunTests().team("b"),seed:[1,2,3,4],policyRevision:"test")
        try save.accept(resources:save.run!.resources,decision:nil,winner:1)
        XCTAssertEqual(save.run?.pointBalance,100);XCTAssertThrowsError(try save.purchase(.fullRecovery,targetID:"a1"))
        try save.start(team:ChallengeRunTests().team(),catalogVersion:"shop-test")
        XCTAssertEqual(save.run?.pointBalance,0)
    }
    func testFullRecoveryIsOneLivingIndividualAndDoesNotClaimTheRequiredReward()throws {
        let save=try ready();let before=save.run!.resources[0],offer=save.run?.rewardRoll
        XCTAssertThrowsError(try save.purchase(.fullRecovery,targetID:"a0"))
        try save.purchase(.fullRecovery,targetID:"a1")
        XCTAssertEqual(save.run?.pointBalance,0);XCTAssertEqual(save.run?.phase,.reward)
        XCTAssertEqual(save.run?.resources[1].hp,500);XCTAssertEqual(save.run?.resources[1].status,"")
        XCTAssertTrue(save.run!.resources[1].moves.allSatisfy{$0.pp==$0.maxPP})
        XCTAssertEqual(save.run?.resources[0],before)
        XCTAssertEqual(save.run?.rewardRoll,offer);XCTAssertThrowsError(try save.advance())
        XCTAssertEqual(ChallengeRunStore(url:save.url).run?.resources,save.run?.resources)
        try save.apply(.buff(.attack));try save.advance()
    }
    func testUnlimitedRepeatedPurchasesCorrectPricesRoundingAndNoOverheal()throws {
        let save=try ready(wins:2)
        try save.purchase(.ppRecovery,targetID:"a3")
        for expectedHP in [101,201]{try save.purchase(.heal20,targetID:"a1");XCTAssertEqual(save.run?.resources[1].hp,expectedHP)}
        try save.purchase(.heal40,targetID:"a1");XCTAssertEqual(save.run?.resources[1].hp,401)
        try save.purchase(.heal20,targetID:"a1");XCTAssertEqual(save.run?.resources[1].hp,500)
        XCTAssertEqual(save.run?.pointBalance,90);XCTAssertEqual(save.run?.resources[1].status,"psn")
        XCTAssertThrowsError(try save.purchase(.heal20,targetID:"a1"))
        try save.purchase(.ppRecovery,targetID:"a1")
        try save.purchase(.heal40,targetID:"a3");XCTAssertEqual(save.run?.resources[3].hp,201)
        try save.purchase(.heal20,targetID:"a3");XCTAssertEqual(save.run?.resources[3].hp,301)
        XCTAssertEqual(save.run?.pointBalance,0)
        XCTAssertThrowsError(try save.purchase(.heal20,targetID:"a3"))
        XCTAssertThrowsError(try save.purchase(.heal20,targetID:"not-in-team"))
    }
    func testLegacyPointsMigrateFromCompletedWinsOnceAndDoNotRefundSpending()throws {
        let save=try ready(wins:3)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any]);json.removeValue(forKey:"challengePoints")
        try JSONSerialization.data(withJSONObject:json).write(to:save.url)
        let migrated=ChallengeRunStore(url:save.url);XCTAssertEqual(migrated.run?.pointBalance,300)
        try migrated.purchase(.heal20,targetID:"a1");XCTAssertEqual(migrated.run?.pointBalance,290)
        XCTAssertEqual(ChallengeRunStore(url:save.url).run?.pointBalance,290)
    }
    func testFailedShopWriteDoesNotSpendOrHealAndCanRetry()throws {
        let save=try ready();let file=save.url,backup=file.appendingPathExtension("backup")
        try FileManager.default.moveItem(at:file,to:backup);try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
        XCTAssertThrowsError(try save.purchase(.fullRecovery,targetID:"a1"))
        XCTAssertEqual(save.run?.pointBalance,100);XCTAssertEqual(save.run?.resources[0].hp,0)
        try FileManager.default.removeItem(at:file);try FileManager.default.moveItem(at:backup,to:file)
        try save.purchase(.fullRecovery,targetID:"a1")
        XCTAssertEqual(save.run?.pointBalance,0);XCTAssertEqual(save.run?.resources[1].hp,500)
    }
    func testMalformedLegacyCountsAndHPAreRejectedBeforeMigrationArithmetic()throws {
        for hugeHP in [false,true] {
            let save=try ready()
            var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
            json.removeValue(forKey:"challengePoints")
            if hugeHP {
                var team=try XCTUnwrap(json["team"] as? [[String:Any]])
                var stats=try XCTUnwrap(team[0]["stats"] as? [String:Any]);stats["hp"]=Int.max;team[0]["stats"]=stats;json["team"]=team
            }else{json["encounterCount"]=Int.max;json["phase"]="cleared"}
            let bytes=try JSONSerialization.data(withJSONObject:json);try bytes.write(to:save.url)
            let reopened=ChallengeRunStore(url:save.url)
            XCTAssertNil(reopened.run);XCTAssertFalse(reopened.canWrite)
            XCTAssertEqual(try Data(contentsOf:save.url),bytes)
        }
    }
    func testEveryProductIsLocalizedAndFullRecoveryCuresSleep() {
        XCTAssertEqual(ChallengeShopItem.allCases.map(\.price),[100,50,10,30,40,30,50,70])
        for language in AppLanguage.allCases{for item in ChallengeShopItem.allCases{
            XCTAssertFalse(L(language).challengeShopName(item).isEmpty);XCTAssertFalse(L(language).challengeShopDescription(item).isEmpty)
        }}
        var state=ChallengePokemonState(id:"a",hp:1,status:"slp",item:"",sleepStart:3,sleepRemaining:2,moves:[.init(id:"tackle",pp:0,maxPP:35)])
        ChallengeShopItem.fullRecovery.apply(to:&state,maxHP:50)
        XCTAssertEqual(state.hp,50);XCTAssertEqual(state.status,"");XCTAssertNil(state.sleepStart);XCTAssertNil(state.sleepRemaining)
        XCTAssertEqual(state.moves[0].pp,35)
        XCTAssertFalse(ChallengeShopItem.fullRecovery.needed(state,maxHP:50))
        state.status="psn"
        XCTAssertTrue(ChallengeShopItem.fullRecovery.needed(state,maxHP:50),"Status-only cure must remain purchasable at full HP/PP")
        state.status="";state.moves[0].pp=1
        XCTAssertTrue(ChallengeShopItem.fullRecovery.needed(state,maxHP:50),"PP-only recovery must remain purchasable at full HP")
    }
    func testOrdinaryRecoveryNeverRevivesAndRevivalLeavesPPSpent()throws {
        let ordinary:[ChallengeShopItem]=[.fullRecovery,.ppRecovery,.heal20,.heal40,.statusCure,.teamHeal30]
        let fainted=ChallengePokemonState(id:"a",hp:0,status:"slp",item:"",sleepStart:3,sleepRemaining:2,moves:[.init(id:"tackle",pp:0,maxPP:35)])
        for item in ordinary {
            var state=fainted
            XCTAssertFalse(item.needed(state,maxHP:501),item.rawValue)
            item.apply(to:&state,maxHP:501);XCTAssertEqual(state,fainted)
        }
        for item in [ChallengeShopItem.revive,.maxRevive] {
            var state=fainted;item.apply(to:&state,maxHP:501)
            XCTAssertEqual(state.hp,item == .revive ? 250:501)
            XCTAssertEqual(state.moves[0].pp,0);XCTAssertEqual(state.status,"")
            XCTAssertNil(state.sleepStart);XCTAssertNil(state.sleepRemaining)
            XCTAssertFalse(item.needed(state,maxHP:501))
        }
        let save=try ready()
        XCTAssertThrowsError(try save.apply(.heal("a0")))
        XCTAssertThrowsError(try save.apply(.pp("a0",0)))
        try save.apply(.revive("a0"));XCTAssertEqual(save.run?.resources[0].hp,250)
        XCTAssertEqual(save.run?.resources[0].moves[0].pp,0)
    }
    func testNewStockPurchasesStatusRevivalAndLivingTeamOnlyHealing()throws {
        let stock:[ChallengeShopItem]=[.statusCure,.revive,.teamHeal30,.maxRevive]
        let save=try ready(wins:3,stock:stock)
        try save.purchase(.statusCure,targetID:"a1")
        XCTAssertEqual(save.run?.pointBalance,260);XCTAssertEqual(save.run?.resources[1].hp,1)
        XCTAssertEqual(save.run?.resources[1].status,"");XCTAssertEqual(save.run?.resources[1].moves[0].pp,0)
        XCTAssertThrowsError(try save.purchase(.statusCure,targetID:"a1"))
        let before=save.run!.resources
        try save.purchase(.teamHeal30,targetID:"")
        XCTAssertEqual(save.run?.pointBalance,210)
        for (i,r) in save.run!.resources.enumerated() {
            XCTAssertEqual(r.hp,before[i].hp==0 ? 0:min(500,before[i].hp+150))
            XCTAssertEqual(r.moves,before[i].moves);XCTAssertEqual(r.status,before[i].status)
        }
        XCTAssertThrowsError(try save.purchase(.revive,targetID:"a1"))
        try save.purchase(.revive,targetID:"a0");XCTAssertEqual(save.run?.resources[0].hp,250)
        try save.purchase(.maxRevive,targetID:"a2");XCTAssertEqual(save.run?.resources[2].hp,500)
        XCTAssertEqual(save.run?.pointBalance,110)
        XCTAssertEqual(save.run?.resources[0].moves[0].pp,0);XCTAssertEqual(save.run?.resources[2].moves[0].pp,0)
        XCTAssertEqual(save.run?.phase,.reward);XCTAssertThrowsError(try save.advance())
        // The fixed revive reward remains available at a three-win milestone.
        let milestone=try ready(wins:3,stock:stock)
        try milestone.apply(.revive("a0"));XCTAssertEqual(milestone.run?.resources[0].hp,250)
    }
    func testFourOffersPersistWithoutRerollAndRefreshOnlyAfterNextVictory()throws {
        let helper=ChallengeRunTests(),temporary=try helper.store()
        let first=Array(ChallengeShopItem.allCases.prefix(4)),second=Array(ChallengeShopItem.allCases.suffix(4))
        var calls=0
        let save=ChallengeRunStore(url:temporary.url,roll:{.attack},shopRoll:{calls+=1;return calls==1 ? first:second})
        try save.start(team:helper.team(),catalogVersion:"stock")
        try helper.victory(save);XCTAssertEqual(calls,1);XCTAssertEqual(save.run?.shopOffers,first)
        XCTAssertThrowsError(try save.purchase(.revive,targetID:"a0"))
        let reopened=ChallengeRunStore(url:save.url,shopRoll:{XCTFail("Stock rerolled on reopening");return second})
        XCTAssertEqual(reopened.run?.shopOffers,first)
        try save.apply(.buff(.attack));XCTAssertEqual(save.run?.shopOffers,first)
        try save.advance();try helper.victory(save)
        XCTAssertEqual(calls,2);XCTAssertEqual(save.run?.shopOffers,second)
        let eligible=try ready(stock:second)
        XCTAssertThrowsError(try eligible.purchase(.heal20,targetID:"a1"),"Affordable and useful but not offered")
        try eligible.purchase(.revive,targetID:"a0")
        XCTAssertEqual(eligible.run?.shopOffers,second)
        XCTAssertEqual(ChallengeRunStore(url:eligible.url).run?.shopOffers,second)
    }
    func testLegacyStockMigratesOnceAndMalformedStockIsPreserved()throws {
        let save=try ready()
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
        json.removeValue(forKey:"shopOffers")
        try JSONSerialization.data(withJSONObject:json).write(to:save.url)
        let stock=Array(ChallengeShopItem.allCases.suffix(4))
        let migrated=ChallengeRunStore(url:save.url,shopRoll:{stock})
        XCTAssertEqual(migrated.run?.shopOffers,stock)
        XCTAssertEqual(ChallengeRunStore(url:save.url,shopRoll:{XCTFail("Migration repeated");return []}).run?.shopOffers,stock)
        for bad in [["revive"],["revive","revive","heal20","heal40"]] {
            json["shopOffers"]=bad
            let bytes=try JSONSerialization.data(withJSONObject:json);try bytes.write(to:save.url)
            let invalid=ChallengeRunStore(url:save.url)
            XCTAssertNil(invalid.run);XCTAssertFalse(invalid.canWrite)
            XCTAssertEqual(try Data(contentsOf:save.url),bytes)
        }
    }

}
