import Foundation

struct BattleEffectRecipe: Decodable, Sendable {
    struct Point: Decodable, Sendable {
        let x, y, z, scaleX, scaleY, opacity: Double
    }
    struct Operation: Decodable, Sendable {
        let effect: String
        let texture: String?
        let width, height: Double
        let start, end: Point
        let begin, finish: Double
        let easing, after: String
    }
    // nil means generation-independent. Never infer an effect's generation from the move's debut.
    let generation: Int?
    let source: String
    let duration, timeScale: Double
    let category, type, scope: String
    let operations: [Operation]
}

struct BattleEffectCatalog: Decodable, Sendable {
    static let generationPriority = [5,9,8,7,6,4,3,2,1]
    let aliases: [String:String]
    let recipes: [String:BattleEffectRecipe]
    var variants: [String:[BattleEffectRecipe]]? = nil

    static var resourceDirectory: URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("BattleEffects")
        return bundled.flatMap { FileManager.default.fileExists(atPath:$0.appendingPathComponent("catalog.json").path) ? $0 : nil }
            ?? Bundle.module.url(forResource:"BattleEffects",withExtension:nil)!
    }
    static let shared = try! JSONDecoder().decode(Self.self,from:Data(contentsOf:resourceDirectory.appendingPathComponent("catalog.json")))

    static func select(_ candidates: [BattleEffectRecipe]) -> BattleEffectRecipe? {
        for generation in generationPriority {
            if let match = candidates.first(where:{ $0.generation == generation }) { return match }
        }
        return candidates.first { $0.generation == nil }
    }
    func recipe(for raw: String, phase: String? = nil) -> BattleEffectRecipe? {
        let key = BattleTextCatalog.key(raw), canonical = (aliases[key] ?? key) + (phase == "charge" ? ":charge" : "")
        return Self.select((variants?[canonical] ?? []) + (recipes[canonical].map { [$0] } ?? []))
    }
    func duration(for event: BattleVisualEvent) -> Double {
        recipe(for:event.moveID ?? event.move,phase:event.phase)?.duration ?? 0.85
    }
}
