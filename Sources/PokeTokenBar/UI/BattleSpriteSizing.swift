import Foundation

/// Visible animation bounds from the same pinned PokéRogue asset revision as move effects.
struct PokeRogueSpriteSizes:Decodable,Sendable {
    struct Record:Decodable,Sendable { let width:Double;let height:Double;let sha256:String }
    let assetRevision:String
    let records:[String:Record]
    static let shared:Self = {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("PokeRoguePlayer/pokemon-sizes.json")
        let url=bundled.flatMap{FileManager.default.fileExists(atPath:$0.path) ? $0:nil}
            ?? Bundle.module.url(forResource:"PokeRoguePlayer",withExtension:nil)!.appendingPathComponent("pokemon-sizes.json")
        return try! JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
    }()
    func size(speciesID:Int,form:PokemonForm?,back:Bool)->CGSize {
        let prefix=back ? "back/":""
        let form=PokemonForm.resolved(speciesID:speciesID,form:form)
        let key=prefix+String(speciesID)
        let record=form.flatMap{records[key+"-"+$0.rawValue]} ?? records[key]
        return record.map{CGSize(width:$0.width,height:$0.height)} ?? CGSize(width:64,height:64)
    }
    /// Absolute display points per species/form, shared by native GIFs and the move player.
    /// Calibrate against height, so a long tail or wingspan cannot normalize the body down.
    func battleSize(speciesID:Int,form:PokemonForm?,back:Bool)->CGSize {
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
            ?? Bundle.module.url(forResource:"PokeRoguePlayer",withExtension:nil)!.appendingPathComponent("pokemon-heights.json")
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
    let pixelScale:CGFloat
    let stageWidth:CGFloat
    let stageHeight:CGFloat
    static let battlefieldTopInset: CGFloat = 45
    static let battlefieldRowSpacing: CGFloat = 4

    // Keep the authored viewport independent of the species-size formula.
    @MainActor static func battlefieldHeight(for mode: BattleMode) -> CGFloat {
        mode == .singles ? 351 : 299
    }

    @MainActor static func battlefieldRowHeightLimit(for mode: BattleMode) -> CGFloat {
        (battlefieldHeight(for: mode) - battlefieldTopInset - battlefieldRowSpacing) / 2
    }

    @MainActor static func forBattle(mode: BattleMode, own: [BattleCombatant], foe: [BattleCombatant]) -> Self {
        Self(pixelScale: 1, stageWidth: mode == .singles ? 282 : 189,
             stageHeight: battlefieldRowHeightLimit(for: mode))
    }
}
