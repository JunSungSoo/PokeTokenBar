import Foundation

struct BattleRosterPresets: Codable {
    static let storageKey = "battleRosterPresets.v1"
    static let slots = 1...2

    private var rosters: [String: [String]] = [:]
    private var heldItems: [String: [String: String]]?

    init(data: Data) {
        if let saved = try? JSONDecoder().decode(Self.self, from: data) {
            self = saved
        }
    }

    func roster(mode: BattleMode, slot: Int) -> [String] {
        rosters[key(mode, slot)] ?? []
    }

    func itemOverrides(mode: BattleMode, slot: Int) -> [String: String] {
        heldItems?[key(mode, slot)] ?? [:]
    }

    mutating func save(_ ids: [String], mode: BattleMode, slot: Int, candidates: [DexEntry],
                       items: [String: String] = [:]) throws -> Data? {
        guard Self.slots.contains(slot), Self.isValid(ids, mode: mode, candidates: candidates) else { return nil }
        var loadout = BattleItemLoadout()
        for id in ids {
            guard let entry = candidates.first(where: { $0.id == id }),
                  loadout.apply(items[id] ?? "", to: entry, roster: ids) else { return nil }
        }
        let slotKey = key(mode, slot)
        rosters[slotKey] = ids
        var savedItems = heldItems ?? [:]
        savedItems[slotKey] = Dictionary(uniqueKeysWithValues: ids.map { ($0, loadout.items[$0] ?? "") })
        heldItems = savedItems
        return try JSONEncoder().encode(self)
    }

    static func isValid(_ ids: [String], mode: BattleMode, candidates: [DexEntry]) -> Bool {
        guard ids.count == mode.teamSize, Set(ids).count == ids.count else { return false }
        let members = ids.compactMap { id in candidates.first { $0.id == id } }
        return members.count == ids.count && Set(members.map(\.finalID)).count == ids.count
            && members.allSatisfy { !$0.isReleased && BattleTeamBuilder.isSpeciesEligible($0.finalID) }
    }

    static func toggle(_ id: String, in ids: inout [String], mode: BattleMode, candidates: [DexEntry]) {
        if ids.contains(id) {
            ids.removeAll { $0 == id }
            return
        }
        guard ids.count < mode.teamSize,
              let entry = candidates.first(where: { $0.id == id }),
              !BattleTeamBuilder.hasSelectedSpecies(entry, selectedIDs: ids, entries: candidates) else { return }
        ids.append(id)
    }

    private func key(_ mode: BattleMode, _ slot: Int) -> String {
        "\(mode.rawValue)-\(slot)"
    }
}
