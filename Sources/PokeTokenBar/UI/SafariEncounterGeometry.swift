import SwiftUI

/// Fixed camera, bottom-center Pokémon origin (as in PokéRogue). Only the ground's
/// footprint changes between encounters; GIF poses and capture scaling never resize it.
struct SafariEncounterGeometry {
    static let groundY: CGFloat = 160
    static let slotHeight: CGFloat = 150
    static let slotWidth: CGFloat = 240
    let spriteSize: CGSize
    let groundSize: CGSize
    init(speciesID:Int) {
        spriteSize = PokeRogueSpriteSizes.shared.battleSize(speciesID:speciesID,form:nil,back:false)
        groundSize = CGSize(width:min(210,max(64,spriteSize.width+32)),height:22)
    }
}

@MainActor
struct SafariEncounterGround: View {
    let layout: SafariEncounterGeometry
    var body: some View {
        // Reuse the battle's black/brown oval, centered on the same foot anchor.
        BattleGroundSurface(size:layout.groundSize)
    }
}

@MainActor
struct SafariEncounterSprite: View {
    let wild: SafariPokemon
    var captureFrame: SafariCaptureSequence.Frame?
    var spriteStore: SpriteStore = .shared
    private var actor: BattleCombatant {
        BattleCombatant(id:wild.id,speciesID:wild.species.id,name:"",level:100,shiny:wild.shiny,
                        active:true,form:nil,fainted:false,hp:1,maxHP:2,status:"",stats:nil)
    }
    var body: some View {
        // The battle renderer crops one union of GIF alpha bounds and uses one
        // duration-weighted stance anchor, preserving animation without frame jitter.
        BattlePokemonSprite(pokemon:actor,back:false,size:SafariEncounterGeometry.slotWidth,
                            pixelScale:1,spriteStore:spriteStore,bobsWhenStatic:true)
            .id(wild.id)
            .scaleEffect(captureFrame?.pokemonScale ?? 1,anchor:.bottom)
            .colorMultiply(Color(red:1-(1-213.0/255)*(captureFrame?.pokemonLight ?? 0),
                                 green:1-(1-41.0/255)*(captureFrame?.pokemonLight ?? 0),
                                 blue:1-(1-41.0/255)*(captureFrame?.pokemonLight ?? 0)))
            .offset(y:captureFrame?.pokemonLift ?? 0)
            .frame(width:SafariEncounterGeometry.slotWidth,height:SafariEncounterGeometry.slotHeight,alignment:.bottom)
    }
}
