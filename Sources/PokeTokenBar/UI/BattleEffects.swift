import SwiftUI

@MainActor
enum BattleMoveEffectRenderer {
    case pokeRogue, pikachu, standard

    static func resolve(_ event: BattleVisualEvent, reducedMotion: Bool = false) -> Self {
        guard !reducedMotion else { return .standard }
        if PokeRogueBattleCatalog.shared.entry(event) != nil { return .pokeRogue }
        if PikachuMoveProfile.resolve(event) != nil { return .pikachu }
        return .standard
    }
}

struct BattleSpriteAnchorKey: PreferenceKey {
    static var defaultValue: [String:Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String:Anchor<CGRect>],nextValue: () -> [String:Anchor<CGRect>]) {
        value.merge(nextValue(),uniquingKeysWith:{ _,new in new })
    }
}

@MainActor
struct BattleEffectsLayer: View {
    let events: [BattleVisualEvent]
    let rects: [String:CGRect]
    let messages: [Int: String]
    let originalPlayer:PokeRogueBattlePlayer?
    let actors:[PokeRogueActor]
    let viewport:CGSize
    var scenes: [Int: BattleScene] = [:]
    var onScene: (BattleScene) -> Void = { _ in }
    var onFinished: () -> Void = {}
    var onAnimatedScene: ((BattleScene) async -> Void)?
    @State private var notices = BattleNoticeQueue()
    @Binding var busy: Bool
    @Binding var playback: BattleEffectPlayback?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private let reducedMotionOverride: Bool?
    private var reduceMotion: Bool { reducedMotionOverride ?? systemReduceMotion }
    @State private var cursor: BattleEffectCursor
    @State private var active: BattleVisualEvent?
    @State private var started = Date()
    @State private var showmotion: ShowmotionPlayer?
    @State private var originalRequested = false
    @State private var pending: [(event: BattleVisualEvent, message: String?, scene: BattleScene?)] = []
    @State private var openingBatch = false
    @State private var openingThroughID = -1
    @State private var lastPresentedScene: BattleScene?
    @State private var draining = false
    @State private var runID = 0
    init(events: [BattleVisualEvent],rects: [String:CGRect],busy: Binding<Bool>,playback: Binding<BattleEffectPlayback?> = .constant(nil),messages: [Int: String] = [:],presentOpeningAbilities: Bool = false,reducedMotionOverride: Bool? = nil,scenes: [Int: BattleScene] = [:],onScene: @escaping (BattleScene) -> Void = { _ in },onFinished: @escaping () -> Void = {},onAnimatedScene: ((BattleScene) async -> Void)? = nil,originalPlayer:PokeRogueBattlePlayer?=nil,actors:[PokeRogueActor]=[],viewport:CGSize = .zero) {
        self.originalPlayer=originalPlayer;self.actors=actors;self.viewport=viewport
        self.events=events;self.rects=rects;self.messages=messages;_busy=busy
        self.scenes=scenes;self.onScene=onScene;self.onFinished=onFinished;self.onAnimatedScene=onAnimatedScene
        self.reducedMotionOverride=reducedMotionOverride
        _playback=playback
        _cursor=State(initialValue:BattleEffectCursor(events:presentOpeningAbilities ? events.filter { !["ability", "state", "transition", "field", "entry", "status", "health", "weather-hit"].contains($0.phase ?? "") } : events))
    }
    var body: some View {
        ZStack {
            // A permanently mounted surface is required: an empty Group never starts .task.
            Color.clear
            if let showmotion {
                ShowmotionSurface(player:showmotion).frame(maxWidth:.infinity,maxHeight:.infinity).opacity(originalRequested ? 1 : 0)
                if showmotion.isPlaying {
                    Text("Showmotion").font(.caption2.bold()).padding(5)
                        .background(.black.opacity(0.65),in:Capsule()).foregroundStyle(.white)
                        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).padding(8)
                }
                if originalRequested && !showmotion.isPlaying { ProgressView().controlSize(.small) }
            }
            if let active, !originalRequested, originalPlayer == nil {
                TimelineView(.animation(minimumInterval:1/60,paused:reduceMotion)) { timeline in
                    let progress=BattleEffectPlayback(event:active,began:started).progress(at:timeline.date)
                    switch BattleMoveEffectRenderer.resolve(active, reducedMotion: reduceMotion) {
                    case .pokeRogue:
                        PokeRogueBattleEffects(event:active,rects:rects,progress:progress)
                    case .pikachu:
                        PikachuMoveEffects(event:active,rects:rects,progress:progress)
                    case .standard:
                        BattleEffectCanvas(event:active,rects:rects,progress:reduceMotion ? 0.8 : progress,reducedMotion:reduceMotion)
                    }
                }
            }
            if !notices.entries.isEmpty { BattleNoticeStack(notices: notices.entries) }
        }.onChange(of:events,initial:true) { _, current in
            let incoming=cursor.takeNew(current)
            guard !incoming.isEmpty else { return }
            if cursor.lastSeen == current.last?.id, !draining, pending.isEmpty,
               current.first?.id == incoming.first?.id,
               incoming.contains(where:{$0.phase=="entry"}), scenes.values.allSatisfy({$0.turn<=1}) {
                openingBatch=true
                openingThroughID=incoming.last?.id ?? -1
                originalPlayer?.entryHiddenPositions=Set(incoming.filter{$0.phase=="entry"}.map{ $0.source.key })
            }
            pending.append(contentsOf:incoming.map { ($0,messages[$0.id],scenes[$0.id]) })
            if !draining { draining=true;busy=true;runID += 1 }
        }.task(id:runID) { [runID] in
            guard runID > 0, draining else { return }
            defer { active=nil;busy=false;draining=false;originalRequested=false;playback=nil;openingBatch=false;originalPlayer?.entryHiddenPositions=[] }
            while !pending.isEmpty {
                guard !Task.isCancelled else { return }
                let item=pending.removeFirst(),event=item.event
                var batch=[item]
                if let next=pending.first,BattleEntryEffects.canAppearTogether(event,next.event) { batch.append(pending.removeFirst()) }
                if event.phase == "health" {
                    while let next=pending.first,next.event.phase=="health",!batch.contains(where:{$0.event.source==next.event.source}) {
                        batch.append(pending.removeFirst())
                    }
                }
                let finalScene=batch.last?.scene
                let isOpening=openingBatch && event.id<=openingThroughID
                if openingBatch && !isOpening { openingBatch=false;originalPlayer?.entryHiddenPositions=[] }
                for member in batch { if let message=member.message { notices.append(id:member.event.id,text:message) } }
                if event.phase == "state" || event.phase == "transition" || event.phase == "health" {
                    active=nil;playback=nil
                    do {
                        if event.phase == "transition" { try await Task.sleep(for: .seconds(0.45)) }
                        if let scene=finalScene, !isOpening { await present(scene) }
                        try await Task.sleep(for: .seconds(event.phase == "transition" ? 0.75 : event.phase == "health" ? 0.1 : 0.25))
                        for member in batch { notices.finish(id:member.event.id) }
                    } catch { return }
                    continue
                }
                if event.phase == "ability" {
                    if let scene=finalScene, !isOpening { await present(scene) }
                    active=nil;playback=nil
                    do {
                        try await Task.sleep(for: .seconds(1.8))
                        for member in batch { notices.finish(id:member.event.id) }
                        try await Task.sleep(for: .seconds(BattleEffectPlayback.interEventPause))
                    }
                    catch { return }
                    continue
                }
                // Announce the move before its animation starts, then keep the same notice
                // throughout both background and foreground playback.
                do { if event.phase != "weather-hit" { try await Task.sleep(for:.seconds(BattleEffectPlayback.announcementLeadIn)) } }
                catch { return }
                started=Date();active=event
                playback=BattleEffectPlayback(event:event,began:started)
                var originalPlayed=false
                if let originalPlayer {
                    let eventActors=actors.compactMap { actor -> PokeRogueActor? in
                        guard let scene=finalScene else{return actor}
                        let members=actor.position.own ? scene.own.filter(\.active):scene.foe
                        guard members.indices.contains(actor.position.slot) else{return isOpening ? actor:nil}
                        return PokeRogueActor(pokemon:members[actor.position.slot],position:actor.position,rect:actor.rect,pixelScale:actor.pixelScale)
                    }
                    if event.phase == "entry" {
                        let old:[PokeRogueActor]=isOpening ? []:batch.compactMap { member in
                            let position=member.event.source
                            let priorMembers=position.own ? lastPresentedScene?.own.filter(\.active):lastPresentedScene?.foe
                            guard let actor=actors.first(where:{$0.position==position}) else{return nil}
                            let pokemon=priorMembers.flatMap { $0.indices.contains(position.slot) ? $0[position.slot]:nil } ?? actor.pokemon
                            return PokeRogueActor(pokemon:pokemon,position:position,rect:actor.rect,pixelScale:actor.pixelScale)
                        }
                        var revealed=false
                        let reveal={
                            guard !revealed else{return};revealed=true
                            for member in batch {
                                originalPlayer.entryHiddenPositions.remove(member.event.source.key)
                                if let scene=member.scene,!isOpening { onScene(scene);lastPresentedScene=scene }
                            }
                        }
                        _ = await originalPlayer.play(event,actors:eventActors,size:viewport,reducedMotion:reduceMotion,entrySources:batch.map{$0.event.source},previousActors:old,beforeFinish:reveal)
                        guard !Task.isCancelled else{return}
                        reveal()
                    } else {
                        _ = await originalPlayer.play(event,actors:eventActors,size:viewport,reducedMotion:reduceMotion)
                    }
                    guard !Task.isCancelled else{return}
                    originalPlayed=true // Never substitute another renderer if original playback fails.
                }
                if originalPlayer == nil,!reduceMotion,BattleMoveEffectRenderer.resolve(event) != .pokeRogue, ShowmotionPlayer.supports(event),
                   BattleEffectCatalog.shared.recipe(for:event.moveID ?? event.move)?.generation == nil {
                    let player=showmotion ?? ShowmotionPlayer();showmotion=player;originalRequested=true
                    let played=await player.play(event,rects:rects)
                    originalRequested=false
                    guard !Task.isCancelled else { return }
                    originalPlayed=played
                    if !played { started=Date();playback=BattleEffectPlayback(event:event,began:started) }
                }
                do {
                    if !originalPlayed {
                        try await Task.sleep(for:.seconds(reduceMotion ? 1.4 : BattleEffectPlayback.animationDuration(event)))
                    }
                    active=nil;playback=nil;for member in batch { notices.finish(id:member.event.id) }
                    if event.phase != "entry", let scene=item.scene, !isOpening { await present(scene) }
                    try await Task.sleep(for:.seconds(BattleEffectPlayback.interEventPause))
                }
                catch { return }
            }
            onFinished()
        }.task(id: notices.entries) {
            guard let expiry = notices.nextExpiry else { return }
            do { try await Task.sleep(for: .seconds(max(0, expiry.timeIntervalSinceNow))) }
            catch { return }
            notices.expire()
        }.onDisappear { notices = BattleNoticeQueue();pending=[];draining=false;busy=false;playback=nil;showmotion?.stop();showmotion=nil;onFinished() }
    }
    private func present(_ scene:BattleScene) async {
        if let onAnimatedScene { await onAnimatedScene(scene) } else { onScene(scene) }
        lastPresentedScene=scene
    }
    static func presentationDuration(_ event: BattleVisualEvent, reducedMotion: Bool = false) -> Double {
        if event.phase == "entry" { return 5 }
        if event.phase == "health" { return 0.9 }
        if event.phase == "weather-hit" { return 0.5 + BattleEffectPlayback.interEventPause }
        if event.phase == "state" { return 0.25 }
        if event.phase == "transition" { return 1.2 }
        if event.phase == "ability" { return 1.8 + BattleEffectPlayback.interEventPause }
        return BattleEffectPlayback.announcementLeadIn + (reducedMotion ? 1.4 : BattleEffectPlayback.animationDuration(event)) + BattleEffectPlayback.interEventPause
    }

}

