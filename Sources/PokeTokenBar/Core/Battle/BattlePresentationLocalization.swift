import Foundation

extension L {
    var battleRegisterTeam: String { t("6마리 등록", "Register six", "6匹を登録", "Registrar seis", "Inscrire six", "Registrar seis", "Sechs registrieren", "Заявить шесть") }
    var battleWaitingForRoster: String { t("상대방이 6마리를 등록하면 양쪽 팀을 보고 출전 포켓몬을 선택할 수 있습니다.", "Once your opponent registers six, choose your lineup while viewing both teams.", "相手が6匹を登録すると両チームを見て出場ポケモンを選べます。", "Cuando tu rival registre seis, elige viendo ambos equipos.", "Après l’inscription adverse, choisis en regardant les deux équipes.", "Quando o rival registrar seis, escolha vendo as duas equipes.", "Sobald der Gegner sechs registriert, wählst du mit Blick auf beide Teams.", "Когда соперник заявит шесть, выберите участников, видя обе команды.") }
    var battleOwnRoster: String { t("나의 포켓몬 · 6마리", "Your Pokémon · Six", "自分のポケモン・6匹", "Tus Pokémon · Seis", "Tes Pokémon · Six", "Seus Pokémon · Seis", "Deine Pokémon · Sechs", "Ваши покемоны · Шесть") }
    var battleOpponentRoster: String { t("상대 포켓몬 · 6마리", "Opponent’s Pokémon · Six", "相手のポケモン・6匹", "Pokémon rivales · Seis", "Pokémon adverses · Six", "Pokémon rivais · Seis", "Gegnerische Pokémon · Sechs", "Покемоны соперника · Шесть") }
    var battleRegisteredTeam: String { t("등록 포켓몬", "Registered roster", "登録ポケモン", "Equipo registrado", "Équipe inscrite", "Equipe registrada", "Registriertes Team", "Заявленная команда") }
    var battleRegisterHint: String { t("먼저 포켓몬 6마리를 등록한 뒤, 실제 출전할 포켓몬을 선택합니다.", "Register six Pokémon, then choose the battle lineup.", "まず6匹を登録し、出場するポケモンを選びます。", "Registra seis Pokémon y luego elige cuáles combatirán.", "Inscris six Pokémon, puis choisis ceux qui combattront.", "Registre seis Pokémon e depois escolha os participantes.", "Registriere sechs Pokémon und wähle dann die Kampfaufstellung.", "Заявите шесть покемонов, затем выберите участников боя.") }
    var battleSelectLineup: String { t("출전 포켓몬 선택", "Choose battle lineup", "出場ポケモンを選ぶ", "Elegir participantes", "Choisir les participants", "Escolher participantes", "Kampfaufstellung wählen", "Выбрать участников") }
    func battleLineupHint(_ mode: BattleMode) -> String {
        let n = mode.battleSize
        return t("등록한 6마리 중 \(n)마리를 선택하세요. 선택한 포켓몬끼리만 교체할 수 있습니다.", "Choose \(n) of your six Pokémon. Only these Pokémon can switch in.", "登録した6匹から\(n)匹を選んでください。交代できるのは選んだポケモンだけです。", "Elige \(n) de tus seis Pokémon. Solo ellos podrán entrar al combate.", "Choisis \(n) de tes six Pokémon. Seuls ceux-ci pourront entrer au combat.", "Escolha \(n) dos seis Pokémon. Apenas eles poderão entrar na batalha.", "Wähle \(n) deiner sechs Pokémon. Nur diese können eingewechselt werden.", "Выберите \(n) из шести покемонов. Только они смогут выходить на поле.")
    }
    var battleBaseAccuracy: String { t("기본 명중률", "Base accuracy", "基本命中率", "Precisión base", "Précision de base", "Precisão base", "Basisgenauigkeit", "Базовая точность") }
    func battleAccuracy(_ accuracy: BattleMoveAccuracy?) -> String {
        switch accuracy {
        case .percent(let value): return "\(value)%"
        case .always: return t("필중", "Always hits", "必中", "No falla", "Touche toujours", "Não falha", "Trifft immer", "Всегда попадает")
        case nil: return "—"
        }
    }
}

