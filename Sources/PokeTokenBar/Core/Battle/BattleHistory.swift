import Foundation

struct BattleIdentity: Codable, Sendable, Equatable {
    let nickname: String
    let code: String
    let nonce: String
}
struct BattleRecord: Codable, Sendable, Identifiable {
    let id: String
    let opponentCode: String
    let opponentName: String
    let mode: BattleMode
    let startedAt: Date
    let endedAt: Date
    let result: String
    let reason: String
    let team: [BattlePokemon]
    let turns: Int
}

@MainActor @Observable
final class BattleHistoryStore {
    private(set) var records: [BattleRecord] = []
    private(set) var error: String?
    private var unreadable = false
    private let url: URL
    init(url: URL? = nil) {
        self.url = url ?? AppStatePaths.directory().appendingPathComponent("battle-history-v1.json")
        guard FileManager.default.fileExists(atPath: self.url.path) else { return }
        do { records = try JSONDecoder().decode([BattleRecord].self, from: Data(contentsOf: self.url)) }
        catch { self.error = error.localizedDescription; unreadable = true }
    }
    func forOpponent(_ code: String?) -> [BattleRecord] {
        records.filter { code == nil || $0.opponentCode == code }.sorted { $0.endedAt > $1.endedAt }
    }
    func append(_ record: BattleRecord) {
        // Preserve an unreadable history file instead of overwriting it with a partial new history.
        guard !unreadable else { return }
        if !records.contains(where: { $0.id == record.id }) { records.append(record) }
        // Keep failed writes in memory and retry on the next result without duplicating IDs.
        let updated = records
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: url, options: .atomic)
            records = updated; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
