import Foundation
import Observation

@MainActor @Observable final class ChallengeActivity {static let shared=ChallengeActivity();var isOpen=false}
enum ChallengeRewardKind:String,CaseIterable {case heal,pp,replace}
enum ChallengeScreen {case setup,resume,loading,battle,reward,result,championReward}

@MainActor @Observable final class ChallengeUIModel {
    let store:CompanionStore
    let session:ChallengeBattleSession
    let intro=ChallengeTrainerIntro()
    let itemMemory:BattlePokemonItemStore
    let itemUsage:BattleItemUsageStore
    let provider:any PokemonDetailProviding
    private(set) var selectedIDs:[String]=[]
    private(set) var itemLoadout=BattleItemLoadout()
    private var overrides:[String:String]=[:]
    private(set) var building=false
    private(set) var running=false
    private(set) var sceneSettled=false
    private(set) var resuming=false
    var shinyRewardSelection=""
    var effectsBusy=false
    var isOpen=false
    var newSetup=false
    var musicEnabled=true
    var problem=false
    var rewardKind:ChallengeRewardKind = .heal
    var rewardPokemonID=""
    var rewardMove=0
    var incomingID=""
    init(store:CompanionStore,session:ChallengeBattleSession,provider:any PokemonDetailProviding=PokeAPIClient.shared,
         itemMemory:BattlePokemonItemStore = .shared,itemUsage:BattleItemUsageStore = .shared) {
        self.store=store;self.session=session;self.provider=provider;self.itemMemory=itemMemory;self.itemUsage=itemUsage
    }
    var save:ChallengeRunStore {session.save}
    var run:ChallengeRun? {save.run}
    var candidates:[DexEntry] {BattleTeamBuilder.storedCandidates(store.state.dex).filter{BattleTeamBuilder.isSpeciesEligible($0.finalID)}}
    var replacements:[DexEntry] {
        guard let run else{return []}
        return candidates.filter{p in !run.retiredIDs.contains(p.id) && !run.team.contains(where:{$0.id==p.id || $0.speciesID==p.finalID})}
    }
    var encounter:ChallengeEncounterCatalog.Encounter? {run.flatMap{session.catalog.encounters.indices.contains($0.encounterIndex) ? session.catalog.encounters[$0.encounterIndex]:nil}}
    var screen:ChallengeScreen {
        if newSetup || run==nil {return .setup}
        guard let run else{return .setup}
        if run.phase == .cleared,let reward=run.championReward {
            if !reward.claimed{return .championReward}
            if !running{return .setup}
        }
        if running && session.error==nil {
            if session.frame==nil{return .loading}
            if run.phase == .battling || (!sceneSettled && session.frame?.ended==true){return .battle}
        }
        switch run.phase {
        case .ready,.battling:return .resume
        case .reward,.intermission:return .reward
        case .lost,.cleared:return .result
        }
    }
    func select(_ id:String) {
        guard !building,let p=candidates.first(where:{$0.id==id}) else{return}
        if selectedIDs.contains(id){selectedIDs.removeAll{$0==id}}
        else if selectedIDs.count<6 && !BattleTeamBuilder.hasSelectedSpecies(p,selectedIDs:selectedIDs,entries:candidates){selectedIDs.append(id)}
        restoreItems()
    }
    func reconcileSelection(){selectedIDs.removeAll{id in !candidates.contains{$0.id==id}};restoreItems()}
    func restoreItems(){itemLoadout.restore(roster:selectedIDs.compactMap{id in candidates.first{$0.id==id}},remembered:itemMemory.items,overrides:overrides)}
    func applyItem(_ item:String,to id:String)->Bool {
        guard !building,let entry=candidates.first(where:{$0.id==id}),itemLoadout.apply(item,to:entry,roster:selectedIDs) else{return false}
        overrides[id]=item;itemMemory.recordApplied(item,to:entry);itemUsage.recordApplied(item);restoreItems();return true
    }
    func start()async {
        guard !building,selectedIDs.count==6,save.canWrite else{return}
        building=true;problem=false;defer{building=false}
        let ids=selectedIDs,items=itemLoadout.items
        do {
            let team=try await BattleTeamBuilder.build(ids:ids,entries:candidates,mode:.singles,language:store.language,provider:provider,heldItems:items)
            guard isOpen,selectedIDs==ids,itemLoadout.items==items,ids.allSatisfy({id in candidates.contains{$0.id==id}}) else{return}
            try session.start(team:team);newSetup=false;running=true;sceneSettled=false;resuming=false
            if let encounter {intro.reset(encounter:encounter.id)}
        } catch {report(error)}
    }
    func resume() {
        problem=false;sceneSettled=false;resuming=true;intro.finish()
        do {
            if run?.phase == .ready {try session.startEncounter();resuming=false;if let encounter{intro.reset(encounter:encounter.id)}}
            else if run?.phase == .battling {try session.resume()}
            else {sceneSettled=true}
            running=true
        } catch {running=false;report(error)}
    }
    func next() {
        guard run?.phase == .intermission,!building else{return}
        problem=false
        do {try session.startEncounter();running=true;sceneSettled=false;resuming=false;if let encounter{intro.reset(encounter:encounter.id)}}
        catch {report(error)}
    }
    var canTestNextTrainer:Bool {
        session.testControlsEnabled && !building && !effectsBusy && run.map{$0.encounterIndex+1<$0.encounterCount} == true
    }
    func nextTrainerForTesting() {
        guard canTestNextTrainer else{return}
        problem=false
        do {
            try session.nextTrainerForTesting()
            running=true;sceneSettled=false;resuming=false
            if let encounter{intro.reset(encounter:encounter.id)}
        }catch{report(error)}
    }
    func didFinishPresentation(){
        session.completePresentation()
        if session.frame?.ended==true {sceneSettled=true;synchronizeChampionAward()}
    }
    func synchronizeChampionAward(){
        guard let run,run.phase == .cleared else{return}
        do{try store.markChallengeChampions(ids:Set(run.team.map(\.id)))}catch{report(error)}
    }
    func runningDidEnd(){running=false;sceneSettled=true;intro.finish()}
    func close(){isOpen=false;running=false;intro.finish();session.stop();sceneSettled=true}
    func newChallenge(){guard run?.phase == .lost || (run?.phase == .cleared && run?.championReward?.claimed==true) else{return};newSetup=true;selectedIDs=[];overrides=[:];restoreItems()}
    var canClaimChampionShiny:Bool {
        guard let run,run.phase == .cleared,run.championReward?.claimed==false,!building else{return false}
        if let id=run.championReward?.recipientID,store.state.challengeShinyClaims?[run.id]==id{return true}
        return store.championShinyTargets.contains{$0.id==shinyRewardSelection}
    }
    func offerChampionReward()throws {
        try save.offerChampionReward();session.stop();runningDidEnd();configureChampionReward()
    }
    func configureChampionReward(){
        if !store.championShinyTargets.contains(where:{$0.id==shinyRewardSelection}) {
            let pending=run?.championReward?.recipientID ?? ""
            shinyRewardSelection=store.championShinyTargets.contains{$0.id==pending} ? pending:""
        }
    }
    @discardableResult func claimChampionShiny()->Bool {
        guard canClaimChampionShiny,let run else{return false}
        building=true;problem=false;defer{building=false}
        do {
            // After a crash between files, use the collection's already-committed claim.
            if let recipient=store.state.challengeShinyClaims?[run.id] {
                guard run.championReward?.recipientID==recipient else{throw ChallengeFailure.invalidReward}
            } else {
                try save.prepareChampionShinyReward(recipientID:shinyRewardSelection)
                try store.claimChallengeShiny(runID:run.id,entryID:shinyRewardSelection)
            }
            try save.finishChampionShinyReward();newChallenge();return true
        } catch{report(error);return false}
    }
    func selectReward(_ kind:ChallengeRewardKind){rewardKind=kind;rewardMove=0;configureRewardSelection()}
    func configureRewardSelection() {
        guard let run else{return}
        if !run.team.contains(where:{$0.id==rewardPokemonID}){rewardPokemonID=run.team[0].id}
        if rewardKind == .heal,let first=run.resources.first(where:{r in r.hp < (run.team.first{$0.id==r.id}?.stats["hp"] ?? 0)}) {rewardPokemonID=first.id}
        if rewardKind == .pp,let first=run.resources.first(where:{$0.moves.contains{$0.pp<$0.maxPP}}) {rewardPokemonID=first.id;rewardMove=first.moves.firstIndex(where:{$0.pp<$0.maxPP}) ?? 0}
        if !replacements.contains(where:{$0.id==incomingID}){incomingID=replacements.first?.id ?? ""}
    }
    var canApplyReward:Bool {
        guard run?.phase == .reward,!building,let r=run?.resources.first(where:{$0.id==rewardPokemonID}) else{return false}
        switch rewardKind {
        case .heal:return r.hp < (run?.team.first{$0.id==r.id}?.stats["hp"] ?? 0)
        case .pp:return r.moves.indices.contains(rewardMove) && r.moves[rewardMove].pp<r.moves[rewardMove].maxPP
        case .replace:return replacements.contains{$0.id==incomingID}
        }
    }
    var noRewardAvailable:Bool {
        guard let run,run.phase == .reward else{return false}
        return replacements.isEmpty && run.resources.allSatisfy{r in r.hp==run.team.first{$0.id==r.id}?.stats["hp"] && r.moves.allSatisfy{$0.pp==$0.maxPP}}
    }
    func applyReward()async {
        guard canApplyReward else{return};problem=false;building=true;defer{building=false}
        do {
            let outgoing=rewardPokemonID
            switch rewardKind {
            case .heal:try session.applyReward(.heal(outgoing))
            case .pp:try session.applyReward(.pp(outgoing,rewardMove))
            case .replace:
                let id=incomingID,runID=run?.id,index=run?.encounterIndex
                let p=try await BattleTeamBuilder.buildIndividual(id:id,entries:replacements,language:store.language,provider:provider)
                guard isOpen,run?.id==runID,run?.encounterIndex==index,run?.phase == .reward,replacements.contains(where:{$0.id==id}) else{return}
                try session.applyReward(.replace(outgoing,p),eligible:candidates)
            }
        } catch {report(error)}
    }
    func skipReward(){do{try save.skipUnavailableReward(eligible:candidates)}catch{report(error)}}
    func report(_ error:Error){problem=true;AppLog.write("challenge operation failed: \(error)")}
}

