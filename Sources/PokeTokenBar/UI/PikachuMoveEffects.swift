import SwiftUI

/// Authored effect-only samples. No Pokémon transform, frame or opacity is modified.
/// Deterministic noise keeps a frame reproducible and prevents random flicker between redraws.
enum PikachuMoveProfile: String, CaseIterable {
    case thunderbolt, protect, quickattack, voltswitch
    var duration: Double {
        switch self { case .thunderbolt: 2.15; case .protect: 2.35; case .quickattack: 1.45; case .voltswitch: 2.1 }
    }
    static func resolve(_ event: BattleVisualEvent) -> Self? {
        guard event.phase != "charge" else { return nil }
        return Self(rawValue:BattleTextCatalog.key(event.moveID ?? event.move))
    }
}

/// Layered additive particles, branching lightning, lens rings and a tessellated barrier.
/// Everything is drawn within the existing battlefield; GIF/idle motion stays in BattlePokemonStage.
@MainActor
struct PikachuMoveEffects: View {
    let event: BattleVisualEvent
    let rects: [String:CGRect]
    let progress: Double
    var body: some View {
        Canvas { context,size in
            guard let profile=PikachuMoveProfile.resolve(event), let source=rects[event.source.key],
                  progress >= 0, progress < 1 else { return }
            let time=progress*profile.duration
            let origin=CGPoint(x:source.midX,y:source.midY)
            let scale=max(0.5,min(1.5,source.width/128))
            if profile == .protect {
                guard event.targets.contains(where: { $0.hit }) else { return }
                barrier(&context,at:origin,time:time,scale:scale)
            } else {
                // Launch effects may play on a miss, but impact effects require the engine's hit flag.
                for target in event.targets {
                    guard let bounds=rects[target.position.key] else { continue }
                    let destination=CGPoint(x:bounds.midX,y:bounds.midY)
                    switch profile {
                    case .thunderbolt: lightning(&context,from:origin,to:destination,time:time,scale:scale,hit:target.hit)
                    case .quickattack: dash(&context,from:origin,to:destination,time:time,scale:scale,hit:target.hit)
                    case .voltswitch: volt(&context,from:origin,to:destination,time:time,scale:scale,hit:target.hit)
                    case .protect: break
                    }
                }
            }
        }.allowsHitTesting(false)
    }
    private let gold=Color(red:1,green:0.71,blue:0.06)
    private let cyan=Color(red:0.18,green:0.94,blue:1)
    private func noise(_ i: Int) -> Double { let n=sin(Double(i)*127.1+311.7)*43758.5453;return n-floor(n) }
    private func mix(_ a: CGPoint,_ b: CGPoint,_ t: Double) -> CGPoint { CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t) }
    private func envelope(_ time: Double,_ start: Double,_ length: Double) -> Double {
        let t=(time-start)/length
        return t >= 0 && t < 1 ? pow(sin(t * .pi),0.65) : 0
    }
    private func glow(_ context: inout GraphicsContext,_ point: CGPoint,_ radius: Double,_ color: Color,_ alpha: Double) {
        guard alpha>0,radius>0 else { return }
        var c=context;c.blendMode = .plusLighter
        c.fill(Path(ellipseIn:CGRect(x:point.x-radius,y:point.y-radius,width:radius*2,height:radius*2)),
            with:.radialGradient(Gradient(stops:[.init(color:color.opacity(alpha),location:0),
                .init(color:color.opacity(alpha*0.32),location:0.35),.init(color:color.opacity(0),location:1)]),
                center:point,startRadius:0,endRadius:radius))
    }
    private func stroke(_ context: inout GraphicsContext,_ path: Path,_ color: Color,_ width: Double,_ alpha: Double) {
        guard alpha>0 else { return }
        var c=context;c.blendMode = .plusLighter
        c.addFilter(.shadow(color:color.opacity(alpha*0.8),radius:8))
        c.stroke(path,with:.color(color.opacity(alpha*0.22)),style:StrokeStyle(lineWidth:width*4,lineCap:.round,lineJoin:.round))
        c.stroke(path,with:.color(color.opacity(alpha)),style:StrokeStyle(lineWidth:width,lineCap:.round,lineJoin:.round))
        c.stroke(path,with:.color(.white.opacity(alpha*0.9)),style:StrokeStyle(lineWidth:max(0.6,width*0.28),lineCap:.round,lineJoin:.round))
    }
    private func ring(_ context: inout GraphicsContext,_ point: CGPoint,_ radius: Double,_ color: Color,_ alpha: Double,_ squash: Double=1) {
        stroke(&context,Path(ellipseIn:CGRect(x:point.x-radius,y:point.y-radius*squash,width:radius*2,height:radius*2*squash)),color,1.3,alpha)
    }
    private func bolt(_ from: CGPoint,_ to: CGPoint,seed: Int,bend: Double) -> Path {
        var path=Path();path.move(to:from)
        let dx=to.x-from.x,dy=to.y-from.y,d=max(1,hypot(dx,dy))
        for j in 1...14 {
            let t=Double(j)/14,offset=j == 14 ? 0 : (noise(seed+j*7)-0.5)*bend
            path.addLine(to:CGPoint(x:from.x+dx*t-dy/d*offset,y:from.y+dy*t+dx/d*offset))
        }
        return path
    }
    private func sparks(_ context: inout GraphicsContext,at point: CGPoint,time: Double,start: Double,color: Color,scale: Double,count: Int=42) {
        for i in 0..<count {
            let age=time-start-noise(i+31)*0.16
            guard age>0 && age<0.65 else { continue }
            let angle=noise(i+1)*2 * .pi,speed=(55+noise(i+2)*150)*scale
            let radius=age*speed
            let head=CGPoint(x:point.x+cos(angle)*radius,y:point.y+sin(angle)*radius+age*age*38)
            let tail=CGPoint(x:head.x-cos(angle)*8*scale,y:head.y-sin(angle)*8*scale)
            var path=Path();path.move(to:tail);path.addLine(to:head)
            stroke(&context,path,color,(1+noise(i+4))*scale,pow(1-age/0.65,2))
        }
    }
    private func burst(_ context: inout GraphicsContext,at point: CGPoint,time: Double,start: Double,color: Color,scale: Double) {
        let age=time-start
        guard age>=0 && age<0.8 else { return }
        glow(&context,point,(95+age*45)*scale,color,pow(1-age/0.8,3)*0.85)
        for i in 0..<3 {
            let t=age-Double(i)*0.08
            if t>=0 { ring(&context,point,(10+t*115)*scale,color,max(0,1-t/0.6)*0.7,0.65+Double(i)*0.17) }
        }
        sparks(&context,at:point,time:time,start:start,color:color,scale:scale)
    }
    private func lightning(_ context: inout GraphicsContext,from: CGPoint,to: CGPoint,time: Double,scale: Double,hit: Bool) {
        let charge=envelope(time,0,0.6)
        glow(&context,from,62*scale,gold,charge*0.6)
        for i in 0..<16 {
            let a=Double(i)/16*2 * .pi+time*3,r=(48-time*50)*scale
            let p=CGPoint(x:from.x+cos(a)*r,y:from.y+sin(a)*r*0.7)
            glow(&context,p,3*scale,.white,charge)
        }
        guard hit else { return }
        // A restrained dark corona gives the white-hot core contrast on the daylight field.
        let corona=envelope(time,0.45,0.85)
        context.fill(Path(ellipseIn:CGRect(x:to.x-105*scale,y:to.y-120*scale,width:210*scale,height:235*scale)),
            with:.radialGradient(Gradient(colors:[Color(red:0.29,green:0.12,blue:0.02).opacity(corona*0.3),.clear]),center:to,startRadius:10,endRadius:115*scale))
        for strike in 0..<3 {
            let start=0.48+Double(strike)*0.27,age=time-start
            guard age>=0 && age<0.22 else { continue }
            let alpha=pow(1-age/0.22,0.6),seed=strike*101+Int(age*35)*23
            let top=CGPoint(x:to.x+Double(strike-1)*28*scale,y:to.y-140*scale)
            stroke(&context,bolt(top,to,seed:seed,bend:45*scale),gold,6.5*scale,alpha)
            for filament in 0..<2 {
                let offset=Double(filament*2-1)*9*scale
                stroke(&context,bolt(CGPoint(x:top.x+offset,y:top.y),CGPoint(x:to.x+offset*0.3,y:to.y),seed:seed+filament*37,bend:26*scale),gold,1.2*scale,alpha*0.65)
            }
            for j in 0..<4 {
                let branch=mix(top,to,Double(j+2)/7)
                let end=CGPoint(x:branch.x+(j%2 == 0 ? 1 : -1)*(22+noise(j+seed)*28)*scale,y:branch.y+27*scale)
                stroke(&context,bolt(branch,end,seed:seed+j,bend:16*scale),gold,1.4*scale,alpha*0.75)
            }
            glow(&context,to,65*scale,gold,alpha*0.7)
        }
        burst(&context,at:to,time:time,start:1.02,color:gold,scale:scale)
    }
    private func barrier(_ context: inout GraphicsContext,at point: CGPoint,time: Double,scale: Double) {
        let alpha=envelope(time,0,2.25),r=(48+min(1,time/0.35)*12)*scale
        glow(&context,point,r*1.7,cyan,alpha*0.33)
        var c=context
        let oval=Path(ellipseIn:CGRect(x:point.x-r,y:point.y-r*1.2,width:r*2,height:r*2.4))
        c.clip(to:oval)
        c.fill(oval,with:.radialGradient(Gradient(colors:[cyan.opacity(0.02),cyan.opacity(alpha*0.28),.white.opacity(alpha*0.65)]),center:point,startRadius:r*0.3,endRadius:r*1.3))
        let cell=15*scale
        for row in -6...6 { for column in -5...5 {
            let center=CGPoint(x:point.x+Double(column)*cell*1.73+Double(abs(row)%2)*cell*0.865,y:point.y+Double(row)*cell*1.5)
            var hex=Path()
            for i in 0...6 {
                let angle=Double(i)*Double.pi/3-Double.pi/6
                let p=CGPoint(x:center.x+cos(angle)*cell,y:center.y+sin(angle)*cell)
                if i == 0 { hex.move(to:p) } else { hex.addLine(to:p) }
            }
            c.stroke(hex,with:.color(cyan.opacity(alpha*(0.18+0.25*noise(row*17+column)))),lineWidth:0.8)
        } }
        let scan=point.y-r*1.3+(time.truncatingRemainder(dividingBy:0.9)/0.9)*r*2.6
        c.fill(Path(CGRect(x:point.x-r,y:scan,width:r*2,height:3*scale)),with:.color(.white.opacity(alpha*0.5)))
        stroke(&context,oval,cyan,2*scale,alpha*0.9)
        ring(&context,CGPoint(x:point.x,y:point.y+r*0.9),r*1.15,cyan,alpha*0.7,0.24)
        for i in 0..<3 { let t=time-0.4-Double(i)*0.42
            if t>0 && t<0.65 { ring(&c,point,t*120*scale,.white,(1-t/0.65)*alpha*0.55) }
        }
    }
    private func dash(_ context: inout GraphicsContext,from: CGPoint,to: CGPoint,time: Double,scale: Double,hit: Bool) {
        let t=max(0,min(1,(time-0.2)/0.48)),head=mix(from,to,t)
        if time<0.78 {
            for i in 0..<25 {
                let side=(noise(i)-0.5)*60*scale,lag=noise(i+8)*0.35
                let a=mix(from,head,max(0,1-lag)),b=mix(from,head,max(0,0.45-lag))
                var path=Path();path.move(to:CGPoint(x:b.x,y:b.y+side));path.addQuadCurve(to:CGPoint(x:a.x,y:a.y+side),control:CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2+side-8*scale))
                stroke(&context,path,i%3 == 0 ? gold : .white,(i%4 == 0 ? 2 : 0.7)*scale,envelope(time,0.1,0.68)*0.65)
            }
            glow(&context,head,30*scale,.white,envelope(time,0.18,0.5)*0.55)
        }
        if hit { burst(&context,at:to,time:time,start:0.68,color:.white,scale:scale) }
    }
    private func volt(_ context: inout GraphicsContext,from: CGPoint,to: CGPoint,time: Double,scale: Double,hit: Bool) {
        glow(&context,from,52*scale,gold,envelope(time,0,0.5)*0.7)
        let t=max(0,min(1,(time-0.25)/0.7)),head=mix(from,to,t)
        if time>=0.25 && time<0.98 {
            for i in 0..<18 {
                let lag=Double(i)/35,p=mix(from,to,max(0,t-lag))
                glow(&context,p,(18-Double(i)*0.6)*scale,gold,(1-Double(i)/18)*0.35)
            }
            glow(&context,head,58*scale,gold,0.75)
            for i in 0..<3 {
                var orbit=Path()
                for j in 0...48 {
                    let a=Double(j)/48*2 * .pi+time*10+Double(i)*2,r=(21+sin(a*3+time*24)*4)*scale
                    let p=CGPoint(x:head.x+cos(a)*r,y:head.y+sin(a)*r*(i == 1 ? 0.45 : 1))
                    if j == 0 { orbit.move(to:p) } else { orbit.addLine(to:p) }
                }
                stroke(&context,orbit,gold,1.6*scale,0.85)
            }
            glow(&context,head,13*scale,.white,0.9)
        }
        if hit { burst(&context,at:to,time:time,start:0.95,color:gold,scale:scale) }
        // Returning energy is effect geometry, never a moved or duplicated Pokémon sprite.
        if hit && time>1.1 && time<1.85 {
            let u=(time-1.1)/0.75,p=mix(to,from,u)
            for i in 0..<8 { let q=CGPoint(x:p.x+sin(u*15+Double(i))*9*scale,y:p.y+cos(u*12+Double(i))*9*scale)
                glow(&context,q,4*scale,cyan,sin(u * .pi)*0.65)
            }
            ring(&context,from,20*scale,cyan,envelope(time,1.5,0.5))
        }
    }
}
