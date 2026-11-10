import Foundation
import Observation

enum ChallengeBuffKind:String,Codable,Sendable,CaseIterable {
    case attack,specialAttack,speed,defense,specialDefense
    /// Decode already-active rewards from the previous version without rerolling them.
    case power
    static let allCases:[Self]=[.attack,.specialAttack,.speed,.defense,.specialDefense]
    var stages:[String:Int] {
        switch self {
        case .attack:["atk":1]
        case .specialAttack:["spa":1]
        case .speed:["spe":1]
        case .defense:["def":1]
        case .specialDefense:["spd":1]
        case .power:["atk":1,"spa":1]
        }
    }
}
struct ChallengeTeamBuff:Codable,Sendable,Equatable,Identifiable {
    let id:String
    let kind:ChallengeBuffKind
    var remaining:Int
    static func stages(_ buffs:[Self])->[String:Int] {
        buffs.filter{$0.remaining>0}.reduce(into:[:]){result,buff in
            for (key,value) in buff.kind.stages{result[key,default:0]+=value}
        }
    }
    static func afterBattle(_ buffs:[Self])->[Self] {
        buffs.compactMap{buff in guard buff.remaining>1 else{return nil};var next=buff;next.remaining-=1;return next}
    }
}
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
    var lineup: [String]? = nil
    var initialBuffs:[ChallengeTeamBuff]? = nil
    var decisions: [BattleDecision]=[]
    var pendingDecision: BattleDecision?
}
struct ChallengeChampionReward:Codable,Sendable {
    var recipientID:String? = nil
    var claimed=false
}
struct ChallengeRun: Codable, Sendable, Identifiable {
    /// Missing in existing singles saves.
    var mode: BattleMode? = nil
    var battleMode: BattleMode { mode ?? .singles }
    var cashVictoryRewards:[Int]? = []
    var championReward:ChallengeChampionReward? = nil
    var shopOffers:[ChallengeShopItem]? = nil
    var shopPurchaseCounts:[String:Int]? = nil
    var challengePoints:Int? = ChallengeRun.startingPoints
    var teamBuffs:[ChallengeTeamBuff]? = nil
    var rewardRoll:ChallengeBuffKind? = nil
    var schemaVersion=1
    let id: String
    var catalogVersion: String
    let encounterCount: Int
    var encounterIndex=0
    var phase: ChallengePhase = .ready
    // Owned loadouts are copied at registration (or an explicit replacement reward).
    // Collection/Pokédex edits must never refresh these values during an active run.
    var team: [BattlePokemon]
    var resources: [ChallengePokemonState]
    var retiredIDs: Set<String>=[]
    var checkpoint: ChallengeCheckpoint?
    var preparedLineup: [String]? = nil
    var milestoneReward:Bool {(encounterIndex+1).isMultiple(of:3)}
    var enhancedReward:Bool {encounterIndex >= (battleMode == .singles ? 15 : 7)}
    var needsFullRecovery:Bool {resources.contains{r in r.hp < (team.first{$0.id==r.id}?.stats["hp"] ?? 0) || !r.status.isEmpty || r.moves.contains{$0.pp<$0.maxPP}}}
}
enum ChallengeReward {
    case heal(String)
    case pp(String,Int)
    case replace(String,BattlePokemon)
    case allHeal
    case buff(ChallengeBuffKind)
    case points
}

