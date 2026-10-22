import SwiftUI

/// Description/dex-derived additions for motion-only, empty, sparse or invalid imported effects.
/// These are effect geometry; Pokémon frames, opacity, transforms and stats are never changed.
@MainActor
struct BattleSemanticEffects: View {
    let event: BattleVisualEvent
    let rects: [String:CGRect]
    let progress: Double
    let kind,scope: String
    var body: some View {
        Canvas { context,size in
            guard progress>0,progress<1,let sourceRect=rects[event.source.key] else { return }
            let hits=event.targets.filter(\.hit)
            guard !hits.isEmpty else { return }
            let source=CGPoint(x:sourceRect.midX,y:sourceRect.midY),scale=sourceRect.width/128,p=progress,alpha=pow(sin(p * .pi),0.7)
            let color=kind == "heal" ? Color.green : BattleEffectCanvas.color(event.type)
            let caster=scope == "self" || kind == "charge" || kind == "copy" || kind == "vanish"
            let targets=(caster || scope == "field") ? Array(hits.prefix(1)) : hits
            for target in targets {
                guard let bounds=rects[target.position.key] else { continue }
                let point=caster ? source : scope == "field" ? CGPoint(x:size.width/2,y:size.height/2) : CGPoint(x:bounds.midX,y:bounds.midY)
                let radius=(25+sin(p * .pi)*29)*scale
                glow(&context,point,radius*1.6,color,alpha*0.45)
                switch kind {
                case "heal":
                    for i in 0..<8 {
                        let t=(p+Double(i)/8).truncatingRemainder(dividingBy:1),x=point.x+sin(Double(i)*2.4)*36*scale,y=point.y+40*scale-t*90*scale
                        var cross=Path();cross.move(to:CGPoint(x:x-5*scale,y:y));cross.addLine(to:CGPoint(x:x+5*scale,y:y));cross.move(to:CGPoint(x:x,y:y-5*scale));cross.addLine(to:CGPoint(x:x,y:y+5*scale))
                        stroke(&context,cross,.green,2*scale,alpha*sin(t * .pi))
                    }
                    ring(&context,point,radius,.green,alpha)
                case "shield":
                    let path=Path(roundedRect:CGRect(x:point.x-44*scale,y:point.y-55*scale,width:88*scale,height:110*scale),cornerRadius:25*scale)
                    context.fill(path,with:.color(color.opacity(alpha*0.14)));stroke(&context,path,color,2.5*scale,alpha)
                    ring(&context,point,radius*0.8,.white,alpha*0.6)
                case "exchange":
                    for direction in [false,true] { for i in 0..<14 {
                        let t=(p+Double(i)/14).truncatingRemainder(dividingBy:1),u=direction ? 1-t : t
                        let dot=CGPoint(x:source.x+(point.x-source.x)*u,y:source.y+(point.y-source.y)*u+sin(u * .pi)*(direction ? 20 : -20)*scale)
                        glow(&context,dot,5*scale,direction ? .cyan : color,alpha)
                    } }
                    ring(&context,source,35*scale,color,alpha);ring(&context,point,35*scale,.cyan,alpha)
                case "copy","vanish":
                    for i in 0..<3 {
                        let r=(18+((p+Double(i)/3).truncatingRemainder(dividingBy:1))*45)*scale
                        ring(&context,point,r,i%2 == 0 ? color : .white,alpha*0.7)
                    }
                    for i in 0..<8 { let a=Double(i)/8*2 * .pi+p*2
                        glow(&context,CGPoint(x:point.x+cos(a)*radius,y:point.y+sin(a)*radius),4*scale,color,alpha)
                    }
                case "weather","field":
                    let id=BattleTextCatalog.key(event.moveID ?? event.move)
                    if kind == "field" {
                        ring(&context,point,radius*1.6,color,alpha*0.8)
                        for i in 0..<8 { let a=Double(i)*Double.pi/4
                            let center=CGPoint(x:point.x+cos(a)*radius,y:point.y+sin(a)*radius*0.3)
                            var shard=Path();shard.move(to:CGPoint(x:center.x-5*scale,y:center.y));shard.addLine(to:CGPoint(x:center.x,y:center.y-16*scale));shard.addLine(to:CGPoint(x:center.x+5*scale,y:center.y));shard.closeSubpath()
                            context.fill(shard,with:.color(color.opacity(alpha*0.7)))
                        }
                    } else if id == "sunnyday" {
                        let sun=CGPoint(x:size.width*0.5,y:size.height*0.22)
                        glow(&context,sun,90*scale,.orange,alpha*0.6)
                        for i in 0..<12 { let a=Double(i)*Double.pi/6+p*0.6
                            var ray=Path();ray.move(to:CGPoint(x:sun.x+cos(a)*32*scale,y:sun.y+sin(a)*32*scale));ray.addLine(to:CGPoint(x:sun.x+cos(a)*58*scale,y:sun.y+sin(a)*58*scale))
                            stroke(&context,ray,.yellow,2*scale,alpha)
                        }
                    } else { for i in 0..<26 {
                        let x=(Double(i)*73.7).truncatingRemainder(dividingBy:size.width),t=(p+Double(i)/26).truncatingRemainder(dividingBy:1)
                        let y=t*size.height
                        var path=Path();path.move(to:CGPoint(x:x,y:y));path.addLine(to:CGPoint(x:x-(id == "sandstorm" ? 17 : 5)*scale,y:y+(id == "sandstorm" ? 3 : 13)*scale))
                        stroke(&context,path,color,1.5*scale,alpha*0.65)
                    } }
                case "wave":
                    for i in 0..<5 {
                        let t=(p+Double(i)/5).truncatingRemainder(dividingBy:1)
                        let x=source.x+(point.x-source.x)*t,y=source.y+(point.y-source.y)*t
                        var path=Path()
                        for j in 0...24 {
                            let u=Double(j)/24,pp=CGPoint(x:x+sin(u*2 * .pi+p*8)*10*scale,y:y+(u-0.5)*100*scale)
                            if j==0 { path.move(to:pp) } else { path.addLine(to:pp) }
                        }
                        stroke(&context,path,color,3*scale,alpha*sin(t * .pi))
                    }
                case "flash":
                    glow(&context,source,85*scale,.yellow,alpha*0.45)
                    for i in 0..<12 { let a=Double(i)*Double.pi/6
                        var ray=Path();ray.move(to:CGPoint(x:source.x+cos(a)*22*scale,y:source.y+sin(a)*22*scale));ray.addLine(to:CGPoint(x:source.x+cos(a)*62*scale,y:source.y+sin(a)*62*scale))
                        stroke(&context,ray,.yellow,2*scale,alpha)
                    }
                case "boost","debuff","charge","aura","status":
                    ring(&context,point,radius,color,alpha)
                    for i in 0..<12 {
                        let t=(p+Double(i)/12).truncatingRemainder(dividingBy:1),x=point.x+sin(Double(i)*2.1)*32*scale,y=point.y+(kind == "debuff" ? -45+t*90 : 45-t*90)*scale
                        var path=Path();path.move(to:CGPoint(x:x,y:y+10*scale));path.addLine(to:CGPoint(x:x,y:y))
                        stroke(&context,path,color,2*scale,alpha*sin(t * .pi))
                    }
                case "sound":
                    for i in 0..<4 {
                        let t=(p+Double(i)*0.15).truncatingRemainder(dividingBy:1)
                        let center=CGPoint(x:source.x+(point.x-source.x)*t,y:source.y+(point.y-source.y)*t)
                        ring(&context,center,(12+t*33)*scale,color,alpha*sin(t * .pi))
                    }
                default:
                    let t=min(1,p/0.58),head=CGPoint(x:source.x+(point.x-source.x)*t,y:source.y+(point.y-source.y)*t)
                    if p<0.65 { glow(&context,head,19*scale,color,alpha*0.8) }
                    if p>0.38 {
                        let burst=(p-0.38)/0.62
                        ring(&context,point,(8+burst*55)*scale,color,alpha)
                        for i in 0..<16 {
                            let a=Double(i)/16*2 * .pi
                            var path=Path();path.move(to:CGPoint(x:point.x+cos(a)*burst*40*scale,y:point.y+sin(a)*burst*40*scale))
                            path.addLine(to:CGPoint(x:point.x+cos(a)*(burst*40+9)*scale,y:point.y+sin(a)*(burst*40+9)*scale))
                            stroke(&context,path,i%3 == 0 ? .white : color,2*scale,alpha)
                        }
                    }
                }
            }
        }.allowsHitTesting(false)
    }
    private func glow(_ c: inout GraphicsContext,_ point: CGPoint,_ radius: Double,_ color: Color,_ alpha: Double) {
        c.fill(Path(ellipseIn:CGRect(x:point.x-radius,y:point.y-radius,width:radius*2,height:radius*2)),with:.radialGradient(Gradient(colors:[color.opacity(alpha),.clear]),center:point,startRadius:0,endRadius:radius))
    }
    private func stroke(_ c: inout GraphicsContext,_ path: Path,_ color: Color,_ width: Double,_ alpha: Double) {
        var layer=c;layer.addFilter(.shadow(color:color.opacity(alpha*0.7),radius:5))
        layer.stroke(path,with:.color(color.opacity(alpha)),style:StrokeStyle(lineWidth:width,lineCap:.round))
        layer.stroke(path,with:.color(.white.opacity(alpha*0.6)),lineWidth:0.6)
    }
    private func ring(_ c: inout GraphicsContext,_ point: CGPoint,_ radius: Double,_ color: Color,_ alpha: Double) {
        stroke(&c,Path(ellipseIn:CGRect(x:point.x-radius,y:point.y-radius,width:radius*2,height:radius*2)),color,2,alpha)
    }
}