/// Offline textures and bounded particles rendered only while a move is active.
/// No idle timers, remote requests, or layout changes in the battle stage.
@MainActor
struct BattleEffectCanvas: View {
    let event: BattleVisualEvent
    let rects: [String:CGRect]
    let progress: Double
    var reducedMotion = false
    var recipe: BattleEffectRecipe? { BattleEffectCatalog.shared.recipe(for:event.moveID ?? event.move,phase:event.phase) }
    var body: some View {
        if !reducedMotion, let recipe, !recipe.operations.isEmpty {
            BattleRecipeCanvas(event:event,recipe:recipe,rects:rects,progress:progress)
                .overlay { if BattleTextCatalog.key(event.moveID ?? event.move) == "protect" { fallback } }
        } else {
            fallback
        }
    }
    private var fallback: some View {
        Canvas(rendersAsynchronously:false) { context,size in
            guard let sourceRect=rects[event.source.key] else { return }
            let source=CGPoint(x:sourceRect.midX,y:sourceRect.midY)
            let p=max(0,min(1,progress)), color=Self.color(event.type)
            let targets: [BattleEffectTarget]
            if recipe?.scope == "self" || event.phase == "charge" { targets=[BattleEffectTarget(position:event.source,hit:event.targets.contains { $0.hit })] }
            else if recipe?.scope == "field" { targets=Array(event.targets.filter(\.hit).prefix(1)) }
            else { targets=event.targets }
            for (index,target) in targets.enumerated() {
                guard let rect=rects[target.position.key] else { continue }
                let point=recipe?.scope == "field" ? CGPoint(x:size.width/2,y:size.height/2) : CGPoint(x:rect.midX,y:rect.midY)
                var layer=context
                if reducedMotion {
                    guard target.hit else { continue }
                    ring(&layer,center:point,radius:25,color:color.opacity(0.6),width:2)
                    continue
                }
                if event.category == "Status" || event.phase == "charge" {
                    guard target.hit else { continue }
                    aura(&layer,center:point,p:p,color:color)
                } else {
                    projectile(&layer,from:source,to:point,p:p,color:color,seed:index)
                    if target.hit { impact(&layer,center:point,p:p,color:color) }
                }
            }
        }
    }
    static func color(_ type: String) -> Color {
        switch type.lowercased() {
        case "electric": return Color(red:1,green:0.76,blue:0.1)
        case "fire": return Color(red:1,green:0.28,blue:0.08)
        case "water","ice": return Color(red:0.15,green:0.75,blue:1)
        case "grass","bug": return Color(red:0.35,green:0.86,blue:0.26)
        case "psychic","fairy": return Color(red:1,green:0.3,blue:0.7)
        case "ghost","poison","dark": return Color(red:0.64,green:0.3,blue:0.96)
        case "dragon": return Color(red:0.42,green:0.48,blue:1)
        case "ground","rock": return Color(red:0.70,green:0.43,blue:0.2)
        case "steel","flying": return Color(red:0.68,green:0.85,blue:0.95)
        case "fighting": return Color(red:1,green:0.48,blue:0.2)
        default: return Color(red:0.95,green:0.87,blue:0.64)
        }
    }
    private func disk(_ context: inout GraphicsContext,center: CGPoint,radius: Double,color: Color) {
        let rect=CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)
        context.fill(Path(ellipseIn:rect),with:.color(color))
    }
    private func glow(_ context: inout GraphicsContext,center: CGPoint,radius: Double,color: Color) {
        let rect=CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)
        context.fill(Path(ellipseIn:rect),with:.radialGradient(Gradient(colors:[color.opacity(0.65),color.opacity(0)]),
            center:center,startRadius:0,endRadius:radius))
    }
    private func ring(_ context: inout GraphicsContext,center: CGPoint,radius: Double,color: Color,width: Double) {
        context.stroke(Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)),
            with:.color(color),style:StrokeStyle(lineWidth:width,lineCap:.round))
    }
    private func projectile(_ context: inout GraphicsContext,from: CGPoint,to: CGPoint,p: Double,color: Color,seed: Int) {
        let travel=max(0,min(1,(p-0.12)/0.53)), fade=min(1,max(0,(0.8-p)/0.15))
        guard fade > 0 else { return }
        glow(&context,center:from,radius:20+travel*12,color:color.opacity((1-travel)*fade))
        let type=event.type.lowercased()
        if type == "electric" && p > 0.16 {
            var bolt=Path()
            let end=CGPoint(x:from.x+(to.x-from.x)*travel,y:from.y+(to.y-from.y)*travel)
            let dx=end.x-from.x,dy=end.y-from.y,d=max(1,hypot(dx,dy))
            for i in 0...14 {
                let t=Double(i)/14, jitter=i==0 || i==14 ? 0 : (i%2==0 ? 1.0 : -1.0)*(8+sin(Double(i)*2.4+p*93+Double(seed))*5)
                let point=CGPoint(x:from.x+dx*t-dy/d*jitter,y:from.y+dy*t+dx/d*jitter)
                if i==0 { bolt.move(to:point) } else { bolt.addLine(to:point) }
            }
            var light=context;light.addFilter(.shadow(color:color.opacity(0.9),radius:5))
            light.stroke(bolt,with:.color(color.opacity(fade)),style:StrokeStyle(lineWidth:4.5,lineCap:.round,lineJoin:.miter))
            light.stroke(bolt,with:.color(.white.opacity(fade)),style:StrokeStyle(lineWidth:1.7,lineCap:.round,lineJoin:.miter))
            for fraction in [0.35,0.7] {
                let origin=CGPoint(x:from.x+dx*fraction,y:from.y+dy*fraction)
                let side=fraction < 0.5 ? 1.0 : -1.0
                var branch=Path();branch.move(to:origin)
                branch.addLine(to:CGPoint(x:origin.x-dy/d*14*side,y:origin.y+dx/d*14*side))
                branch.addLine(to:CGPoint(x:origin.x+dx/d*15-dy/d*25*side,y:origin.y+dy/d*15+dx/d*25*side))
                light.stroke(branch,with:.color(color.opacity(fade*0.8)),style:StrokeStyle(lineWidth:2,lineJoin:.miter))
            }
        } else {
            for i in 0..<16 {
                let t=travel-Double(i)*0.026
                guard t >= 0 && t <= 1 else { continue }
                let wave=sin(t*Double.pi)*sin(Double(i)*2.4)*9
                let point=CGPoint(x:from.x+(to.x-from.x)*t,y:from.y+(to.y-from.y)*t-sin(t*Double.pi)*20+wave)
                let alpha=(1-Double(i)/18)*fade
                if type == "grass" || type == "bug" || type == "ice" {
                    var shape=Path()
                    let r=4+Double(i%3)
                    shape.move(to:CGPoint(x:point.x,y:point.y-r*1.6));shape.addLine(to:CGPoint(x:point.x+r,y:point.y))
                    shape.addLine(to:CGPoint(x:point.x,y:point.y+r*1.6));shape.addLine(to:CGPoint(x:point.x-r,y:point.y));shape.closeSubpath()
                    context.fill(shape,with:.color(color.opacity(alpha)))
                } else {
                    glow(&context,center:point,radius:14-Double(i)*0.4,color:color.opacity(alpha))
                    disk(&context,center:point,radius:max(2,7-Double(i)*0.3),color:color.opacity(alpha))
                    if i<3 { disk(&context,center:point,radius:2,color:.white.opacity(alpha)) }
                }
            }
        }
    }
    private func impact(_ context: inout GraphicsContext,center: CGPoint,p: Double,color: Color) {
        let t=(p-0.58)/0.42
        guard t > 0 && t < 1 else { return }
        let alpha=1-t
        glow(&context,center:center,radius:26+t*34,color:color.opacity(alpha))
        ring(&context,center:center,radius:8+t*42,color:color.opacity(alpha),width:3*(1-t)+1)
        for i in 0..<14 {
            let angle=Double(i)*Double.pi*2/14, distance=10+t*(35+Double(i%3)*9)
            let point=CGPoint(x:center.x+cos(angle)*distance,y:center.y+sin(angle)*distance*0.75)
            disk(&context,center:point,radius:(1-t)*3+1,color:i%3==0 ? .white.opacity(alpha) : color.opacity(alpha))
        }
        if event.category == "Physical" {
            for i in -1...1 {
                var slash=Path()
                let shift=Double(i)*12
                slash.move(to:CGPoint(x:center.x-22+shift,y:center.y+22))
                slash.addQuadCurve(to:CGPoint(x:center.x+20+shift,y:center.y-24),control:CGPoint(x:center.x+shift,y:center.y-18))
                context.stroke(slash,with:.color(.white.opacity(alpha)),style:StrokeStyle(lineWidth:4*alpha+1,lineCap:.round))
            }
        }
    }
    private func aura(_ context: inout GraphicsContext,center: CGPoint,p: Double,color: Color) {
        let alpha=sin(p*Double.pi)
        glow(&context,center:center,radius:42,color:color.opacity(alpha*0.7))
        for i in 0..<3 {
            let t=(p+Double(i)/3).truncatingRemainder(dividingBy:1)
            ring(&context,center:center,radius:12+t*35,color:color.opacity((1-t)*alpha),width:2)
        }
        if BattleTextCatalog.key(event.moveID ?? event.move) == "protect" {
            let shield=Path(roundedRect:CGRect(x:center.x-25,y:center.y-33,width:50,height:66),cornerRadius:20)
            context.fill(shield,with:.color(color.opacity(alpha*0.25)))
            context.stroke(shield,with:.color(.white.opacity(alpha)),lineWidth:2)
        }
    }
}
