import Foundation

/// Only feed the presented frame: authoritative requests can be a whole turn ahead
/// of the animation. Keep raw public records so changing language also translates history.
struct BattleTurnLog {
    struct Record: Identifiable {
        let id: Int
        let turn: Int?
        let raw: String
    }
    struct Entry: Identifiable {
        let id: Int
        let text: String
    }
    struct Group: Identifiable {
        let id: Int
        let turn: Int?
        var entries: [Entry]
    }
    static let capacity = 1000
    private(set) var records: [Record] = []
    private var end = 0
    private var currentTurn: Int?

    mutating func receive(_ frame: BattleFrame) {
        let offset = frame.logOffset ?? 0
        let nextEnd = offset + frame.log.count
        let existing = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.raw) })
        if nextEnd < end || frame.log.enumerated().contains(where: { index, raw in
            existing[offset + index].map { $0 != raw } ?? false
        }) {
            self = Self()
        }
        if records.isEmpty { currentTurn = offset == 0 ? 0 : nil }
        // A reopened/reconnected window may start partway through a turn.
        if offset > end { currentTurn = nil }
        for (index, raw) in frame.log.enumerated() where offset + index >= end {
            let parts = raw.split(separator:"|",omittingEmptySubsequences:false)
            if parts.count > 2, parts[1] == "turn" { currentTurn = Int(parts[2]) }
            records.append(Record(id:offset + index,turn:currentTurn,raw:raw))
        }
        end = nextEnd
        if records.count > Self.capacity { records.removeFirst(records.count - Self.capacity) }
    }

    func groups(language: AppLanguage, ownPlayer: Int) -> [Group] {
        let raw = records.map(\.raw)
        var result: [Group] = []
        for (index, record) in records.enumerated() {
            let parts=record.raw.split(separator:"|",omittingEmptySubsequences:false)
            guard parts.count > 1, parts[1] != "turn" else { continue }
            if parts[1] == "-weather", parts.contains("[upkeep]") { continue }
            var text = parts[1] == "-miss"
                ? BattleLogText.describeMiss(raw,at:index,language:language,ownPlayer:ownPlayer)
                : BattleLogText.describe(record.raw,language:language,ownPlayer:ownPlayer)
            if ["switch","drag"].contains(parts[1]), parts.count > 2, let line=text {
                let side=parts[2].hasPrefix("p1") ? 0:1
                text=L(language).battleSide(ally:side==ownPlayer)+" "+line
            }
            guard let text, !text.isEmpty else { continue }
            let entry=Entry(id:record.id,text:text)
            if result.last?.turn == record.turn, !result.isEmpty { result[result.count-1].entries.append(entry) }
            else { result.append(Group(id:record.id,turn:record.turn,entries:[entry])) }
        }
        return result
    }
}

extension L {
    var battleTurnLogTitle: String {
        t("턴 로그", "Turn log", "ターンログ", "Registro de turnos", "Journal des tours", "Registro de turnos", "Rundenprotokoll", "Журнал ходов")
    }
    func battleTurnLogState(_ expanded: Bool) -> String {
        expanded ? t("펼쳐짐", "Expanded", "展開中", "Expandido", "Développé", "Expandido", "Ausgeklappt", "Развёрнуто")
            : t("접힘", "Collapsed", "折りたたみ中", "Contraído", "Réduit", "Recolhido", "Eingeklappt", "Свёрнуто")
    }
    var battleTurnLogEmpty: String {
        t("아직 기록된 행동이 없습니다.", "No actions recorded yet.", "まだ行動の記録はありません。", "Aún no hay acciones registradas.", "Aucune action enregistrée.", "Nenhuma ação registrada ainda.", "Noch keine Aktionen protokolliert.", "Действий пока нет.")
    }
    func battleLogTurn(_ turn: Int?) -> String {
        guard let turn else {
            return t("이전 기록", "Earlier records", "以前の記録", "Registros anteriores", "Historique précédent", "Registros anteriores", "Frühere Einträge", "Предыдущие записи")
        }
        return turn > 0 ? battleTurn(turn) : t("배틀 시작", "Battle start", "バトル開始", "Inicio del combate", "Début du combat", "Início da batalha", "Kampfbeginn", "Начало боя")
    }
}
