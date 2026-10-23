import AppKit
import SwiftUI
@testable import PokeTokenBar

/// Development harness using the production GIF stage, camera sizing and original player.
@MainActor struct PokemonSizeComparison:View {
    let mode:BattleMode
    private let backdropPreview=CommandLine.arguments.contains("--background-preview")
    private let statusPreview=CommandLine.arguments.contains("--status-preview")
    private let cryPreview=CommandLine.arguments.contains("--cry-preview")
    @State private var lowHP=false
    @State private var foeChanged=false
    @State private var ownHP=100
    @State private var foeHP=100
    @State private var statusOnOwn=true
    @State private var currentMove=""
    let spriteStore:SpriteStore
    @State private var player:PokeRogueBattlePlayer
    init(mode:BattleMode,spriteStore:SpriteStore) {
        self.mode=mode;self.spriteStore=spriteStore
        _player=State(initialValue:PokeRogueBattlePlayer(spriteStore:spriteStore))
    }
    @State private var changed=false
    @State private var shiny=true
    @State private var audioSettings=BattleAudioSettings(defaults:UserDefaults(suiteName:"dev.poketokenbar.battlepreview.audio")!)
    @State private var busy=false
    @State private var rects:[String:CGRect]=[:]
    @State private var viewport=CGSize.zero
    private var sizing:BattleSpriteSizing {
        let catalog=PokeRogueSpriteSizes.shared
        return .make(mode:mode,sizes:[25,143,321,384].flatMap{id in [false,true].map{catalog.size(speciesID:id,form:nil,back:$0)}})
    }
    private var positions:[BattleEffectPosition] {
        (0..<(mode == .singles ? 2:4)).map{.init(own:$0%2==0,slot:$0/2)}
    }
    private func pokemon(_ id:Int)->BattleCombatant {
        BattleCombatant(id:String(id),speciesID:id,name:BattleTextCatalog.shared.speciesName(id,language:.ko),level:50,shiny:id==25 && shiny,active:true,form:nil,fainted:false,hp:id==25 || id==143 ? ownHP:foeHP,maxHP:100,status:"",stats:nil)
    }
    private func current(_ p:BattleEffectPosition,swap:Bool?=nil,foeSwap:Bool?=nil)->BattleCombatant {
        if p.own { return pokemon(p.slot==0 ? ((swap ?? changed) ? 143:25):321) }
        return pokemon(mode == .singles ? ((foeSwap ?? foeChanged) ? 384:321):(p.slot==0 ? 143:384))
    }
    private func actors(swap:Bool?=nil,foeSwap:Bool?=nil)->[PokeRogueActor] {
        positions.compactMap{p in rects[p.key].map{PokeRogueActor(pokemon:current(p,swap:swap,foeSwap:foeSwap),position:p,rect:$0,pixelScale:sizing.pixelScale)}}
    }
    private func combatant(_ p:BattleEffectPosition)->some View {
        let mon=current(p)
        return HStack(spacing:4) {
            if p.own { sprite(mon,p) }
            VStack(alignment:.leading,spacing:6) {
                HStack{Text(mon.name).font(.headline);Spacer(minLength:2);Text("Lv50").font(.caption)}
                GeometryReader { geometry in
                    ZStack(alignment:.leading) {
                        Capsule().fill(.black.opacity(0.15))
                        Capsule().fill(.green).frame(width:geometry.size.width*CGFloat(mon.hp)/100)
                    }
                }.frame(height:8)
                Text("\(mon.hp) / 100").font(.caption.monospacedDigit()).frame(maxWidth:.infinity,alignment:.trailing)
            }.padding(10).frame(width:mode == .singles ? 205:148)
                .foregroundStyle(.black).background(Color(red:0.97,green:0.97,blue:0.87),in:RoundedRectangle(cornerRadius:6))
                .overlay(RoundedRectangle(cornerRadius:6).stroke(Color(red:0.25,green:0.32,blue:0.31),lineWidth:3))
            if !p.own { sprite(mon,p) }
        }
    }
    private func sprite(_ mon:BattleCombatant,_ p:BattleEffectPosition)->some View {
        BattlePokemonStage(spriteOpacity:player.isPlaying ? 0:1,pokemon:mon,back:p.own,stageSize:mode == .singles ? 108:90,sizing:sizing,spriteStore:spriteStore)
            .anchorPreference(key:BattleSpriteAnchorKey.self,value:.bounds){[p.key:$0]}
    }
    var body:some View {
        VStack(spacing:12) {
            HStack {
                Text(mode == .singles ? "싱글 · 660px":"더블 · 680px").font(.headline)
                Spacer()
                Text(cryPreview ? "등장·교체 울음소리 테스트" : statusPreview ? "상태이상 연출 테스트 · 기존 GIF" : backdropPreview ? "배경 연출 확인 · 기존 GIF":"PokéRogue 크기 기준 · 기존 GIF").font(.caption).foregroundStyle(.secondary)
                BattleVolumeControl(settings:audioSettings,label:"BGM 볼륨",effectsLabel:"효과음 볼륨")
            }
            ZStack {
                VStack {
                    HStack(spacing:14) {Spacer(minLength:0);ForEach(positions.filter{!$0.own},id:\.key){combatant($0)}}
                    Spacer(minLength:16)
                    HStack(spacing:14) {ForEach(positions.filter(\.own),id:\.key){combatant($0)};Spacer(minLength:0)}
                }.padding(18)
            }.frame(height:backdropPreview || statusPreview || cryPreview ? 310:nil).modifier(PokeRogueBattlefieldLayers(player:player))
                .overlayPreferenceValue(BattleSpriteAnchorKey.self){anchors in
                    GeometryReader{g in
                        let values=anchors.mapValues{g[$0]}
                        Color.clear.onChange(of:values,initial:true){_,values in rects=values;viewport=g.size}
                    }
                }.clipShape(RoundedRectangle(cornerRadius:8))
            if cryPreview {
                HStack {
                    Button("나의 포켓몬 등장") { replayAppearance() }
                    Button("상대 포켓몬 등장") { replayAppearance(own:false) }
                    Button("나의 포켓몬 교체") { perform(switching:true) }
                    Button("상대 포켓몬 교체") { performFoeSwitch() }
                }.disabled(busy)
                Toggle("HP 25% · 낮은 울음소리 속도",isOn:$lowHP).toggleStyle(.checkbox).disabled(busy)
                    .onChange(of:lowHP){_,value in ownHP=value ? 25:100;foeHP=value ? 25:100}
                Text(busy ? "등장·울음소리 재생 중":"버튼을 눌러 양쪽의 등장·교체 울음소리를 확인하세요. 상단 효과음 볼륨을 따릅니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if statusPreview {
                HStack {
                    Picker("적용 대상",selection:$statusOnOwn) { Text("나의 포켓몬").tag(true);Text("상대 포켓몬").tag(false) }.pickerStyle(.segmented).frame(width:260)
                    Spacer()
                    Button("HP 초기화") { ownHP=100;foeHP=100 }
                }.disabled(busy)
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4),spacing:8) {
                    ForEach(["slp","psn","tox","par","confusion","brn","frz","attract"],id:\.self){key in
                        Button(L(.ko).battleStatus(key)) { performStatus(key) }.frame(maxWidth:.infinity)
                    }
                }.disabled(busy)
                Text(busy ? currentMove+" 재생 중" : "상태를 선택하면 원본 연출·효과음이 재생됩니다. 독·맹독·화상은 연출 후 HP가 감소합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if backdropPreview {
                HStack {
                    ForEach(["closecombat","thunder","psychic","surf"],id:\.self){move in
                        Button(BattleTextCatalog.shared.moveName(move,language:.ko)){perform(switching:false,move:move)}
                    }
                    Spacer()
                    Text(busy ? currentMove+" 재생 중":"기술을 눌러 연출 확인").font(.caption).foregroundStyle(.secondary)
                }.disabled(busy)
            } else {
            HStack {
                Button("기술 · 10만볼트") { perform(switching:false) }
                Button(changed ? "피카츄로 교체":"잠만보로 교체") { perform(switching:true) }
                Button("다시 등장") { replayAppearance() }
                Toggle("이로치",isOn:$shiny).toggleStyle(.checkbox)
                Spacer()
                Text("크기·연출 비교용").font(.caption).foregroundStyle(.secondary)
            }.disabled(busy)
            }
            if let error=player.error {Text(error).font(.caption).foregroundStyle(.red)}
        }.padding(12).frame(width:mode == .singles ? 660:680)
            .fixedSize(horizontal:false,vertical:true)
            .onChange(of:audioSettings.effectsVolume,initial:true){_,value in player.setEffectsVolume(value)}
            .onDisappear{player.stop()}
    }
    private func performStatus(_ key:String) {
        guard !busy,let move=BattleStatusEffects.animations[key] else{return}
        busy=true;currentMove=L(.ko).battleStatus(key)
        Task { @MainActor in
            defer{busy=false}
            let source=BattleEffectPosition(own:statusOnOwn,slot:0)
            let event=BattleVisualEvent(id:1,move:move,type:"",category:"Status",source:source,
                targets:[.init(position:source,hit:true)],moveID:move,phase:"status")
            let played=await player.play(event,actors:actors(),size:viewport)
            if played,["psn","tox","brn"].contains(key) {
                if source.own { ownHP=max(1,ownHP-12) } else { foeHP=max(1,foeHP-12) }
            }
        }
    }
    private func replayAppearance(own:Bool=true) {
        guard !busy else{return};busy=true
        Task { @MainActor in
            defer{busy=false}
            let sources=positions.filter{$0.own==own}
            let event=BattleVisualEvent(id:1,move:"",type:"",category:"Status",source:sources[0],targets:[],phase:"entry")
            _ = await player.play(event,actors:actors(),size:viewport,entrySources:sources)
        }
    }
    private func performFoeSwitch() {
        guard !busy else{return};busy=true
        Task { @MainActor in
            defer{busy=false}
            let source=BattleEffectPosition(own:false,slot:0)
            let event=BattleVisualEvent(id:1,move:"",type:"",category:"Status",source:source,targets:[],phase:"entry")
            _ = await player.play(event,actors:actors(foeSwap:!foeChanged),size:viewport,
                previousActor:actors().first{$0.position==source},beforeFinish:{foeChanged.toggle()})
        }
    }
    private func perform(switching:Bool,move:String="thunderbolt") {
        guard !busy else{return};busy=true;currentMove=BattleTextCatalog.shared.moveName(move,language:.ko)
        Task { @MainActor in
            defer{busy=false}
            let source=BattleEffectPosition(own:true,slot:0)
            let old=actors().first{$0.position==source}
            let event=BattleVisualEvent(id:1,move:move,type:["closecombat":"fighting","thunder":"electric","psychic":"psychic","surf":"water"][move] ?? "electric",category:move=="closecombat" ? "Physical":"Special",source:source,
                targets:[.init(position:.init(own:false,slot:0),hit:true)],moveID:move,phase:switching ? "entry":nil)
            _ = await player.play(event,actors:actors(swap:switching ? !changed:nil),size:viewport,
                previousActor:switching ? old:nil,beforeFinish:{if switching{changed.toggle()}})
        }
    }
}
