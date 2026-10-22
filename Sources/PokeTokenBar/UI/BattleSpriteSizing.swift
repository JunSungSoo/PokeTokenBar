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
}

/// One camera scale for both teams; never normalize each species to the same square.
struct BattleSpriteSizing:Equatable {
    let pixelScale:CGFloat
    let stageWidth:CGFloat
    let stageHeight:CGFloat
    @MainActor static func make(mode:BattleMode,sizes:[CGSize])->Self {
        let width=sizes.map(\.width).max() ?? 64,height=sizes.map(\.height).max() ?? 64
        let scale=min(mode == .singles ? 1.5:1.25,(mode == .singles ? 180:118)/max(1,width),(mode == .singles ? 150:110)/max(1,height))
        return Self(pixelScale:scale,stageWidth:max(72,width*scale+12),stageHeight:max(mode == .singles ? 113:95,height*scale+BattleSpriteGeometry.footInset))
    }
}
