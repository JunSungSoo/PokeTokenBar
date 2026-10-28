import Foundation

/// A Fairy-only supplement to BW2 selection metadata. Never rewrites saved/default moves,
/// base stats, species types, or the API cache. Thus old offline caches gain the same choices.
struct PokemonFairyMoves:Decodable,Sendable {
    let moves:[String:BattleTextCatalog.Move]
    let types:[String:[String:String]]
    let learnsets:[String:[String:[PokemonMoveLearnMethod]]]
    static let shared:Self = {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("BattleText/gen6-fairy.json")
        let url=bundled.flatMap{FileManager.default.fileExists(atPath:$0.path) ? $0:nil}
            ?? Bundle.module.url(forResource:"gen6-fairy",withExtension:"json",subdirectory:"BattleText")!
        return try! JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
    }()
    static func mergedMoves(details:PokemonDetails)->[PokemonMoveOption] {
        let extra=(shared.learnsets[String(details.speciesID)] ?? [:]).map {
            PokemonMoveOption(name:$0.key,learnMethods:$0.value)
        }
        var result:[String:PokemonMoveOption]=[:]
        for move in details.moves+extra {
            let key=BattleTextCatalog.key(move.name)
            if let old=result[key] {
                var methods=old.learnMethods
                for method in move.learnMethods where !methods.contains(method) {methods.append(method)}
                result[key]=PokemonMoveOption(name:old.name,learnMethods:methods)
            } else {result[key]=move}
        }
        return result.values.sorted{$0.name<$1.name}
    }
}