extension L {
    var battleFinalOnly: String { t("육성이 완료된 BW2 기준 최종 진화체만 출전할 수 있습니다. 진화하지 않는 포켓몬도 포함됩니다.", "Only graduated Pokémon in their final BW2 evolution can battle, including species that do not evolve.", "育成を完了したBW2時点の最終進化形のみ参加できます。進化しないポケモンも含みます。", "Solo pueden combatir Pokémon con crianza completada y evolución final de B2N2, incluidos los que no evolucionan.", "Seuls les Pokémon élevés jusqu’au bout et à leur évolution finale de NB2 peuvent combattre, y compris ceux sans évolution.", "Apenas Pokémon com criação concluída e evolução final de B2W2 podem batalhar, incluindo os que não evoluem.", "Nur fertig aufgezogene Pokémon auf ihrer letzten SW2-Entwicklungsstufe dürfen kämpfen, auch Arten ohne Entwicklung.", "Участвуют только покемоны с завершённым выращиванием на последней стадии B2W2, включая неэволюционирующих.") }

    var loadoutChooseMove: String { t("기술 선택", "Choose move", "技を選ぶ", "Elegir movimiento", "Choisir une capacité", "Escolher golpe", "Attacke wählen", "Выбрать приём") }
    var loadoutLearnsetHint: String { t("BW2 기술과 습득 가능한 6세대 페어리 기술 중 최대 4개를 선택합니다. 레벨 제한을 적용하며 선택은 즉시 저장됩니다.", "Choose up to four BW2 or compatible Gen VI Fairy moves. Level limits apply; choices save immediately.", "BW2の技と習得可能な第6世代フェアリー技から最大4つ。レベル制限が適用され、即時保存されます。", "Elige hasta cuatro movimientos de BW2 o Hada de sexta generación compatibles. Se aplican límites de nivel y se guardan al instante.", "Choisis jusqu’à quatre capacités NB2 ou Fée de 6e génération compatibles. Limites de niveau et sauvegarde immédiate.", "Escolha até quatro golpes de B2W2 ou Fada da 6ª geração compatíveis. Limites de nível e salvamento imediato.", "Bis zu vier SW2- oder passende Feen-Attacken der 6. Generation. Levelgrenzen gelten; sofortige Speicherung.", "До четырёх приёмов B2W2 или доступных волшебных приёмов VI поколения. Учитывается уровень; выбор сохраняется сразу.") }

