import CryptoKit
import Foundation
import Observation

struct ChallengeEncounterCatalog: Decodable, Sendable {
    struct Encounter: Codable, Sendable, Identifiable {
        let id: String
        let index: Int
        let nameKo: String
        let phase: String
        let team: [BattlePokemon]
    }
    let version: String
    let encounters: [Encounter]
    var compatiblePreviousVersions:[String]? = nil
    var mode: BattleMode = .singles
    private static let previousDoublesPolicy = "ptb-challenge-doubles-v1"
    private static let tacticalDoublesPolicy = "ptb-challenge-doubles-v2"
    private static let doublesPolicy = "ptb-challenge-doubles-v3"

    private struct DoublesSet: Decodable {
        let speciesID: Int
        let ability: String
        let item: String
        let moves: [String]
    }

    // The bundled source catalog predates mode selection.
    enum CodingKeys: String, CodingKey { case version, encounters, compatiblePreviousVersions }

    @MainActor static func load(mode: BattleMode = .singles) throws -> Self {
        let url=BattleEngineProcess.resourceDirectory.appendingPathComponent("challenge-opponents.json")
        let data = try Data(contentsOf: url)
        let catalog=try JSONDecoder().decode(Self.self,from:data)
        guard catalog.encounters.count==27,Set(catalog.encounters.map(\.id)).count==27,
              catalog.encounters.enumerated().allSatisfy({$0.offset==$0.element.index && $0.element.team.count==6}) else{throw ChallengeFailure.invalidState}
        let version = catalog.version+"/"+SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        if mode == .singles {
            return Self(version:version,encounters:catalog.encounters,compatiblePreviousVersions:catalog.compatiblePreviousVersions)
        }
        let ids = ["brock","misty","ltsurge","erika","koga1","sabrina","blaine","giovanni",
                   "lorelei","bruno1","agatha","lance1","blue","red"]
        let previous = try ids.enumerated().map { index, id in
            guard let original = catalog.encounters.first(where: { $0.id == id }) else {
                throw ChallengeFailure.invalidState
            }
            return Encounter(id:id,index:index,nameKo:original.nameKo,phase:original.phase,team:original.team)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func digest(_ encounters: [Encounter]) throws -> String {
            SHA256.hash(data:try encoder.encode(encounters)).map{String(format:"%02x",$0)}.joined()
        }
        let doublesURL = BattleEngineProcess.resourceDirectory.appendingPathComponent("challenge-doubles-opponents.json")
        let sets = try JSONDecoder().decode([String:[DoublesSet]].self,from:Data(contentsOf:doublesURL))
        guard Set(sets.keys) == Set(ids) else { throw ChallengeFailure.invalidState }
        let encounters = try previous.map { original in
            guard let roster = sets[original.id], roster.count == 6,
                  Set(roster.map(\.speciesID)) == Set(original.team.map(\.speciesID)),
                  Set(roster.map(\.item)).count == 6 else { throw ChallengeFailure.invalidState }
            let team = try roster.map { set in
                guard var pokemon = original.team.first(where: { $0.speciesID == set.speciesID }),
                      set.moves.count == 4, Set(set.moves).count == 4 else { throw ChallengeFailure.invalidState }
                pokemon.ability = set.ability
                pokemon.abilitySlot = nil
                pokemon.item = set.item
                pokemon.moves = set.moves
                return pokemon
            }
            return Encounter(id:original.id,index:original.index,nameKo:original.nameKo,phase:original.phase,team:team)
        }
        return try Self(version:"doubles-v2/"+digest(encounters),encounters:encounters,
                        compatiblePreviousVersions:["doubles-v1/"+digest(previous)],mode:.doubles)
    }
    @MainActor static func supportsPolicyRevision(_ revision:String, mode: BattleMode = .singles)throws->Bool {
        if mode == .doubles { return [doublesPolicy,tacticalDoublesPolicy,previousDoublesPolicy].contains(revision) }
        for name in ["challenge-policy.json","challenge-policy-v1.json"] {
            let url=BattleEngineProcess.resourceDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath:url.path) else{continue}
            if SHA256.hash(data:try Data(contentsOf:url)).map({String(format:"%02x",$0)}).joined()==revision{return true}
        }
        return false
    }
    @MainActor static func policyRevision(mode: BattleMode = .singles)throws->String {
        if mode == .doubles { return doublesPolicy }
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
        guard save.mode == catalog.mode else { throw ChallengeFailure.incompatibleVersion }
        self.testControlsEnabled=testControlsEnabled;self.save=save;self.catalog=catalog
        if let run=save.run,![.lost,.cleared].contains(run.phase),run.catalogVersion != catalog.version {
            guard catalog.compatiblePreviousVersions?.contains(run.catalogVersion)==true else{throw ChallengeFailure.incompatibleVersion}
            try save.adoptCatalog(version:catalog.version,previousVersion:run.catalogVersion,encounterCount:catalog.encounters.count)
        }
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
        try save.beginEncounter(opponent:opponent,seed:(0..<4).map{_ in UInt16.random(in:0...UInt16.max)},policyRevision:ChallengeEncounterCatalog.policyRevision(mode:save.mode),useDoublesLineup:true)
        try launch(replay:false)
    }
    func resume()throws {try launch(replay:true)}
    private func launch(replay:Bool)throws {
        guard let run=save.run,run.phase == .battling,let checkpoint=run.checkpoint,
              (checkpoint.engineRevision==BattleEngineProcess.revision || checkpoint.engineRevision==BattleEngineProcess.previousRewardRevision || (checkpoint.engineRevision==BattleEngineProcess.previousChallengeRevision && (checkpoint.initialBuffs ?? []).isEmpty)),
              try ChallengeEncounterCatalog.supportsPolicyRevision(checkpoint.policyRevision,mode:save.mode) else{throw ChallengeFailure.incompatibleVersion}
        stop();frame=nil;error=nil;submitted=false
        replayQueue=replay ? checkpoint.decisions + (checkpoint.pendingDecision.map{[$0]} ?? []):[]
        replaying=replay && !replayQueue.isEmpty
        let process=BattleEngineProcess();engine=process
        let lineup=checkpoint.lineup
        let playerTeam = try lineup.map { ids in
            try ids.map { id in
                guard let member=checkpoint.initialTeam.first(where:{$0.id==id}) else{throw ChallengeFailure.invalidState}
                return member
            } + checkpoint.initialTeam.filter{!ids.contains($0.id)}
        } ?? checkpoint.initialTeam
        let resources=checkpoint.initialResources.filter{lineup?.contains($0.id) ?? true}
        try process.start(mode:save.mode,teams:[playerTeam,checkpoint.opponent],profile:"challenge",
                          resources:[resources,nil],challengeBoosts:ChallengeTeamBuff.stages(checkpoint.initialBuffs ?? []),seed:checkpoint.seed,automaticOpponent:true,policyRevision:checkpoint.policyRevision,challengeBattleSize:lineup?.count)
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
              frame.decisionID==decision.decisionID,decision.actions.count==frame.slots.count else{throw ChallengeFailure.invalidState}
        error=nil
        try save.queueIntent(decision)
        pending=decision;submitted=true
        do {try engine?.choose(player:0,decision:decision)} catch {pending=nil;submitted=false;try save.clearIntent();throw error}
    }
    func applyReward(_ reward:ChallengeReward,eligible:[DexEntry]=[])throws {
        guard save.run?.phase == .reward,(frame==nil || frame?.ended==true),!presentation.pending else{throw ChallengeFailure.invalidReward}
        try save.apply(reward,eligible:eligible)
    }
    func purchase(_ item:ChallengeShopItem,targetID:String,moveIndex:Int?=nil)throws {
        guard (frame==nil || frame?.ended==true),!presentation.pending else{throw ChallengeFailure.invalidReward}
        try save.purchase(item,targetID:targetID,moveIndex:moveIndex)
    }
    func winForTesting()throws {
        guard testControlsEnabled,engine != nil,!submitted,!replaying,
              frame?.ended==false,!presentation.pending else{throw ChallengeFailure.invalidState}
        try engine?.surrender(player:1)
    }
    func nextTrainerForTesting()throws {
        guard testControlsEnabled,!submitted,!replaying,frame?.ended==false,!presentation.pending else{throw ChallengeFailure.invalidState}
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