@MainActor @Observable final class ChallengeBattleAdapter:BattleSessionPresentation {
    let model:ChallengeUIModel
    let identity:BattleIdentity
    init(model:ChallengeUIModel,identity:BattleIdentity){self.model=model;self.identity=identity}
    var opponent:BattleIdentity? {model.encounter.map{BattleIdentity(nickname:ChallengeTrainerCatalog.name($0.id,language:model.store.language),code:$0.id,nonce:$0.id)}}
    var presentation:BattleScenePlayback {model.session.presentation}
    var frame:BattleFrame? {model.session.frame}
    var phase:BattleCoordinator.Phase {frame==nil ? .preparing:frame?.ended==true ? .ended:.playing}
    var mode:BattleMode {.singles}
    var arena:BattleArena {BattleArena.forChallenge(encounterID:model.encounter?.id,roster:opponentRoster)}
    var registeredTeam:[BattlePokemon] {model.run?.team ?? []}
    var opponentRoster:[BattleRosterMember] {model.encounter?.team.map(BattleRosterMember.init) ?? []}
    var decisionDeadline:Date? {nil}
    var submitted:Bool {model.session.submitted || model.intro.active}
    var outcome:String? {guard frame?.ended==true else{return nil};return frame?.winner==0 ? "win":"loss"}
    var error:String? {model.session.error==nil && !model.problem ? nil:model.store.l.challengeProblem}
    var isHost:Bool {true}
    var isChallenge:Bool {true}
    func choose(_ decision:BattleDecision){do{try model.session.choose(decision)}catch{model.report(error)}}
    func completePresentation(){model.didFinishPresentation()}
    func connectManual(_ code:String){} // Only rendered for peer .reconnecting, which this adapter never enters.
}
