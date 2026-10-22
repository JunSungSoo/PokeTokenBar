import AppKit
import Foundation

/// Development-only format adapter. The actual battle engine never consumes these fixtures.
struct PokeRoguePreviewFrame: Decodable {
    let x,y: Double
    let zoomX,zoomY,angle,opacity: Double?
    let visible,mirror: Bool?
    let target: Int
    let blendType: Int?
    let graphicFrame: Int?
    let priority: Int?
    let focus: Int?
    let tone: [Double]?
}
struct PokeRoguePreviewEvent: Decodable {
    let resourceName: String?
    let eventType: String
    let bgX,bgY,opacity,duration: Double?
}
struct PokeRoguePreviewAnimation: Decodable {
    let graphic: String?
    let hue: Double?
    let frames: [[PokeRoguePreviewFrame]]
    let frameTimedEvents: [String:[PokeRoguePreviewEvent]]
    var length: Double {
        max(Double(frames.count),frameTimedEvents.flatMap { key,events in events.map { (Double(key) ?? 0)+($0.duration ?? 0) } }.max() ?? 0)
    }
    // Upstream animates one imported frame per getFrameMs(3), at its 60 Hz base cadence.
    var duration: Double { max(0.8,length*0.05) }
    struct Background {
        let name: String
        let x,y,opacity: Double
    }
    private struct Tween {
        var start=0.0,duration=0.0,from=0.0,to=0.0
        func value(_ frame: Double) -> Double { duration<=0 ? to : from+(to-from)*max(0,min(1,(frame-start)/duration)) }
        mutating func set(_ target: Double,at frame: Double,duration: Double) {
            let current=value(frame);self=Tween(start:frame,duration:duration,from:current,to:target)
        }
        mutating func reset(_ value: Double,at frame: Double) { self=Tween(start:frame,duration:0,from:value,to:value) }
    }
    func background(at frame: Double) -> Background? {
        guard !frames.isEmpty,frame>=0,frame<length else { return nil }
        var name: String?,x=Tween(),y=Tween(),alpha=Tween()
        for key in frameTimedEvents.keys.sorted(by:{ (Double($0) ?? 0)<(Double($1) ?? 0) }) {
            let start=Double(key) ?? 0
            guard start<=frame else { break }
            for event in frameTimedEvents[key] ?? [] {
                if event.eventType == "AnimTimedAddBgEvent" {
                    name=event.resourceName ?? ""
                    x.reset(event.bgX ?? 0,at:start);y.reset(event.bgY ?? 0,at:start);alpha.reset(event.opacity ?? 0,at:start)
                } else if event.eventType == "AnimTimedUpdateBgEvent",name != nil {
                    if let target=event.bgX { x.set(target,at:start,duration:event.duration ?? 0) }
                    if let target=event.bgY { y.set(target,at:start,duration:event.duration ?? 0) }
                    if let target=event.opacity { alpha.set(target,at:start,duration:event.duration ?? 0) }
                }
            }
        }
        return name.map { Background(name:$0,x:x.value(frame),y:y.value(frame),opacity:max(0,min(1,alpha.value(frame)/255))) }
    }
    struct Pose: Identifiable {
        let id: Int
        let own: Bool
        let x,y,scaleX,scaleY,angle,opacity: Double
        let tone: [Double]
        let blendType: Int
    }
    func poses(at frame: Double,sourceOwn: Bool,selfTarget: Bool,rects: [String:CGRect]) -> [Pose] {
        guard frame>=0,frame<Double(frames.count),let source=rects[sourceOwn ? "own-0" : "foe-0"],
              let target=rects[selfTarget ? (sourceOwn ? "own-0" : "foe-0") : (sourceOwn ? "foe-0" : "own-0")] else { return [] }
        let s=CGPoint(x:source.midX,y:source.midY),t=CGPoint(x:target.midX,y:target.midY)
        let scale=source.width/128,direction=sourceOwn ? 1.0 : -1.0
        return frames[Int(frame)].enumerated().compactMap { index,entry in
            guard entry.target == 0 || entry.target == 1,entry.visible != false,
                  !(selfTarget && entry.target == 0) else { return nil }
            let own=entry.target == 0 ? sourceOwn : (selfTarget ? sourceOwn : !sourceOwn)
            let anchor=entry.target == 0 ? s : t
            var point: CGPoint
            if entry.focus == 3 && !selfTarget {
                // Source-format baselines are (0,0) and (128,-64); use the same affine line map.
                let dx=t.x-s.x,dy=t.y-s.y,den=128.0*128+64.0*64
                let along=(entry.x*128-entry.y*64)/den,normal=(entry.x*64+entry.y*128)/den
                point=CGPoint(x:s.x+along*dx-normal*dy,y:s.y+along*dy+normal*dx)
            } else {
                let baseX=entry.target == 0 ? 0.0 : 128.0,baseY=entry.target == 0 ? 0.0 : -64.0
                point=CGPoint(x:anchor.x+(entry.x-baseX)*scale*direction,y:anchor.y+(entry.y-baseY)*scale)
            }
            return Pose(id:index,own:own,x:point.x,y:point.y,
                scaleX:(entry.zoomX ?? 100)/100*(entry.mirror == true ? -1 : 1),scaleY:(entry.zoomY ?? 100)/100,
                angle:-(entry.angle ?? 0)*direction,opacity:max(0,min(1,(entry.opacity ?? 255)/255)),tone:entry.tone ?? [],blendType:entry.blendType ?? 0)
        }
    }
}

@MainActor
final class PokeRoguePreviewCatalog {
    struct Move: Decodable, Identifiable {
        var id: String { move }
        let move,path,classification: String
    }
    struct Manifest: Decodable {
        let revision: String
        let moves: [Move]
        let sha256: [String:String]
    }
    let directory: URL
    let manifest: Manifest
    private var animations: [String:[PokeRoguePreviewAnimation]] = [:]
    private var images: [String:NSImage] = [:]
    init(directory: URL) throws {
        self.directory=directory
        manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:directory.appendingPathComponent("manifest.json")))
        for move in manifest.moves {
            let data=try Data(contentsOf:directory.appendingPathComponent(move.path))
            if let multiple=try? JSONDecoder().decode([PokeRoguePreviewAnimation].self,from:data) { animations[move.id]=multiple }
            else { animations[move.id]=[try JSONDecoder().decode(PokeRoguePreviewAnimation.self,from:data)] }
        }
    }
    func animation(_ id: String,opponent: Bool=false) -> PokeRoguePreviewAnimation? {
        guard let variants=animations[id] else { return nil }
        return variants[opponent && variants.count>1 ? 1 : 0]
    }
    func backgroundImage(_ name: String) -> NSImage? {
        if let image=images[name] { return image }
        guard let image=NSImage(contentsOf:directory.appendingPathComponent("images/battle_anims/"+name+".png")) else { return nil }
        images[name]=image;return image
    }
}
