import Foundation

extension L {
    var safariCatchRate: String { t("포획률", "Catch chance", "捕獲率", "Captura", "Capture", "Captura", "Fangchance", "Шанс поимки") }
    var safariFleeRate: String { t("도주율", "Flee chance", "逃走率", "Huida", "Fuite", "Fuga", "Fluchtchance", "Шанс побега") }
    var safariRockHint: String { t("포획 +5%p · 도주 +10%p (누적)", "Catch +5pp · Flee +10pp (stacks)", "捕獲+5pt・逃走+10pt（累積）", "Captura +5pp · Huida +10pp acumulable", "Capture +5pt · Fuite +10pt cumulable", "Captura +5pp · Fuga +10pp cumulativa", "Fang +5pp · Flucht +10pp kumulativ", "Поимка +5п.п. · Побег +10п.п. (суммируется)") }
    var safariBaitHint: String { t("포획 -5%p · 도주 -10%p (누적)", "Catch −5pp · Flee −10pp (stacks)", "捕獲−5pt・逃走−10pt（累積）", "Captura −5pp · Huida −10pp acumulable", "Capture −5pt · Fuite −10pt cumulable", "Captura −5pp · Fuga −10pp cumulativa", "Fang −5pp · Flucht −10pp kumulativ", "Поимка −5п.п. · Побег −10п.п. (суммируется)") }

    var safariTravelChooseMessage: String { t("어느 지역으로 갈까요?", "Where would you like to go?", "どのエリアへ行きますか？", "¿A qué zona quieres ir?", "Où voulez-vous aller ?", "Para qual área quer ir?", "Wohin möchtest du gehen?", "Куда отправимся?") }
    var safariTravelTitle: String { t("지역 이동", "Change area", "エリア移動", "Cambiar de zona", "Changer de zone", "Mudar de área", "Gebiet wechseln", "Сменить зону") }
    var safariTravelButton: String { safariTravelTitle }
    var safariTravelSelect: String { t("선택", "Select", "選択", "Elegir", "Choisir", "Escolher", "Wählen", "Выбрать") }
    var safariTravelFleeNote: String { t("마주친 포켓몬은 도망칩니다.", "The Pokémon you are facing will flee.", "出会っているポケモンは逃げてしまいます。", "El Pokémon que tienes delante huirá.", "Le Pokémon rencontré va s’enfuir.", "O Pokémon que você encontrou vai fugir.", "Das Pokémon vor dir wird fliehen.", "Встреченный покемон убежит.") }
    func safariTravelMessage(_ area: SafariArea) -> String {
        let name = safariArea(area)
        return t("다음 지역은 \(name) 입니다.", "The next area is \(name).", "次のエリアは\(name)です。", "La siguiente zona es \(name).", "La prochaine zone est \(name).", "A próxima área é \(name).", "Das nächste Gebiet ist \(name).", "Следующая зона: \(name).")
    }


    var safariThrowingBall: String { t("사파리볼을 던졌다!", "Threw a Safari Ball!", "サファリボールを投げた！", "¡Lanzaste una Safari Ball!", "Une Safari Ball a été lancée !", "Lançou uma Safari Ball!", "Ein Safariball wurde geworfen!", "Брошен Сафари-бол!") }

    var safariRepresentative: String { t("대표 출현 포켓몬", "Featured Pokémon", "代表ポケモン", "Pokémon destacado", "Pokémon vedette", "Pokémon em destaque", "Gebiets-Pokémon", "Покемон зоны") }

