import Foundation
import Observation

struct ChallengeMoveState: Codable, Sendable, Equatable {
    let id: String
    var pp: Int
    let maxPP: Int
}
struct ChallengePokemonState: Codable, Sendable, Equatable, Identifiable {
    let id: String
    var hp: Int
    var status: String
    var item: String
    var sleepStart: Int?
    var sleepRemaining: Int?
    var moves: [ChallengeMoveState]
    static func fresh(_ pokemon: BattlePokemon) throws -> Self {
        let moves = try pokemon.moves.map { raw -> ChallengeMoveState in
            let key=BattleTextCatalog.key(raw)
            guard let pp=BattleTextCatalog.shared.moves[key.hasPrefix("hiddenpower") ? "hiddenpower":key]?.pp, pp>0 else {throw ChallengeFailure.invalidState}
            return ChallengeMoveState(id:key.hasPrefix("hiddenpower") ? "hiddenpower":key,pp:pp,maxPP:pp)
        }
        return Self(id:pokemon.id,hp:pokemon.stats["hp"] ?? 0,status:"",item:BattleTextCatalog.key(pokemon.item ?? ""),moves:moves)
    }
}
enum ChallengeFailure: Error { case invalidState, unavailableSave, activeRun, invalidReward, retiredMember, incompatibleVersion }
enum ChallengePhase: String, Codable, Sendable { case ready, battling, reward, intermission, lost, cleared }
struct ChallengeCheckpoint: Codable, Sendable {
    let opponent: [BattlePokemon]
    let initialTeam: [BattlePokemon]
    let initialResources: [ChallengePokemonState]
    let seed: [UInt16]
    let engineRevision: String
    let policyRevision: String
    var decisions: [BattleDecision]=[]
    var pendingDecision: BattleDecision?
}
struct ChallengeChampionReward:Codable,Sendable {
    var recipientID:String? = nil
    var claimed=false
}
struct ChallengeRun: Codable, Sendable, Identifiable {
    var championReward:ChallengeChampionReward? = nil
    var schemaVersion=1
    let id: String
    let catalogVersion: String
    let encounterCount: Int
    var encounterIndex=0
    var phase: ChallengePhase = .ready
    var team: [BattlePokemon]
    var resources: [ChallengePokemonState]
    var retiredIDs: Set<String>=[]
    var checkpoint: ChallengeCheckpoint?
}
enum ChallengeReward {
    case heal(String)
    case pp(String,Int)
    case replace(String,BattlePokemon)
}