    var battleUnknownPokemon: String { t("포켓몬","Pokémon","ポケモン","Pokémon","Pokémon","Pokémon","Pokémon","Покемон") }
    var battleUnknownMove: String { t("기술","Move","技","Movimiento","Capacité","Golpe","Attacke","Приём") }
    var battleUnknownType: String { t("속성","Type","タイプ","Tipo","Type","Tipo","Typ","Тип") }
    var battleDescriptionUnavailable: String { t("기술 설명을 불러올 수 없습니다.","Move description unavailable.","技の説明を読み込めません。","No se puede cargar la descripción.","Description indisponible.","Descrição indisponível.","Beschreibung nicht verfügbar.","Описание недоступно.") }
    var battleAbility: String { t("특성","Ability","特性","Habilidad","Talent","Habilidade","Fähigkeit","Способность") }
    var battleHP: String { t("체력","HP","HP","PS","PV","PS","KP","ОЗ") }
    var battlePP: String { t("PP","PP","PP","PP","PP","PP","AP","ОД") }
    var battleLogTitle: String { t("배틀 기록","Battle log","バトルログ","Registro del combate","Journal du combat","Registro da batalha","Kampfprotokoll","Журнал боя") }
    var battleHistoryProblem: String { t("배틀 이력을 읽거나 저장할 수 없습니다. 저장 폴더를 확인해 주세요.","Battle history could not be read or saved. Check the save folder.","履歴を読み込み・保存できません。保存先を確認してください。","No se pudo leer o guardar el historial. Revisa la carpeta.","Impossible de lire ou sauvegarder l’historique. Vérifie le dossier.","Não foi possível ler ou salvar o histórico. Verifique a pasta.","Verlauf konnte nicht gelesen oder gespeichert werden. Prüfe den Ordner.","Не удалось прочитать или сохранить историю. Проверьте папку.") }
    func battleTurn(_ number: Int) -> String { t("\(number)턴","Turn \(number)","\(number)ターン","Turno \(number)","Tour \(number)","Turno \(number)","Runde \(number)","Ход \(number)") }
    func battleSide(ally: Bool) -> String {
        ally ? t("아군","Ally","味方","Aliado","Allié","Aliado","Verbündet","Союзник") : t("상대","Opponent","相手","Rival","Adversaire","Oponente","Gegner","Противник")
    }
    func battleUserError(_ raw: String) -> String {
        if raw == battleDuplicateItem || raw.contains("Duplicate held item"){return battleDuplicateItem}
        if raw == "Battle mode mismatch" {
            return t("상대와 같은 배틀 방식(싱글/더블)으로 매칭을 요청해 주세요.","Request the same battle format (singles/doubles) as your opponent.","相手と同じ形式（シングル・ダブル）でマッチングしてください。","Solicita el mismo formato (individual/doble) que tu rival.","Choisis le même format (simple/double) que ton adversaire.","Escolha o mesmo formato (individual/dupla) do oponente.","Wähle dasselbe Kampfformat (Einzel/Doppel) wie dein Gegner.","Выберите одинаковый формат боя (одиночный/двойной).")
        }
        if raw.contains("Invalid battle lineup") { return battleRegisterHint }
        if raw == battleFinalOnly || raw.contains("Fully evolved Pokémon required") { return battleFinalOnly }
        if raw == battleDuplicateSpecies || raw.contains("Duplicate species") { return battleDuplicateSpecies }
        if raw == battleItemTypeExcluded { return raw }
        if raw.contains("Incompatible") || raw.contains("revision") {
            return t("두 기기의 앱을 같은 버전으로 업데이트해 주세요.","Update both apps to the same version.","両方のアプリを同じ版に更新してください。","Actualiza ambas apps a la misma versión.","Mets les deux apps à la même version.","Atualize os dois apps para a mesma versão.","Aktualisiere beide Apps auf dieselbe Version.","Обновите оба приложения до одной версии.")
        }
        if raw.contains("engine") || raw.contains("Engine") {
            return t("배틀 엔진을 실행할 수 없습니다. 최신 앱으로 다시 시도해 주세요.","The battle engine is unavailable. Try the latest app.","エンジンを起動できません。最新版で再試行してください。","El motor no está disponible. Prueba la última app.","Moteur indisponible. Réessaie avec la dernière app.","O motor está indisponível. Tente o app mais recente.","Kampf-Engine nicht verfügbar. Versuche die aktuelle App.","Движок боя недоступен. Используйте последнюю версию.")
        }
        if raw.contains("disconnect") || raw.contains("connect") {
            return t("상대와의 연결을 확인해 주세요.","Check the connection to your opponent.","相手との接続を確認してください。","Comprueba la conexión con tu rival.","Vérifie la connexion avec l’adversaire.","Verifique a conexão com o oponente.","Prüfe die Verbindung zum Gegner.","Проверьте соединение с противником.")
        }
        return t("배틀 선택 또는 데이터를 확인한 뒤 다시 시도해 주세요.","Check the battle choices and data, then try again.","バトルの選択・データを確認して再試行してください。","Revisa las opciones y los datos e inténtalo de nuevo.","Vérifie les choix et les données, puis réessaie.","Verifique as escolhas e os dados e tente novamente.","Prüfe Auswahl und Daten und versuche es erneut.","Проверьте выбор и данные боя и повторите попытку.")
    }
    func battleStatus(_ code: String) -> String {
        switch code.lowercased() {
        case "brn": t("화상","Burn","やけど","Quemadura","Brûlure","Queimadura","Verbrennung","Ожог")
        case "par": t("마비","Paralysis","まひ","Parálisis","Paralysie","Paralisia","Paralyse","Паралич")
        case "slp": t("잠듦","Sleep","ねむり","Sueño","Sommeil","Sono","Schlaf","Сон")
        case "frz": t("얼음","Frozen","こおり","Congelación","Gel","Congelado","Eingefroren","Заморозка")
        case "psn": t("독","Poison","どく","Veneno","Poison","Veneno","Vergiftung","Отравление")
        case "tox": t("맹독","Bad poison","もうどく","Veneno grave","Poison grave","Veneno grave","Schwere Vergiftung","Сильное отравление")
        case "confusion": t("혼란","Confusion","こんらん","Confusión","Confusion","Confusão","Verwirrung","Замешательство")
        case "flinch": t("풀죽음","Flinch","ひるみ","Retroceso","Apeurement","Recuo","Zurückschrecken","Испуг")
        case "attract": t("헤롱헤롱","Infatuation","メロメロ","Enamoramiento","Amour","Atração","Anziehung","Влюблённость")
        case "trapped", "partiallytrapped": t("교체 불가","Trapped","交代不可","Atrapado","Piégé","Preso","Gefangen","В ловушке")
        default: t("상태 효과","Status effect","状態効果","Efecto de estado","Effet de statut","Efeito de status","Statuseffekt","Эффект состояния")
        }
    }
    func battleWeather(_ code: String) -> String {
        switch code.lowercased() {
        case "sunnyday", "sun": t("쾌청","Sunlight","ひざしがつよい","Sol","Soleil","Sol","Sonnenschein","Солнце")
        case "raindance", "rain": t("비","Rain","あめ","Lluvia","Pluie","Chuva","Regen","Дождь")
        case "sandstorm": t("모래바람","Sandstorm","すなあらし","Tormenta de arena","Tempête de sable","Tempestade de areia","Sandsturm","Песчаная буря")
        case "hail": t("싸라기눈","Hail","あられ","Granizo","Grêle","Granizo","Hagel","Град")
        default: t("날씨 효과 종료","Weather ended","天候終了","Fin del clima","Fin de la météo","Fim do clima","Wetter beendet","Погода закончилась")
        }
    }
    func battleEvent(_ code: String) -> String {
        switch code {
        case "faint": t("기절","Fainted","ひんし","Debilitado","K.O.","Desmaiou","Besiegt","Без сознания")
        case "-damage": t("체력 감소","HP lost","HP減少","Pierde PS","PV perdus","Perde PS","KP verloren","Потеря ОЗ")
        case "-heal": t("체력 회복","HP restored","HP回復","Recupera PS","PV restaurés","Recupera PS","KP geheilt","Восстановление ОЗ")
        case "-curestatus": t("상태 회복","Status cured","状態回復","Estado curado","Statut soigné","Status curado","Status geheilt","Состояние снято")
        case "-immune": t("효과 없음","No effect","効果なし","Sin efecto","Sans effet","Sem efeito","Wirkungslos","Нет эффекта")
        case "-supereffective": t("효과가 굉장함","Super effective","効果抜群","Supereficaz","Super efficace","Supereficaz","Sehr effektiv","Суперэффективно")
        case "-resisted": t("효과가 별로","Not very effective","いまひとつ","Poco eficaz","Peu efficace","Pouco eficaz","Nicht sehr effektiv","Малоэффективно")
        case "-crit": t("급소 명중","Critical hit","急所に当たった","Golpe crítico","Coup critique","Acerto crítico","Volltreffer","Критический удар")
        case "-boost": t("능력 상승","Stat rose","能力上昇","Sube estadística","Stat en hausse","Atributo aumentou","Wert gestiegen","Показатель повышен")
        case "-unboost": t("능력 하락","Stat fell","能力低下","Baja estadística","Stat en baisse","Atributo diminuiu","Wert gesunken","Показатель снижен")
        case "-fail": t("실패","Failed","失敗","Falló","Échec","Falhou","Fehlgeschlagen","Неудача")
        case "-end": t("효과 종료","Effect ended","効果終了","Fin del efecto","Fin de l’effet","Fim do efeito","Effekt beendet","Эффект закончился")
        default: t("효과 발동","Effect activated","効果発動","Efecto activado","Effet activé","Efeito ativado","Effekt aktiviert","Эффект сработал")
        }
    }
    func battleStat(_ code: String) -> String {
        let names = ["hp":"hp","atk":"attack","def":"defense","spa":"special-attack","spd":"special-defense","spe":"speed"]
        if let name = names[code] { return statLabel(name) }
        return code == "accuracy" ? t("명중률","Accuracy","命中率","Precisión","Précision","Precisão","Genauigkeit","Точность")
            : t("회피율","Evasion","回避率","Evasión","Esquive","Evasão","Fluchtwert","Уклонение")
    }
}

