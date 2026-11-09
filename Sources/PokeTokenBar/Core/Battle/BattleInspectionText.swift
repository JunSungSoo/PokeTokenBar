import Foundation

extension L {
    var battleNoPP: String {
        t("PP 부족", "No PP", "PP不足", "Sin PP", "PP épuisés", "Sem PP", "Keine AP", "Нет ОД")
    }
    var battleUnavailable: String {
        t("사용 불가", "Unavailable", "使用不可", "No disponible", "Indisponible", "Indisponível", "Nicht verfügbar", "Недоступно")
    }
    var battleChoiceLock: String {
        t("구애 도구로 기술 고정", "Move locked by Choice item", "こだわりアイテムで技固定",
          "Movimiento fijado por objeto Elegido", "Capacité bloquée par objet Choix", "Golpe fixado por item Escolha",
          "Attacke durch Wahl-Item festgelegt", "Приём зафиксирован предметом выбора")
    }
    var battleTrappedNotice: String {
        t("교체 불가", "Cannot switch", "交代不可", "No puede cambiar", "Changement impossible",
          "Não pode trocar", "Wechsel nicht möglich", "Замена невозможна")
    }
    var battleTypelessMove: String {
        t("타입 상성을 무시합니다.", "Ignores type matchups.", "タイプ相性を無視します。",
          "Ignora las afinidades de tipo.", "Ignore les affinités de type.", "Ignora as afinidades de tipo.",
          "Ignoriert Typenwechselwirkungen.", "Игнорирует взаимодействия типов.")
    }
    func battleMoveType(_ move: BattleMove) -> String {
        if move.ignoresTypeMatchup == true {
            return t("무속성", "Typeless", "タイプなし", "Sin tipo", "Sans type", "Sem tipo", "Ohne Typ", "Без типа")
        }
        return BattleTextCatalog.shared.typeName(move.type, language: lang)
    }
    func battleActiveEffect(_ id: String) -> String {
        switch id {
        case "confusion": return battleStatus("confusion")
        case "trapped", "partiallytrapped": return battleTrappedNotice
        case "choicelock": return battleChoiceLock
        default: return BattleTextCatalog.shared.moveName(id, language: lang)
        }
    }
    func battleDisabledReason(_ move: BattleMove) -> String? {
        if move.pp == 0 || move.disableReason == "pp" { return battleNoPP }
        guard move.disabled else { return nil }
        guard let reason = move.disableReason, reason != "unavailable" else { return battleUnavailable }
        if reason == "choicelock" { return battleChoiceLock }
        return battleUnavailable + " · " + BattleTextCatalog.shared.effectName(reason, language: lang)
    }
    func battleMoveDescription(_ move: BattleMove) -> String {
        guard BattleTextCatalog.key(move.apiName ?? move.name) == "curse", move.targetScope != nil else {
            return BattleTextCatalog.shared.description(move.apiName ?? move.name, language: lang)
        }
        if move.targetScope == "self" {
            return t("자신의 공격과 방어가 1단계 오르고 스피드가 1단계 내려갑니다. HP는 소모하지 않습니다.",
                     "Raises the user's Attack and Defense by one stage and lowers Speed by one stage. Costs no HP.",
                     "自分の攻撃と防御を1段階上げ、素早さを1段階下げる。HP消費なし。",
                     "Sube un nivel el Ataque y la Defensa y baja uno la Velocidad. No consume PS.",
                     "Augmente l’Attaque et la Défense d’un cran et baisse la Vitesse d’un cran, sans coût en PV.",
                     "Aumenta Ataque e Defesa em um estágio e reduz Velocidade em um estágio. Não gasta PS.",
                     "Erhöht Angriff und Verteidigung um eine Stufe und senkt Initiative um eine Stufe. Keine KP-Kosten.",
                     "Повышает Атаку и Защиту на ступень, снижает Скорость на ступень. ОЗ не расходуются.")
        }
        return t("자신의 최대 HP의 절반을 소모해 대상을 저주합니다. 대상은 매 턴 종료 시 최대 HP의 1/4을 잃으며 교체하면 풀립니다.",
                 "Costs half the user's maximum HP to curse the target. The target loses 1/4 of its maximum HP at each turn's end until it switches out.",
                 "自分の最大HPの半分を消費して相手をのろう。相手は毎ターン終了時に最大HPの1/4を失い、交代するとのろいが解ける。",
                 "Consume la mitad de los PS máximos del usuario. El objetivo pierde 1/4 de sus PS máximos por turno hasta cambiar.",
                 "Coûte la moitié des PV maximum du lanceur. La cible perd 1/4 de ses PV maximum en fin de tour jusqu’à son changement.",
                 "Gasta metade dos PS máximos do usuário. O alvo perde 1/4 dos PS máximos ao fim de cada turno até trocar.",
                 "Kostet die Hälfte der maximalen KP. Das Ziel verliert am Rundenende 1/4 seiner maximalen KP, bis es ausgewechselt wird.",
                 "Расходует половину максимальных ОЗ. Цель теряет 1/4 максимальных ОЗ в конце каждого хода до замены.")
    }
    func battleSwitchSummary(_ pokemon: BattleCombatant) -> String {
        let catalog = BattleTextCatalog.shared
        var parts = [catalog.speciesName(pokemon.speciesID, language: lang), "HP \(pokemon.hp)/\(pokemon.maxHP)"]
        if !pokemon.status.isEmpty { parts.append(battleStatus(pokemon.status)) }
        parts.append(battleHeldItem + " " + (BattleHeldItems.item(pokemon.item)?.name(lang) ?? battleNoItem))
        if pokemon.active {
            parts.append(t("출전 중", "Active", "出場中", "En combate", "Au combat", "Em campo", "Im Kampf", "В бою"))
        }
        if pokemon.fainted { parts.append(battleEvent("faint")) }
        return parts.joined(separator: " · ")
    }
}
