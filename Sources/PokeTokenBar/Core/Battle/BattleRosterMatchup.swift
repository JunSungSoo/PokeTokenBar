import Foundation

/// Public roster types only: no moves, abilities, weather or private opponent data.
struct BattleRosterMatchup {
    enum Advantage { case strong, weak, neutral }
    let outgoing:Double
    let incoming:Double
    var advantage:Advantage { outgoing>incoming ? .strong:outgoing<incoming ? .weak:.neutral }
    private static let chart:[String:[String:Double]] = {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("BattleText/type-chart.json")
        let url=bundled.flatMap { FileManager.default.fileExists(atPath:$0.path) ? $0:nil }
            ?? Bundle.module.url(forResource:"type-chart",withExtension:"json",subdirectory:"BattleText")!
        return try! JSONDecoder().decode([String:[String:Double]].self,from:Data(contentsOf:url))
    }()
    static func evaluate(_ own:BattleRosterMember,against opponent:BattleRosterMember)->Self {
        let catalog=BattleTextCatalog.shared
        let ownTypes=catalog.pokemonTypes(own.speciesID,form:own.form)
        let foeTypes=catalog.pokemonTypes(opponent.speciesID,form:opponent.form)
        func best(_ attacks:[String],_ defenses:[String])->Double {
            attacks.map { attack in defenses.reduce(1.0) { $0*(chart[attack]?[$1] ?? 1) } }.max() ?? 1
        }
        return Self(outgoing:best(ownTypes,foeTypes),incoming:best(foeTypes,ownTypes))
    }
}