extension L {
    func battleMoveTarget(_ move: BattleMove) -> String {
        switch move.targetScope {
        case "all":
            return t("모두", "Everyone", "全員", "Todos", "Tout le monde", "Todos", "Alle", "Все")
        case "allAdjacent":
            return t("모두 (자신 제외)", "Everyone except self", "自分以外全員", "Todos salvo el usuario", "Tous sauf le lanceur", "Todos exceto o usuário", "Alle außer Anwender", "Все, кроме себя")
        case "allAdjacentFoes":
            return t("상대 모두", "All opponents", "相手全員", "Todos los rivales", "Tous les adversaires", "Todos os oponentes", "Alle Gegner", "Все противники")
        case "self":
            return t("자신", "Self", "自分", "Usuario", "Soi-même", "Usuário", "Anwender", "Себя")
        case "adjacentAlly":
            return t("아군 단일", "One ally", "味方1体", "Un aliado", "Un allié", "Um aliado", "Ein Verbündeter", "Один союзник")
        case "adjacentAllyOrSelf":
            return t("자신 또는 아군 단일", "Self or one ally", "自分か味方1体", "Usuario o un aliado", "Soi-même ou un allié", "Usuário ou um aliado", "Anwender oder ein Verbündeter", "Себя или одного союзника")
        case "allyTeam":
            return t("아군 모두 (대기 포함)", "All allies, including bench", "味方全員（控え含む）", "Todos los aliados, incluidos suplentes", "Tous les alliés, réserve comprise", "Todos os aliados, incluindo reservas", "Alle Verbündeten, auch Reserve", "Все союзники, включая запас")
        case "allySide":
            return t("아군 모두 (진영)", "All allies / allied side", "味方全員・味方の場", "Todos los aliados / campo aliado", "Tous les alliés / camp allié", "Todos os aliados / campo aliado", "Alle Verbündeten / eigene Seite", "Все союзники / своя сторона")
        case "foeSide":
            return t("상대 진영", "Opposing side", "相手の場", "Campo rival", "Camp adverse", "Campo oponente", "Gegnerische Seite", "Сторона противника")
        case "randomNormal":
            return t("상대 단일 (무작위)", "One random opponent", "相手1体（ランダム）", "Un rival al azar", "Un adversaire au hasard", "Um oponente aleatório", "Ein zufälliger Gegner", "Один случайный противник")
        case "scripted":
            return t("반격 대상 (자동)", "Counterattack target (automatic)", "反撃対象（自動）", "Objetivo del contraataque (automático)", "Cible de contre-attaque (automatique)", "Alvo do contra-ataque (automático)", "Konterziel (automatisch)", "Цель контратаки (автоматически)")
        case "normal", "any":
            if move.targets.contains(where: { $0.location < 0 }) {
                return t("상대 또는 아군 단일", "One opponent or ally", "相手か味方1体", "Un rival o aliado", "Un adversaire ou allié", "Um oponente ou aliado", "Ein Gegner oder Verbündeter", "Один противник или союзник")
            }
            return t("상대 단일", "One opponent", "相手1体", "Un rival", "Un adversaire", "Um oponente", "Ein Gegner", "Один противник")
        case "adjacentFoe":
            return t("상대 단일", "One opponent", "相手1体", "Un rival", "Un adversaire", "Um oponente", "Ein Gegner", "Один противник")
        default: return "—"
        }
    }
}


