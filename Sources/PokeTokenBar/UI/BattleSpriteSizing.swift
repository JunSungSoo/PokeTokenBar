import Foundation

/// Visible animation bounds from the same pinned PokéRogue asset revision as move effects.
struct PokeRogueSpriteSizes:Decodable,Sendable {
    struct Record:Decodable,Sendable { let width:Double;let height:Double;let sha256:String }
    let assetRevision:String
    let records:[String:Record]
    static let shared:Self = {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("PokeRoguePlayer/pokemon-sizes.json")
        let url=bundled.flatMap{FileManager.default.fileExists(atPath:$0.path) ? $0:nil}
            ?? AppResources.module.url(forResource:"PokeRoguePlayer",withExtension:nil)!.appendingPathComponent("pokemon-sizes.json")
        return try! JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
    }()
    func size(speciesID:Int,form:PokemonForm?,back:Bool)->CGSize {
        let prefix=back ? "back/":""
        let form=PokemonForm.resolved(speciesID:speciesID,form:form)
        let key=prefix+String(speciesID)
        let record=form.flatMap{records[key+"-"+$0.rawValue]} ?? records[key]
        return record.map{CGSize(width:$0.width,height:$0.height)} ?? CGSize(width:64,height:64)
    }
    /// Safari encounter size from physical height; battles draw the atlas size at the field scale instead.
    /// Calibrate against height, so a long tail or wingspan cannot normalize the body down.
    func physicalSize(speciesID:Int,form:PokemonForm?,back:Bool)->CGSize {
        let raw = size(speciesID:speciesID,form:form,back:back)
        let front = size(speciesID:speciesID,form:form,back:false)
        let rear = size(speciesID:speciesID,form:form,back:true)
        let physicalHeight = 80 * sqrt(PokemonDisplayHeights.shared.metres(speciesID:speciesID,form:form))
        let height = physicalHeight <= 96 ? physicalHeight : 96 + 16 * (1 - exp(-(physicalHeight - 96) / 60))
        let factor = min(height / max(1,front.height,rear.height),
                         177 / max(1,front.width,rear.width))
        return CGSize(width:raw.width*factor,height:raw.height*factor)
    }
}

struct PokemonDisplayHeights:Decodable,Sendable {
    struct Record:Decodable,Sendable {let decimetres:Int;let pokemonID:Int}
    let records:[String:Record]
    static let shared:Self = {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("PokeRoguePlayer/pokemon-heights.json")
        let url=bundled.flatMap{FileManager.default.fileExists(atPath:$0.path) ? $0:nil}
            ?? AppResources.module.url(forResource:"PokeRoguePlayer",withExtension:nil)!.appendingPathComponent("pokemon-heights.json")
        return try! JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
    }()
    func metres(speciesID:Int,form:PokemonForm?)->Double {
        let base=String(speciesID),form=PokemonForm.resolved(speciesID:speciesID,form:form)
        let record=form.flatMap{records[base+"-"+$0.rawValue]} ?? records[base]
        return max(0.1,Double(record?.decimetres ?? 10)/10)
    }
}

/// Fixed camera and slots. Species/form dimensions never depend on another battler.
struct BattleSpriteSizing:Equatable {
    /// Points per original atlas pixel; PokéRogue draws one atlas pixel per field unit.
    let pixelScale:CGFloat
    let stageWidth:CGFloat
    let stageHeight:CGFloat
    static let battlefieldTopInset: CGFloat = 45
    /// Side of the original move-focus box around a battler, in field units.
    private static let focusBox: CGFloat = 64

    // Keep the authored viewport independent of the species-size formula.
    @MainActor static func battlefieldHeight(for mode: BattleMode) -> CGFloat {
        mode == .singles ? 351 : 299
    }

    @MainActor static func forBattle(mode: BattleMode, own: [BattleCombatant], foe: [BattleCombatant]) -> Self {
        let unit = battlefieldHeight(for: mode) / BattleFieldScene.fieldHeight
        return Self(pixelScale: unit, stageWidth: focusBox * unit,
                    stageHeight: focusBox * unit + 2 * BattleSpriteGeometry.footInset)
    }
}
