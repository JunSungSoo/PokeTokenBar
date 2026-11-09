import SwiftUI

@MainActor struct ChallengeRootView:View {
    let model:ChallengeUIModel
    let battle:ChallengeBattleAdapter
    let audioSettings:BattleAudioSettings
    let auxiliary:BattleAuxiliaryState
    var allowsAudio=true
    var onClose:()->Void
    var onSurrender:()->Void
    var onMusic:()->Void
    var onShowField:()->Void
    var onShowStats:()->Void
    var onLayout:(BattleContentMeasurement)->Void
    var onState:()->Void
    @State private var editingItem:DexEntry?
    private var l:L {model.store.l}
    var body:some View {
        VStack(spacing:0) {
            if model.screen == .battle {
                BattleView(battle:battle,store:model.store,onSurrender:onSurrender,onMusic:onMusic,onPlayMusic:onState,
                    audioSettings:audioSettings,allowsEffectsAudio:allowsAudio,trainerIntro:model.intro,showsResultClose:false,
                    replayOpening:!model.resuming,musicActive:model.musicEnabled,challengeBuffSummary:model.buffSummary,auxiliaryState:auxiliary,
                    onShowField:onShowField,onShowStats:onShowStats,onClose:onClose,onLayout:onLayout,
                    onTestWin:model.session.testControlsEnabled ? {do{try model.session.winForTesting()}catch{model.report(error)}}:nil,
                    onTestNextTrainer:model.session.testControlsEnabled ? {model.nextTrainerForTesting()}:nil,
                    canTestNextTrainer:model.canTestNextTrainer,
                    onPlaybackBusy:{model.playbackBusyChanged($0)})
                    .id(model.run?.encounterIndex)
            } else if model.screen == .championReward {
                ChallengeShinyRewardView(model:model,onClose:onClose)
            } else {
                header
                if let text=model.buffSummary{Text(text).font(.caption).foregroundStyle(.orange).padding(.horizontal,16).padding(.bottom,8)}
                Divider()
                if model.screen == .result,let run=model.run,run.phase == .cleared {
                    ChallengeChampionView(runID:run.id,team:run.team,language:model.store.language,onClose:onClose)
                } else {
                    ScrollView {
                        VStack(alignment:.leading,spacing:16) {
                            switch model.screen {
                            case .setup:setup
                            case .preparation:preparation
                            case .resume:resume
                            case .loading:ProgressView(l.battlePreparing).frame(maxWidth:.infinity).padding(60)
                            case .reward:reward
                            case .result:result
                            case .battle,.championReward:EmptyView()
                            }
                        }.padding(20).frame(maxWidth:.infinity,alignment:.leading).reservesScrollerLane()
                    }
                }
            }
            if model.screen == .setup || model.screen == .reward || model.screen == .preparation {
                Divider()
                HStack {
                    if model.screen == .setup {
                        Text("\(model.selectedIDs.count)/6").monospacedDigit();Spacer()
                        if model.building {ProgressView().controlSize(.small)}
                        Button(l.challengeStart){Task{await model.start()}}.buttonStyle(.borderedProminent)
                            .disabled(model.selectedIDs.count != 6 || model.building || !model.save.canWrite).accessibilityIdentifier("challenge-start")
                    } else if model.screen == .preparation {
                        Button(l.challengeSaveExit){if model.savePreparation(){onClose()}}.disabled(!model.canStartPrepared)
                        Spacer()
                        Button(l.challengeStart){model.beginPreparedEncounter()}.buttonStyle(.borderedProminent)
                            .disabled(!model.canStartPrepared).accessibilityIdentifier("challenge-preparation-start")
                    } else {
                        Button(l.challengeSaveExit,action:onClose).disabled(![ChallengePhase.reward,.intermission].contains(model.run?.phase ?? .ready) || model.building)
                            .accessibilityIdentifier("challenge-save-exit")
                        Spacer()
                        Button(l.challengeNext){model.next()}.buttonStyle(.borderedProminent)
                            .disabled(model.run?.phase != .intermission || model.building).accessibilityIdentifier("challenge-next")
                    }
                }.padding(14)
            }
            if model.problem || model.session.error != nil || !model.save.canWrite {
                Text(l.challengeProblem).font(.caption).foregroundStyle(.red).padding(10)
                    .accessibilityIdentifier("challenge-error")
            }
        }
        .background(Color(nsColor:.windowBackgroundColor))
        .environment(\.locale,model.store.language.displayLocale)
        .sheet(item:$editingItem) { entry in
            BattleItemPicker(pokemon:entry,current:(model.preparing ? model.preparationItems:model.itemLoadout.items)[entry.id] ?? "",assignments:model.preparing ? model.preparationItems:model.itemLoadout.items,
                language:model.store.language,usage:model.itemUsage,onApply:{item in
                    guard model.preparing ? model.applyPreparedItem(item,to:entry.id):model.applyItem(item,to:entry.id) else{return false};editingItem=nil;return true
                },onCancel:{editingItem=nil})
        }
        .onAppear{model.synchronizeChampionAward()}
        .onChange(of:model.screen,initial:true){_,screen in
            if screen == .reward {model.configureRewardSelection()}
            if screen == .championReward {model.configureChampionReward()}
            onState()
        }
        .onChange(of:model.session.frame?.decisionID){_,_ in onState()}
        .onChange(of:model.session.presentation.pending){_,_ in onState()}
        .onChange(of:model.store.state.dex.map {"\($0.id)|\($0.isReleased)|\($0.finalID)|\($0.battleDefaultItem ?? "")"}){_,_ in model.reconcileSelection()}
    }
    private var header:some View {
        HStack {
            Label(l.challengeTitle,systemImage:"flag.checkered").font(.title2.bold())
            Spacer()
            if let run=model.run,model.screen != .setup {Text(l.challengeRound((model.preparing ? model.preparationOpponent?.index:run.encounterIndex).map{$0+1} ?? run.encounterIndex+1,run.encounterCount)).font(.callout.monospacedDigit())}
        }.padding(18)
    }
    private var setup:some View {
        VStack(alignment:.leading,spacing:14) {
            Text(l.challengeRules).font(.headline)
            Text(l.challengeSetupHint).font(.callout).foregroundStyle(.secondary)
            Text(l.battleDuplicateItem).font(.caption).foregroundStyle(.secondary)
            HStack {Text(l.battleRegisteredTeam).font(.headline);Spacer();Text("\(model.selectedIDs.count)/6").monospacedDigit()}
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
                ForEach(Array(model.selectedIDs.enumerated()),id:\.element){index,id in
                    if let entry=model.candidates.first(where:{$0.id==id}) {
                        VStack(spacing:5) {
                            HStack{Text(index==0 ? "LEAD":"\(index+1)").font(.caption2.bold());Spacer()}
                            SpriteView(speciesID:entry.finalID,size:55,shiny:entry.isShiny,form:entry.form).frame(height:60)
                            Text(name(entry.finalID)).font(.caption).lineLimit(1)
                            Button(BattleHeldItems.item(model.itemLoadout.items[id])?.name(model.store.language) ?? l.battleNoItem){editingItem=entry}
                                .font(.caption2).lineLimit(1).accessibilityIdentifier("challenge-item-\(id)")
                        }.padding(9).frame(maxWidth:.infinity).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
                    }
                }
            }
            Text(l.battleFinalOnly).font(.caption).foregroundStyle(.secondary)
            Text(l.battleDuplicateSpecies).font(.caption).foregroundStyle(.secondary)
            ForEach(model.candidates){entry in
                let selected=model.selectedIDs.contains(entry.id)
                let duplicate=BattleTeamBuilder.hasSelectedSpecies(entry,selectedIDs:model.selectedIDs,entries:model.candidates)
                Button{model.select(entry.id)}label:{
                    HStack {
                        Image(systemName:selected ? "checkmark.circle.fill":"circle")
                        SpriteView(speciesID:entry.finalID,size:32,shiny:entry.isShiny,form:entry.form)
                        ChallengePokemonLoadoutLabel(entry:entry,language:model.store.language)
                        Text("\(l.level) \(entry.profile?.level ?? 0)").font(.caption.monospacedDigit()).fixedSize()
                    }.padding(5).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(model.building || duplicate || (!selected && model.selectedIDs.count==6))
                    .accessibilityIdentifier("challenge-select-\(entry.id)")
            }
        }
    }
    private var preparation:some View {
        VStack(alignment:.leading,spacing:8) {
            if let encounter=model.preparationOpponent {
                HStack {
                    ChallengeTrainerSprite(key:ChallengeTrainerCatalog.key(encounter.id)).frame(width:36,height:44)
                    Text(ChallengeTrainerCatalog.name(encounter.id,language:model.store.language)).font(.headline)
                    Spacer()
                    Text(l.challengeRound(encounter.index+1,model.session.catalog.encounters.count)).font(.caption)
                }
            }
            Text(l.challengePreparationHint).font(.callout).foregroundStyle(.secondary)
            BattleTeamPreview(own:(model.run?.team ?? []).map(BattleRosterMember.init),
                opponent:(model.preparationOpponent?.team ?? []).map(BattleRosterMember.init),
                selected:model.preparationOrder,mode:.singles,language:model.store.language,enabled:!model.building,
                onSelect:{model.selectPrepared($0)},selectionLimit:6)
            Text("\(model.preparationOrder.count)/6").font(.caption.monospacedDigit())
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
                ForEach(model.run?.team ?? []){p in
                    if let entry=model.preparationEntries.first(where:{$0.id==p.id}) {
                        VStack(spacing:4) {
                            Text(name(p.speciesID)).font(.caption.bold()).lineLimit(1)
                            if let r=model.run?.resources.first(where:{$0.id==p.id}) {
                                Text("HP \(r.hp)/\(p.stats["hp"] ?? 0) · PP \(r.moves.reduce(0){$0+$1.pp})/\(r.moves.reduce(0){$0+$1.maxPP})").font(.caption2.monospacedDigit())
                            }
                            Button(BattleHeldItems.item(model.preparationItems[p.id])?.name(model.store.language) ?? l.battleNoItem){editingItem=entry}
                                .font(.caption).accessibilityIdentifier("challenge-preparation-item-\(p.id)")
                        }.padding(7).frame(maxWidth:.infinity).background(.quaternary,in:RoundedRectangle(cornerRadius:6))
                    }
                }
            }
            Text(l.battleDuplicateItem).font(.caption).foregroundStyle(.secondary)
        }.accessibilityIdentifier("challenge-preparation")
    }
    private var resume:some View {
        VStack(alignment:.leading,spacing:16) {
            opponent
            Text(l.challengeSaved).foregroundStyle(.secondary)
            roster(selectable:false)
            HStack {
                Button(l.challengeResume){model.resume()}.buttonStyle(.borderedProminent).disabled(!model.save.canWrite)
                    .accessibilityIdentifier("challenge-resume")
                Spacer();Button(l.quit,action:onClose)
            }
        }
    }
    private var opponent:some View {
        HStack(spacing:20) {
            if let encounter=model.encounter {
                ChallengeTrainerSprite(key:ChallengeTrainerCatalog.key(encounter.id)).frame(width:90,height:110)
                Text(ChallengeTrainerCatalog.name(encounter.id,language:model.store.language)).font(.title2.bold())
            }
            Spacer()
        }
    }
    private var reward:some View {
        VStack(alignment:.leading,spacing:16) {
            opponent
            ChallengeShopView(model:model)
            Divider()
            if model.run?.phase == .reward {
                Text(l.challengeReward).font(.headline)
                VStack(alignment:.leading,spacing:8) {
                    ForEach(model.rewardOptions,id:\.self){kind in
                        Button{model.selectReward(kind)}label:{Label(rewardTitle(kind),systemImage:model.rewardKind==kind ? "largecircle.fill.circle":"circle")}
                            .buttonStyle(.plain).accessibilityIdentifier("challenge-reward-\(kind.rawValue)")
                    }
                }
                if model.rewardKind == .replace {Text(l.challengeReplaceHint).font(.caption).foregroundStyle(.secondary);Text(l.challengeOutgoing).font(.headline)}
                if model.rewardKind != .points {
                    roster(selectable:model.rewardKind != .allHeal && model.rewardKind != .buff)
                }
                if model.rewardKind == .pp,model.run?.enhancedReward != true,let resource=model.run?.resources.first(where:{$0.id==model.rewardPokemonID}) {
                    VStack(alignment:.leading,spacing:6) {
                        ForEach(Array(resource.moves.enumerated()),id:\.offset){index,move in
                            Button{model.rewardMove=index}label:{
                                HStack {
                                    Image(systemName:model.rewardMove==index ? "checkmark.circle.fill":"circle")
                                    Text(BattleTextCatalog.shared.moveName(move.id,language:model.store.language))
                                    Spacer();Text("PP \(move.pp)/\(move.maxPP)").monospacedDigit()
                                }.padding(7).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(BattleTextCatalog.shared.moveTooltip(move.id,language:model.store.language))
                                .accessibilityIdentifier("challenge-pp-\(index)")
                        }
                    }
                }
                if model.rewardKind == .replace {
                    Text(l.challengeIncoming).font(.headline)
                    ForEach(model.replacements){entry in
                        Button{model.incomingID=entry.id}label:{
                            HStack {
                                Image(systemName:model.incomingID==entry.id ? "checkmark.circle.fill":"circle")
                                SpriteView(speciesID:entry.finalID,size:32,shiny:entry.isShiny,form:entry.form)
                                ChallengePokemonLoadoutLabel(entry:entry,language:model.store.language)
                                Text("\(l.level) \(entry.profile?.level ?? 0)").font(.caption.monospacedDigit()).fixedSize()
                            }.padding(5).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("challenge-incoming-\(entry.id)")
                    }
                }
                HStack {
                    Button(l.challengeApplyReward){Task{await model.applyReward()}}.buttonStyle(.borderedProminent)
                        .disabled(!model.canApplyReward).accessibilityIdentifier("challenge-apply-reward")
                    if model.building{ProgressView().controlSize(.small)}
                }
            } else {
                Label(l.challengeRewardDone,systemImage:"checkmark.seal.fill").foregroundStyle(.green)
                roster(selectable:false)
            }

        }
    }
    private var result:some View {
        VStack(alignment:.leading,spacing:20) {
            Label(model.run?.phase == .cleared ? l.challengeCleared:l.challengeLost,systemImage:model.run?.phase == .cleared ? "trophy.fill":"flag.checkered")
                .font(.title2.bold())
            opponent
            if let run=model.run,let amount=model.store.state.challengeCashClaims?[run.id],amount>0 {
                Text(l.challengeCashAward(amount/1_000_000)).foregroundStyle(.green).bold()
                    .accessibilityIdentifier("challenge-cash-award")
            }
            roster(selectable:false)
            HStack{Button(l.challengeNew){model.newChallenge()}.buttonStyle(.borderedProminent);Spacer();Button(l.quit,action:onClose)}
        }
    }
    private func roster(selectable:Bool)->some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
            ForEach(model.run?.team ?? []){pokemon in
                let resource=model.run?.resources.first{$0.id==pokemon.id}
                Button{if selectable{model.rewardPokemonID=pokemon.id;model.rewardMove=0}}label:{
                    VStack(spacing:5) {
                        SpriteView(speciesID:pokemon.speciesID,size:48,shiny:pokemon.shiny,form:pokemon.form).frame(height:50)
                        Text(name(pokemon.speciesID)).font(.caption).lineLimit(1)
                        Text("HP \(resource?.hp ?? 0)/\(pokemon.stats["hp"] ?? 0)").font(.caption.monospacedDigit())
                        if let resource{Text("PP \(resource.moves.reduce(0){$0+$1.pp})/\(resource.moves.reduce(0){$0+$1.maxPP})").font(.caption2.monospacedDigit())}
                        if let resource,!resource.status.isEmpty{Text(l.battleStatus(resource.status)).font(.caption2).foregroundStyle(.secondary)}
                    }.padding(8).frame(maxWidth:.infinity)
                        .background(selectable && model.rewardPokemonID==pokemon.id ? Color.accentColor.opacity(0.16):Color.secondary.opacity(0.07),in:RoundedRectangle(cornerRadius:8))
                        .overlay(RoundedRectangle(cornerRadius:8).stroke(selectable && model.rewardPokemonID==pokemon.id ? Color.accentColor:Color.clear,lineWidth:2))
                }.buttonStyle(.plain).disabled(!selectable || model.building).accessibilityIdentifier("challenge-member-\(pokemon.id)")
            }
        }
    }
    private func name(_ id:Int)->String{BattleTextCatalog.shared.speciesName(id,language:model.store.language)}
    private func rewardTitle(_ kind:ChallengeRewardKind)->String {
        switch kind {
        case .heal:model.run?.enhancedReward == true ? l.challengeHealFull:l.challengeHeal
        case .pp:model.run?.enhancedReward == true ? l.challengePPFull:l.challengePP
        case .replace:l.challengeReplace
        case .allHeal:l.challengeAllHeal
        case .buff:l.challengeBuffReward(model.run?.rewardRoll ?? .attack)+" · "+l.challengeBuffDuration
        case .points:"+" + l.challengePoints(ChallengeRun.rewardPoints)
        }
    }
}
