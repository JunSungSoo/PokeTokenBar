import XCTest
@testable import PokeTokenBar

private struct CashNoProvider:PokeProviding {
    func line(baseSpeciesID:Int)async throws->EvoLine {throw URLError(.notConnectedToInternet)}
    func baseSpeciesIndex()async throws->[BaseSpecies]{[]}
    func baseSpecies(id:Int)async throws->BaseSpecies?{nil}
}
@MainActor final class ChallengeCashRewardTests:XCTestCase {
    private func defeated(after wins:Int)throws->ChallengeRunStore {
        let helper=ChallengeRunTests(),save=try helper.store()
        try save.start(team:helper.team(),catalogVersion:"cash",encounterCount:27)
        for _ in 0..<wins {
            try helper.victory(save)
            try save.apply(.buff(save.run!.rewardRoll!));try save.advance()
        }
        try save.beginEncounter(opponent:helper.team("b"),seed:[1,2,3,4],policyRevision:"test")
        try save.accept(resources:save.run!.resources,decision:nil,winner:1)
        return save
    }
    func testBoundaryAndTrainerTierTotalsAndNoPaymentOnFullClear()throws {
        for (wins,millions) in [(0,0),(1,0),(2,0),(3,10),(4,20),(16,140),(17,170),(24,380),(25,430),(26,480)] {
            let save=try defeated(after:wins)
            XCTAssertEqual(save.run!.defeatCashTokens,millions*1_000_000)
            XCTAssertEqual(ChallengeRunStore(url:save.url).run?.defeatCashTokens,millions*1_000_000)
            XCTAssertThrowsError(try save.advance())
        }
        let helper=ChallengeRunTests(),save=try helper.store()
        try save.start(team:helper.team(),catalogVersion:"cash",encounterCount:27)
        for i in 0..<27 {
            try helper.victory(save)
            if i<26{try save.apply(.buff(save.run!.rewardRoll!));try save.advance()}
        }
        XCTAssertEqual(save.run?.phase,.cleared);XCTAssertEqual(save.run?.defeatCashTokens,0)
        try save.offerChampionReward();XCTAssertNotNil(save.run?.championReward)
    }
    func testCreditIsAtomicIdempotentPersistentAndDoesNotAffectGrowth()throws {
        let save=try defeated(after:3),run=save.run!,dir=save.url.deletingLastPathComponent()
        let file=dir.appendingPathComponent("companion.json"),suite="Cash.\(UUID())",defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer{defaults.removePersistentDomain(forName:suite)}
        var state=CompanionState();state.usedSinceInstall=2_000_000;state.spentTokens=1_000_000
        try JSONEncoder().encode(state).write(to:file)
        let store=CompanionStore(provider:CashNoProvider(),fileURL:file,defaults:defaults)
        try store.claimChallengeCash(run);try store.claimChallengeCash(run)
        XCTAssertEqual(store.availableTokens,11_000_000)
        XCTAssertEqual(store.state.usedSinceInstall,2_000_000);XCTAssertEqual(store.state.eggUsage,0)
        let reopened=CompanionStore(provider:CashNoProvider(),fileURL:file,defaults:defaults)
        try reopened.claimChallengeCash(run);XCTAssertEqual(reopened.availableTokens,11_000_000)
        let snapshot=store.state
        let model=ChallengeUIModel(store:reopened,session:try ChallengeBattleSession(save:save,catalog:ChallengeEncounterCatalog.load()))
        model.synchronizeChampionAward();model.newChallenge()
        XCTAssertTrue(model.newSetup);XCTAssertEqual(reopened.availableTokens,11_000_000)
        XCTAssertEqual(snapshot.challengeCashClaims,reopened.state.challengeCashClaims)
        try reopened.claimChallengeCash(try defeated(after:24).run!)
        XCTAssertEqual(reopened.availableTokens,391_000_000)
        XCTAssertTrue(reopened.buy(.mint))
        XCTAssertEqual(reopened.availableTokens,391_000_000-reopened.price(of:.mint)!)
        XCTAssertEqual(reopened.state.usedSinceInstall,2_000_000)
        // Missing/unwritable collection directory cannot publish a receipt or credit.
        let blocked=CompanionStore(provider:CashNoProvider(),fileURL:dir.appendingPathComponent("missing/state.json"),defaults:defaults)
        try FileManager.default.removeItem(at:dir.appendingPathComponent("missing"))
        XCTAssertThrowsError(try blocked.claimChallengeCash(run))
        XCTAssertNil(blocked.state.challengeCashClaims);XCTAssertEqual(blocked.availableTokens,0)
        let pending=ChallengeUIModel(store:blocked,session:try ChallengeBattleSession(save:save,catalog:ChallengeEncounterCatalog.load()))
        pending.newChallenge();XCTAssertFalse(pending.newSetup,"Unpaid run must remain available for retry")
        try FileManager.default.createDirectory(at:dir.appendingPathComponent("missing"),withIntermediateDirectories:true)
        pending.newChallenge();XCTAssertTrue(pending.newSetup)
        XCTAssertEqual(blocked.availableTokens,10_000_000)
    }
    func testStartupRepairsOnlyMissingCashReceiptsAfterAnOlderAppRewritesSave() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("companion-state.json")
        var historical = CompanionState()
        historical.challengeCashClaims = ["retained": 70_000_000, "older": 20_000_000]
        historical.challengeShinyClaims = ["unrelated": "pokemon"]
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        try SaveSnapshotManager.createSnapshot(state: historical, for: file, date: oldDate)
        historical.challengeCashClaims = ["older": 30_000_000, "newer": 80_000_000, "invalid": -10]
        try SaveSnapshotManager.createSnapshot(state: historical, for: file, date: oldDate.addingTimeInterval(60))
        historical.challengeCashClaims = nil
        try SaveSnapshotManager.createSnapshot(state: historical, for: file, date: oldDate.addingTimeInterval(120))