    var safariTitle: String { t("사파리존", "Safari Zone", "サファリゾーン", "Zona Safari", "Parc Safari", "Zona Safari", "Safari-Zone", "Зона Сафари") }
    var safariTicketLabel: String { t("입장권", "Ticket", "入場券", "Entrada", "Ticket", "Ingresso", "Eintrittskarte", "Билет") }
    var safariTicketDescription: String { t("250M 고정 가격. 사파리볼 20개로 탐험하고 포켓몬 한 마리를 데려와요.", "Fixed price: 250M. Explore with 20 Safari Balls and bring home one Pokémon.", "250M固定。サファリボール20個で探索し、1匹を連れて帰ります。", "Precio fijo: 250M. Explora con 20 Safari Balls y llévate un Pokémon.", "Prix fixe : 250M. Explorez avec 20 Safari Balls et repartez avec un Pokémon.", "Preço fixo: 250M. Explore com 20 Safari Balls e leve um Pokémon.", "Festpreis: 250M. Erkunde mit 20 Safaribällen und nimm ein Pokémon mit.", "Цена: 250M. Исследуйте с 20 Сафари-болами и заберите одного покемона.") }
    var safariResume: String { t("사파리존 이어하기", "Resume Safari", "サファリを続ける", "Continuar Safari", "Reprendre le Safari", "Continuar Safari", "Safari fortsetzen", "Продолжить Сафари") }
    var safariChooseArea: String { t("입장할 장소를 선택해 주세요.", "Choose your starting area.", "最初の場所を選んでください。", "Elige la zona inicial.", "Choisissez la zone de départ.", "Escolha a área inicial.", "Wähle dein Startgebiet.", "Выберите начальную зону.") }
    var safariEnter: String { t("입장하기", "Enter", "入場する", "Entrar", "Entrer", "Entrar", "Betreten", "Войти") }
    var safariExitQuestion: String { t("탐험을 종료하고 보관 중인 포켓몬과 나갈까요?", "End the Safari and leave with your kept Pokémon?", "探索を終了して、保管中のポケモンと帰りますか？", "¿Terminar y salir con el Pokémon guardado?", "Terminer et repartir avec le Pokémon conservé ?", "Encerrar e sair com o Pokémon guardado?", "Safari beenden und mit deinem behaltenen Pokémon gehen?", "Завершить Сафари и уйти с сохранённым покемоном?") }
    var safariBall: String { t("사파리볼 던지기", "Throw Safari Ball", "サファリボール", "Lanzar Safari Ball", "Lancer Safari Ball", "Lançar Safari Ball", "Safariball werfen", "Бросить Сафари-бол") }
    var safariRock: String { t("돌 던지기", "Throw rock", "いしをなげる", "Lanzar piedra", "Lancer une pierre", "Jogar pedra", "Stein werfen", "Бросить камень") }
    var safariBait: String { t("먹이 주기", "Give bait", "エサをなげる", "Dar cebo", "Donner un appât", "Dar isca", "Köder geben", "Дать приманку") }
    var safariRun: String { t("도망 가기", "Run away", "にげる", "Huir", "Fuir", "Fugir", "Fliehen", "Убежать") }
    var safariKeep: String { t("기존 포켓몬 유지", "Keep previous Pokémon", "元のポケモンを残す", "Conservar anterior", "Garder le précédent", "Manter anterior", "Bisheriges behalten", "Оставить прежнего") }
    var safariReplace: String { t("새 포켓몬으로 교체", "Keep new Pokémon", "新しいポケモンに交代", "Conservar nuevo", "Garder le nouveau", "Manter novo", "Neues behalten", "Оставить нового") }
    var safariCarried: String { t("데려갈 포켓몬", "Kept Pokémon", "連れて帰るポケモン", "Pokémon guardado", "Pokémon conservé", "Pokémon guardado", "Behaltenes Pokémon", "Сохранённый покемон") }
    var safariNone: String { t("없음", "None", "なし", "Ninguno", "Aucun", "Nenhum", "Keines", "Нет") }
    var safariNext: String { t("계속 탐험", "Continue exploring", "探索を続ける", "Seguir explorando", "Continuer à explorer", "Continuar explorando", "Weiter erkunden", "Продолжить исследование") }
    var safariFinish: String { t("탐험이 종료되었습니다.", "Your Safari has ended.", "探索が終了しました。", "Safari terminado.", "Le Safari est terminé.", "Safari encerrado.", "Deine Safari ist beendet.", "Сафари завершено.") }
    var safariSaveHint: String { t("진행상황은 자동 저장됩니다. 앱을 다시 실행하면 가방에서 이어갈 수 있어요.", "Progress saves automatically. Resume from the Bag after restarting the app.", "自動保存されます。アプリ再起動後もバッグから再開できます。", "Se guarda automáticamente. Continúa desde la Bolsa.", "Sauvegarde automatique. Reprenez depuis le Sac.", "Salvo automaticamente. Continue pela Bolsa.", "Automatisch gespeichert. Über den Beutel fortsetzen.", "Прогресс сохраняется. Продолжите из Сумки.") }
    var safariBalls: String { t("남은 볼", "Balls left", "残りのボール", "Bolas restantes", "Balls restantes", "Bolas restantes", "Übrige Bälle", "Осталось болов") }
    var safariEncounters: String { t("조우", "Encounters", "遭遇", "Encuentros", "Rencontres", "Encontros", "Begegnungen", "Встречи") }
    var safariTurns: String { t("턴", "Turn", "ターン", "Turno", "Tour", "Turno", "Runde", "Ход") }
    func safariArea(_ area: SafariArea) -> String {
        switch area {
        case .plains: return t("초원", "Plains", "草原", "Pradera", "Plaine", "Planície", "Ebene", "Равнина")
        case .forest: return t("울창한 숲", "Dense forest", "深い森", "Bosque frondoso", "Forêt dense", "Floresta densa", "Dichter Wald", "Густой лес")
        case .lake: return t("호수", "Lake", "湖", "Lago", "Lac", "Lago", "See", "Озеро")
        case .mountain: return t("산악지대", "Mountains", "山岳地帯", "Montañas", "Montagnes", "Montanhas", "Gebirge", "Горы")
        case .desert: return t("사막", "Desert", "砂漠", "Desierto", "Désert", "Deserto", "Wüste", "Пустыня")
        case .volcano: return t("화산지대", "Volcano", "火山", "Volcán", "Volcan", "Vulcão", "Vulkan", "Вулкан")
        case .metropolis: return t("도시 외곽", "City outskirts", "街の郊外", "Afueras", "Périphérie", "Arredores", "Stadtrand", "Окраина")
        case .dojo: return t("수련터", "Dojo", "道場", "Dojo", "Dojo", "Dojo", "Dojo", "Додзё")
        case .cave: return t("어두운 동굴", "Dark cave", "暗い洞窟", "Cueva oscura", "Grotte sombre", "Caverna escura", "Dunkle Höhle", "Тёмная пещера")
        case .fairyCave: return t("신비한 동굴", "Mystic cave", "神秘の洞窟", "Cueva mística", "Grotte mystique", "Caverna mística", "Mystische Höhle", "Таинственная пещера")
        case .iceCave: return t("얼음 동굴", "Ice cave", "氷の洞窟", "Cueva helada", "Grotte de glace", "Caverna de gelo", "Eishöhle", "Ледяная пещера")
        }
    }
    func safariNotice(_ notice: SafariNotice) -> String {
        switch notice {
        case .appeared: return t("야생 포켓몬이 나타났다!", "A wild Pokémon appeared!", "野生のポケモンが現れた！", "¡Apareció un Pokémon salvaje!", "Un Pokémon sauvage apparaît !", "Um Pokémon selvagem apareceu!", "Ein wildes Pokémon erscheint!", "Появился дикий покемон!")
        case .missed: return t("아쉽다! 볼에서 빠져나왔다.", "Oh no! It broke free.", "残念！ボールから出てしまった。", "¡Se escapó de la bola!", "Il est sorti de la Ball !", "Escapou da bola!", "Es ist ausgebrochen!", "Он вырвался из бола.")
        case .caught: return t("포획에 성공했다!", "Caught it!", "捕まえた！", "¡Capturado!", "Capture réussie !", "Capturado!", "Gefangen!", "Пойман!")
        case .fled: return t("야생 포켓몬이 도망쳤다.", "The wild Pokémon fled.", "野生のポケモンは逃げ出した。", "El Pokémon salvaje huyó.", "Le Pokémon sauvage a fui.", "O Pokémon selvagem fugiu.", "Das wilde Pokémon ist geflohen.", "Дикий покемон убежал.")
        case .waited: return t("야생 포켓몬이 기다리고 있다.", "The wild Pokémon is watching.", "野生のポケモンは様子を見ている。", "El Pokémon salvaje observa.", "Le Pokémon sauvage observe.", "O Pokémon selvagem está observando.", "Das wilde Pokémon wartet ab.", "Дикий покемон наблюдает.")
        case .ran: return t("다른 포켓몬을 찾아보자.", "Let’s look for another Pokémon.", "別のポケモンを探そう。", "Busquemos otro Pokémon.", "Cherchons un autre Pokémon.", "Vamos procurar outro Pokémon.", "Suchen wir ein anderes Pokémon.", "Поищем другого покемона.")
        case .rock: return t("돌을 던졌다!", "Threw a rock!", "石を投げた！", "¡Lanzaste una piedra!", "Une pierre a été lancée !", "Jogou uma pedra!", "Ein Stein wurde geworfen!", "Брошен камень!")
        case .bait: return t("먹이를 주었다!", "Gave some bait!", "エサを投げた！", "¡Diste cebo!", "Un appât a été donné !", "Deu uma isca!", "Ein Köder wurde gegeben!", "Дана приманка!")
        case .ended: return t("탐험이 종료되었습니다.", "Your Safari has ended.", "探索が終了しました。", "Safari terminado.", "Le Safari est terminé.", "Safari encerrado.", "Deine Safari ist beendet.", "Сафари завершено.")
        case .replaced: return t("새로 잡은 포켓몬을 데려간다.", "You kept the new Pokémon.", "新しいポケモンを連れて帰る。", "Conservaste el nuevo Pokémon.", "Vous gardez le nouveau Pokémon.", "Você manteve o novo Pokémon.", "Du behältst das neue Pokémon.", "Вы оставили нового покемона.")
        case .kept: return t("기존 포켓몬을 계속 데려간다.", "You kept the previous Pokémon.", "元のポケモンを連れて帰る。", "Conservaste el Pokémon anterior.", "Vous gardez le précédent Pokémon.", "Você manteve o Pokémon anterior.", "Du behältst das bisherige Pokémon.", "Вы оставили прежнего покемона.")
        }
    }
    func safariReplacement(old: String, new: String) -> String {
        t("\(old) 대신 \(new)을 데리고 갈까요?", "Take \(new) instead of \(old)?", "\(old)の代わりに\(new)を連れて帰りますか？", "¿Llevar a \(new) en lugar de \(old)?", "Garder \(new) à la place de \(old) ?", "Levar \(new) no lugar de \(old)?", "\(new) statt \(old) mitnehmen?", "Взять \(new) вместо \(old)?")
    }
}
