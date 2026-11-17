import AppKit
import SwiftUI

/// Native GIF stays at the same view identity throughout absorption and breakout.
@MainActor
struct SafariBattlefield: View {
    let session: SafariSession
    let language: AppLanguage
    var captureFrame: SafariCaptureSequence.Frame?
    var projectile: SafariAction?
    var projectileProgress = 0.0
    var spriteStore: SpriteStore = .shared
    private var l: L { L(language) }
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                if let image = SafariArtwork.arena(session.area) {
                    Image(nsImage:image).resizable().interpolation(.none).scaledToFill()
                        .frame(width:width,height:280).clipped()
                }
                if let wild = session.wild {
                    let layout = SafariEncounterGeometry(speciesID:wild.species.id)
                    SafariEncounterGround(layout:layout)
                        .position(x:width*0.75,y:SafariEncounterGeometry.groundY)
                }
                if let captureFrame, captureFrame.ballBehindPokemon {
                    SafariCaptureEffect(frame:captureFrame,layer:.ball)
                }
                if let wild = session.wild {
                    SafariEncounterSprite(wild:wild,captureFrame:captureFrame,spriteStore:spriteStore)
                        .position(x:width*0.75,y:SafariEncounterGeometry.groundY-SafariEncounterGeometry.slotHeight/2)
                        .opacity(pokemonOpacity)
                    VStack(alignment:.leading,spacing:4) {
                        Text(BattleTextCatalog.shared.speciesName(wild.species.id,language:language) + (wild.shiny ? " ✨" : "")).font(.headline)
                        Text(wild.species.types.map { BattleTextCatalog.shared.typeName($0,language:language) }.joined(separator:" / "))
                        Text("\(l.safariTurns): \(session.turn)/5")
                        Text("\(l.safariCatchRate): \(String(format:"%.1f",session.catchChance))%")
                        Text("\(l.safariFleeRate): \(Int(session.displayedFleeChance))%")
                    }.font(.caption).padding(10)
                        .background(Color(red:0.97,green:0.97,blue:0.87),in:RoundedRectangle(cornerRadius:8))
                        .foregroundStyle(.black).position(x:width*0.25,y:54)
                }
                if let image = SafariArtwork.redDisplayFrame(captureFrame?.trainerFrame ?? 0) {
                    Image(decorative:image,scale:1).interpolation(.none)
                        .frame(width:192,height:192).position(x:(width*0.22).rounded(),y:184)
                }
                if let projectile {
                    SafariThrownItem(action:projectile,progress:projectileProgress)
                        .position(SafariThrowPath.item(width:width).point(at:projectileProgress))
                }
                if let captureFrame { SafariCaptureEffect(frame:captureFrame,layer:captureFrame.ballBehindPokemon ? .particles:.all) }
            }.clipped()
        }.frame(height:280).clipShape(RoundedRectangle(cornerRadius:8))
            .accessibilityIdentifier("safari-battlefield")
    }
    private var pokemonOpacity: Double {
        if let captureFrame { return captureFrame.pokemonOpacity }
        return session.phase == .between && session.notices.contains(where: { [.fled,.caught,.ran].contains($0) }) ? 0:1
    }
}

@MainActor
struct SafariCaptureEffect: View {
    enum Layer { case all, ball, particles }
    let frame: SafariCaptureSequence.Frame
    var layer: Layer = .all
    static let scale = 1.5
    static func point(x:Double,y:Double,width:Double) -> CGPoint {
        CGPoint(x:width*0.75+(x-236)*scale,y:156+(y-72)*scale)
    }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if layer != .particles {
                    let key = frame.open >= 1 ? "pb_open":frame.open > 0 ? "pb_opening":"pb"
                    if let image = SafariRogueAssets.balls[key] {
                        let point = Self.point(x:frame.x,y:frame.y,width:geometry.size.width)
                        let height = Double(image.height)*Self.scale
                        Image(decorative:image,scale:1).resizable().interpolation(.none)
                            .frame(width:Double(image.width)*Self.scale,height:height)
                            .colorMultiply(Color(white:1-frame.ballShade))
                            .rotationEffect(.degrees(frame.angle),anchor:UnitPoint(x:0.5,y:0.625))
                            .opacity(frame.ballOpacity).position(x:point.x,y:point.y-height*0.125)
                    }
                }
                if layer != .ball {
                    ForEach(frame.particles,id:\.id) { particle in
                        if let image = SafariRogueAssets.particles[particle.texture] {
                            let point = Self.point(x:particle.x,y:particle.y,width:geometry.size.width)
                            Image(decorative:image,scale:1).resizable().interpolation(.none)
                                .frame(width:Double(image.width)*Self.scale,height:Double(image.height)*Self.scale)
                                .opacity(particle.alpha).position(point)
                        }
                    }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