        let original: [String: Any] = [
            "usedSinceInstall": 150_000_000, "spentTokens": 190_000_000,
            "eggUsage": 12_345, "inventory": ["rareCandy": 2],
            "futureProgress": ["value": "must survive"]
        ]
        let suite = "CashRecovery.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try JSONSerialization.data(withJSONObject: original).write(to: file)
        let recovered = CompanionStore(provider: CashNoProvider(), fileURL: file, defaults: defaults)
        XCTAssertEqual(recovered.availableTokens, 140_000_000)
        XCTAssertNil(recovered.state.challengeShinyClaims)
        let bytes = try Data(contentsOf: file)
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(document.removeValue(forKey: "challengeCashClaims") as? [String: Int],
                       ["retained": 70_000_000, "older": 30_000_000, "newer": 80_000_000])
        XCTAssertEqual(document as NSDictionary, original as NSDictionary)

        let reopened = CompanionStore(provider: CashNoProvider(), fileURL: file, defaults: defaults)
        XCTAssertEqual(reopened.availableTokens, recovered.availableTokens)
        XCTAssertEqual(try Data(contentsOf: file), bytes)

        // A partial current ledger wins on conflicting amounts, while gaps still get filled.
        document["challengeCashClaims"] = ["retained": 40_000_000]
        try JSONSerialization.data(withJSONObject: document).write(to: file)
        let partial = CompanionStore(provider: CashNoProvider(), fileURL: file, defaults: defaults)
        XCTAssertEqual(partial.state.challengeCashClaims?["retained"], 40_000_000)
        XCTAssertEqual(partial.availableTokens, 110_000_000)
    }

    func testImportRetainsReceiptsAndMalformedCreditsAreDiscarded() {
        var current=CompanionState(),imported=CompanionState()
        current.challengeCashClaims=["same":30_000_000,"local":50_000_000]
        imported.challengeCashClaims=["same":40_000_000,"remote":60_000_000,"bad":Int.max,"negative":-1]
        let clean=SaveTransfer.sanitized(imported)
        XCTAssertNil(clean.challengeCashClaims?["bad"]);XCTAssertNil(clean.challengeCashClaims?["negative"])
        let merged=SaveTransfer.rebasedForThisDevice(clean,current:current,todayTokensByProvider:[:],todayDate:"2026-11-03",hasUsageData:false)
        XCTAssertEqual(merged.challengeCashClaims,["same":40_000_000,"local":50_000_000,"remote":60_000_000])
    }

    func testSkippedRoundsDoNotCountAndOldSavesRemainReadable()throws {
        let helper=ChallengeRunTests(),save=try helper.store()
        try save.start(team:helper.team(),catalogVersion:"cash",encounterCount:27)
        for _ in 0..<3 {
            try save.beginEncounter(opponent:helper.team("b"),seed:[1,2,3,4],policyRevision:"test")
            try save.skipEncounterForTesting()
        }
        try save.beginEncounter(opponent:helper.team("b"),seed:[1,2,3,4],policyRevision:"test");try save.forfeit()
        XCTAssertEqual(save.run?.defeatCashTokens,0)
        let legacy=try defeated(after:3)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:legacy.url)) as? [String:Any])
        json.removeValue(forKey:"cashVictoryRewards")
        try JSONSerialization.data(withJSONObject:json).write(to:legacy.url)
        XCTAssertEqual(ChallengeRunStore(url:legacy.url).run?.defeatCashTokens,10_000_000)
    }
}
