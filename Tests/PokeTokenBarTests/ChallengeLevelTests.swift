import XCTest
@testable import PokeTokenBar

@MainActor final class ChallengeLevelTests:XCTestCase {
    private func wait(_ session:ChallengeBattleSession,after:String?=nil)async throws->BattleFrame {
        let end=Date().addingTimeInterval(8)
        while Date()<end {
            if let error=session.error{XCTFail(error);throw ChallengeFailure.invalidState}
            if let frame=session.frame,!session.submitted,after==nil || frame.decisionID != after{return frame}
            try await Task.sleep(for:.milliseconds(15))
        }
        throw ChallengeFailure.invalidState
    }
    func testCatalogUsesThreeLevelTiersAndExistingBattleResumesBeforeNextOpponentChanges()async throws {
        let catalog=try ChallengeEncounterCatalog.load(),legacy=try XCTUnwrap(catalog.compatiblePreviousVersions?.first)
        for encounter in catalog.encounters {
            XCTAssertTrue(encounter.team.allSatisfy{$0.level == (encounter.index<12 ? 75:encounter.index<16 ? 90:100)})
        }
        let helper=ChallengeRunTests(),save=try helper.store(),own=helper.team(),oldOpponent=helper.team("old")
        try save.start(team:own,catalogVersion:legacy)
        try save.beginEncounter(opponent:oldOpponent,seed:[1,2,3,4],policyRevision:ChallengeEncounterCatalog.policyRevision())
        let checkpoint=try XCTUnwrap(save.run?.checkpoint),id=save.run?.id,resources=save.run?.resources
        let session=try ChallengeBattleSession(save:save,catalog:catalog,testControlsEnabled:true);defer{session.stop()}
        XCTAssertEqual(save.run?.catalogVersion,catalog.version)
        XCTAssertEqual(save.run?.id,id);XCTAssertEqual(save.run?.resources,resources)
        XCTAssertEqual(save.run?.team,own);XCTAssertEqual(save.run?.checkpoint?.opponent,checkpoint.opponent)
        try session.resume();let resumed=try await wait(session)
        XCTAssertEqual(resumed.foe.first?.level,100,"An in-flight old battle retains its original opponent")
        session.completePresentation();try session.winForTesting()
        let won=try await wait(session,after:resumed.decisionID);XCTAssertEqual(won.winner,0)
        session.completePresentation();try session.applyReward(.buff(try XCTUnwrap(save.run?.rewardRoll)))
        try session.startEncounter();let next=try await wait(session,after:won.decisionID)
        XCTAssertEqual(save.run?.encounterIndex,1)
        XCTAssertEqual(save.run?.checkpoint?.opponent,catalog.encounters[1].team)
        XCTAssertEqual(next.foe.first?.level,75)
        XCTAssertEqual(save.run?.team,own,"Player loadouts and stats remain frozen")
        XCTAssertEqual(ChallengeRunStore(url:save.url).run?.catalogVersion,catalog.version)
    }
    func testUnknownCatalogAndIncompatibleEncounterCountNeverRewriteTheSave()throws {
        let catalog=try ChallengeEncounterCatalog.load()
        for known in [false,true] {
            let helper=ChallengeRunTests(),save=try helper.store()
            try save.start(team:helper.team(),catalogVersion:known ? XCTUnwrap(catalog.compatiblePreviousVersions?.first):"unreviewed-catalog",encounterCount:known ? 26:27)
            let bytes=try Data(contentsOf:save.url)
            XCTAssertThrowsError(try ChallengeBattleSession(save:save,catalog:catalog))
            XCTAssertEqual(try Data(contentsOf:save.url),bytes)
        }
    }
}
