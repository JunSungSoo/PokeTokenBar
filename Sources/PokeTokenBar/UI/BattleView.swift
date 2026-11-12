import SwiftUI

@MainActor
struct BattleView: View {
    let battle: any BattleSessionPresentation
    let store: CompanionStore
    var onSurrender: () -> Void
    var onMusic: () -> Void
    var onPlayMusic: () -> Void
    var audioSettings: BattleAudioSettings? = nil
    var allowsEffectsAudio = true
    var trainerIntro:ChallengeTrainerIntro? = nil
    var showsResultClose=true
    var replayOpening=true
    var musicActive:Bool? = nil
    var challengeBuffSummary:String? = nil
    var auxiliaryState: BattleAuxiliaryState? = nil
    var onShowField: () -> Void = {}
    var onShowStats: () -> Void = {}
    var onClose: () -> Void = {}
    var onLayout: (BattleContentMeasurement) -> Void = { _ in }
    var onTestWin:(()->Void)? = nil
    var onTestNextTrainer:(()->Void)? = nil
    var canTestNextTrainer=true
    var onPlaybackBusy:(Bool)->Void = {_ in}
    @State private var layoutWidth: CGFloat = BattleWindowLayout.preferredWidth(for: .singles)
    @State private var choices: [Int: BattleAction] = [:]
    @State private var editingSlot = 0
    @State private var megaSelection=BattleMegaSelection()
    @State private var musicEnabled = true
    @State private var effectsBusy = false
    @State private var roguePlayer=PokeRogueBattlePlayer()
    @State private var effectPlayback: BattleEffectPlayback?
    @State private var reconnectCode = ""
    @State private var turnLog = BattleTurnLog()
    @State var turnLogExpanded = false
    private var l: L { store.l }

