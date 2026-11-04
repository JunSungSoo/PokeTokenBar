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
    /// Physical height controls extent, while atlas proportions and front/back differences survive.
    func battleSize(speciesID:Int,form:PokemonForm?,back:Bool)->CGSize {
        let raw=size(speciesID:speciesID,form:form,back:back)
        let front=size(speciesID:speciesID,form:form,back:false),rear=size(speciesID:speciesID,form:form,back:true)
        let reference=max(1,[front.width,front.height,rear.width,rear.height].max() ?? 1)
        let physicalExtent=90*sqrt(PokemonDisplayHeights.shared.metres(speciesID:speciesID,form:form))
        // Compress extreme heights smoothly so one giant reserve does not shrink both teams.
        // A square-root curve separates small species from large ones without life-size giants.
        // The shared camera still bounds both teams and preserves original atlas proportions.
        let extent=physicalExtent<=180 ? physicalExtent:180+20*(1-exp(-(physicalExtent-180)/50))
        let factor=extent/reference
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

/// One camera scale for both teams; never normalize each species to the same square.
struct BattleSpriteSizing:Equatable {
    let pixelScale:CGFloat
    let stageWidth:CGFloat
    let stageHeight:CGFloat
    @MainActor static func make(mode:BattleMode,sizes:[CGSize])->Self {
        let width=sizes.map(\.width).max() ?? 64,height=sizes.map(\.height).max() ?? 64
        let singles = mode == .singles
        let originalScale = min(singles ? 1.5 : 1.25,
                                (singles ? 180 : 118) / max(1, width),
                                (singles ? 150 : 110) / max(1, height))
        let scale = originalScale * 1.5
        return Self(pixelScale:scale,stageWidth:max(72,width*scale+12),stageHeight:max(mode == .singles ? 113:95,height*scale+BattleSpriteGeometry.footInset))
    }
}
