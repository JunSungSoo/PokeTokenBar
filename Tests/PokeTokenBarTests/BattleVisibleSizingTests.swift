import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleVisibleSizingTests: XCTestCase {
    private func pokemon(_ id: Int, active: Bool = true, form: PokemonForm? = nil) -> BattleCombatant {
        .init(id:String(id),speciesID:id,name:"",level:100,shiny:false,active:active,form:form,
              fainted:false,hp:100,maxHP:100,status:"",stats:nil)
    }
    func testGiantReservesCannotShrinkVisiblePokemonInEitherMode() {
        for mode in BattleMode.allCases {
            let own = [pokemon(26)] + (mode == .doubles ? [pokemon(151)] : [])
            let foe = [pokemon(151)] + (mode == .doubles ? [pokemon(26)] : [])
            let visible = BattleSpriteSizing.forBattle(mode:mode,own:own,foe:foe)
            let reserves = [321,208,249,130].map { pokemon($0,active:false) }
            XCTAssertEqual(BattleSpriteSizing.forBattle(mode:mode,own:own+reserves,foe:foe),visible)
            XCTAssertEqual(BattleSpriteSizing.forBattle(mode:mode,own:own,foe:foe+reserves),visible)
            let old = BattleSpriteSizing.make(mode:mode,sizes:(own+foe+reserves).flatMap { member in
                [false,true].map { PokeRogueSpriteSizes.shared.battleSize(speciesID:member.speciesID,form:member.form,back:$0) }
            },rowHeightLimit:BattleSpriteSizing.battlefieldRowHeightLimit(for:mode))
            XCTAssertGreaterThan(visible.pixelScale,old.pixelScale*1.5)
        }
    }
    func testSwitchAndMegaKeepSlotGroundAndViewportFixed() {
        for mode in BattleMode.allCases {
            let initial=BattleSpriteSizing.forBattle(mode:mode,own:[pokemon(26)],foe:[pokemon(151)])
            for id in [25,151,6,130,249,321] {
                for form in BattleHeldItems.sizingForms(speciesID:id) {
                    let changed=BattleSpriteSizing.forBattle(mode:mode,own:[pokemon(id,form:form)],foe:[pokemon(151)])
                    XCTAssertEqual(changed.stageWidth,initial.stageWidth)
                    XCTAssertEqual(changed.stageHeight,initial.stageHeight)
                    XCTAssertEqual(BattleSpriteGeometry.groundSize(stageWidth:changed.stageWidth),BattleSpriteGeometry.groundSize(stageWidth:initial.stageWidth))
                    XCTAssertEqual(2*changed.stageHeight+BattleSpriteSizing.battlefieldTopInset+BattleSpriteSizing.battlefieldRowSpacing,
                                   BattleSpriteSizing.battlefieldHeight(for:mode),accuracy:0.01)
                }
            }
        }
    }
    func testOriginalPlayerUsesEachSceneScaleThroughSwitchAndMega() throws {
        let field=BattleFieldState(weather:"",weatherSuppressed:false,conditions:[],ownSide:[],foeSide:[])
        for mode in BattleMode.allCases {
            let small=BattleScene(id:1,turn:1,own:[pokemon(26),pokemon(321,active:false)],foe:[pokemon(151)],field:field)
            let large=BattleScene(id:2,turn:1,own:[pokemon(321),pokemon(26,active:false)],foe:[pokemon(151)],field:field)
            let initial=BattleSpriteSizing.forBattle(mode:mode,own:small.own,foe:small.foe)
            let actor=PokeRogueActor(pokemon:small.own[0],position:.init(own:true,slot:0),rect:CGRect(x:0,y:0,width:initial.stageWidth,height:initial.stageHeight),pixelScale:initial.pixelScale)
            for scene in [small,large,small] {
                let rendered=try XCTUnwrap(actor.inScene(scene,mode:mode))
                XCTAssertEqual(rendered.pokemon.speciesID,scene.own[0].speciesID)
                XCTAssertEqual(rendered.pixelScale,BattleSpriteSizing.forBattle(mode:mode,own:scene.own,foe:scene.foe).pixelScale)
                XCTAssertEqual(rendered.rect,actor.rect)
            }
            for form in BattleHeldItems.sizingForms(speciesID:6) {
                let mega=BattleScene(id:3,turn:2,own:[pokemon(6,form:form)],foe:small.foe,field:field)
                let rendered=try XCTUnwrap(actor.inScene(mega,mode:mode))
                XCTAssertEqual(rendered.pokemon.form,form)
                XCTAssertEqual(rendered.pixelScale,BattleSpriteSizing.forBattle(mode:mode,own:mega.own,foe:mega.foe).pixelScale)
            }
            XCTAssertEqual(try XCTUnwrap(actor.inScene(large,mode:nil)).pixelScale,actor.pixelScale)
        }
    }
    func testAllSupportedVisibleFormsFitTheFixedSlots() {
        let catalog=PokeRogueSpriteSizes.shared
        for mode in BattleMode.allCases {
            for id in 1...649 {
                for form in BattleHeldItems.sizingForms(speciesID:id) {
                    let member=pokemon(id,form:form)
                    let sizing=BattleSpriteSizing.forBattle(mode:mode,own:[member],foe:[member])
                    for back in [false,true] {
                        let raw=catalog.battleSize(speciesID:id,form:form,back:back)
                        XCTAssertLessThanOrEqual(raw.width*sizing.pixelScale,sizing.stageWidth-12+0.01,"\(id) \(mode)")
                        XCTAssertLessThanOrEqual(raw.height*sizing.pixelScale+BattleSpriteGeometry.footInset,sizing.stageHeight+0.01,"\(id) \(mode)")
                    }
                }
            }
        }
    }
}
