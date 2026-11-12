import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleVisibleSizingTests: XCTestCase {
    private func pokemon(_ id: Int, active: Bool = true, form: PokemonForm? = nil) -> BattleCombatant {
        .init(id:String(id),speciesID:id,name:"",level:100,shiny:false,active:active,form:form,
              fainted:false,hp:100,maxHP:100,status:"",stats:nil)
    }
    func testOpponentSwitchAndMegaCannotResizeAnExistingPokemon() throws {
        for mode in BattleMode.allCases {
            let base = BattleSpriteSizing.forBattle(mode: mode, own: [pokemon(25)], foe: [pokemon(16)])
            for opponent in [16, 25, 6, 130, 208, 321] {
                let changed = BattleSpriteSizing.forBattle(mode: mode, own: [pokemon(25)], foe: [pokemon(opponent)])
                XCTAssertEqual(changed.pixelScale, base.pixelScale, "Opponent \(opponent) must not resize Pikachu")
                for form in BattleHeldItems.sizingForms(speciesID: 26) {
                    let scene = BattleScene(id: 1, turn: 2, own: [pokemon(26, form: form)], foe: [pokemon(opponent)], field: BattleFieldState(weather: "", weatherSuppressed: false, conditions: [], ownSide: [], foeSide: []))
                    let actor = PokeRogueActor(pokemon: pokemon(26, form: form), position: .init(own: true, slot: 0), rect: .zero, pixelScale: base.pixelScale)
                    XCTAssertEqual(try XCTUnwrap(actor.inScene(scene, mode: mode)).pixelScale, base.pixelScale,
                                   "Queued Mega/entry actors must use the same fixed scale")
                }
            }
        }
    }

    func testSmallSpeciesAndMegaBodyHeightsStayDistinctAndRenderReference() async throws {
        let catalog = PokeRogueSpriteSizes.shared
        XCTAssertEqual(catalog.battleSize(speciesID: 16, form: nil, back: false).height, 43.82, accuracy: 0.1)
        XCTAssertEqual(catalog.battleSize(speciesID: 25, form: nil, back: true).height, 50.60, accuracy: 0.1)
        for back in [false, true] {
            let base = catalog.battleSize(speciesID: 26, form: nil, back: back)
            for form in [PokemonForm("mega-x"), PokemonForm("mega-y")] {
                XCTAssertGreaterThan(catalog.battleSize(speciesID: 26, form: form, back: back).height, base.height)
            }
            XCTAssertLessThan(catalog.battleSize(speciesID: 16, form: nil, back: back).height,
                              catalog.battleSize(speciesID: 6, form: nil, back: back).height * 0.5)
        }
        let members = [pokemon(16), pokemon(25), pokemon(26), pokemon(26, form: .init("mega-x")),
                       pokemon(26, form: .init("mega-y")), pokemon(6)]
        let names = ["구구", "피카츄", "라이츄", "메가라이츄 X", "메가라이츄 Y", "리자몽"]
        let root = VStack(spacing: 16) {
            Text("배틀 고정 크기 기준 · 싱글/더블 동일").font(.headline)
            ForEach([false, true], id: \.self) { back in
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.offset) { index, member in
                        VStack(spacing: 4) {
                            Text(names[index] + (back ? " · 뒤" : " · 앞")).font(.caption)
                            BattlePokemonStage(pokemon: member, back: back, stageSize: 90,
                                sizing: BattleSpriteSizing.forBattle(mode: .doubles, own: [], foe: []))
                        }
                    }
                }
            }
        }.padding(16).frame(width: 1166, height: 440, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1166, height: 440),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = host; window.setContentSize(NSSize(width: 1166, height: 440)); window.orderFront(nil)
        defer { window.orderOut(nil); window.contentViewController = nil }
        try await Task.sleep(for: .seconds(1))
        host.view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/ptb-fixed-battle-size-reference.png"))
    }

    func testGiantReservesCannotShrinkVisiblePokemonInEitherMode() {
        for mode in BattleMode.allCases {
            let own = [pokemon(26)] + (mode == .doubles ? [pokemon(151)] : [])
            let foe = [pokemon(151)] + (mode == .doubles ? [pokemon(26)] : [])
            let visible = BattleSpriteSizing.forBattle(mode:mode,own:own,foe:foe)
            let reserves = [321,208,249,130].map { pokemon($0,active:false) }
            XCTAssertEqual(BattleSpriteSizing.forBattle(mode:mode,own:own+reserves,foe:foe),visible)
            XCTAssertEqual(BattleSpriteSizing.forBattle(mode:mode,own:own,foe:foe+reserves),visible)
            XCTAssertEqual(visible.pixelScale, 1)
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