extension L {
    var battleEffectsUnavailable:String {
        switch lang {
        case .ko:"PokéRogue 연출을 불러오지 못했습니다. 다음 기술에서 다시 시도합니다."
        case .en:"PokéRogue animation could not load. The next move will retry."
        case .ja:"PokéRogueの演出を読み込めませんでした。次の技で再試行します。"
        case .de:"PokéRogue-Animation konnte nicht geladen werden. Der nächste Zug versucht es erneut."
        case .fr:"Impossible de charger l’animation PokéRogue. Nouvel essai au prochain mouvement."
        case .es:"No se pudo cargar la animación PokéRogue. Se reintentará en el siguiente movimiento."
        case .pt:"Não foi possível carregar a animação PokéRogue. A próxima jogada tentará novamente."
        case .ru:"Не удалось загрузить анимацию PokéRogue. Следующий приём повторит попытку."
        }
    }
}

extension L {
    var battleFieldUntilRemoved: String { t("해제까지", "Until removed", "解除まで", "Hasta eliminarse", "Jusqu’au retrait", "Até ser removido", "Bis zur Aufhebung", "До отмены") }
    var battleFieldTitle: String { t("날씨 · 필드", "Weather · Field", "天候・場", "Clima · Campo", "Météo · Terrain", "Clima · Campo", "Wetter · Feld", "Погода · Поле") }
    var battleWeatherSuppressed: String { t("날씨 효과 무효", "Weather effects suppressed", "天候の効果無効", "Efectos del clima anulados", "Effets météo neutralisés", "Efeitos do clima anulados", "Wetterwirkung aufgehoben", "Эффекты погоды подавлены") }
    func battleFieldEffect(_ raw: String) -> String {
        let id = BattleTextCatalog.key(raw.components(separatedBy: ": ").last ?? raw)
        switch id {
        case "electricterrain": return t("일렉트릭필드","Electric Terrain","エレキフィールド","Campo eléctrico","Champ Électrifié","Terreno Elétrico","Elektrofeld","Электрическое поле")
        case "rainbow": return t("무지개", "Rainbow", "にじ", "Arcoíris", "Arc-en-ciel", "Arco-íris", "Regenbogen", "Радуга")
        case "swamp": return t("습지", "Swamp", "しつげん", "Pantano", "Marécage", "Pântano", "Sumpf", "Болото")
        case "seaoffire": return t("불바다", "Sea of fire", "ひのうみ", "Mar de fuego", "Mer de feu", "Mar de fogo", "Feuermeer", "Море огня")
        default: return BattleTextCatalog.shared.effectName(raw, language: lang)
        }
    }
}

