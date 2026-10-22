import Foundation

extension L {
    var battleEffectsVolume: String { t("효과음 볼륨", "Sound effects volume", "効果音音量", "Volumen de efectos", "Volume des effets", "Volume dos efeitos", "Effektlautstärke", "Громкость эффектов") }
    var battleVolume: String { t("BGM 볼륨", "BGM volume", "BGM音量", "Volumen de música", "Volume de la musique", "Volume da música", "Musiklautstärke", "Громкость музыки") }
    var battleDuplicateSpecies: String { t("같은 팀에는 같은 종을 한 마리만 선택할 수 있습니다. 폼이 달라도 같은 종으로 취급합니다.", "Choose only one Pokémon of each species per team. Different forms count as the same species.", "同じチームには同じ種類を1匹だけ選べます。フォルムが違っても同じ種類として扱います。", "Solo se permite un Pokémon de cada especie por equipo, aunque tenga otra forma.", "Un seul Pokémon de chaque espèce par équipe, même avec des formes différentes.", "Apenas um Pokémon de cada espécie por equipe, mesmo com formas diferentes.", "Nur ein Pokémon jeder Art pro Team, auch bei unterschiedlichen Formen.", "В команде может быть только один покемон каждого вида, даже если формы различаются.") }
    var battleItemTypeExcluded: String { t("도구에 따라 타입이 정해지는 포켓몬은 배틀에 참가할 수 없습니다.", "Pokémon whose type depends on a held item cannot battle.", "持ち物でタイプが決まるポケモンは参加できません。", "Los Pokémon cuyo tipo depende de un objeto no pueden combatir.", "Les Pokémon dont le type dépend d’un objet ne peuvent pas combattre.", "Pokémon cujo tipo depende de um item não podem batalhar.", "Pokémon mit einem vom Item abhängigen Typ können nicht kämpfen.", "Покемоны, чей тип зависит от предмета, не могут участвовать в бою.") }
    var battle: String { t("배틀", "Battle", "バトル", "Combate", "Combat", "Batalha", "Kampf", "Бой") }
    var battleSingles: String { t("싱글 · 3마리", "Singles · 3", "シングル・3匹", "Individual · 3", "Solo · 3", "Individual · 3", "Einzel · 3", "Одиночный · 3") }
    var battleDoubles: String { t("더블 · 4마리", "Doubles · 4", "ダブル・4匹", "Doble · 4", "Duo · 4", "Dupla · 4", "Doppel · 4", "Парный · 4") }
    var battleRules: String { t("BW2 규칙 · 현재 레벨/스탯 · 도구 없음", "BW2 rules · Current stats · No items", "BW2ルール・現在の能力・道具なし", "Reglas BW2 · Estadísticas actuales · Sin objetos", "Règles BW2 · Stats actuelles · Sans objets", "Regras BW2 · Atributos atuais · Sem itens", "BW2 · Aktuelle Werte · Keine Items", "BW2 · Текущие характеристики · Без предметов") }
    var battleFind: String { t("매칭 요청", "Find a Wi-Fi/LAN opponent", "Wi-Fi/LANの相手を探す", "Buscar rival Wi-Fi/LAN", "Chercher un adversaire Wi-Fi/LAN", "Buscar oponente Wi-Fi/LAN", "WLAN/LAN-Gegner suchen", "Найти соперника Wi-Fi/LAN") }
    var battleMatching: String { t("매칭 요청 중…", "Finding a match…", "マッチング中…", "Buscando partida…", "Recherche en cours…", "Buscando partida…", "Gegnersuche…", "Поиск соперника…") }
    var battleMatchingHint: String { t("같은 Wi-Fi/LAN에서 매칭을 요청한 상대입니다. 선택하거나 매칭을 취소할 때까지 계속 검색합니다.", "Players requesting a match on your Wi-Fi/LAN. Searching continues until you select someone or cancel.", "同じWi-Fi/LANで対戦を希望する相手です。選択またはキャンセルするまで検索します。", "Jugadores que buscan partida en tu Wi-Fi/LAN. La búsqueda continúa hasta elegir o cancelar.", "Joueurs en recherche sur votre Wi-Fi/LAN. La recherche continue jusqu’au choix ou à l’annulation.", "Jogadores buscando partida no seu Wi-Fi/LAN. A busca continua até escolher ou cancelar.", "Suchende im selben WLAN/LAN. Die Suche läuft bis zur Auswahl oder zum Abbruch.", "Игроки, ищущие бой в вашей Wi-Fi/LAN. Поиск продолжается до выбора или отмены.") }
    var battleMatchingEmpty: String { t("아직 매칭을 요청한 상대가 없습니다.", "No players are requesting a match yet.", "対戦を希望する相手はまだいません。", "Aún no hay jugadores buscando partida.", "Aucun joueur en recherche pour le moment.", "Ainda não há jogadores buscando partida.", "Noch keine suchenden Spieler.", "Пока никто не ищет бой.") }
    var battleConnecting: String { t("상대방과 연결 중…", "Connecting to opponent…", "相手に接続中…", "Conectando al rival…", "Connexion à l’adversaire…", "Conectando ao oponente…", "Verbindung zum Gegner…", "Подключение к сопернику…") }
    var battleManual: String { t("수동 연결", "Manual connection", "手動接続", "Conexión manual", "Connexion manuelle", "Conexão manual", "Manuelle Verbindung", "Ручное подключение") }
    var battleSelected: String { t("선택됨", "Selected", "選択中", "Seleccionado", "Sélectionné", "Selecionado", "Ausgewählt", "Выбран") }
    var battleHiddenTeam: String { t("상대 포켓몬 6마리 · 비공개", "Opponent’s six Pokémon · Hidden", "相手の6匹・非公開", "Seis Pokémon rivales · Ocultos", "Six Pokémon adverses · Cachés", "Seis Pokémon rivais · Ocultos", "Sechs gegnerische Pokémon · Verborgen", "Шесть покемонов соперника · Скрыты") }
    var battleSelectionOrder: String { t("선택한 순서대로 출전합니다. 싱글은 1번, 더블은 1·2번이 먼저 나갑니다. 상대의 출전 선택은 공개되지 않습니다.", "Selection sets team order. Singles leads with #1; doubles with #1 and #2. Your opponent’s lineup choices stay hidden.", "選択順で出場します。シングルは1番、ダブルは1・2番が先発。相手の選出は非公開です。", "El orden de selección decide la salida: 1 en individual, 1 y 2 en doble. La selección rival permanece oculta.", "L’ordre de sélection définit l’entrée : 1 en solo, 1 et 2 en duo. La sélection adverse reste cachée.", "A ordem de seleção define a entrada: 1 em individual, 1 e 2 em dupla. A seleção rival fica oculta.", "Auswahlreihenfolge ist Teamreihenfolge: 1 im Einzel, 1 und 2 im Doppel. Die gegnerische Auswahl bleibt verborgen.", "Порядок выбора задаёт выход: №1 в одиночном, №1 и №2 в парном. Выбор соперника скрыт.") }
    var battleTeam: String { t("출전 포켓몬", "Your team", "出場ポケモン", "Tu equipo", "Ton équipe", "Sua equipe", "Dein Team", "Ваша команда") }
    var battleReady: String { t("동의하고 준비 완료", "Agree and ready", "同意して準備完了", "Aceptar y listo", "Accepter et prêt", "Concordar e pronto", "Zustimmen und bereit", "Согласиться и готов") }
    var battleUnready: String { t("준비 취소", "Cancel readiness", "準備を取り消す", "Cancelar preparación", "Annuler la préparation", "Cancelar prontidão", "Bereitschaft aufheben", "Отменить готовность") }
    var battleWaiting: String { t("상대방을 기다리고 있어요…", "Waiting for your opponent…", "相手を待っています…", "Esperando al rival…", "En attente de l’adversaire…", "Aguardando o oponente…", "Warte auf den Gegner…", "Ожидание соперника…") }
    var battleHistory: String { t("배틀 이력", "Battle history", "バトル履歴", "Historial de combates", "Historique des combats", "Histórico de batalhas", "Kampfverlauf", "История боёв") }
    var battleNoHistory: String { t("아직 배틀 이력이 없어요.", "No battles yet.", "まだバトル履歴がありません。", "Aún no hay combates.", "Aucun combat pour l’instant.", "Nenhuma batalha ainda.", "Noch keine Kämpfe.", "Пока нет боёв.") }
    var battleOpen: String { t("배틀 창 열기", "Open battle window", "バトル画面を開く", "Abrir ventana de combate", "Ouvrir le combat", "Abrir janela de batalha", "Kampffenster öffnen", "Открыть окно боя") }
    var battleConfirmClose: String { t("정말 종료하겠습니까?", "Are you sure you want to quit?", "本当に終了しますか？", "¿Seguro que quieres salir?", "Veux-tu vraiment quitter ?", "Quer mesmo sair?", "Möchtest du wirklich beenden?", "Вы действительно хотите выйти?") }
    var battleCloseDetail: String { t("배틀을 종료하면 항복으로 처리되며 상대방이 승리합니다.", "Quitting forfeits the battle. Your opponent wins.", "終了すると降参となり、相手の勝利になります。", "Salir cuenta como rendición. Tu rival gana.", "Quitter vaut abandon. Ton adversaire gagne.", "Sair conta como desistência. Seu oponente vence.", "Beenden zählt als Aufgabe. Dein Gegner gewinnt.", "Выход считается сдачей. Соперник побеждает.") }
    var battleConfirm: String { t("확인", "Confirm", "確認", "Confirmar", "Confirmer", "Confirmar", "Bestätigen", "Подтвердить") }
    var battleCancel: String { t("매칭 취소", "Cancel matching", "キャンセル", "Cancelar", "Annuler", "Cancelar", "Abbrechen", "Отмена") }
    var battleFight: String { t("공격", "Fight", "たたかう", "Luchar", "Attaquer", "Lutar", "Kämpfen", "Атака") }
    var battleSwitch: String { t("교체", "Switch", "交代", "Cambiar", "Changer", "Trocar", "Wechseln", "Замена") }
    var battleSurrender: String { t("항복", "Surrender", "降参", "Rendirse", "Abandonner", "Desistir", "Aufgeben", "Сдаться") }
    var battleChooseLeads: String { t("선봉 순서를 선택하세요", "Choose your lead order", "先発の順番を選ぶ", "Elige el orden inicial", "Choisis l’ordre de départ", "Escolha a ordem inicial", "Startreihenfolge wählen", "Выберите порядок выхода") }
    var battleSubmit: String { t("선택 확정", "Confirm choices", "選択を確定", "Confirmar opciones", "Confirmer les choix", "Confirmar escolhas", "Auswahl bestätigen", "Подтвердить выбор") }
    var battleTarget: String { t("대상", "Target", "対象", "Objetivo", "Cible", "Alvo", "Ziel", "Цель") }
    var battleMusic: String { t("골드·실버 배틀 BGM", "Gold/Silver battle music", "金・銀バトルBGM", "Música de combate Oro/Plata", "Musique de combat Or/Argent", "Música de batalha Gold/Silver", "Gold/Silber-Kampfmusik", "Музыка боя Gold/Silver") }
    var battleReconnecting: String { t("연결 복구 중… 30초 후 중단", "Reconnecting… interrupted after 30s", "再接続中…30秒で中断", "Reconectando… se interrumpe en 30 s", "Reconnexion… interruption après 30 s", "Reconectando… interrupção após 30 s", "Verbinde erneut… Abbruch nach 30 s", "Переподключение… прерывание через 30 с") }
    var battlePreparing: String { t("배틀 데이터 준비 중…", "Preparing battle…", "バトル準備中…", "Preparando combate…", "Préparation du combat…", "Preparando batalha…", "Kampf wird vorbereitet…", "Подготовка боя…") }
    var battleSearchHint: String { t("두 기기에서 같은 Wi-Fi/LAN에 연결한 후 매칭 요청을 눌러주세요.", "Open Battle on both Macs to find each other.", "両方のMacでバトルを開いてください。", "Abre Combate en ambos Mac.", "Ouvrez Combat sur les deux Mac.", "Abra Batalha nos dois Macs.", "Auf beiden Macs Kampf öffnen.", "Откройте Бой на обоих Mac.") }
    func battleResult(_ result: String) -> String {
        switch result {
        case "win": t("승리", "Victory", "勝利", "Victoria", "Victoire", "Vitória", "Sieg", "Победа")
        case "loss": t("패배", "Defeat", "敗北", "Derrota", "Défaite", "Derrota", "Niederlage", "Поражение")
        case "draw": t("무승부", "Draw", "引き分け", "Empate", "Égalité", "Empate", "Unentschieden", "Ничья")
        default: t("중단", "Interrupted", "中断", "Interrumpido", "Interrompu", "Interrompida", "Unterbrochen", "Прерван")
        }
    }
}

