import AppKit
import SwiftUI

@MainActor
final class BattleEffectTextures {
    static let shared = BattleEffectTextures()
    private var images: [String:NSImage] = [:]
    func image(_ name: String) -> NSImage? {
        if let image = images[name] { return image }
        guard let image = NSImage(contentsOf:BattleEffectCatalog.resourceDirectory.appendingPathComponent("textures/"+name)) else { return nil }
        images[name] = image
        return image
    }
}

/// Only effect operations are replayed. The Pokémon view and its animation state are untouched.
@MainActor
struct BattleRecipeCanvas: View {
    let event: BattleVisualEvent
    let recipe: BattleEffectRecipe
    let rects: [String:CGRect]
    let progress: Double
    var body: some View {
        Canvas { context,size in
            guard progress >= 0 && progress < 1, let sourceRect=rects[event.source.key] else { return }
            let origin=CGPoint(x:sourceRect.midX,y:sourceRect.midY)
            let time=progress*recipe.duration*1000/recipe.timeScale
            let targets: [BattleEffectTarget]
            if recipe.scope == "self" { targets=[BattleEffectTarget(position:event.source,hit:event.targets.contains { $0.hit })] }
            else if recipe.scope == "field" { targets=Array(event.targets.filter(\.hit).prefix(1)) }
            else { targets=event.targets }
            for target in targets where target.hit {
                guard let targetRect=rects[target.position.key] else { continue }
                let destination=recipe.scope == "field" ? CGPoint(x:size.width/2,y:size.height/2) : CGPoint(x:targetRect.midX,y:targetRect.midY)
                let scale=min(sourceRect.width,targetRect.width)/145
                for operation in recipe.operations {
                    draw(operation,time:time,origin:origin,destination:destination,scale:scale,context:&context)
                }
            }
        }
    }
    private func draw(_ op: BattleEffectRecipe.Operation,time: Double,origin: CGPoint,destination: CGPoint,
                      scale: Double,context: inout GraphicsContext) {
        let tail=op.after == "fade" || op.after == "explode" ? 180.0 : 0
        guard time >= op.begin && time < op.finish+tail else { return }
        let raw=max(0,min(1,(time-op.begin)/max(1,op.finish-op.begin)))
        let t: Double
        switch op.easing {
        case "accel","quadUp": t=raw*raw
        case "decel","quadDown": t=1-(1-raw)*(1-raw)
        case "swing": t=(1-cos(raw * .pi))/2
        default: t=raw
        }
        func lerp(_ a: Double,_ b: Double) -> Double { a+(b-a)*t }
        let z=lerp(op.start.z,op.end.z)/200
        let direction=event.source.own ? 1.0 : -1.0
        var point=CGPoint(x:origin.x+(destination.x-origin.x)*z+lerp(op.start.x,op.end.x)*scale*direction,
                          y:origin.y+(destination.y-origin.y)*z-lerp(op.start.y,op.end.y)*scale)
        if op.easing.lowercased().contains("ballistic") {
            point.y -= sin(raw * .pi)*35*scale*(op.easing.lowercased().contains("under") ? -1 : 1)
        }
        let fade=tail>0 ? max(0,1-max(0,time-op.finish)/tail) : 1
        let expansion=op.after == "explode" ? 1+max(0,time-op.finish)/180*2 : 1
        let perspective=max(0.45,1-0.3*z)
        let width=max(0,op.width*lerp(op.start.scaleX,op.end.scaleX)*scale*perspective*expansion)
        let height=max(0,op.height*lerp(op.start.scaleY,op.end.scaleY)*scale*perspective*expansion)
        guard width>0 && height>0 else { return }
        var layer=context
        layer.opacity=max(0,min(1,lerp(op.start.opacity,op.end.opacity)*fade))
        let rect=CGRect(x:point.x-width/2,y:point.y-height/2,width:width,height:height)
        if let texture=op.texture, let image=BattleEffectTextures.shared.image(texture) {
            layer.draw(Image(nsImage:image),in:rect)
        } else {
            // Explicitly excluded upstream textures / HTML effects use our own vector shapes.
            let color=BattleEffectCanvas.color(event.type)
            var path=Path()
            if op.effect == "lightning" {
                for i in 0...10 {
                    let p=CGPoint(x:point.x+(i%2 == 0 ? -0.22 : 0.22)*width,
                                  y:rect.minY+Double(i)/10*height)
                    if i == 0 { path.move(to:p) } else { path.addLine(to:p) }
                }
                layer.addFilter(.shadow(color:color,radius:5))
                layer.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:4,lineCap:.round))
                layer.stroke(path,with:.color(.white),lineWidth:1.5)
            } else if op.effect.contains("icicle") || op.effect.contains("rock") || op.effect == "bone" {
                path.move(to:CGPoint(x:point.x,y:rect.minY));path.addLine(to:CGPoint(x:rect.maxX,y:point.y))
                path.addLine(to:CGPoint(x:point.x,y:rect.maxY));path.addLine(to:CGPoint(x:rect.minX,y:point.y));path.closeSubpath()
                layer.fill(path,with:.linearGradient(Gradient(colors:[.white,color]),startPoint:rect.origin,
                    endPoint:CGPoint(x:rect.maxX,y:rect.maxY)))
            } else {
                path=Path(roundedRect:rect,cornerRadius:min(width,height)/3)
                layer.fill(path,with:.color(color.opacity(0.18)))
                layer.stroke(path,with:.color(color),lineWidth:2)
            }
        }
    }
}