/// Mutations are committed to disk before becoming visible. An unreadable save is never overwritten.
@MainActor @Observable final class ChallengeRunStore {
    private(set) var run: ChallengeRun?
    private(set) var error: String?
    private var unreadable=false
    let url: URL
    let mode: BattleMode
    private let roll:()->ChallengeBuffKind
    static func saveFilename(mode: BattleMode, test: Bool = false) -> String {
        "challenge" + (mode == .doubles ? "-doubles" : "") + (test ? "-test" : "") + "-run-v1.json"
    }
    init(url: URL?=nil,mode: BattleMode = .singles,
         roll:@escaping ()->ChallengeBuffKind = {ChallengeBuffKind.allCases.randomElement()!}) {
        self.roll=roll
        self.mode = mode
        self.url=url ?? AppStatePaths.directory().appendingPathComponent(
            Self.saveFilename(mode:mode))
        guard FileManager.default.fileExists(atPath:self.url.path) else{return}
        do {
            var saved=try JSONDecoder().decode(ChallengeRun.self,from:Data(contentsOf:self.url))
            guard saved.schemaVersion==1, saved.battleMode == mode else{throw ChallengeFailure.incompatibleVersion}
            try Self.validate(saved)
            let needsShop=saved.shopOffers != nil || [.reward,.intermission].contains(saved.phase)
            let changedShop=needsShop && saved.shopOffers != ChallengeShopItem.allCases
            if changedShop{saved.shopOffers=ChallengeShopItem.allCases}
            let missingPoints=saved.challengePoints==nil
            let missingOffer=saved.phase == .reward && (saved.rewardRoll==nil || saved.rewardRoll == .power)
            if missingPoints{saved.challengePoints=max(ChallengeRun.startingPoints,ChallengeRun.legacyVictoryPoints(saved.completedVictories))}
            if missingOffer{saved.rewardRoll=roll()}
            if missingPoints || missingOffer || changedShop{try commit(saved)}else{run=saved}
        } catch {self.error=error.localizedDescription;unreadable=true}
    }
    private static func validate(_ run:ChallengeRun)throws {
        guard run.encounterCount>0,run.encounterCount<=100,run.encounterIndex>=0,run.encounterIndex<run.encounterCount,
              run.team.count==6,Set(run.team.map(\.id)).count==6,Set(run.team.map(\.speciesID)).count==6,
              run.resources.count==6,Set(run.resources.map(\.id))==Set(run.team.map(\.id)),
              run.retiredIDs.isDisjoint(with:run.team.map(\.id)) else{throw ChallengeFailure.invalidState}
        for pokemon in run.team {
            guard let r=run.resources.first(where:{$0.id==pokemon.id}),let maxHP=pokemon.stats["hp"],(1...1000).contains(maxHP),
                  r.hp>=0,r.hp<=maxHP,r.moves.count==pokemon.moves.count,
                  r.moves.allSatisfy({$0.maxPP>0 && $0.pp>=0 && $0.pp<=$0.maxPP}),
                  ["","brn","par","psn","tox","slp","frz"].contains(r.status) else{throw ChallengeFailure.invalidState}
            let fresh=try ChallengePokemonState.fresh(pokemon)
            guard zip(fresh.moves,r.moves).allSatisfy({$0.id==$1.id && $0.maxPP==$1.maxPP}) else{throw ChallengeFailure.invalidState}
        }
        if let lineup=run.preparedLineup {
            guard run.battleMode == .doubles, Self.validLineup(lineup, team:run.team, resources:run.resources) else{throw ChallengeFailure.invalidState}
        }
        if let checkpoint=run.checkpoint,let lineup=checkpoint.lineup {
            guard run.battleMode == .doubles, Self.validLineup(lineup, team:checkpoint.initialTeam, resources:checkpoint.initialResources) else{throw ChallengeFailure.invalidState}
        }
        if let rewards=run.cashVictoryRewards {
            guard rewards.count<=run.completedVictories,rewards.allSatisfy({[0,10,30,50].contains($0)}),rewards.reduce(0,+)<=500 else{throw ChallengeFailure.invalidState}
        }
        let maximumPoints = ChallengeRun.legacyVictoryPoints(run.encounterCount)
            + ChallengeRun.startingPoints + ChallengeRun.rewardPoints * run.encounterCount
        guard run.pointBalance>=0,run.pointBalance<=maximumPoints else{throw ChallengeFailure.invalidState}
        if let counts=run.shopPurchaseCounts {
            guard counts.allSatisfy({ChallengeShopItem(rawValue:$0.key) != nil && $0.value>=0 && $0.value<=maximumPoints/10}) else{throw ChallengeFailure.invalidState}
        }
        if let offers=run.shopOffers {guard [4,ChallengeShopItem.allCases.count].contains(offers.count),Set(offers).count==offers.count else{throw ChallengeFailure.invalidState}}
        let buffs=run.teamBuffs ?? []
        guard Set(buffs.map(\.id)).count==buffs.count,buffs.allSatisfy({(1...3).contains($0.remaining)}) else{throw ChallengeFailure.invalidState}
        if let snapshot=run.checkpoint?.initialBuffs {
            guard Set(snapshot.map(\.id)).count==snapshot.count,snapshot.allSatisfy({(1...3).contains($0.remaining)}) else{throw ChallengeFailure.invalidState}
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
        try commit(ChallengeRun(mode:mode == .doubles ? .doubles : nil,
                                id:UUID().uuidString,catalogVersion:catalogVersion,encounterCount:encounterCount,
                                team:team,resources:try team.map(ChallengePokemonState.fresh)))
    }
    private static func validLineup(_ order:[String],team:[BattlePokemon],resources:[ChallengePokemonState])->Bool {
        order.count==BattleMode.doubles.battleSize && Set(order).count==order.count
            && Set(order).isSubset(of:Set(team.map(\.id))) && resources.contains{order.contains($0.id) && $0.hp>0}
    }
    /// Only order and held gear are editable between battles. Never rebuild owned profiles.
    func prepareEncounter(order:[String],items:[String:String])throws {
        guard var next=run,next.phase == .ready || next.phase == .intermission,
              Set(items.keys).isSubset(of:Set(next.team.map(\.id))) else{throw ChallengeFailure.invalidState}
        let rosterOrder:[String]
        if mode == .doubles {
            guard Self.validLineup(order,team:next.team,resources:next.resources) else{throw ChallengeFailure.invalidState}
            next.preparedLineup=order
            rosterOrder=next.team.map(\.id)
        } else {
            guard order.count==6,Set(order)==Set(next.team.map(\.id)) else{throw ChallengeFailure.invalidState}
            rosterOrder=order
        }
        next.team=try rosterOrder.map { id in
            guard var pokemon=next.team.first(where:{$0.id==id}) else{throw ChallengeFailure.invalidState}
            let item=items[id] ?? ""
            guard item.isEmpty || BattleHeldItems.choices(speciesID:pokemon.speciesID,form:pokemon.form).contains(where:{$0.id==item}) else{throw ChallengeFailure.invalidState}
            pokemon.item=item;return pokemon
        }
        guard !BattleHeldItems.hasDuplicates(next.team) else{throw ChallengeFailure.invalidState}
        next.resources=try rosterOrder.map {id in
            guard var resource=next.resources.first(where:{$0.id==id}) else{throw ChallengeFailure.invalidState}
            resource.item=items[id] ?? "";return resource
        }
        try commit(next)
    }
    // Upgrade only a reviewed compatible catalog; replay uses the untouched checkpoint.
    func adoptCatalog(version:String,previousVersion:String,encounterCount:Int)throws {
        guard var next=run,next.catalogVersion==previousVersion,next.encounterCount==encounterCount else{throw ChallengeFailure.incompatibleVersion}
        next.catalogVersion=version;try commit(next)
    }
    func beginEncounter(opponent:[BattlePokemon],seed:[UInt16],policyRevision:String, useDoublesLineup:Bool=false)throws {
        guard var next=run,next.phase == .ready || next.phase == .intermission,
              next.resources.contains(where:{$0.hp>0}),opponent.count==6,seed.count==4 else{throw ChallengeFailure.invalidState}
        // Wake only between encounters, never while replaying an unfinished battle.
        for i in next.resources.indices where next.resources[i].status == "slp" {
            next.resources[i].status="";next.resources[i].sleepStart=nil;next.resources[i].sleepRemaining=nil
        }
        var lineup: [String]?
        if useDoublesLineup && mode == .doubles {
            let livingFirst = next.resources.filter{$0.hp>0} + next.resources.filter{$0.hp==0}
            lineup = next.preparedLineup ?? livingFirst.prefix(mode.battleSize).map(\.id)
        }
        next.preparedLineup=nil
        next.checkpoint=ChallengeCheckpoint(opponent:opponent,initialTeam:next.team,initialResources:next.resources,seed:seed,
                                           engineRevision:BattleEngineProcess.revision,policyRevision:policyRevision,lineup:lineup,initialBuffs:next.teamBuffs)
        next.phase = .battling
        try commit(next)
    }
    func accept(resources:[ChallengePokemonState],decision:BattleDecision?,winner:Int?)throws {
        guard var next=run,next.phase == .battling else{throw ChallengeFailure.invalidState}
        let participants = next.checkpoint?.lineup ?? next.team.map(\.id)
        guard resources.count==participants.count,Set(resources.map(\.id))==Set(participants) else{throw ChallengeFailure.invalidState}
        let allResources = resources + next.resources.filter{!participants.contains($0.id)}
        // Sketch changes the original move slot; Transform/Mimic do not. Carry only an
        // actual supported Sketch replacement, without editing the collection's profile.
        for i in next.team.indices {
            guard let r=allResources.first(where:{$0.id==next.team[i].id}),r.moves.count==next.team[i].moves.count else{throw ChallengeFailure.invalidState}
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
            guard let r=allResources.first(where:{$0.id==p.id}) else{throw ChallengeFailure.invalidState}
            return r
        }
        if let decision {next.checkpoint?.decisions.append(decision);next.checkpoint?.pendingDecision=nil}
        if let winner {
            if winner==0{next.cashVictoryRewards=next.completedCashRewards+[ChallengeRun.cashReward(encounterIndex:next.encounterIndex,mode:next.battleMode)]}
            next.teamBuffs=ChallengeTeamBuff.afterBattle(next.teamBuffs ?? [])
            next.phase=winner==0 ? (next.encounterIndex==next.encounterCount-1 ? .cleared:.reward):.lost
            next.rewardRoll=next.phase == .reward ? roll():nil
            next.shopOffers=next.phase == .reward ? ChallengeShopItem.allCases:nil
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
        case .points:
            next.challengePoints = next.pointBalance + ChallengeRun.rewardPoints
        case .heal(let id):
            guard !next.milestoneReward else{throw ChallengeFailure.invalidReward}
            guard let index=next.resources.firstIndex(where:{$0.id==id}),let p=next.team.first(where:{$0.id==id}),let maxHP=p.stats["hp"],next.resources[index].hp<maxHP else{throw ChallengeFailure.invalidReward}
            let wasFainted=next.resources[index].hp==0
            next.resources[index].hp=min(maxHP,next.resources[index].hp+(next.enhancedReward ? maxHP:max(1,Int(Double(maxHP)*0.35))))
            if wasFainted{next.resources[index].status="";next.resources[index].sleepStart=nil;next.resources[index].sleepRemaining=nil}
        case .pp(let id,let move):
            guard !next.milestoneReward,let index=next.resources.firstIndex(where:{$0.id==id}) else{throw ChallengeFailure.invalidReward}
            if next.enhancedReward {
                guard next.resources[index].moves.contains(where:{$0.pp<$0.maxPP}) else{throw ChallengeFailure.invalidReward}
                for j in next.resources[index].moves.indices{next.resources[index].moves[j].pp=next.resources[index].moves[j].maxPP}
            }else{
                guard next.resources[index].moves.indices.contains(move),next.resources[index].moves[move].pp<next.resources[index].moves[move].maxPP else{throw ChallengeFailure.invalidReward}
                next.resources[index].moves[move].pp=min(next.resources[index].moves[move].maxPP,next.resources[index].moves[move].pp+3)
            }
        case .allHeal:
            guard next.milestoneReward,next.needsFullRecovery else{throw ChallengeFailure.invalidReward}
            for i in next.resources.indices {
                next.resources[i].hp=next.team.first{$0.id==next.resources[i].id}!.stats["hp"]!
                next.resources[i].status="";next.resources[i].sleepStart=nil;next.resources[i].sleepRemaining=nil
                for j in next.resources[i].moves.indices{next.resources[i].moves[j].pp=next.resources[i].moves[j].maxPP}
            }
        case .buff(let kind):
            guard ChallengeBuffKind.allCases.contains(kind),next.rewardRoll==kind else{throw ChallengeFailure.invalidReward}
            next.teamBuffs=(next.teamBuffs ?? [])+[ChallengeTeamBuff(id:UUID().uuidString,kind:kind,remaining:3)]
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
    func purchase(_ item:ChallengeShopItem,targetID:String,moveIndex:Int?=nil)throws {
        guard var next=run,(item != .ppMoveRecovery || moveIndex != nil),next.canPurchase(item,targetID:targetID,moveIndex:moveIndex) else{throw ChallengeFailure.invalidReward}
        next.challengePoints=next.pointBalance-next.shopPrice(item)
        next.shopPurchaseCounts=next.shopPurchaseCounts ?? [:]
        next.shopPurchaseCounts?[item.rawValue,default:0]+=1
        let indices=item.teamWide ? Array(next.resources.indices):next.resources.indices.filter{next.resources[$0].id==targetID}
        for index in indices {
            let id=next.resources[index].id
            let maxHP=next.team.first{$0.id==id}!.stats["hp"]!
            item.apply(to:&next.resources[index],maxHP:maxHP,moveIndex:moveIndex)
        }
        try commit(next)
    }
    /// A rolled team buff is always available, so no reward can be deferred or skipped.
    func skipUnavailableReward(eligible:[DexEntry])throws {throw ChallengeFailure.invalidReward}
    func advance()throws {
        guard var next=run,next.phase == .intermission,next.encounterIndex+1<next.encounterCount else{throw ChallengeFailure.invalidState}
        next.encounterIndex+=1;next.phase = .ready
        try commit(next)
    }
    /// QA-only encounter traversal; preserve the current resources and never mark a victory.
    func skipEncounterForTesting()throws {
        guard var next=run,next.phase == .battling,
              next.encounterIndex+1<next.encounterCount else{throw ChallengeFailure.invalidState}
        next.teamBuffs=ChallengeTeamBuff.afterBattle(next.teamBuffs ?? [])
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
