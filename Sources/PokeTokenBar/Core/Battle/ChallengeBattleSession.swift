import CryptoKit
import Foundation
import Observation

/// Enabled only by an explicitly marked local test app or developer launch environment.
enum ChallengeTestMode {
    static var enabled:Bool {ProcessInfo.processInfo.environment["PTB_CHALLENGE_TEST_MODE"]=="1" || Bundle.main.object(forInfoDictionaryKey:"PTBChallengeTestMode") as? Bool==true}
}

struct ChallengeEncounterCatalog: Decodable, Sendable {
    struct Encounter: Decodable, Sendable, Identifiable {
        let id: String
        let index: Int
        let nameKo: String
        let phase: String
        let team: [BattlePokemon]
    }
    let version: String
    let encounters: [Encounter]
    @MainActor static func load() throws -> Self {
        let url=BattleEngineProcess.resourceDirectory.appendingPathComponent("challenge-opponents.json")
        let catalog=try JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
        guard catalog.encounters.count==27,Set(catalog.encounters.map(\.id)).count==27,
              catalog.encounters.enumerated().allSatisfy({$0.offset==$0.element.index && $0.element.team.count==6}) else{throw ChallengeFailure.invalidState}
        return Self(version:catalog.version+"/"+SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",$0)}.joined(),encounters:catalog.encounters)
    }
    @MainActor static func policyRevision()throws->String {
        let data=try Data(contentsOf:BattleEngineProcess.resourceDirectory.appendingPathComponent("challenge-policy.json"))
        return SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
    }
}

/// Local single-player session. No LAN peer, matchmaking timer or private human decision feeds the CPU.
@MainActor @Observable final class ChallengeBattleSession {
    let testControlsEnabled:Bool
    let save: ChallengeRunStore
    let catalog: ChallengeEncounterCatalog
    let presentation=BattleScenePlayback()
    private(set) var frame: BattleFrame?
    private(set) var error: String?
    private(set) var submitted=false
    private var engine: BattleEngineProcess?
    private var replayQueue: [BattleDecision]=[]
    private var replaying=false
    private var pending: BattleDecision?
    init(save:ChallengeRunStore,catalog:ChallengeEncounterCatalog,testControlsEnabled:Bool=ChallengeTestMode.enabled)throws {
        self.testControlsEnabled=testControlsEnabled;self.save=save;self.catalog=catalog
        if let run=save.run,![.lost,.cleared].contains(run.phase),run.catalogVersion != catalog.version {throw ChallengeFailure.incompatibleVersion}
    }
    func start(team:[BattlePokemon])throws {
        try save.start(team:team,catalogVersion:catalog.version,encounterCount:catalog.encounters.count)
        try startEncounter()
    }
    func startEncounter()throws {
        guard let run=save.run,run.phase == .ready || run.phase == .intermission else{throw ChallengeFailure.invalidState}
        if run.phase == .intermission {try save.advance()}
        guard let updated=save.run else{throw ChallengeFailure.invalidState}
        let opponent=catalog.encounters[updated.encounterIndex].team
        try save.beginEncounter(opponent:opponent,seed:(0..<4).map{_ in UInt16.random(in:0...UInt16.max)},policyRevision:ChallengeEncounterCatalog.policyRevision())
        try launch(replay:false)
    }
    func resume()throws {try launch(replay:true)}
    private func launch(replay:Bool)throws {
        guard let run=save.run,run.phase == .battling,let checkpoint=run.checkpoint,
              checkpoint.engineRevision==BattleEngineProcess.revision,
              checkpoint.policyRevision == (try ChallengeEncounterCatalog.policyRevision()) else{throw ChallengeFailure.incompatibleVersion}
        stop();frame=nil;error=nil;submitted=false
        replayQueue=replay ? checkpoint.decisions + (checkpoint.pendingDecision.map{[$0]} ?? []):[]
        replaying=replay && !replayQueue.isEmpty
        let process=BattleEngineProcess();engine=process
        try process.start(mode:.singles,teams:[checkpoint.initialTeam,checkpoint.opponent],profile:"challenge",
                          resources:[checkpoint.initialResources,nil],seed:checkpoint.seed,automaticOpponent:true)
        process.onFrames={ [weak self] frames in self?.receive(frames[0]) }
        process.onFailure={ [weak self] reason in
            guard let self else{return}
            self.error=reason;self.submitted=false;self.pending=nil
            if !self.replaying {try? self.save.clearIntent()}
        }
        process.onExit={ [weak self] reason in self?.error=reason }
    }
    private func receive(_ next:BattleFrame) {
        if replaying,!replayQueue.isEmpty {
            let decision=replayQueue.removeFirst()
            guard decision.decisionID==next.decisionID else{error="Saved challenge command no longer matches the engine.";stop();return}
            do {try engine?.choose(player:0,decision:decision)} catch {self.error=error.localizedDescription}
            return
        }
        let replayJustFinished=replaying;replaying=false
        guard let resources=next.resources else{error="Missing challenge resources.";return}
        do {
            // A crash can leave the final intent saved but not yet acknowledged.
            let acknowledged=replayJustFinished ? save.run?.checkpoint?.pendingDecision:pending
            try save.accept(resources:resources,decision:acknowledged,winner:next.ended ? (next.winner ?? -1):nil)
            frame=next;presentation.accept(next);pending=nil;submitted=false
        } catch {self.error=error.localizedDescription;submitted=true}
    }
    func choose(_ decision:BattleDecision)throws {
        guard engine != nil,!submitted,!replaying,let frame,!frame.ended,!frame.waiting,
              frame.decisionID==decision.decisionID,decision.actions.count==1 else{throw ChallengeFailure.invalidState}
        error=nil
        try save.queueIntent(decision)
        pending=decision;submitted=true
        do {try engine?.choose(player:0,decision:decision)} catch {pending=nil;submitted=false;try save.clearIntent();throw error}
    }
    func applyReward(_ reward:ChallengeReward,eligible:[DexEntry]=[])throws {
        guard save.run?.phase == .reward,(frame==nil || frame?.ended==true),!presentation.pending else{throw ChallengeFailure.invalidReward}
        try save.apply(reward,eligible:eligible)
    }
    func winForTesting()throws {
        guard testControlsEnabled,engine != nil,!submitted,!replaying,
              frame?.ended==false,!presentation.pending else{throw ChallengeFailure.invalidState}
        try engine?.surrender(player:1)
    }
    func nextTrainerForTesting()throws {
        guard testControlsEnabled,!submitted,!replaying,!presentation.pending else{throw ChallengeFailure.invalidState}
        try save.skipEncounterForTesting()
        stop();frame=nil
        try startEncounter()
    }
    func surrender()throws {
        try save.forfeit();stop()
    }
    func completePresentation(){presentation.finish()}
    func stop(){engine?.stop();engine=nil;pending=nil;submitted=false;presentation.reset()}
}
