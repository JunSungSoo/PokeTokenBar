import AppKit
import SwiftUI

@MainActor
final class PokeRogueBattleCatalog {
    struct Entry: Decodable {
        let file: String
        let duration,length: Double
        let scope,kind,classification: String
        let supplement: Bool
        let discarded: Int
    }
    struct Catalog: Decodable {
        let revision: String
        let aliases: [String:String]
        let entries: [String:Entry]
    }
    static var directory: URL {
        let app=Bundle.main.resourceURL?.appendingPathComponent("PokeRogue")
        return app.flatMap { FileManager.default.fileExists(atPath:$0.appendingPathComponent("catalog.json").path) ? $0 : nil }
            ?? Bundle.module.url(forResource:"PokeRogue",withExtension:nil)!
    }
    static let shared=PokeRogueBattleCatalog()
    let catalog: Catalog
    private let animations=NSCache<NSString,AnimationBox>()
    private let images=NSCache<NSString,NSImage>()
    private let cells=NSCache<NSString,NSImage>()
    init() {
        catalog=try! JSONDecoder().decode(Catalog.self,from:Data(contentsOf:Self.directory.appendingPathComponent("catalog.json")))
        animations.countLimit=24;images.countLimit=16;cells.countLimit=160
    }
    func key(_ event: BattleVisualEvent) -> String {
        let raw=BattleTextCatalog.key(event.moveID ?? event.move)
        return (catalog.aliases[raw] ?? raw)+(event.phase == "charge" ? ":charge" : "")
    }
    func entry(_ event: BattleVisualEvent) -> Entry? { catalog.entries[key(event)] }
    func animation(_ event: BattleVisualEvent) -> PokeRoguePreviewAnimation? {
        let id=key(event)
        guard let entry=catalog.entries[id] else { return nil }
        let box: AnimationBox
        if let cached=animations.object(forKey:id as NSString) { box=cached }
        else {
            guard let data=try? Data(contentsOf:Self.directory.appendingPathComponent(entry.file)),
                  let values=try? JSONDecoder().decode([PokeRoguePreviewAnimation].self,from:data),!values.isEmpty else { return nil }
            box=AnimationBox(values);animations.setObject(box,forKey:id as NSString)
        }
        return box.values[!event.source.own && box.values.count>1 ? 1 : 0]
    }
    func image(_ name: String) -> NSImage? {
        if let image=images.object(forKey:name as NSString) { return image }
        guard let image=NSImage(contentsOf:Self.directory.appendingPathComponent("images/battle_anims/"+name+".png")) else { return nil }
        images.setObject(image,forKey:name as NSString);return image
    }
    func cell(_ name: String,index: Int) -> NSImage? {
        let key="\(name):\(index)" as NSString
        if let image=cells.object(forKey:key) { return image }
        guard index>=0,let source=image(name),let cg=source.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return nil }
        let columns=cg.width/96,rows=cg.height/96
        guard columns>0,index<columns*rows,
              let crop=cg.cropping(to:CGRect(x:index%columns*96,y:index/columns*96,width:96,height:96)) else { return nil }
        let image=NSImage(cgImage:crop,size:NSSize(width:96,height:96));cells.setObject(image,forKey:key);return image
    }
    private final class AnimationBox { let values: [PokeRoguePreviewAnimation];init(_ values: [PokeRoguePreviewAnimation]) { self.values=values } }
}

struct BattleEffectPlayback {
    let event: BattleVisualEvent
    let began: Date
    static let announcementLeadIn = 0.45
    static let interEventPause = 0.55
    @MainActor static func duration(_ event: BattleVisualEvent) -> Double {
        PokeRogueBattleCatalog.shared.entry(event)?.duration ?? PikachuMoveProfile.resolve(event)?.duration ?? BattleEffectCatalog.shared.duration(for:event)
    }
    @MainActor static func animationDuration(_ event: BattleVisualEvent) -> Double {
        max(2.2, duration(event) / 0.65)
    }
    @MainActor func progress(at date: Date) -> Double {
        max(0, min(1, date.timeIntervalSince(began) / Self.animationDuration(event)))
    }
}

@MainActor
struct PokeRogueBattleBackground: View {
    let playback: BattleEffectPlayback?
    let rects: [String:CGRect]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if let playback,!reduceMotion {
            TimelineView(.animation(minimumInterval:1/60)) { timeline in
                PokeRogueBattleCanvas(event:playback.event,rects:rects,
                    progress:playback.progress(at:timeline.date),behind:true)
            }
        }
    }
}