    var body: some View {
        VStack(spacing: 0) {
            header.measureBattleContent("header")
            Divider()
            if let frame = battle.presentation.frame ?? battle.frame {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        battlefield(frame).measureBattleContent("battlefield")
                        HStack(spacing: 8) {
                            ForEach(frame.own) { member in
                                HStack(spacing: 4) {
                                    Circle().fill(member.fainted ? Color.gray : Color.green).frame(width: 7,height: 7)
                                    Text(BattleTextCatalog.shared.speciesName(member.speciesID,language:store.state.language)).font(.caption2).lineLimit(1)
                                }.opacity(member.fainted ? 0.4 : 1)
                            }
                        }.measureBattleContent("roster")
                        if let outcome = battle.outcome, !battle.presentation.pending, !effectsBusy {
                            Text(l.battleResult(outcome)).font(.largeTitle.bold()).padding()
                        } else if battle.phase == .reconnecting {
                            VStack {
                                Text(l.battleReconnecting).foregroundStyle(.orange)
                                HStack {
                                    TextField(l.tradeManualEnterCode, text: $reconnectCode)
                                    Button(l.tradeManualConnect) { battle.connectManual(reconnectCode) }
                                }.frame(maxWidth: 360)
                            }.padding()
                        } else {
                            commands(frame, detailWidth: max(300, min(420, layoutWidth * 0.45)))
                                .measureBattleContent("commands")
                        }
                        BattleTurnLogView(log:turnLog,language:store.language,ownPlayer:battle.isHost ? 0 : 1,expanded:$turnLogExpanded).measureBattleContent("turn-log")
                        if roguePlayer.error != nil{Text(l.battleEffectsUnavailable).font(.caption).foregroundStyle(.orange)}
                        if let error = battle.error { Text(l.battleUserError(error)).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    }.padding(.horizontal, 12).padding(.top, 5)
                        .frame(maxWidth: .infinity, alignment: .top)
                    Divider().measureBattleContent("footer")
                    if showsResultClose && battle.outcome != nil && !battle.presentation.pending && !effectsBusy {
                        HStack { Spacer(); Button(l.quit, action:onClose)
                            .accessibilityIdentifier("battle-close-result") }
                            .padding(.horizontal,18).padding(.vertical,8)
                    }
                    if !frame.preview && !frame.ended && (battle.phase == .playing || battle.presentation.pending) {
                        HStack { Spacer(); submitButton(frame) }.padding(.horizontal,18).padding(.vertical,8)
                        Divider()
                    }
                }
                .onChange(of: frame.log, initial: true) { _, _ in turnLog.receive(frame) }
                .onChange(of: frame.logOffset) { _, _ in turnLog.receive(frame) }
                .onChange(of: frame.decisionID, initial: true) { _, _ in
                    choices = [:]; editingSlot = 0; megaSelection=BattleMegaSelection()
                    for slot in frame.slots where slot.canPass { choices[slot.slot] = .pass }
                }
            } else {
                Spacer()
                if let error = battle.error { Text(l.battleUserError(error)).foregroundStyle(.red).padding() }
                else { ProgressView(l.battlePreparing) }
                Spacer()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .measureBattleContent("content")
        .coordinateSpace(name: "battle-content")
        .onPreferenceChange(BattleContentBoundsKey.self) { regions in
            guard let content = regions["content"], content.width > 0, content.height > 0 else { return }
            if abs(layoutWidth - content.width) > 0.5 { layoutWidth = content.width }
            onLayout(BattleContentMeasurement(content: content, commands: regions["commands"], footer: regions["footer"], header:regions["header"],battlefield:regions["battlefield"],battlers:regions["battlers"],roster:regions["roster"],commandTitle:regions["command-title"],turnLog:regions["turn-log"]))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale,store.state.language.displayLocale)
        .onChange(of: audioSettings?.effectsVolume, initial: true) { _, volume in
            roguePlayer.setEffectsVolume(allowsEffectsAudio ? (volume ?? 0) : 0)
        }
        .onChange(of:effectsBusy,initial:true){_,busy in onPlaybackBusy(busy)}
        .onAppear { battle.completePresentation() }
        .onDisappear{roguePlayer.stop()}
        .onChange(of:battle.frame == nil){_,empty in if empty{roguePlayer.stop();turnLog=BattleTurnLog();turnLogExpanded=false}}
        .onChange(of: battle.phase, initial: true) { _, phase in if phase == .playing { onPlayMusic() } }
    }
    private var header: some View {
        VStack(spacing: 8) {
        HStack(spacing: 14) {
            Image(systemName: "bolt.shield.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(battle.identity.nickname)  ×  \(battle.opponent?.nickname ?? "…")").font(.headline)
                Text(battle.isChallenge ? l.challengeRules(battle.mode):l.battleRules).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(battle.isChallenge ? l.challengeMode(battle.mode):(battle.mode == .singles ? l.battleSingles:l.battleDoubles)).font(.callout)
            if let deadline = battle.decisionDeadline { Text(timerInterval: Date()...max(Date(), deadline), countsDown: true).font(.caption.monospacedDigit()).frame(width: 45) }
            if let frame = battle.presentation.frame ?? battle.frame { Text("\(frame.turn)").font(.title2.monospacedDigit()).accessibilityLabel(l.battleTurn(frame.turn)) }
            Button { if musicActive == nil {musicEnabled.toggle()}; onMusic() } label: {
                Image(systemName: (musicActive ?? musicEnabled) ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }.help(l.battleMusic).accessibilityLabel(l.battleMusic)
            if let audioSettings { BattleVolumeControl(settings:audioSettings,label:l.battleVolume,effectsLabel:l.battleEffectsVolume) }
        }
        if battle.isChallenge, battle.frame?.ended == false {
            Button(l.battleSurrender, action: onSurrender)
                .accessibilityIdentifier("challenge-battle-surrender")
        }
        if let challengeBuffSummary {
            Text(challengeBuffSummary).font(.caption).foregroundStyle(.orange).accessibilityIdentifier("challenge-team-buffs")
        }
        if let onTestWin {
            HStack {
                Spacer()
                Button(l.challengeTestWin,action:onTestWin).accessibilityIdentifier("challenge-test-win")
                if let onTestNextTrainer {
                    Button(l.challengeTestNextTrainer,action:onTestNextTrainer)
                        .disabled(!canTestNextTrainer).accessibilityIdentifier("challenge-test-next-trainer")
                }
            }.disabled(effectsBusy || battle.submitted || battle.presentation.pending || battle.frame?.ended != false)
        }
        if let auxiliaryState, !auxiliaryState.fieldVisible || !auxiliaryState.statsVisible {
            HStack {
                Spacer()
                if !auxiliaryState.fieldVisible {
                    Button(l.battleFieldWindow, systemImage: "cloud.sun", action: onShowField)
                        .accessibilityIdentifier("battle-show-field")
                }
                if !auxiliaryState.statsVisible {
                    Button(l.battleStatsWindow, systemImage: "chart.bar", action: onShowStats)
                        .accessibilityIdentifier("battle-show-stats")
                }
            }
        }
        }.padding(12)
    }
    private func battlefield(_ frame: BattleFrame) -> some View {
        let ownParty = BattlePartyStatus(selected: frame.own.count, fainted: frame.own.filter(\.fainted).count)
        return ZStack {
            VStack(spacing: BattleSpriteSizing.battlefieldRowSpacing) {
                battleSide(frame.foe, own: false, party: frame.foeTeamStatus)
                    .opacity(trainerIntro?.active == true ? 0 : 1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                battleSide(frame.own.filter(\.active), own: true, party: ownParty)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, battle.mode == .doubles ? 8 : 18)
            .measureBattleContent("battlers")
            .padding(.top, BattleSpriteSizing.battlefieldTopInset)
            if frame.preview { Image(systemName:"bolt.shield").font(.system(size:50)).foregroundStyle(.black.opacity(0.3)) }
        }
        .fixedSize(horizontal:false,vertical:true)
        .frame(height: BattleSpriteSizing.battlefieldHeight(for: battle.mode), alignment: .top)
        .modifier(PokeRogueBattlefieldLayers(player:roguePlayer,arena:battle.arena))
        .overlay(alignment:.topTrailing) {
            if let trainerIntro,trainerIntro.active {
                ChallengeTrainerSprite(key:trainerIntro.key).frame(width:140,height:170)
                    .offset(x:trainerIntro.exiting ? 230:0).opacity(trainerIntro.exiting ? 0:1)
                    .padding(.trailing,32).padding(.top,30).allowsHitTesting(false)
            }
        }
        .overlayPreferenceValue(BattleSpriteAnchorKey.self) { anchors in
            GeometryReader { geometry in
                let latest = battle.frame ?? frame
                let presentation = BattlePresentationEvents(frame: latest, language: store.language, ownPlayer: battle.isHost ? 0 : 1)
                BattleEffectsLayer(events:presentation.events,rects:anchors.mapValues { geometry[$0] },busy:$effectsBusy,playback:$effectPlayback,messages:trainerIntro?.openingMessages(events:presentation.events,messages:presentation.messages,language:store.language,enabled:replayOpening && latest.turn<=1) ?? presentation.messages,presentOpeningAbilities:replayOpening && latest.turn <= 1,
                    scenes:Dictionary(uniqueKeysWithValues:(latest.scenes ?? []).map { ($0.id,$0) }),
                    onScene:{ battle.presentation.apply($0) },onFinished:{ battle.completePresentation() },onAnimatedScene:{ await battle.presentation.animate($0) },originalPlayer:roguePlayer,
                    actors:renderActors(frame,rects:anchors.mapValues{geometry[$0]}),viewport:geometry.size,
                    beforeEvent:{event in await trainerIntro?.before(event)},
                    hideActor:{position in trainerIntro?.active == true && !position.own},completionToken:latest.decisionID,battleMode:battle.mode)
            }.allowsHitTesting(false)
        }.clipShape(RoundedRectangle(cornerRadius:8))
    }

    private func renderActors(_ frame:BattleFrame,rects:[String:CGRect])->[PokeRogueActor]{
        var result:[PokeRogueActor]=[]
        for own in [true,false]{
            let members=own ? frame.own.filter(\.active):frame.foe
            for (slot,pokemon) in members.enumerated(){
                let position=BattleEffectPosition(own:own,slot:slot)
                if let rect=rects[position.key]{result.append(PokeRogueActor(pokemon:pokemon,position:position,rect:rect,pixelScale:spriteSizing.pixelScale))}
            }
        }
        return result
    }
    @ViewBuilder
    private func battleSide(_ members: [BattleCombatant], own: Bool, party: BattlePartyStatus?) -> some View {
        if battle.mode == .doubles {
            HStack(alignment: .center, spacing: 0) {
                if own {
                    pairedSprites(members, own: true)
                    Spacer(minLength: 14)
                }
                VStack(spacing: 4) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { slot, pokemon in
                        combatantCard(pokemon, own: own, slot: slot, party: party)
                    }
                }
                if !own {
                    Spacer(minLength: 14)
                    pairedSprites(members, own: false)
                }
            }
        } else {
            ForEach(Array(members.enumerated()), id: \.element.id) { slot, pokemon in
                HStack(alignment: own ? .center : .top, spacing: 4) {
                    if own { battleSprite(pokemon, own: true, slot: slot, sizing: spriteSizing).opacity(pokemon.fainted ? 0.35 : 1) }
                    combatantCard(pokemon, own: own, slot: slot, party: party)
                    if !own { battleSprite(pokemon, own: false, slot: slot, sizing: spriteSizing).opacity(pokemon.fainted ? 0.35 : 1) }
                }
            }
        }
    }

    private func pairedSprites(_ members: [BattleCombatant], own: Bool) -> some View {
        let sizing = spriteSizing
        let widths = members.map {
            PokeRogueSpriteSizes.shared.battleSize(speciesID: $0.speciesID, form: $0.form, back: own).width * sizing.pixelScale
        }
        let layout = BattlePairGroundLayout(widths: widths, living: members.map { !$0.fainted }, stageWidth: sizing.stageWidth)
        return HStack(spacing: layout.spacing) {
            ForEach(Array(members.enumerated()), id: \.element.id) { slot, pokemon in
                battleSprite(pokemon, own: own, slot: slot, sizing: sizing, showsGround: false)
                    .opacity(pokemon.fainted ? 0 : 1)
            }
        }
        .background(alignment: .bottom) {
            if let ground = layout.ground {
                BattleGroundSurface(size: ground.size)
                    .offset(x: ground.midX - layout.width / 2)
            }
        }
    }

    private var targetSelection: (slot: Int, action: BattleAction, move: BattleMove)? {
        guard !battle.submitted, !effectsBusy, !battle.presentation.pending,
              let frame = battle.presentation.frame ?? battle.frame, !frame.waiting,
              let slot = frame.slots.first(where: { $0.slot == editingSlot }),
              let action = choices[slot.slot], action.kind == "move",
              let move = slot.moves.first(where: { $0.index == action.index }), move.targetRequired else { return nil }
        return (slot.slot, action, move)
    }

    @ViewBuilder
    private func combatantCard(_ pokemon: BattleCombatant, own: Bool, slot: Int, party: BattlePartyStatus?) -> some View {
        let location = own ? -(slot + 1) : slot + 1
        if let selection = targetSelection, selection.move.targets.contains(where: { $0.location == location }) {
            Button {
                choices[selection.slot] = BattleAction(kind: "move", index: selection.action.index, target: location)
            } label: {
                healthCard(pokemon, own: own, slot: slot, party: party)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.5), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("battle-target-\(selection.slot)-\(location)")
            .accessibilityLabel(l.battleTarget + ": " + l.battleChoiceTarget(location, own: (battle.presentation.frame ?? battle.frame)?.own ?? [], foe: (battle.presentation.frame ?? battle.frame)?.foe ?? []))
            .accessibilityValue(selection.action.target == location ? l.battleSelected : "")
            .help(l.battleTarget)
        } else {
            healthCard(pokemon, own: own, slot: slot, party: party)
                .opacity(targetSelection == nil ? 1 : 0.55)
        }
    }

    private func healthCard(_ pokemon: BattleCombatant, own: Bool, slot: Int, party: BattlePartyStatus?) -> some View {
        let compact = battle.mode == .doubles
        return VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            HStack {
                Text(pokemon.mega == true ? BattleTextCatalog.shared.pokemonName(pokemon.name,language:store.language):BattleTextCatalog.shared.speciesName(pokemon.speciesID,language:store.language)).font(compact ? .subheadline.bold() : .headline).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(l.level) \(pokemon.level)").font(.caption.monospacedDigit())
            }
            if own, !compact, let item=BattleHeldItems.item(pokemon.item) {
                Text(item.name(store.language)).font(.caption2).lineLimit(1).foregroundStyle(.secondary).help(item.tooltip(store.language))
            }
            HStack(spacing: 5) {
                Text(l.battleHP).font(.caption2.bold()).foregroundStyle(.orange)
                GeometryReader { geometry in
                    Capsule().fill(.black.opacity(0.18)).overlay(alignment:.leading) {
                        Capsule().fill(pokemon.hp * 4 <= pokemon.maxHP ? Color.red : pokemon.hp * 2 <= pokemon.maxHP ? Color.orange : Color.green)
                            .frame(width: geometry.size.width * max(0,min(1,Double(pokemon.hp)/Double(max(1,pokemon.maxHP)))))
                    }
                }.frame(height: 8)
            }
            HStack(spacing: 4) {
                if own, compact, let item = BattleHeldItems.item(pokemon.item) {
                    Text(item.name(store.language)).font(.caption2).lineLimit(1)
                        .foregroundStyle(.secondary).help(item.tooltip(store.language))
                }
                if !pokemon.status.isEmpty { Text(l.battleStatus(pokemon.status)).font(.caption.bold()).foregroundStyle(.orange).lineLimit(1) }
                Spacer(minLength: 0)
                Text(own ? "\(pokemon.hp) / \(pokemon.maxHP)" : "\(pokemon.hp)%").font((compact ? Font.caption2 : .caption).monospacedDigit()).lineLimit(1)
            }
        }.padding(compact ? 4 : 10).frame(width: 205)
            .background(Color(red:0.97,green:0.97,blue:0.87),in:RoundedRectangle(cornerRadius:6))
            .overlay(RoundedRectangle(cornerRadius:6).stroke(Color(red:0.25,green:0.32,blue:0.31),lineWidth:3))
            .overlay {
                if isSelectedTarget(own: own, slot: slot) {
                    RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 3)
                        .padding(-3).allowsHitTesting(false)
                }
            }
            .foregroundStyle(.black)
            .opacity(pokemon.fainted ? 0.35 : 1)
            .overlay(alignment: .topLeading) {
                if slot == 0 {
                    BattlePartyIndicators(status: party,
                        expectedCount: battle.isChallenge ? 6 : battle.mode.battleSize,
                        language: store.language)
                        .offset(y: -17)
                }
            }
            .opacity(roguePlayer.entryHiddenPositions.contains(BattleEffectPosition.key(own:own,slot:slot)) ? 0:1)
            .padding(.top, !compact || slot == 0 ? 17 : 0)
    }
    private func isSelectedTarget(own: Bool, slot: Int) -> Bool {
        guard battle.mode == .doubles, !battle.submitted, !effectsBusy, !battle.presentation.pending,
              let frame = battle.presentation.frame ?? battle.frame, !frame.waiting,
              let commandSlot = frame.slots.first(where: { $0.slot == editingSlot }) else { return false }
        return BattleChoiceSummary(slot: commandSlot, choice: choices[editingSlot], own: frame.own, foe: frame.foe,
                                   language: store.language).positions.contains(.init(own: own, slot: slot))
    }
    private var spriteSizing:BattleSpriteSizing {
        let frame = battle.presentation.frame ?? battle.frame
        return BattleSpriteSizing.forBattle(mode: battle.mode, own: frame?.own ?? [], foe: frame?.foe ?? [])
    }