extension L {
    var battleFullDescription: String {
        switch lang {
        case .ko: "기술 설명 전체 보기"
        case .ja: "技の説明をすべて表示"
        case .en: "Show full move description"
        case .de: "Vollständige Attackenbeschreibung"
        case .fr: "Afficher la description complète"
        case .es: "Ver descripción completa"
        case .pt: "Ver descrição completa"
        case .ru: "Полное описание приёма"
        }
    }

    var battleFieldWindow: String {
        switch lang {
        case .ko: "날씨/필드"
        case .ja: "天候・フィールド"
        case .en: "Weather / field"
        case .de: "Wetter / Feld"
        case .fr: "Météo / terrain"
        case .es: "Clima / campo"
        case .pt: "Clima / campo"
        case .ru: "Погода / поле"
        }
    }
    var battleStatsWindow: String {
        switch lang {
        case .ko: "스탯 현황"
        case .ja: "能力変化"
        case .en: "Stat stages"
        case .de: "Statusstufen"
        case .fr: "Niveaux de stats"
        case .es: "Niveles de estadísticas"
        case .pt: "Estágios de atributos"
        case .ru: "Ступени характеристик"
        }
    }
    var battleNoFieldEffects: String {
        switch lang {
        case .ko: "현재 적용 중인 날씨·필드 효과가 없습니다."
        case .ja: "現在、天候・フィールド効果はありません。"
        case .en: "No weather or field effects are active."
        case .de: "Keine Wetter- oder Feldeffekte aktiv."
        case .fr: "Aucun effet de météo ou de terrain actif."
        case .es: "No hay efectos de clima o campo activos."
        case .pt: "Nenhum efeito de clima ou campo ativo."
        case .ru: "Нет активных эффектов погоды или поля."
        }
    }
}