/// The importer removes every USER/TARGET operation. Only effect textures/backgrounds draw here.
@MainActor
struct PokeRogueBattleCanvas: View {
    let event: BattleVisualEvent
    let rects: [String:CGRect]
    let progress: Double
    var behind=false
    private let catalog=PokeRogueBattleCatalog.shared
    var body: some View {
        Canvas { context,size in
            guard progress>=0,progress<1,let entry=catalog.entry(event),let anim=catalog.animation(event),
                  let sourceRect=rects[event.source.key] else { return }
            let frame=progress*max(1,entry.length),hits=event.targets.filter(\.hit)
            guard !hits.isEmpty else { return }
            if behind,let bg=anim.background(at:frame) {
                var background=context
                background.opacity=PokeRogueReadabilityProfile.resolve(event)?.backgroundOpacity(original:bg.opacity,progress:progress) ?? bg.opacity
                if bg.name.isEmpty { background.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.black)) }
                else if let image=catalog.image(bg.name) {
                    let scale=size.width/896*1.25,w=image.size.width*scale,h=image.size.height*scale
                    if w>0,h>0 {
                        let x=(bg.x*0.5*scale).truncatingRemainder(dividingBy:w),y=(bg.y*0.5*scale).truncatingRemainder(dividingBy:h)
                        for row in -1...Int(ceil(size.height/h))+1 { for column in -1...Int(ceil(size.width/w))+1 {
                            background.draw(Image(nsImage:image),in:CGRect(x:x+Double(column)*w,y:y+Double(row)*h,width:w,height:h))
                        } }
                    }
                }
            }
            guard !anim.frames.isEmpty,Int(frame)<anim.frames.count else { return }
            let source=CGPoint(x:sourceRect.midX,y:sourceRect.midY),scale=sourceRect.width/128
            for operation in anim.frames[Int(frame)] where operation.target == 2 && operation.visible != false {
                let isBehind=operation.priority == 0 || operation.priority == 2
                guard isBehind == behind,let name=anim.graphic,let image=catalog.cell(name,index:operation.graphicFrame ?? 0) else { continue }
                let targets=(entry.scope == "self" || entry.scope == "field" || operation.focus == 2 || operation.focus == 4) ? Array(hits.prefix(1)) : hits
                for target in targets {
                    let bounds=entry.scope == "self" || event.phase == "charge" ? sourceRect : rects[target.position.key]
                    guard let bounds else { continue }
                    let destination=CGPoint(x:bounds.midX,y:bounds.midY),point=Self.point(operation,source:source,target:destination,scale:scale,size:size,own:event.source.own)
                    var layer=context
                    layer.opacity=max(0,min(1,(operation.opacity ?? 255)/255))
                    layer.blendMode=operation.blendType == 1 ? .plusLighter : operation.blendType == 2 ? .difference : .normal
                    if let hue=anim.hue,hue != 0 { layer.addFilter(.hueRotation(.degrees(hue))) }
                    layer.translateBy(x:point.x,y:point.y);layer.rotate(by:.degrees(-(operation.angle ?? 0)))
                    layer.scaleBy(x:(operation.zoomX ?? 100)/100*(operation.mirror == true ? -1 : 1),y:(operation.zoomY ?? 100)/100)
                    let side=96*scale
                    layer.draw(Image(nsImage:image),in:CGRect(x:-side/2,y:-side/2,width:side,height:side))
                }
            }
        }
    }
    static func point(_ op: PokeRoguePreviewFrame,source: CGPoint,target: CGPoint,scale: Double,size: CGSize,own: Bool) -> CGPoint {
        let direction=own ? 1.0 : -1.0
        if op.focus == 4 { return CGPoint(x:(op.x+106)/320*size.width,y:(op.y+116)/180*size.height) }
        if op.focus == 2 { return CGPoint(x:source.x+op.x*scale*direction,y:source.y+op.y*scale) }
        if op.focus == 3,source != target {
            let dx=target.x-source.x,dy=target.y-source.y,den=128.0*128+64.0*64
            let along=(op.x*128-op.y*64)/den,normal=(op.x*64+op.y*128)/den
            return CGPoint(x:source.x+along*dx-normal*dy,y:source.y+along*dy+normal*dx)
        }
        return CGPoint(x:target.x+(op.x-128)*scale*direction,y:target.y+(op.y+64)*scale)
    }
}

@MainActor
struct PokeRogueBattleEffects: View {
    let event: BattleVisualEvent
    let rects: [String:CGRect]
    let progress: Double
    var body: some View {
        ZStack {
            PokeRogueBattleCanvas(event:event,rects:rects,progress:progress)
            if PokeRogueReadabilityProfile.resolve(event) != nil {
                PokeRogueReadabilityEffects(event:event,rects:rects,progress:progress)
            } else if let entry=PokeRogueBattleCatalog.shared.entry(event),entry.supplement {
                BattleSemanticEffects(event:event,rects:rects,progress:progress,kind:entry.kind,scope:entry.scope)
            }
        }
    }
}
