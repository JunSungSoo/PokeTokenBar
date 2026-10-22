import SwiftUI

/// Explicit authored additions to quiet preview imports; original fixture bytes are untouched.
/// Semantics follow the localized BW2 move descriptions, never modify stats or chance outcomes.
enum PokeRogueReadabilityProfile: String, CaseIterable {
    case psychic, confusion, telekinesis, powersplit, powertrick, meditate, workup, nightmare
    static func resolve(_ event: BattleVisualEvent) -> Self? {
        guard event.phase != "charge" else { return nil }
        return Self(rawValue:BattleTextCatalog.key(event.moveID ?? event.move))
    }
    var affectsCaster: Bool { self == .powertrick || self == .meditate || self == .workup }
    func backgroundOpacity(original: Double,progress: Double) -> Double {
        guard self == .psychic || self == .confusion,progress>0,progress<1 else { return original }
        return max(original,sin(progress * .pi)*(self == .psychic ? 0.24 : 0.13))
    }
}

@MainActor
struct PokeRogueReadabilityEffects: View {
    let event: BattleVisualEvent
    let rects: [String:CGRect]
    let progress: Double
    var reducedMotion=false
    var body: some View {
        Canvas { context,size in
            guard let profile=PokeRogueReadabilityProfile.resolve(event),progress>0,progress<1,
                  event.targets.contains(where: { $0.hit }),let source=rects[event.source.key] else { return }
            let origin=CGPoint(x:source.midX,y:source.midY)
            let scale=max(0.6,min(1.5,source.width/128))
            let p=reducedMotion ? 0.5 : progress
            let alpha=pow(sin(p * .pi),0.65)
            let purple=Color(red:0.64,green:0.25,blue:1),pink=Color(red:1,green:0.36,blue:0.84)
            for target in event.targets where target.hit {
                guard let bounds=rects[target.position.key] else { continue }
                let point=profile.affectsCaster ? origin : CGPoint(x:bounds.midX,y:bounds.midY)
                if reducedMotion {
                    ellipse(&context,at:point,rx:48*scale,ry:50*scale,color:purple,alpha:0.65,width:2)
                    continue
                }
                switch profile {
                case .psychic,.confusion:
                    let strength=profile == .psychic ? 1.0 : 0.63
                    aura(&context,at:point,radius:83*scale*strength,color:purple,alpha:alpha*0.38)
                    // A visible advancing pressure wave, followed by a target-centred compression field.
                    for i in 0..<5 {
                        let phase=max(0,min(1,(p-Double(i)*0.055)/0.55))
                        guard phase>0 && phase<1 else { continue }
                        let center=CGPoint(x:origin.x+(point.x-origin.x)*phase,y:origin.y+(point.y-origin.y)*phase)
                        ellipse(&context,at:center,rx:(10+phase*22)*scale,ry:(19+phase*38)*scale,color:i%2 == 0 ? purple : pink,alpha:sin(phase * .pi)*alpha*0.8,width:2.3*strength)
                    }
                    for i in 0..<3 {
                        let angle=p*3.5+Double(i)*Double.pi/3,radius=(48+sin(p*8+Double(i))*9)*scale*strength
                        orbit(&context,at:point,radius:radius,angle:angle,color:i == 1 ? pink : purple,alpha:alpha,width:2.5*strength)
                    }
                    if profile == .psychic {
                        let compress=max(0,1-abs(p-0.68)/0.23)
                        ellipse(&context,at:point,rx:(73-compress*25)*scale,ry:(79-compress*20)*scale,color:.white,alpha:compress*0.7,width:2)
                    }
                case .telekinesis:
                    aura(&context,at:point,radius:76*scale,color:purple,alpha:alpha*0.3)
                    for i in 0..<4 {
                        let rise=(p+Double(i)/4).truncatingRemainder(dividingBy:1)
                        let center=CGPoint(x:point.x,y:point.y+55*scale-rise*110*scale)
                        ellipse(&context,at:center,rx:(45-sin(rise * .pi)*6)*scale,ry:12*scale,color:i%2 == 0 ? purple : pink,alpha:sin(rise * .pi)*alpha,width:2)
                    }
                case .powersplit:
                    aura(&context,at:origin,radius:48*scale,color:purple,alpha:alpha*0.3)
                    aura(&context,at:point,radius:48*scale,color:pink,alpha:alpha*0.3)
                    for i in 0..<12 {
                        let t=(p*1.4+Double(i)/12).truncatingRemainder(dividingBy:1)
                        for returning in [false,true] {
                            let u=returning ? 1-t : t
                            let dot=CGPoint(x:origin.x+(point.x-origin.x)*u,y:origin.y+(point.y-origin.y)*u+sin(u * .pi)*(returning ? 16 : -16)*scale)
                            aura(&context,at:dot,radius:5*scale,color:returning ? pink : purple,alpha:alpha*0.85)
                        }
                    }
                case .powertrick:
                    aura(&context,at:origin,radius:70*scale,color:purple,alpha:alpha*0.3)
                    for i in 0..<2 {
                        orbit(&context,at:origin,radius:48*scale,angle:p*6+Double(i)*Double.pi/2,color:i == 0 ? .orange : .cyan,alpha:alpha,width:3)
                    }
                case .meditate,.workup:
                    let color: Color=profile == .workup ? .orange : purple
                    aura(&context,at:origin,radius:66*scale,color:color,alpha:alpha*0.32)
                    for i in 0..<12 {
                        let t=(p+Double(i)/12).truncatingRemainder(dividingBy:1)
                        let x=origin.x+sin(Double(i)*2.4)*36*scale,y=origin.y+45*scale-t*100*scale
                        var path=Path();path.move(to:CGPoint(x:x,y:y+9*scale));path.addLine(to:CGPoint(x:x,y:y))
                        line(&context,path: path,color:color,alpha:sin(t * .pi)*alpha,width:2)
                    }
                    ellipse(&context,at:CGPoint(x:origin.x,y:origin.y+47*scale),rx:51*scale,ry:13*scale,color:color,alpha:alpha,width:2)
                case .nightmare:
                    aura(&context,at:point,radius:80*scale,color:Color(red:0.2,green:0.02,blue:0.32),alpha:alpha*0.6)
                    for i in 0..<7 {
                        let angle=Double(i)*2 * .pi/7+p*3
                        let center=CGPoint(x:point.x+cos(angle)*47*scale,y:point.y+sin(angle)*43*scale)
                        aura(&context,at:center,radius:15*scale,color:purple,alpha:alpha*0.5)
                    }
                }
            }
        }.allowsHitTesting(false)
    }
    private func aura(_ context: inout GraphicsContext,at center: CGPoint,radius: Double,color: Color,alpha: Double) {
        context.fill(Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)),
            with:.radialGradient(Gradient(colors:[color.opacity(alpha),color.opacity(alpha*0.3),.clear]),center:center,startRadius:0,endRadius:radius))
    }
    private func line(_ context: inout GraphicsContext,path: Path,color: Color,alpha: Double,width: Double) {
        var c=context;c.addFilter(.shadow(color:color.opacity(alpha*0.8),radius:5))
        c.stroke(path,with:.color(color.opacity(alpha*0.2)),style:StrokeStyle(lineWidth:width*3,lineCap:.round))
        c.stroke(path,with:.color(color.opacity(alpha)),style:StrokeStyle(lineWidth:width,lineCap:.round))
        c.stroke(path,with:.color(.white.opacity(alpha*0.65)),lineWidth:0.65)
    }
    private func ellipse(_ context: inout GraphicsContext,at center: CGPoint,rx: Double,ry: Double,color: Color,alpha: Double,width: Double) {
        line(&context,path:Path(ellipseIn:CGRect(x:center.x-rx,y:center.y-ry,width:rx*2,height:ry*2)),color:color,alpha:alpha,width:width)
    }
    private func orbit(_ context: inout GraphicsContext,at center: CGPoint,radius: Double,angle: Double,color: Color,alpha: Double,width: Double) {
        var path=Path()
        for i in 0...64 {
            let t=Double(i)/64*2 * .pi,x=cos(t)*radius,y=sin(t)*radius*0.36
            let point=CGPoint(x:center.x+x*cos(angle)-y*sin(angle),y:center.y+x*sin(angle)+y*cos(angle))
            if i == 0 { path.move(to:point) } else { path.addLine(to:point) }
        }
        line(&context,path:path,color:color,alpha:alpha,width:width)
    }
}