extension L {
    var battleSelectMove: String { t("기술을 선택하면 상세 정보가 표시됩니다.","Select a move to see its details.","技を選ぶと詳細を表示します。","Elige un movimiento para ver detalles.","Choisis une capacité pour voir ses détails.","Selecione um golpe para ver detalhes.","Wähle eine Attacke für Details.","Выберите приём для просмотра сведений.") }
    var battlePower: String { t("위력","Power","威力","Potencia","Puissance","Poder","Stärke","Мощность") }
    func battleRosterTypeMatchup(_ outgoing:Double,incoming:Double)->String {
        let own=outgoing.formatted(.number.locale(lang.displayLocale))
        let foe=incoming.formatted(.number.locale(lang.displayLocale))
        return t("타입 기준 · 나의 공격 ×\(own) / 상대 공격 ×\(foe) · 기술·특성 미반영",
            "Types only · My attack ×\(own) / Opponent attack ×\(foe) · Excludes moves and abilities",
            "タイプのみ · 自分の攻撃 ×\(own) / 相手の攻撃 ×\(foe) · 技・特性を除く",
            "Solo tipos · Mi ataque ×\(own) / Rival ×\(foe) · Sin movimientos ni habilidades",
            "Types seuls · Mon attaque ×\(own) / Adversaire ×\(foe) · Sans capacités ni talents",
            "Só tipos · Meu ataque ×\(own) / Rival ×\(foe) · Sem golpes e habilidades",
            "Nur Typen · Mein Angriff ×\(own) / Gegner ×\(foe) · Ohne Attacken und Fähigkeiten",
            "Только типы · Моя атака ×\(own) / Противник ×\(foe) · Без приёмов и способностей")
    }
    var battleTypeOnly: String { t("기술 속성 × 현재 상대 타입 기준입니다. 특성·날씨 등의 효과는 포함하지 않습니다.","Move type vs current opposing types only. Abilities, weather and other effects are excluded.","技のタイプと現在の相手タイプのみ。特性・天候などは含みません。","Solo tipos actuales. No incluye habilidades ni clima.","Types actuels uniquement, sans talents ni météo.","Apenas tipos atuais, sem habilidades ou clima.","Nur aktuelle Typen, ohne Fähigkeiten oder Wetter.","Только текущие типы, без способностей и погоды.") }
    func battleCategory(_ category: String) -> String {
        switch category {
        case "Physical": t("물리","Physical","物理","Físico","Physique","Físico","Physisch","Физический")
        case "Special": t("특수","Special","特殊","Especial","Spécial","Especial","Speziell","Специальный")
        default: t("변화","Status","変化","Estado","Statut","Status","Status","Статусный")
        }
    }
    func battleEffectiveness(_ multiplier: Double?) -> String {
        guard let multiplier else { return battleCategory("Status") }
        let label: String
        if multiplier == 0 { label = t("효과 없음","No effect","効果なし","Sin efecto","Sans effet","Sem efeito","Wirkungslos","Нет эффекта") }
        else if multiplier > 1 { label = t("효과가 굉장함","Super effective","効果抜群","Supereficaz","Super efficace","Supereficaz","Sehr effektiv","Суперэффективно") }
        else if multiplier < 1 { label = t("효과가 별로","Not very effective","いまひとつ","Poco eficaz","Peu efficace","Pouco eficaz","Nicht sehr effektiv","Малоэффективно") }
        else { label = t("보통","Normal","通常","Normal","Normal","Normal","Normal","Обычно") }
        return label + " ×" + multiplier.formatted(.number.precision(.fractionLength(0...2)).locale(lang.displayLocale))
    }
}
