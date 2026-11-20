import SwiftUI

/// Fixed camera, bottom-center Pokémon origin (as in PokéRogue). GIF poses and
/// capture scaling never move the area's platform.
struct SafariEncounterGeometry {
    static let groundY: CGFloat = 160
    static let slotHeight: CGFloat = 150
    static let slotWidth: CGFloat = 240
    let spriteSize: CGSize
    /// Points per atlas pixel that reproduce `spriteSize`.
    let pixelScale: CGFloat
    init(speciesID:Int) {
        let sizes = PokeRogueSpriteSizes.shared
        spriteSize = sizes.physicalSize(speciesID:speciesID,form:nil,back:false)
        pixelScale = spriteSize.width / max(1, sizes.size(speciesID:speciesID,form:nil,back:false).width)
    }
}

@MainActor
struct SafariEncounterGround: View {
    let area: SafariArea
    var body: some View {
        // Zero-size anchor at the feet; the wild Pokémon stands on the area's enemy platform.
        Color.clear.frame(width:0,height:0).overlay(alignment:.bottom) {
            if let platform = BattleArena(rawValue:area.rawValue).flatMap(BattleArenaPlatform.load) {
                BattleArenaPlatformSurface(platform:platform).fixedSize()
            }
        }.offset(y:BattleSpriteGeometry.footInset)
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
                            pixelScale:SafariEncounterGeometry(speciesID:wild.species.id).pixelScale,spriteStore:spriteStore,bobsWhenStatic:true)
            .id(wild.id)
            .scaleEffect(captureFrame?.pokemonScale ?? 1,anchor:.bottom)
            .colorMultiply(Color(red:1-(1-213.0/255)*(captureFrame?.pokemonLight ?? 0),
                                 green:1-(1-41.0/255)*(captureFrame?.pokemonLight ?? 0),
                                 blue:1-(1-41.0/255)*(captureFrame?.pokemonLight ?? 0)))
            .offset(y:captureFrame?.pokemonLift ?? 0)
            .frame(width:SafariEncounterGeometry.slotWidth,height:SafariEncounterGeometry.slotHeight,alignment:.bottom)
    }
}