    private func battleSprite(_ pokemon: BattleCombatant, own: Bool, slot: Int, sizing: BattleSpriteSizing, showsGround: Bool = true) -> some View {
        let size: CGFloat = battle.mode == .singles ? 108 : 90
        return BattlePokemonStage(spriteOpacity:roguePlayer.hidesNative(.init(own:own,slot:slot)) ? 0:1,pokemon:pokemon,back:own,stageSize:size,sizing:sizing,showsGround:showsGround)
            .anchorPreference(key:BattleSpriteAnchorKey.self,value:.bounds) { [BattleEffectPosition.key(own:own,slot:slot):$0] }
    }

    private func commands(_ frame: BattleFrame, detailWidth: CGFloat) -> some View {
        VStack(spacing: 10) {
            if frame.slots.count > 1 {
                HStack(spacing: 8) {
                    ForEach(frame.slots) { slot in
                        let member = frame.own.filter(\.active).dropFirst(slot.slot).first
                        let summary = BattleChoiceSummary(slot: slot, choice: choices[slot.slot], own: frame.own, foe: frame.foe, language: store.language)
                        Button { editingSlot = slot.slot } label: {
                            BattleChoiceSummaryView(
                                name: "\(slot.slot + 1) · " + (member.map { BattleTextCatalog.shared.speciesName($0.speciesID, language: store.language) } ?? l.battleUnknownPokemon),
                                summary: summary, selected: editingSlot == slot.slot,
                                mega: megaSelection.slot == slot.slot && choices[slot.slot]?.kind == "move", language: store.language)
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("battle-choice-summary-\(slot.slot)")
                            .accessibilityValue(summary.action + " · " + summary.target)
                    }
                }.disabled(battle.submitted || frame.waiting || effectsBusy || battle.presentation.pending)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(frame.slots.filter { $0.slot == editingSlot }) { slot in
                    VStack(alignment: .leading, spacing: 7) {
                        if let own = frame.own.filter(\.active).dropFirst(slot.slot).first { Text(BattleTextCatalog.shared.speciesName(own.speciesID,language:store.state.language) + " · " + l.battleFight).font(.headline).measureBattleContent("command-title") }
                        if !slot.canPass {
                            if !slot.mustSwitch {
                                if slot.canMegaEvo == true {
                                    Toggle(l.battleMegaEvolution,isOn:Binding(get:{megaSelection.slot==slot.slot},set:{megaSelection.set($0,slot:slot.slot)}))
                                        .toggleStyle(.checkbox).accessibilityIdentifier("battle-mega-\(slot.slot)")
                                }
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                    ForEach(slot.moves) { move in
                                        Button {
                                            choices[slot.slot] = BattleAction(kind: "move", index: move.index,
                                                target: move.targetRequired ? (move.targets.first?.location ?? 0) : 0)
                                        } label: {
                                            BattleMoveButtonLabel(move:move,language:store.state.language,
                                                selected:choices[slot.slot]?.kind == "move" && choices[slot.slot]?.index == move.index)
                                        }.buttonStyle(.plain)
                                            .accessibilityIdentifier("battle-move-\(slot.slot)-\(move.index)")
                                            .accessibilityValue(choices[slot.slot]?.kind == "move" && choices[slot.slot]?.index == move.index ? l.battleSelected : "")
                                            .disabled(move.disabled || move.pp == 0)
                                            .help(l.battleDisabledReason(move) ?? l.battleMoveDescription(move))
                                            .accessibilityHint(l.battleDisabledReason(move) ?? "")
                                    }
                                }
                                if let action = choices[slot.slot], action.kind == "move",
                                   let move = slot.moves.first(where: { $0.index == action.index }), move.targetRequired {
                                    Label(l.battleTarget + ": " + l.battleChoiceTarget(action.target, own: frame.own, foe: frame.foe), systemImage: "scope")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Menu(l.battleSwitch) {
                                ForEach(Array(frame.own.enumerated()), id: \.element.id) { index, pokemon in
                                    Button(l.battleSwitchSummary(pokemon)) { choices[slot.slot] = BattleAction(kind: "switch", index: index + 1, target: 0) }
                                        .disabled(pokemon.active || pokemon.fainted || choices.contains(where: {
                                            $0.key != slot.slot && $0.value.kind == "switch" && $0.value.index == index + 1
                                        }))
                                }
                            }.disabled(slot.trapped && !slot.mustSwitch)
                                .help(slot.trapped && !slot.mustSwitch ? l.battleTrappedNotice : l.battleSwitch)
                            if slot.trapped && !slot.mustSwitch {
                                Text(l.battleTrappedNotice).font(.caption).foregroundStyle(.orange)
                            }
                            if let selected = choices[slot.slot], selected.kind == "switch", frame.own.indices.contains(selected.index - 1) {
                                Label(BattleTextCatalog.shared.speciesName(frame.own[selected.index - 1].speciesID,language:store.state.language), systemImage: "arrow.left.arrow.right").font(.caption)
                            }
                        }
                    }.frame(maxWidth: .infinity)
                    ZStack(alignment: .topLeading) {
                        ForEach(slot.moves) { move in
                            BattleMoveDetails(move: move, language: store.state.language, compact: true)
                                .hidden().accessibilityHidden(true)
                        }
                        if let action = choices[slot.slot], action.kind == "move",
                           let move = slot.moves.first(where: { $0.index == action.index }) {
                            BattleMoveDetails(move:move,language:store.state.language,compact:true)
                        } else {
                            Text(l.battleSelectMove).font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).frame(minHeight:140)
                        }
                    }.frame(width:detailWidth,alignment:.leading)
                }
            }.disabled(battle.submitted || frame.waiting || effectsBusy || battle.presentation.pending)
            if battle.submitted || frame.waiting { Text(l.battleWaiting).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func submitButton(_ frame: BattleFrame) -> some View {
        Button(l.battleSubmit) {
            battle.choose(BattleDecision(decisionID:frame.decisionID,
                actions:frame.slots.map { slot in
                    megaSelection.applying(to:choices[slot.slot] ?? .pass,slot:slot.slot,canMega:slot.canMegaEvo==true)
                },order:[]))
        }.buttonStyle(.borderedProminent)
            .accessibilityIdentifier("battle-confirm")
            .disabled(battle.submitted || frame.waiting || effectsBusy || battle.presentation.pending || !validChoices(frame))
    }

    private func validChoices(_ frame: BattleFrame) -> Bool {
        guard frame.slots.allSatisfy({ choices[$0.slot] != nil }) else { return false }
        let switches = choices.values.filter { $0.kind == "switch" }.map(\.index)
        return Set(switches).count == switches.count
    }

}

@MainActor
struct BattleVolumeControl: View {
    let settings: BattleAudioSettings
    let label: String
    let effectsLabel: String
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: { Image(systemName:"slider.horizontal.3") }
            .help("\(label) / \(effectsLabel)").accessibilityLabel("\(label) / \(effectsLabel)")
            .popover(isPresented:$showing, arrowEdge:.bottom) {
                VStack(alignment:.leading,spacing:12) {
                    HStack { Text(label); Spacer(); Text(settings.volume,format:.percent.precision(.fractionLength(0))).monospacedDigit() }
                    Slider(value:Binding(get:{ settings.volume },set:{ settings.setVolume($0) }),in:0...1)
                        .accessibilityLabel(label)
                        .accessibilityValue(Text(settings.volume,format:.percent.precision(.fractionLength(0))))
                    Divider()
                    HStack { Text(effectsLabel); Spacer(); Text(settings.effectsVolume,format:.percent.precision(.fractionLength(0))).monospacedDigit() }
                    Slider(value:Binding(get:{ settings.effectsVolume },set:{ settings.setEffectsVolume($0) }),in:0...1)
                        .accessibilityLabel(effectsLabel)
                        .accessibilityIdentifier("battle-effects-volume")
                        .accessibilityValue(Text(settings.effectsVolume,format:.percent.precision(.fractionLength(0))))
                }.padding(16).frame(width:260)
            }
    }
}

enum BattleLogText {
    /// Public protocol only: never infer an unrevealed passive ability from a team sheet.
    static func abilityChanges(_ events: [String], language: AppLanguage, ownPlayer: Int = 0) -> [String] {
        abilityNotices(events, language: language, ownPlayer: ownPlayer).map(\.text)
    }
    static func abilityNotices(_ events: [String], language: AppLanguage, ownPlayer: Int = 0) -> [BattleAbilityNotice] {
        var result: [BattleAbilityNotice] = []
        var boostSources: [(owner: String, text: String, opposingDrop: Bool)] = []
        for (index, event) in events.enumerated() {
            let parts = event.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count > 1 else { continue }
            let actor = parts.count > 2 ? parts[2].components(separatedBy: ":").first ?? "" : ""
            let explicitCause = parts.dropFirst(2).contains { $0.hasPrefix("[from] ability:") }
            if parts[1] == "-ability" {
                let text = describe(event, language: language, ownPlayer: ownPlayer)
                if let text { result.append(BattleAbilityNotice(id: index, text: text)) }
                if parts.last == "boost", let text {
                    boostSources.append((actor, text, parts.count > 3 && BattleTextCatalog.key(parts[3]) == "intimidate"))
                }
            } else if (parts[1] == "-boost" || parts[1] == "-unboost"), !explicitCause,
                      let source = boostSources.last(where: {
                          $0.owner == actor || ($0.opposingDrop && parts[1] == "-unboost" && $0.owner.prefix(2) != actor.prefix(2))
                      }) {
                if let text = describe(event, language: language, ownPlayer: ownPlayer) { result.append(BattleAbilityNotice(id: index, text: source.text + " → " + text)) }
            } else {
                // Reactions such as Defiant or Clear Body may interleave two Intimidate targets.
                if !parts[1].hasPrefix("-") { boostSources.removeAll() }
                let namedAbility = parts.count > 3 && ["-start", "-end", "-activate"].contains(parts[1])
                    && (BattleTextCatalog.shared.abilities[BattleTextCatalog.key(parts[3])] != nil || BattleMegaText.catalog.abilities[BattleTextCatalog.key(parts[3])] != nil)
                if parts.dropFirst(2).contains(where: { $0.contains("ability:") }) || namedAbility,
                   let text = describe(event, language: language, ownPlayer: ownPlayer) { result.append(BattleAbilityNotice(id: index, text: text)) }
            }
        }
        return result
    }

    /// -miss contains the attacker and target, but the move name is in the preceding
    /// public move record. Never substitute a selected move or an older turn's move.
    static func describeMiss(_ log:[String],at index:Int,language:AppLanguage,ownPlayer:Int)->String? {
        guard log.indices.contains(index) else{return nil}
        let miss=log[index].split(separator:"|",omittingEmptySubsequences:false).map(String.init)
        guard miss.count>2,miss[1]=="-miss" else{return nil}
        for prior in log[..<index].reversed() {
            let parts=prior.split(separator:"|",omittingEmptySubsequences:false).map(String.init)
            guard parts.count>1 else{continue}
            if parts[1]=="turn"{return nil}
            guard parts[1]=="move" else{continue}
            guard parts.count>3,parts[2]==miss[2] else{return nil}
            let l=L(language),catalog=BattleTextCatalog.shared
            let side=parts[2].hasPrefix("p1") ? 0:1
            let pokemon=l.battleSide(ally:side==ownPlayer)+" "+catalog.pokemonName(parts[2],language:language)
            return l.battleMoveMissed(pokemon,move:catalog.moveName(parts[3],language:language))
        }
        return nil
    }

    static func describe(_ event: String, language: AppLanguage = .en, ownPlayer: Int = 0) -> String? {
        let parts = event.split(separator:"|",omittingEmptySubsequences:false).map(String.init)
        guard parts.count > 1 else { return nil }
        let args = Array(parts.dropFirst(2)), l = L(language), catalog = BattleTextCatalog.shared
        func value(_ i: Int) -> String { args.indices.contains(i) ? args[i] : "" }
        let side = value(0).hasPrefix("p1") ? 0 : value(0).hasPrefix("p2") ? 1 : nil
        let sideName = side.map { l.battleSide(ally: $0 == ownPlayer) + " " } ?? ""
        let pokemon = sideName + catalog.pokemonName(value(0),language:language)
        let abilityCause = args.first(where: { $0.hasPrefix("[from] ability:") }).map {
            catalog.abilityName($0.components(separatedBy: "ability:").last?.trimmingCharacters(in: .whitespaces) ?? "", language: language)
        }
        let otherCause = args.first(where: { $0.hasPrefix("[from] ") && !$0.hasPrefix("[from] ability:") })
            .map { l.battleDamageCause(String($0.dropFirst(7))) }
        let cause = (abilityCause ?? otherCause).map { " · " + $0 } ?? ""
        switch parts[1] {
        case "cant":
            let reason = ["par", "slp", "frz", "flinch", "confusion", "attract"].contains(BattleTextCatalog.key(value(1)))
                ? l.battleStatus(value(1)) : catalog.effectName(value(1), language: language)
            return pokemon + " · " + reason + " · " + l.battleCannotAct + cause
        case "move":
            guard !parts.contains("[notarget]") else{return nil}
            return "\(pokemon) → \(catalog.moveName(value(1),language:language))"
        case "switch", "drag": return "↔ " + catalog.pokemonName(value(1),language:language)
        case "-damage":
            guard !cause.isEmpty else { return nil }
            return pokemon + " · " + l.battleEvent(parts[1]) + cause
        case "-heal": return "\(pokemon) · \(l.battleEvent(parts[1])) · \(value(1).split(separator:" ").first ?? "")" + cause
        case "faint", "-immune", "-supereffective", "-resisted", "-crit", "-fail": return pokemon + " · " + l.battleEvent(parts[1]) + cause
        case "-status": return pokemon + " · " + l.battleStatus(value(1)) + cause
        case "-curestatus": return pokemon + " · " + l.battleEvent(parts[1]) + cause
        case "-item", "-enditem":
            return pokemon + " · " + (BattleHeldItems.item(value(1))?.name(language) ?? l.battleHeldItem) + " · " + (parts[1] == "-enditem" ? l.battleItemConsumed:l.battleEvent("-activate"))
        case "-mega": return pokemon + " · " + l.battleMegaEvolution + (BattleHeldItems.item(value(2)).map{" · "+$0.name(language)} ?? "")
        case "-ability": return pokemon + " · " + catalog.abilityName(value(1),language:language) + cause
        case "-activate", "-block":
            return pokemon + " · " + l.battleDamageCause(value(1)) + " · " + l.battleEvent(parts[1]) + cause
        case "-weather": return l.battleWeather(value(0)) + cause
        case "-fieldstart", "-fieldactivate", "-fieldend":
            return l.battleFieldEffect(value(0)) + " · " + l.battleEvent(parts[1] == "-fieldend" ? "-end" : "-activate") + cause
        case "-sidestart", "-sideend":
            return sideName + l.battleFieldEffect(value(1)) + " · " + l.battleEvent(parts[1] == "-sideend" ? "-end" : "-activate") + cause
        case "-start", "-end": return pokemon + " · " + l.battleDamageCause(value(1)) + " · " + l.battleEvent(parts[1]) + cause
        case "-boost", "-unboost": return pokemon + " · " + l.battleStat(value(1)) + " · " + l.battleEvent(parts[1]) + " " + value(2) + cause
        case "turn": return l.battleTurn(Int(value(0)) ?? 0)
        default: return abilityCause.map { pokemon + " · " + l.battleEvent(parts[1]) + " · " + $0 }
        }
    }
}
