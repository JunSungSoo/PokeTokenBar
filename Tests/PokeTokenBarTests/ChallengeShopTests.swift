import XCTest
@testable import PokeTokenBar

@MainActor final class ChallengeShopTests:XCTestCase {
    private func ready(wins:Int=1)throws->ChallengeRunStore {
        let helper=ChallengeRunTests(),temporary=try helper.store(),save=ChallengeRunStore(url:temporary.url,roll:{.attack})
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
    func testFullRecoveryRevivesEntireTeamWithoutClaimingRequiredReward()throws {
        let save=try ready()
        try save.purchase(.fullRecovery,targetID:"a0")
        XCTAssertEqual(save.run?.pointBalance,0);XCTAssertEqual(save.run?.phase,.reward)
        XCTAssertEqual(save.run?.resources[0].hp,500);XCTAssertEqual(save.run?.resources[0].status,"")
        XCTAssertTrue(save.run!.resources[0].moves.allSatisfy{$0.pp==$0.maxPP})
        XCTAssertTrue(save.run!.resources.allSatisfy{$0.hp==500 && $0.status.isEmpty && $0.moves.allSatisfy{$0.pp==$0.maxPP}})
        XCTAssertEqual(save.run?.shopPrice(.fullRecovery),105)
        XCTAssertThrowsError(try save.advance())
        XCTAssertEqual(ChallengeRunStore(url:save.url).run?.resources,save.run?.resources)
        try save.apply(.buff(.attack));try save.advance()
    }
    func testUnlimitedRepeatedPurchasesCorrectPricesRoundingAndNoOverheal()throws {
        let save=try ready(wins:2)
        try save.purchase(.ppRecovery,targetID:"a3")
        for expectedHP in [101,201]{try save.purchase(.heal20,targetID:"a1");XCTAssertEqual(save.run?.resources[1].hp,expectedHP)}
        try save.purchase(.heal40,targetID:"a1");XCTAssertEqual(save.run?.resources[1].hp,401)
        try save.purchase(.heal20,targetID:"a1");XCTAssertEqual(save.run?.resources[1].hp,500)
        XCTAssertEqual(save.run?.pointBalance,105);XCTAssertEqual(save.run?.resources[1].status,"psn")
        XCTAssertThrowsError(try save.purchase(.heal20,targetID:"a1"))
        try save.purchase(.ppRecovery,targetID:"a1")
        try save.purchase(.heal40,targetID:"a3");XCTAssertEqual(save.run?.resources[3].hp,201)
        try save.purchase(.heal20,targetID:"a3");XCTAssertEqual(save.run?.resources[3].hp,301)
        XCTAssertEqual(save.run?.pointBalance,20)
        XCTAssertEqual(save.run?.shopPrice(.heal20),30)
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
        XCTAssertEqual(save.run?.pointBalance,100);XCTAssertEqual(save.run?.resources[0].hp,0);XCTAssertEqual(save.run?.shopPrice(.fullRecovery),100)
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
        XCTAssertEqual(ChallengeShopItem.allCases.map(\.price),[100,30,10,20,10,50,10])
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
    func testHPRecoveryRevivesAndCuresOnlyRevivedMembersWhilePPDoesNotRevive()throws {
        let fainted=ChallengePokemonState(id:"a",hp:0,status:"slp",item:"",sleepStart:3,sleepRemaining:2,moves:[.init(id:"tackle",pp:0,maxPP:35)])
        for (item,hp) in [(ChallengeShopItem.fullRecovery,501),(.heal20,100),(.heal40,200),(.teamHeal50,250)] {
            var state=fainted;XCTAssertTrue(item.needed(state,maxHP:501))
            item.apply(to:&state,maxHP:501);XCTAssertEqual(state.hp,hp)
            XCTAssertEqual(state.status,"");XCTAssertNil(state.sleepStart);XCTAssertNil(state.sleepRemaining)
            XCTAssertEqual(state.moves[0].pp,item == .fullRecovery ? 35:0)
            var alive=fainted;alive.hp=1;alive.status="psn"
            item.apply(to:&alive,maxHP:501)
            XCTAssertEqual(alive.status,item == .fullRecovery ? "":"psn")
        }
        var pp=fainted;ChallengeShopItem.ppRecovery.apply(to:&pp,maxHP:501)
        XCTAssertEqual(pp.hp,0);XCTAssertEqual(pp.moves[0].pp,35)
        XCTAssertFalse(ChallengeShopItem.statusCure.needed(fainted,maxHP:501))
        var unchanged=fainted;ChallengeShopItem.statusCure.apply(to:&unchanged,maxHP:501);XCTAssertEqual(unchanged,fainted)
        for retired in [ChallengeShopItem.revive,.maxRevive] {
            XCTAssertFalse(ChallengeShopItem.allCases.contains(retired))
            XCTAssertFalse(retired.needed(fainted,maxHP:501))
        }
        let save=try ready();try save.apply(.pp("a0",0))
        XCTAssertEqual(save.run?.resources[0].hp,0);XCTAssertEqual(save.run?.resources[0].moves[0].pp,3)
        let heal=try ready();try heal.apply(.heal("a0"));XCTAssertEqual(heal.run?.resources[0].hp,175)
    }
    func testStatusCureAndTeamHealingIncludeRevivalWithoutClearingLivingStatus()throws {
        let save=try ready(wins:3)
        let before=save.run!.resources
        try save.purchase(.teamHeal50,targetID:"")
        XCTAssertEqual(save.run?.pointBalance,250)
        for (i,r) in save.run!.resources.enumerated() {
            XCTAssertEqual(r.hp,min(500,before[i].hp+250))
            XCTAssertEqual(r.moves,before[i].moves);XCTAssertEqual(r.status,before[i].hp==0 ? "":before[i].status)
        }
        try save.purchase(.statusCure,targetID:"a1")
        XCTAssertEqual(save.run?.pointBalance,240);XCTAssertEqual(save.run?.resources[1].hp,251)
        XCTAssertEqual(save.run?.resources[1].status,"");XCTAssertEqual(save.run?.resources[1].moves[0].pp,0)
        XCTAssertThrowsError(try save.purchase(.statusCure,targetID:"a1"))
        XCTAssertEqual(save.run?.phase,.reward);XCTAssertThrowsError(try save.advance())
    }
    func testRemovedProductsMigrateWithoutResettingRunPointsOrOtherOffers()throws {
        let save=try ready()
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
        json["shopOffers"]=["statusCure","revive","teamHeal30","maxRevive"]
        try JSONSerialization.data(withJSONObject:json).write(to:save.url)
        let loaded=ChallengeRunStore(url:save.url)
        XCTAssertEqual(loaded.run?.id,save.run?.id);XCTAssertEqual(loaded.run?.pointBalance,100)
        XCTAssertEqual(loaded.run?.resources,save.run?.resources)
        XCTAssertEqual(loaded.run?.shopOffers,ChallengeShopItem.allCases)
        XCTAssertFalse(loaded.run!.canPurchase(.revive,targetID:"a0"))
        XCTAssertFalse(loaded.run!.canPurchase(.maxRevive,targetID:"a0"))
        XCTAssertEqual(ChallengeRunStore(url:save.url).run?.shopOffers,loaded.run?.shopOffers)
    }
    func testAllSevenProductsPersistAcrossPurchasesRewardsAndNextVictory()throws {
        let helper=ChallengeRunTests(),save=try ready(wins:3)
        XCTAssertEqual(save.run?.shopOffers,ChallengeShopItem.allCases)
        XCTAssertEqual(ChallengeRunStore(url:save.url).run?.shopOffers,ChallengeShopItem.allCases)
        for item in ChallengeShopItem.allCases {
            let target=item == .statusCure ? "a1":"a0"
            XCTAssertTrue(save.run!.canPurchase(item,targetID:target,moveIndex:item == .ppMoveRecovery ? 0:nil),item.rawValue)
        }
        try save.purchase(.heal20,targetID:"a0")
        XCTAssertEqual(save.run?.shopPrice(.heal20),15)
        try save.apply(.buff(.attack));try save.advance();try helper.victory(save)
        XCTAssertEqual(save.run?.shopOffers,ChallengeShopItem.allCases)
        XCTAssertEqual(save.run?.shopPrice(.heal20),15)
        XCTAssertEqual(ChallengeRunStore(url:save.url).run?.shopOffers,ChallengeShopItem.allCases)
    }
    func testExistingFourOffersExpandWithoutChangingMoneyPricesOrResources()throws {
        let save=try ready(wins:3)
        try save.purchase(.ppRecovery,targetID:"a0")
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
        json["shopOffers"]=["heal20","heal40","fullRecovery","ppRecovery"]
        try JSONSerialization.data(withJSONObject:json).write(to:save.url)
        let migrated=ChallengeRunStore(url:save.url)
        XCTAssertEqual(migrated.run?.shopOffers,ChallengeShopItem.allCases)
        XCTAssertEqual(migrated.run?.id,save.run?.id)
        XCTAssertEqual(migrated.run?.pointBalance,save.run?.pointBalance)
        XCTAssertEqual(migrated.run?.shopPurchaseCounts,save.run?.shopPurchaseCounts)
        XCTAssertEqual(migrated.run?.resources,save.run?.resources)
        let bytes=try Data(contentsOf:save.url)
        _ = ChallengeRunStore(url:save.url)
        XCTAssertEqual(try Data(contentsOf:save.url),bytes,"Already-expanded stock is not rewritten")
    }
    func testLegacyStockMigratesOnceAndMalformedStockIsPreserved()throws {
        let save=try ready()
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
        json.removeValue(forKey:"shopOffers")
        try JSONSerialization.data(withJSONObject:json).write(to:save.url)
        let stock=ChallengeShopItem.allCases
        let migrated=ChallengeRunStore(url:save.url)
        XCTAssertEqual(migrated.run?.shopOffers,stock)
        XCTAssertEqual(ChallengeRunStore(url:save.url).run?.shopOffers,stock)
        for bad in [["revive"],["revive","revive","heal20","heal40"]] {
            json["shopOffers"]=bad
            let bytes=try JSONSerialization.data(withJSONObject:json);try bytes.write(to:save.url)
            let invalid=ChallengeRunStore(url:save.url)
            XCTAssertNil(invalid.run);XCTAssertFalse(invalid.canWrite)
            XCTAssertEqual(try Data(contentsOf:save.url),bytes)
        }
    }

    func testSelectedMovePPRecoveryOnlyChangesChosenSlotAndCountsPurchasesPerProduct()throws {
        let save=try ready(wins:3)
        let before=save.run!.resources
        for bad in [nil,-1,2] as [Int?] {
            XCTAssertThrowsError(try save.purchase(.ppMoveRecovery,targetID:"a0",moveIndex:bad))
            XCTAssertEqual(save.run?.resources,before);XCTAssertEqual(save.run?.pointBalance,300)
            XCTAssertEqual(save.run?.shopPrice(.ppMoveRecovery),10)
        }
        try save.purchase(.ppMoveRecovery,targetID:"a0",moveIndex:1)
        XCTAssertEqual(save.run?.resources[0].hp,0)
        XCTAssertEqual(save.run?.resources[0].moves.map(\.pp),[0,10])
        XCTAssertEqual(save.run?.resources[1],before[1])
        XCTAssertEqual(save.run?.pointBalance,290);XCTAssertEqual(save.run?.shopPrice(.ppMoveRecovery),15)
        XCTAssertEqual(save.run?.shopPrice(.ppRecovery),30);XCTAssertEqual(save.run?.shopPrice(.heal20),10)
        XCTAssertThrowsError(try save.purchase(.ppMoveRecovery,targetID:"a0",moveIndex:1))
        try save.purchase(.ppMoveRecovery,targetID:"a0",moveIndex:0)
        XCTAssertEqual(save.run?.pointBalance,275);XCTAssertEqual(save.run?.shopPrice(.ppMoveRecovery),20)
        let loaded=ChallengeRunStore(url:save.url)
        XCTAssertEqual(loaded.run?.shopPrice(.ppMoveRecovery),20)
        try save.apply(.buff(.attack));try save.advance()
        try save.beginEncounter(opponent:ChallengeRunTests().team("b"),seed:[1,2,3,4],policyRevision:"test")
        try save.accept(resources:save.run!.resources,decision:nil,winner:0)
        XCTAssertEqual(save.run?.shopPrice(.ppMoveRecovery),20,"New stock does not reset prices")
        try save.apply(.buff(.attack));try save.advance()
        try save.beginEncounter(opponent:ChallengeRunTests().team("b"),seed:[1,2,3,4],policyRevision:"test")
        try save.forfeit();try save.start(team:ChallengeRunTests().team(),catalogVersion:"shop-test")
        XCTAssertEqual(save.run?.shopPrice(.ppMoveRecovery),10,"A new run resets price history")
    }
    func testMalformedPurchaseHistoryCannotOverflowPricesAndFailedWritesDoNotInflate()throws {
        for count in [-1,Int.max] {
            let save=try ready()
            var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
            json["shopPurchaseCounts"]=["heal20":count]
            let bytes=try JSONSerialization.data(withJSONObject:json);try bytes.write(to:save.url)
            let loaded=ChallengeRunStore(url:save.url)
            XCTAssertNil(loaded.run);XCTAssertFalse(loaded.canWrite);XCTAssertEqual(try Data(contentsOf:save.url),bytes)
        }
    }

    func testVictoryPointsIncreaseEveryThreeEncountersThroughRedAndPersistWithoutDoubleCredit()throws {
        let helper=ChallengeRunTests(),save=try helper.store()
        try save.start(team:helper.team(),catalogVersion:"tiered-points")
        let tiers=[100,120,140,160,180,200,220,240,260]
        var total=0
        for index in 0..<27 {
            try save.beginEncounter(opponent:helper.team("b"),seed:[1,2,3,4],policyRevision:"test")
            let resources=save.run!.resources
            try save.accept(resources:resources,decision:nil,winner:0)
            total+=tiers[index/3]
            XCTAssertEqual(save.run?.pointBalance,total,"Victory \(index+1)")
            XCTAssertThrowsError(try save.accept(resources:resources,decision:nil,winner:0))
            XCTAssertEqual(ChallengeRunStore(url:save.url).run?.pointBalance,total)
            if index<26{try save.apply(.buff(try XCTUnwrap(save.run?.rewardRoll)));try save.advance()}
        }
        XCTAssertEqual(total,4860);XCTAssertEqual(save.run?.phase,.cleared)
    }
    func testLegacyMissingPointsUseTieredTotalButSavedSpentBalanceIsNotRecalculated()throws {
        let save=try ready(wins:4)
        XCTAssertEqual(save.run?.pointBalance,420)
        try save.purchase(.heal20,targetID:"a1");XCTAssertEqual(save.run?.pointBalance,410)
        XCTAssertEqual(ChallengeRunStore(url:save.url).run?.pointBalance,410)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:save.url)) as? [String:Any])
        json.removeValue(forKey:"challengePoints")
        try JSONSerialization.data(withJSONObject:json).write(to:save.url)
        let migrated=ChallengeRunStore(url:save.url)
        XCTAssertEqual(migrated.run?.pointBalance,420)
        XCTAssertEqual(migrated.run?.shopPrice(.heal20),15)
    }

}
