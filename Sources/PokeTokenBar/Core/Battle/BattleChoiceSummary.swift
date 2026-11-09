import Foundation

/// A preview of the command, never a prediction of a random or redirected hit.
struct BattleChoiceSummary {
    let chosen: Bool
    let action: String
    let target: String
    let positions: Set<BattleEffectPosition>

    init(slot: BattleSlot, choice: BattleAction?, own: [BattleCombatant], foe: [BattleCombatant], language: AppLanguage) {
        chosen = choice != nil
        let l = L(language)
        let allies = own.filter(\.active)
        func positions(_ members: [BattleCombatant], own: Bool) -> Set<BattleEffectPosition> {
            Set(members.enumerated().filter { !$0.element.fainted }.map { .init(own: own, slot: $0.offset) })
        }
        guard let choice else {
            action = slot.mustSwitch ? l.battleSwitch : l.battleChoicePending
            target = "—"; self.positions = []; return
        }
        guard choice.kind == "move", let move = slot.moves.first(where: { $0.index == choice.index }) else {
            action = choice.kind == "switch" ? l.battleSwitch : l.battleChoicePass
            target = choice.kind == "switch" && own.indices.contains(choice.index - 1)
                ? BattleTextCatalog.shared.speciesName(own[choice.index - 1].speciesID, language: language) : "—"
            self.positions = []; return
        }
        action = BattleTextCatalog.shared.moveName(move.apiName ?? move.name, language: language)
        if move.targetRequired, let selected = move.targets.first(where: { $0.location == choice.target }) {
            target = l.battleChoiceTarget(selected.location, own: own, foe: foe)
            self.positions = [.init(own: selected.location < 0, slot: abs(selected.location) - 1)]
        } else {
            target = l.battleMoveTarget(move)
            let alliesPositions = positions(allies, own: true), foesPositions = positions(foe, own: false)
            switch move.targetScope {
            case "self": self.positions = [.init(own: true, slot: slot.slot)]
            case "all", "allAdjacent":
                self.positions = move.targetScope == "allAdjacent"
                    ? alliesPositions.union(foesPositions).subtracting([.init(own: true, slot: slot.slot)])
                    : alliesPositions.union(foesPositions)
            case "allAdjacentFoes", "foeSide": self.positions = foesPositions
            case "allySide", "allyTeam": self.positions = alliesPositions
            default: self.positions = []
            }
        }
    }
}

extension L {
    var battleChoicePending: String {
        t("미선택", "Not selected", "未選択", "Sin seleccionar", "Non sélectionné", "Não selecionado", "Nicht gewählt", "Не выбрано")
    }
    var battleChoicePass: String {
        t("행동 없음", "No action", "行動なし", "Sin acción", "Aucune action", "Sem ação", "Keine Aktion", "Нет действия")
    }

    func battleChoiceTarget(_ location: Int, own: [BattleCombatant], foe: [BattleCombatant]) -> String {
        let members = location < 0 ? own.filter(\.active) : foe
        let index = abs(location) - 1
        let name = members.indices.contains(index)
            ? BattleTextCatalog.shared.speciesName(members[index].speciesID, language: lang) : battleUnknownPokemon
        return "\(battleSide(ally: location < 0)) \(abs(location)) · \(name)"
    }
}
