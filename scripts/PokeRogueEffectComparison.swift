import AppKit
import SwiftUI
@testable import PokeTokenBar

@MainActor
struct PokeRogueEffectComparison: View {
    let catalog: PokeRoguePreviewCatalog
    @State private var group=0
    @State private var selected="surf"
    @State private var began=Date()
    @State private var still: Double? = nil
    @State private var motion=true
    @State private var reverse=false
    @State private var autoNext=false
    @State private var readability=true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let rects=["own-0":CGRect(x:45,y:177,width:128,height:128),"foe-0":CGRect(x:405,y:25,width:128,height:128)]
    private let kinds=["background-without-effect-graphics","motion-without-effect-graphics","empty"]
    init(catalog: PokeRoguePreviewCatalog,initialMove: String="surf") {
        self.catalog=catalog
        let move=catalog.manifest.moves.first { $0.id == initialMove } ?? catalog.manifest.moves.first { $0.id == "surf" }!
        _selected=State(initialValue:move.id)
        _group=State(initialValue:move.classification == "empty" ? 2 : move.classification == "motion-without-effect-graphics" ? 1 : 0)
    }
    private var moves: [PokeRoguePreviewCatalog.Move] {
        let first=group == 0 ? ["surf","psychic","agility"] : group == 1 ? ["doubleteam","tailwhip","heatwave"] : ["naturepower","rest","secretpower"]
        return catalog.manifest.moves.filter { $0.classification == kinds[group] }.sorted {
            let a=first.firstIndex(of:$0.id) ?? 100,b=first.firstIndex(of:$1.id) ?? 100
            return a == b ? $0.id<$1.id : a<b
        }
    }
    private var animation: PokeRoguePreviewAnimation { catalog.animation(selected,opponent:reverse)! }
    private var selfTarget: Bool { BattleEffectCatalog.shared.recipe(for:selected)?.scope == "self" }
    private var event: BattleVisualEvent {
        let recipe=BattleEffectCatalog.shared.recipe(for:selected)
        return BattleVisualEvent(id:1,move:selected,type:recipe?.type ?? "Normal",category:recipe?.category ?? "Status",
            source:.init(own:!reverse,slot:0),targets:[.init(position:.init(own:selfTarget ? !reverse : reverse,slot:0),hit:true)],moveID:selected)
    }
    private func pokemon(_ own: Bool) -> BattleCombatant {
        .init(id:own ? "own" : "foe",speciesID:25,name:"Pikachu",level:37,shiny:false,active:true,form:nil,fainted:false,hp:143,maxHP:143,status:"",stats:nil)
    }
    private func next() {
        if let i=moves.firstIndex(where:{$0.id==selected}),i+1<moves.count { selected=moves[i+1].id }
        else if group<2 { group+=1;selected=moves.first!.id }
        else { autoNext=false }
        still=nil;began=Date()
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text("피카츄 · PokéRogue 배경 / 움직임 테스트").font(.title2.bold())
                    Text("기술 습득 제한을 적용하지 않는 시각 테스트 · GIF 재생 유지 · 피해량 / PP / 저장 데이터 변경 없음").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("자동으로 다음 기술",isOn:$autoNext).toggleStyle(.switch)
            }
            Picker("테스트 순서",selection:$group) {
                Text("① 배경 중심 · 15종").tag(0);Text("② 움직임 중심 · 30종").tag(1);Text("③ 마지막 · 원본 없음 3종").tag(2)
            }.pickerStyle(.segmented)
            HStack {
                Picker("기술",selection:$selected) {
                    ForEach(moves) { move in Text(BattleTextCatalog.shared.moveName(move.id,language:.ko)).tag(move.id) }
                }.frame(width:290)
                Text("\((moves.firstIndex(where:{$0.id==selected}) ?? 0)+1) / \(moves.count)").font(.caption.monospacedDigit())
                Spacer()
                Button("다시 재생") { still=nil;began=Date() }
                Button(group == 2 && selected==moves.last?.id ? "처음부터" : "다음 기술 →") {
                    if group == 2 && selected==moves.last?.id { group=0;selected="surf";began=Date();still=nil }
                    else { next() }
                }.buttonStyle(.borderedProminent)
            }
            Text(BattleTextCatalog.shared.description(selected,language:.ko)).font(.caption).foregroundStyle(.secondary)
            TimelineView(.animation(minimumInterval:1/60)) { timeline in
                let cycle=max(2.4,animation.duration+0.8)
                let elapsed=max(0,timeline.date.timeIntervalSince(began)).truncatingRemainder(dividingBy:cycle)
                let frame=reduceMotion ? animation.length*0.5 : (still.map { $0*max(1,animation.length) } ?? elapsed/0.05)
                HStack(spacing:18) {
                    panel(enhanced:false,frame:frame)
                    panel(enhanced:true,frame:frame)
                }
            }
            HStack(spacing:18) {
                Toggle("가시성 보완",isOn:$readability)
                Toggle("원본 이동·잔상·회전 적용",isOn:$motion)
                Toggle("상대 피카츄가 사용",isOn:$reverse)
                Button(still == nil ? "효과 정지" : "효과 재생") {
                    if still == nil { still=min(0.98,Date().timeIntervalSince(began).truncatingRemainder(dividingBy:max(2.4,animation.duration+0.8))/animation.duration) }
                    else { still=nil;began=Date() }
                }
                Slider(value:Binding(get:{still ?? 0},set:{still=$0}),in:0...0.99).frame(width:190)
                Text("효과 정지 중에도 GIF는 재생").font(.caption).foregroundStyle(.secondary)
            }
            Text(group == 2 ? "원본 JSON의 프레임이 0개입니다. 오른쪽은 의도적으로 효과를 추가하지 않았습니다. 왼쪽은 현재 앱의 보완 효과입니다." : "가시성 보완은 기술 설명에 맞춰 추가 제작한 파동·오라입니다. 체크를 끄면 PokéRogue 원본 데이터만 비교합니다. 포켓몬 GIF는 유지합니다.")
                .font(.caption).foregroundStyle(group == 2 ? .orange : .secondary)
        }.padding(22).frame(width:1206,height:610).background(Color(nsColor:.windowBackgroundColor))
        .onChange(of:group) { _,_ in selected=moves.first!.id;still=nil;began=Date() }
        .onChange(of:selected) { _,_ in still=nil;began=Date() }
        .onChange(of:reverse) { _,_ in still=nil;began=Date() }
        .task(id:autoNext) {
            guard autoNext else { return }
            while !Task.isCancelled && autoNext {
                let move=selected
                do { try await Task.sleep(for:.seconds(max(3,animation.duration+1))) } catch { return }
                if selected == move && still == nil { next() }
            }
        }
    }
    private func panel(enhanced: Bool,frame: Double) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(enhanced ? "PokéRogue\(readability && PokeRogueReadabilityProfile.resolve(event) != nil ? " + 가시성 보완" : "") · \(BattleTextCatalog.shared.moveName(selected,language:.ko))" : "현재 앱 · 기존 효과 / 움직임 유지").font(.headline)
            ZStack {
                LinearGradient(colors:[Color(red:0.61,green:0.70,blue:0.64),Color(red:0.86,green:0.87,blue:0.71)],startPoint:.top,endPoint:.bottom)
                if enhanced,let background=animation.background(at:frame) { backgroundView(background,progress:frame/max(1,animation.length)) }
                ForEach([true,false],id:\.self) { own in
                    let rect=rects[own ? "own-0" : "foe-0"]!
                    let poses=enhanced && motion ? animation.poses(at:frame,sourceOwn:!reverse,selfTarget:selfTarget,rects:rects).filter { $0.own == own } : []
                    if poses.isEmpty {
                        BattlePokemonStage(pokemon:pokemon(own),back:own,stageSize:128).position(x:rect.midX,y:rect.midY)
                    } else {
                        ForEach(Array(poses.enumerated()),id:\.element.id) { index,pose in
                            Group {
                                if index == 0 { BattlePokemonStage(pokemon:pokemon(own),back:own,stageSize:128) }
                                else { BattlePokemonSprite(pokemon:pokemon(own),back:own,size:BattleSpriteGeometry.imageBox(stageSize:128)) }
                            }.scaleEffect(x:pose.scaleX,y:pose.scaleY).rotationEffect(.degrees(pose.angle))
                                .blendMode(pose.blendType == 1 ? .plusLighter : pose.blendType == 2 ? .difference : .normal)
                                .colorMultiply(tint(pose.tone)).opacity(pose.opacity).position(x:pose.x,y:pose.y)
                        }
                    }
                }
                hp(own:false).position(x:162,y:58);hp(own:true).position(x:380,y:258)
                if !enhanced { BattleEffectCanvas(event:event,rects:rects,progress:frame/max(1,animation.length)) }
                if enhanced && readability {
                    PokeRogueReadabilityEffects(event:event,rects:rects,progress:frame/max(1,animation.length),reducedMotion:reduceMotion)
                }
                if enhanced && animation.frames.isEmpty {
                    Text("PokéRogue 원본 프레임 없음").font(.headline).padding(10).background(.black.opacity(0.72),in:Capsule()).foregroundStyle(.white).position(x:285,y:160)
                }
            }.frame(width:570,height:320).clipShape(RoundedRectangle(cornerRadius:10))
        }
    }
    private func tint(_ tone: [Double]) -> Color {
        guard tone.count>=3 else { return .white }
        return Color(red:max(0,min(1,1+tone[0]/255)),green:max(0,min(1,1+tone[1]/255)),blue:max(0,min(1,1+tone[2]/255)))
    }
    private func backgroundView(_ bg: PokeRoguePreviewAnimation.Background,progress: Double) -> some View {
        Canvas { context,size in
            context.opacity=readability ? (PokeRogueReadabilityProfile.resolve(event)?.backgroundOpacity(original:bg.opacity,progress:progress) ?? bg.opacity) : bg.opacity
            if bg.name.isEmpty { context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.black));return }
            guard let image=catalog.backgroundImage(bg.name) else { return }
            let scale=570.0/896*1.25,w=image.size.width*scale,h=image.size.height*scale
            guard w>0,h>0 else { return }
            // Tile the actual source PNG; phase follows the original background scrolling coordinates.
            let x=(bg.x*0.5*scale).truncatingRemainder(dividingBy:w),y=(bg.y*0.5*scale).truncatingRemainder(dividingBy:h)
            for row in -1...Int(ceil(size.height/h))+1 { for column in -1...Int(ceil(size.width/w))+1 {
                context.draw(Image(nsImage:image),in:CGRect(x:x+Double(column)*w,y:y+Double(row)*h,width:w,height:h))
            } }
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
