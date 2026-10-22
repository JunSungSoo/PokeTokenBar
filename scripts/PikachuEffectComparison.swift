import AppKit
import SwiftUI
@testable import PokeTokenBar

/// Development-only comparison of production effect views, using the unchanged production GIF stage.
@MainActor
struct PikachuEffectComparison: View {
    @State private var move=PikachuMoveProfile.thunderbolt
    @State private var began=Date()
    @State private var repeatPlayback=true
    @State private var hit=true
    @State private var reverse=false
    @State private var still: Double? = nil
    private let width: CGFloat=570
    private let height: CGFloat=320
    private var rects: [String:CGRect] { ["own-0":CGRect(x:45,y:177,width:128,height:128),"foe-0":CGRect(x:405,y:25,width:128,height:128)] }
    private func pokemon(_ id: String) -> BattleCombatant {
        BattleCombatant(id:id,speciesID:25,name:"Pikachu",level:37,shiny:false,active:true,form:nil,fainted:false,hp:143,maxHP:143,status:"",stats:nil)
    }
    private var event: BattleVisualEvent {
        BattleVisualEvent(id:1,move:move.rawValue,type:move == .protect ? "Normal" : move == .quickattack ? "Normal" : "Electric",
            category:move == .protect ? "Status" : move == .quickattack ? "Physical" : "Special",
            source:BattleEffectPosition(own:!reverse,slot:0),
            targets:[BattleEffectTarget(position:BattleEffectPosition(own:move == .protect ? !reverse : reverse,slot:0),hit:hit)],moveID:move.rawValue)
    }
    var body: some View {
        VStack(spacing:18) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text("피카츄 · 기술 이펙트 비교").font(.title2.bold())
                    Text("왼쪽: 기존 효과  ·  오른쪽: 신규 제작 효과  |  동일 진행률 비교 · 포켓몬 애니메이션 유지").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("반복 재생",isOn:$repeatPlayback).toggleStyle(.switch)
            }
            HStack(spacing:8) {
                ForEach(PikachuMoveProfile.allCases,id:\.rawValue) { profile in
                    Button { move=profile;still=nil;began=Date() } label: {
                        HStack { Image(systemName:move == profile ? "checkmark.circle.fill" : "circle");Text(BattleTextCatalog.shared.moveName(profile.rawValue,language:.ko)) }
                            .frame(width:130,height:28)
                    }.buttonStyle(.bordered).tint(move == profile ? .orange : .gray)
                }
                Spacer()
                Button("다시 재생") { still=nil;began=Date() }
            }
            TimelineView(.animation(minimumInterval:1/60)) { timeline in
                let elapsed=max(0,timeline.date.timeIntervalSince(began))
                let cycle=move.duration+0.8
                let time=still.map { $0*move.duration } ?? (repeatPlayback ? elapsed.truncatingRemainder(dividingBy:cycle) : elapsed)
                HStack(spacing:18) {
                    panel(title:"기존 효과",enhanced:false,time:time)
                    panel(title:"신규 제작 · 입자 / 발광 / 궤적",enhanced:true,time:time)
                }
            }
            HStack {
                Toggle("명중",isOn:$hit).frame(width:100)
                Toggle("상대방이 사용",isOn:$reverse).frame(width:160)
                Button(still == nil ? "효과 정지" : "효과 재생") {
                    if still == nil { still=min(0.98,Date().timeIntervalSince(began).truncatingRemainder(dividingBy:move.duration+0.8)/move.duration) }
                    else { still=nil;began=Date() }
                }
                Slider(value:Binding(get:{still ?? 0},set:{still=$0}),in:0...0.99).frame(width:240)
                Text("효과만 정지 · 포켓몬 애니메이션 유지").font(.caption).foregroundStyle(.secondary)
            }
            Text("실제 피해량·PP를 소모하지 않는 시각 비교 화면입니다. 신규 효과는 자체 제작이며 Showmotion 원본으로 표시하지 않습니다.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth:1206,minHeight:540).background(Color(nsColor:.windowBackgroundColor))
        .onChange(of:hit) { _,_ in still=nil;began=Date() }
        .onChange(of:reverse) { _,_ in still=nil;began=Date() }
    }
    private func panel(title: String,enhanced: Bool,time: Double) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(.headline)
            ZStack {
                LinearGradient(colors:[Color(red:0.61,green:0.70,blue:0.64),Color(red:0.86,green:0.87,blue:0.71)],startPoint:.top,endPoint:.bottom)
                ForEach([true,false],id:\.self) { own in
                    let rect=rects[own ? "own-0" : "foe-0"]!
                    BattlePokemonStage(pokemon:pokemon(own ? "own" : "foe"),back:own,stageSize:128)
                        .frame(width:128,height:128).position(x:rect.midX,y:rect.midY)
                }
                hp(own:false).position(x:162,y:58)
                hp(own:true).position(x:380,y:258)
                if enhanced { PikachuMoveEffects(event:event,rects:rects,progress:time/move.duration) }
                else { BattleEffectCanvas(event:event,rects:rects,progress:time/move.duration) }
            }.frame(width:width,height:height).clipShape(RoundedRectangle(cornerRadius:10))
        }
    }
    private func hp(own: Bool) -> some View {
        VStack(alignment:.leading,spacing:5) {
            HStack { Text("피카츄").bold();Spacer();Text("Lv.37").font(.caption) }
            HStack { Text("HP").font(.caption.bold()).foregroundStyle(.orange);Capsule().fill(.green).frame(height:6) }
            if own { Text("143 / 143").font(.caption.monospacedDigit()).frame(maxWidth:.infinity,alignment:.trailing) }
        }.padding(9).frame(width:180).background(Color(red:0.97,green:0.97,blue:0.87),in:RoundedRectangle(cornerRadius:6))
            .overlay(RoundedRectangle(cornerRadius:6).stroke(.black.opacity(0.55),lineWidth:2)).foregroundStyle(.black)
    }
}
