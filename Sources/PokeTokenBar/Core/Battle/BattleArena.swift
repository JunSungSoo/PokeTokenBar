import CryptoKit
import Foundation

/// Keep the order stable: both peers derive the same cosmetic arena from their shared match ID.
/// The random handshake nonces give each new match a fresh selection without consuming battle RNG.
enum BattleArena: String, CaseIterable, Sendable {
    case plains, forest, snowyForest = "snowy_forest"
    case sea, beach, lake
    case mountain, desert, volcano
    case cave, iceCave = "ice_cave", fairyCave = "fairy_cave"
    case town, metropolis, dojo

    var group: String {
        switch self {
        case .plains, .forest, .snowyForest: "woods"
        case .sea, .beach, .lake: "water"
        case .mountain, .desert, .volcano: "highlands"
        case .cave, .iceCave, .fairyCave: "caves"
        case .town, .metropolis, .dojo: "settlements"
        }
    }
    var backgroundPath: String { "images/arenas/\(rawValue)_bg.png" }

    static func forMatch(_ matchID: String) -> Self {
        guard !matchID.isEmpty else { return .plains }
        // Swift's hashValue is process-randomized, so it must never choose a networked arena.
        let digest = SHA256.hash(data: Data(("ptb-arena-v1:" + matchID).utf8))
        let index = digest.reduce(0) { ($0 * 256 + Int($1)) % allCases.count }
        return allCases[index]
    }
}
