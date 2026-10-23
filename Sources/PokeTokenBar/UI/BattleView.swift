import SwiftUI

@MainActor
struct BattleView: View {
    let battle: BattleCoordinator
    let store: CompanionStore
    var onSurrender: () -> Void
    var onMusic: () -> Void
    var onPlayMusic: () -> Void
    var audioSettings: BattleAudioSettings? = nil
    var allowsEffectsAudio = true
    var auxiliaryState: BattleAuxiliaryState? = nil
    var onShowField: () -> Void = {}
    var onShowStats: () -> Void = {}
    var onLayout: (BattleContentMeasurement) -> Void = { _ in }
    @State private var layoutWidth: CGFloat = BattleWindowLayout.preferredWidth(for: .singles)
    @State private var choices: [Int: BattleAction] = [:]
    @State private var editingSlot = 0
    @State private var musicEnabled = true
    @State private var effectsBusy = false
    @State private var roguePlayer=PokeRogueBattlePlayer()
    @State private var effectPlayback: BattleEffectPlayback?
    @State private var reconnectCode = ""
    private var l: L { store.l }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let frame = battle.presentation.frame ?? battle.frame {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        battlefield(frame).frame(height: battle.mode == .doubles ? 260 : 310)
                        HStack(spacing: 8) {
                            ForEach(frame.own) { member in
                                HStack(spacing: 4) {
                                    Circle().fill(member.fainted ? Color.gray : Color.green).frame(width: 7,height: 7)
                                    Text(BattleTextCatalog.shared.speciesName(member.speciesID,language:store.state.language)).font(.caption2).lineLimit(1)
                                }.opacity(member.fainted ? 0.4 : 1)
                            }
                        }
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
                        if roguePlayer.error != nil{Text(l.battleEffectsUnavailable).font(.caption).foregroundStyle(.orange)}
                        if let error = battle.error { Text(l.battleUserError(error)).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    }.padding(.horizontal, 12).padding(.top, 12)
                        .frame(maxWidth: .infinity, alignment: .top)
                    Divider().measureBattleContent("footer")
                    if !frame.preview && !frame.ended && (battle.phase == .playing || battle.presentation.pending) {
                        HStack { Spacer(); submitButton(frame) }.padding(.horizontal,18).padding(.vertical,8)
                        Divider()
                    }
                }
                .onChange(of: frame.decisionID, initial: true) { _, _ in
                    choices = [:]; editingSlot = 0
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
            onLayout(BattleContentMeasurement(content: content, commands: regions["commands"], footer: regions["footer"]))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale,store.state.language.displayLocale)
        .onChange(of: audioSettings?.effectsVolume, initial: true) { _, volume in
            roguePlayer.setEffectsVolume(allowsEffectsAudio ? (volume ?? 0) : 0)
        }
        .onAppear { battle.completePresentation() }
        .onDisappear{roguePlayer.stop()}
        .onChange(of:battle.frame == nil){_,empty in if empty{roguePlayer.stop()}}
        .onChange(of: battle.phase, initial: true) { _, phase in if phase == .playing { onPlayMusic() } }
    }
    private var header: some View {
        VStack(spacing: 8) {
        HStack(spacing: 14) {
            Image(systemName: "bolt.shield.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(battle.identity.nickname)  ×  \(battle.opponent?.nickname ?? "…")").font(.headline)
                Text(l.battleRules).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(battle.mode == .singles ? l.battleSingles : l.battleDoubles).font(.callout)
            if let deadline = battle.decisionDeadline { Text(timerInterval: Date()...max(Date(), deadline), countsDown: true).font(.caption.monospacedDigit()).frame(width: 45) }
            if let frame = battle.presentation.frame ?? battle.frame { Text("\(frame.turn)").font(.title2.monospacedDigit()).accessibilityLabel(l.battleTurn(frame.turn)) }
            Button { musicEnabled.toggle(); onMusic() } label: {
                Image(systemName: musicEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }.help(l.battleMusic).accessibilityLabel(l.battleMusic)
            if let audioSettings { BattleVolumeControl(settings:audioSettings,label:l.battleVolume,effectsLabel:l.battleEffectsVolume) }
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
        ZStack {
            VStack {
                HStack(spacing: 14) {
                    Spacer(minLength: 0)
                    ForEach(Array(frame.foe.enumerated()),id:\.element.id) { slot,pokemon in combatant(pokemon,own:false,slot:slot) }
                }
                Spacer(minLength: 8)
                HStack(spacing: 14) {
                    ForEach(Array(frame.own.filter(\.active).enumerated()),id:\.element.id) { slot,pokemon in combatant(pokemon,own:true,slot:slot) }
                    Spacer(minLength: 0)
                }
            }.padding(18)
            if frame.preview { Image(systemName:"bolt.shield").font(.system(size:50)).foregroundStyle(.black.opacity(0.3)) }
        }.modifier(PokeRogueBattlefieldLayers(player:roguePlayer))
        .overlayPreferenceValue(BattleSpriteAnchorKey.self) { anchors in
            GeometryReader { geometry in
                let latest = battle.frame ?? frame
                let presentation = BattlePresentationEvents(frame: latest, language: store.language, ownPlayer: battle.isHost ? 0 : 1)
                BattleEffectsLayer(events:presentation.events,rects:anchors.mapValues { geometry[$0] },busy:$effectsBusy,playback:$effectPlayback,messages:presentation.messages,presentOpeningAbilities:latest.turn <= 1,
                    scenes:Dictionary(uniqueKeysWithValues:(latest.scenes ?? []).map { ($0.id,$0) }),
                    onScene:{ battle.presentation.apply($0) },onFinished:{ battle.completePresentation() },onAnimatedScene:{ await battle.presentation.animate($0) },originalPlayer:roguePlayer,
                    actors:renderActors(frame,rects:anchors.mapValues{geometry[$0]}),viewport:geometry.size)
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
    private func combatant(_ pokemon: BattleCombatant, own: Bool, slot: Int) -> some View {
        HStack(spacing: 4) {
            if own { battleSprite(pokemon,own:true,slot:slot) }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(BattleTextCatalog.shared.speciesName(pokemon.speciesID,language:store.state.language)).font(.headline).lineLimit(1)
                    Spacer(minLength: 2)
                    Text("\(l.level) \(pokemon.level)").font(.caption.monospacedDigit())
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
                Text(own ? "\(pokemon.hp) / \(pokemon.maxHP)" : "\(pokemon.hp)%")
                    .font(.caption.monospacedDigit()).frame(maxWidth:.infinity,alignment:.trailing)
                if !pokemon.status.isEmpty { Text(l.battleStatus(pokemon.status)).font(.caption.bold()).foregroundStyle(.orange) }
            }.padding(10).frame(width: battle.mode == .singles ? 205 : 148)
                .background(Color(red:0.97,green:0.97,blue:0.87),in:RoundedRectangle(cornerRadius:6))
                .overlay(RoundedRectangle(cornerRadius:6).stroke(Color(red:0.25,green:0.32,blue:0.31),lineWidth:3))
                .foregroundStyle(.black)
                .opacity(roguePlayer.entryHiddenPositions.contains(BattleEffectPosition.key(own:own,slot:slot)) ? 0:1)
            if !own { battleSprite(pokemon,own:false,slot:slot) }
        }.opacity(pokemon.fainted ? 0.35 : 1)
    }
    private var spriteSizing:BattleSpriteSizing {
        let catalog=PokeRogueSpriteSizes.shared
        var ids=Set(battle.registeredTeam.map(\.speciesID)+battle.opponentRoster.map(\.speciesID))
        if let frame=battle.presentation.frame ?? battle.frame { ids.formUnion(frame.own.map(\.speciesID)+frame.foe.map(\.speciesID)) }
        // Include both facings and form changes up front so switching/Transform cannot pop the camera.
        let sizes=ids.flatMap { id in
            let forms=PokemonForm.forms(speciesID:id)
            return (forms.isEmpty ? [nil]:forms.map(Optional.some)).flatMap { form in
                [false,true].map{catalog.size(speciesID:id,form:form,back:$0)}
            }
        }
        return BattleSpriteSizing.make(mode:battle.mode,sizes:sizes)
    }
    private func battleSprite(_ pokemon: BattleCombatant, own: Bool, slot: Int) -> some View {
        let size: CGFloat = battle.mode == .singles ? 108 : 90
        return BattlePokemonStage(spriteOpacity:roguePlayer.isPlaying || roguePlayer.entryHiddenPositions.contains(BattleEffectPosition.key(own:own,slot:slot)) ? 0:1,pokemon:pokemon,back:own,stageSize:size,sizing:spriteSizing)
            .anchorPreference(key:BattleSpriteAnchorKey.self,value:.bounds) { [BattleEffectPosition.key(own:own,slot:slot):$0] }
    }

    private func commands(_ frame: BattleFrame, detailWidth: CGFloat) -> some View {
        VStack(spacing: 10) {
            if frame.slots.count > 1 {
                Picker(l.battleTeam, selection: $editingSlot) {
                    ForEach(frame.slots) { slot in
                        Text("\(slot.slot + 1) · " + (choices[slot.slot] == nil ? l.battleFight : l.battleSelected)).tag(slot.slot)
                    }
                }.pickerStyle(.segmented)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(frame.slots.filter { $0.slot == editingSlot }) { slot in
                    VStack(alignment: .leading, spacing: 7) {
                        if let own = frame.own.filter(\.active).dropFirst(slot.slot).first { Text(BattleTextCatalog.shared.speciesName(own.speciesID,language:store.state.language) + " · " + l.battleFight).font(.headline) }
                        if !slot.canPass {
                            if !slot.mustSwitch {
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
                                    }
                                }
                                if let action = choices[slot.slot], action.kind == "move",
                                   let move = slot.moves.first(where: { $0.index == action.index }), move.targetRequired {
                                    Picker(l.battleTarget, selection: Binding(get: { action.target }, set: { target in
                                        choices[slot.slot] = BattleAction(kind: "move", index: action.index, target: target)
                                    })) {
                                        ForEach(move.targets, id: \.self) { target in Text(targetLabel(target,frame:frame)).tag(target.location) }
                                    }
                                }
                            }
                            Menu(l.battleSwitch) {
                                ForEach(Array(frame.own.enumerated()), id: \.element.id) { index, pokemon in
                                    if !pokemon.active && !pokemon.fainted {
                                        Button(BattleTextCatalog.shared.speciesName(pokemon.speciesID,language:store.state.language)) { choices[slot.slot] = BattleAction(kind: "switch", index: index + 1, target: 0) }
                                    }
                                }
                            }.disabled(slot.trapped && !slot.mustSwitch)
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
                actions:frame.slots.map { choices[$0.slot] ?? .pass },order:[]))
        }.buttonStyle(.borderedProminent)
            .accessibilityIdentifier("battle-confirm")
            .disabled(battle.submitted || frame.waiting || effectsBusy || battle.presentation.pending || !validChoices(frame))
    }

    private func targetLabel(_ target: BattleTarget, frame: BattleFrame) -> String {
        let allies = frame.own.filter(\.active)
        let members = target.location < 0 ? allies : frame.foe
        let number = abs(target.location)
        let name = members.indices.contains(number-1) ? BattleTextCatalog.shared.speciesName(members[number-1].speciesID,language:store.state.language) : l.battleUnknownPokemon
        return "\(l.battleSide(ally:target.location < 0)) \(number) · \(name)"
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
                    && BattleTextCatalog.shared.abilities[BattleTextCatalog.key(parts[3])] != nil
                if parts.dropFirst(2).contains(where: { $0.contains("ability:") }) || namedAbility,
                   let text = describe(event, language: language, ownPlayer: ownPlayer) { result.append(BattleAbilityNotice(id: index, text: text)) }
            }
        }
        return result
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
        case "move": return "\(pokemon) → \(catalog.moveName(value(1),language:language))"
        case "switch", "drag": return "↔ " + catalog.pokemonName(value(1),language:language)
        case "-damage":
            guard !cause.isEmpty else { return nil }
            return pokemon + " · " + l.battleEvent(parts[1]) + cause
        case "-heal": return "\(pokemon) · \(l.battleEvent(parts[1])) · \(value(1).split(separator:" ").first ?? "")" + cause
        case "faint", "-immune", "-supereffective", "-resisted", "-crit", "-fail": return pokemon + " · " + l.battleEvent(parts[1]) + cause
        case "-status": return pokemon + " · " + l.battleStatus(value(1)) + cause
        case "-curestatus": return pokemon + " · " + l.battleEvent(parts[1]) + cause
        case "-ability": return pokemon + " · " + catalog.abilityName(value(1),language:language) + cause
        case "-activate", "-block":
            return pokemon + " · " + l.battleDamageCause(value(1)) + " · " + l.battleEvent(parts[1]) + cause
        case "-weather": return l.battleWeather(value(0)) + cause
        case "-fieldstart", "-fieldend":
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