// Development-only Korean comparison harness copy (the move catalog also uses .ko).
extension L {
    var faithfulPreviewPreparing: String { "원본 재생기 준비 중…" }
    var faithfulPreviewPageReady: String { "웹 페이지 준비 완료 · 원본 코드 로드 중…" }
    var faithfulPreviewCodeReady: String { "원본 코드 준비 완료 · GIF 로드 중…" }
    var faithfulPreviewReady: String { "원본 재생기 준비 완료 · 기존 GIF 재생 중" }
    var faithfulPreviewFailed: String { "재생 실패" }
    var faithfulPreviewTitle: String { "피카츄 · 현재 앱 / PokéRogue 비교" }
    var faithfulPreviewSubtitle: String { "현재 전장 배경 고정 · 기술 배경 전환 제외 · 양쪽 모두 기존 GIF 유지 · 같은 기술 프레임으로 비교" }
    var faithfulPreviewMove: String { "기술" }
    var faithfulPreviewSpeed: String { "재생 속도" }
    var faithfulPreviewOriginalSpeed: String { "원본 1×" }
    var faithfulPreviewReplay: String { "다시 재생" }
    var faithfulPreviewResume: String { "계속 재생" }
    var faithfulPreviewPause: String { "효과 일시정지" }
    var faithfulPreviewLoop: String { "반복" }
    var faithfulPreviewSound: String { "효과음" }
    var faithfulPreviewCurrentLabel: String { "현재 앱 · 피카츄 / 현재 이펙트" }
    var faithfulPreviewOriginalLabel: String { "PokéRogue · 피카츄 / 원본 기술 움직임" }
    var faithfulPreviewReverse: String { "상대 피카츄가 사용" }
    func faithfulPreviewFrame(_ frame: Int) -> String { "기술 프레임 \(frame)" }
    var faithfulPreviewIdleLabel: String { "GIF·플로팅 유지 · 기술 움직임 비교" }
    var faithfulPreviewInspectFrames: String { "프레임 확인" }
    var faithfulPreviewPausedGIF: String { "효과 정지 중에도 GIF 재생" }
    func faithfulPreviewDetails(_ status: String) -> String { "\(status)\n오른쪽은 PokéRogue 원본 재생 코드의 독립 실행입니다. 이번 비교는 피카츄 4개 기술에 한정하며, 원본 배경 전환은 요청에 따라 표시하지 않습니다." }
}

extension L {
    var battleCannotAct: String { t("행동할 수 없습니다", "Cannot act", "行動できない", "No puede actuar", "Ne peut pas agir", "Não pode agir", "Kann nicht handeln", "Не может действовать") }
    func battleDamageCause(_ raw: String) -> String {
        switch BattleTextCatalog.key(raw) {
        case "brn", "psn", "tox", "confusion": return battleStatus(raw)
        case "sandstorm", "hail": return battleWeather(raw)
        case "recoil": return t("반동", "Recoil", "反動", "Retroceso", "Recul", "Recuo", "Rückstoß", "Отдача")
        default: return BattleTextCatalog.shared.effectName(raw, language: lang)
        }
    }
}