/// Mutations are committed to disk before becoming visible. An unreadable save is never overwritten.
@MainActor @Observable final class ChallengeRunStore {
    private(set) var run: ChallengeRun?
    private(set) var error: String?
    private var unreadable=false
    let url: URL
    init(url: URL?=nil) {
        self.url=url ?? AppStatePaths.directory().appendingPathComponent("challenge-run-v1.json")
        guard FileManager.default.fileExists(atPath:self.url.path) else{return}
        do {
            let saved=try JSONDecoder().decode(ChallengeRun.self,from:Data(contentsOf:self.url))
            guard saved.schemaVersion==1 else{throw ChallengeFailure.incompatibleVersion}
            try Self.validate(saved);run=saved
        } catch {self.error=error.localizedDescription;unreadable=true}
    }
    private static func validate(_ run:ChallengeRun)throws {
        guard run.encounterCount>0,run.encounterCount<=100,run.encounterIndex>=0,run.encounterIndex<run.encounterCount,
              run.team.count==6,Set(run.team.map(\.id)).count==6,Set(run.team.map(\.speciesID)).count==6,
              run.resources.count==6,Set(run.resources.map(\.id))==Set(run.team.map(\.id)),
              run.retiredIDs.isDisjoint(with:run.team.map(\.id)) else{throw ChallengeFailure.invalidState}
        for pokemon in run.team {
            guard let r=run.resources.first(where:{$0.id==pokemon.id}),let maxHP=pokemon.stats["hp"],
                  r.hp>=0,r.hp<=maxHP,r.moves.count==pokemon.moves.count,
                  r.moves.allSatisfy({$0.maxPP>0 && $0.pp>=0 && $0.pp<=$0.maxPP}),
                  ["","brn","par","psn","tox","slp","frz"].contains(r.status) else{throw ChallengeFailure.invalidState}
            let fresh=try ChallengePokemonState.fresh(pokemon)
            guard zip(fresh.moves,r.moves).allSatisfy({$0.id==$1.id && $0.maxPP==$1.maxPP}) else{throw ChallengeFailure.invalidState}
        }
        if let reward=run.championReward {
            guard run.phase == .cleared,reward.recipientID != "",!reward.claimed || reward.recipientID != nil else{throw ChallengeFailure.invalidState}
        }
        if run.phase == .battling,run.checkpoint==nil {throw ChallengeFailure.invalidState}
    }
    private func commit(_ updated:ChallengeRun)throws {
        guard !unreadable else{throw ChallengeFailure.unavailableSave}
        try Self.validate(updated)
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(updated).write(to:url,options:.atomic)
            run=updated;error=nil
        } catch {self.error=error.localizedDescription;throw error}
    }
    var canWrite:Bool {!unreadable}
    func start(team:[BattlePokemon],catalogVersion:String,encounterCount:Int=27)throws {
        if let run,run.phase != .lost && !(run.phase == .cleared && run.championReward?.claimed==true){throw ChallengeFailure.activeRun}
        guard !BattleHeldItems.hasDuplicates(team) else{throw ChallengeFailure.invalidState}
        try commit(ChallengeRun(id:UUID().uuidString,catalogVersion:catalogVersion,encounterCount:encounterCount,
                                team:team,resources:try team.map(ChallengePokemonState.fresh)))
    }
    func beginEncounter(opponent:[BattlePokemon],seed:[UInt16],policyRevision:String)throws {
        guard var next=run,next.phase == .ready || next.phase == .intermission,
              next.resources.contains(where:{$0.hp>0}),opponent.count==6,seed.count==4 else{throw ChallengeFailure.invalidState}
        next.checkpoint=ChallengeCheckpoint(opponent:opponent,initialTeam:next.team,initialResources:next.resources,seed:seed,
                                           engineRevision:BattleEngineProcess.revision,policyRevision:policyRevision)
        next.phase = .battling
        try commit(next)
    }
    func accept(resources:[ChallengePokemonState],decision:BattleDecision?,winner:Int?)throws {
        guard var next=run,next.phase == .battling else{throw ChallengeFailure.invalidState}
        guard resources.count==6,Set(resources.map(\.id))==Set(next.team.map(\.id)) else{throw ChallengeFailure.invalidState}
        // Sketch changes the original move slot; Transform/Mimic do not. Carry only an
        // actual supported Sketch replacement, without editing the collection's profile.
        for i in next.team.indices {
            guard let r=resources.first(where:{$0.id==next.team[i].id}),r.moves.count==next.team[i].moves.count else{throw ChallengeFailure.invalidState}
            for j in next.team[i].moves.indices {
                let old=BattleTextCatalog.key(next.team[i].moves[j])
                let canonical=old.hasPrefix("hiddenpower") ? "hiddenpower":old
                if canonical != r.moves[j].id {
                    guard next.team[i].speciesID==235,old=="sketch",BattleTextCatalog.shared.moves[r.moves[j].id] != nil else{throw ChallengeFailure.invalidState}
                    next.team[i].moves[j]=r.moves[j].id
                }
            }
        }
        next.resources=try next.team.map { p in
            guard let r=resources.first(where:{$0.id==p.id}) else{throw ChallengeFailure.invalidState}
            return r
        }
        if let decision {next.checkpoint?.decisions.append(decision);next.checkpoint?.pendingDecision=nil}
        if let winner {
            next.phase=winner==0 ? (next.encounterIndex==next.encounterCount-1 ? .cleared:.reward):.lost
        }
        try commit(next)
    }
    func queueIntent(_ decision:BattleDecision)throws {
        guard var next=run,next.phase == .battling,next.checkpoint?.pendingDecision==nil else{throw ChallengeFailure.invalidState}
        next.checkpoint?.pendingDecision=decision;try commit(next)
    }
    func clearIntent()throws {
        guard var next=run,next.phase == .battling else{throw ChallengeFailure.invalidState}
        next.checkpoint?.pendingDecision=nil;try commit(next)
    }
    func apply(_ reward:ChallengeReward,eligible:[DexEntry]=[])throws {
        guard var next=run,next.phase == .reward else{throw ChallengeFailure.invalidReward}
        switch reward {
        case .heal(let id):
            guard let index=next.resources.firstIndex(where:{$0.id==id}),let p=next.team.first(where:{$0.id==id}),let maxHP=p.stats["hp"],next.resources[index].hp<maxHP else{throw ChallengeFailure.invalidReward}
            let wasFainted=next.resources[index].hp==0
            next.resources[index].hp=min(maxHP,next.resources[index].hp+max(1,Int(Double(maxHP)*0.35)))
            if wasFainted {next.resources[index].status="";next.resources[index].sleepStart=nil;next.resources[index].sleepRemaining=nil}
        case .pp(let id,let move):
            guard let index=next.resources.firstIndex(where:{$0.id==id}),next.resources[index].moves.indices.contains(move),
                  next.resources[index].moves[move].pp<next.resources[index].moves[move].maxPP else{throw ChallengeFailure.invalidReward}
            next.resources[index].moves[move].pp=min(next.resources[index].moves[move].maxPP,next.resources[index].moves[move].pp+3)
        case .replace(let id,var incoming):
            guard !next.retiredIDs.contains(incoming.id) else{throw ChallengeFailure.retiredMember}
            guard let index=next.team.firstIndex(where:{$0.id==id}),let resourceIndex=next.resources.firstIndex(where:{$0.id==id}),
                  BattleTeamBuilder.storedCandidates(eligible).contains(where:{$0.id==incoming.id && $0.finalID==incoming.speciesID}),
                  !next.team.contains(where:{$0.id==incoming.id || $0.speciesID==incoming.speciesID}) else{throw ChallengeFailure.invalidReward}
            let held=next.resources[resourceIndex].item
            incoming.item=BattleHeldItems.choices(speciesID:incoming.speciesID,form:incoming.form).contains(where:{$0.id==held}) ? held:nil
            next.team[index]=incoming;next.resources[resourceIndex]=try .fresh(incoming);next.retiredIDs.insert(id)
        }
        next.phase = .intermission;next.checkpoint=nil
        try commit(next)
    }
    func skipUnavailableReward(eligible:[DexEntry])throws {
        guard var next=run,next.phase == .reward,
              next.resources.allSatisfy({r in r.hp==next.team.first(where:{$0.id==r.id})?.stats["hp"] && r.moves.allSatisfy({$0.pp==$0.maxPP})}),
              !BattleTeamBuilder.storedCandidates(eligible).contains(where:{e in
                  !next.retiredIDs.contains(e.id) && !next.team.contains(where:{$0.id==e.id || $0.speciesID==e.finalID})
              }) else{throw ChallengeFailure.invalidReward}
        next.phase = .intermission;next.checkpoint=nil;try commit(next)
    }
    func advance()throws {
        guard var next=run,next.phase == .intermission,next.encounterIndex+1<next.encounterCount else{throw ChallengeFailure.invalidState}
        next.encounterIndex+=1;next.phase = .ready
        try commit(next)
    }
    /// QA-only encounter traversal; preserve the current resources and never mark a victory.
    func skipEncounterForTesting()throws {
        guard var next=run,[.battling,.reward,.intermission].contains(next.phase),
              next.encounterIndex+1<next.encounterCount else{throw ChallengeFailure.invalidState}
        next.encounterIndex+=1;next.phase = .ready;next.checkpoint=nil
        try commit(next)
    }
    func offerChampionReward()throws {
        guard var next=run,next.phase == .cleared,next.championReward?.claimed != true else{throw ChallengeFailure.invalidReward}
        if next.championReward==nil{next.championReward=ChallengeChampionReward();try commit(next)}
    }
    func prepareChampionShinyReward(recipientID:String)throws {
        guard var next=run,next.phase == .cleared,next.championReward != nil,
              next.championReward?.claimed != true,!recipientID.isEmpty else{throw ChallengeFailure.invalidReward}
        next.championReward?.recipientID=recipientID;try commit(next)
    }
    func finishChampionShinyReward()throws {
        guard var next=run,next.phase == .cleared,next.championReward?.claimed==false,
              next.championReward?.recipientID != nil else{throw ChallengeFailure.invalidReward}
        next.championReward?.claimed=true;try commit(next)
    }
    func forfeit()throws {
        guard var next=run,next.phase == .battling else{throw ChallengeFailure.invalidState}
        next.phase = .lost;try commit(next)
    }
}
