import Foundation

extension L {
    var challengeAllHeal:String {t("전체 회복 · 선발 전원 HP·PP 최대, 부활·상태이상 해제","Full recovery · Team HP/PP, revive and cure","全回復・全員のHP・PP、復活と状態回復","Recuperación total · PS/PP, revivir y curar","Récupération complète · PV/PP, rappel et soin","Recuperação total · PS/PP, reviver e curar","Komplettheilung · Team-KP/AP, Wiederbelebung und Heilung","Полное восстановление команды · ОЗ/ОД, оживление и лечение")}
    var challengeHealFull:String {t("선택한 포켓몬 HP 최대 회복 · 기절 시 부활","Restore selected Pokémon's full HP · Revive if fainted","選んだ1匹のHP全回復・ひんしも復活","Recuperar todos los PS de un Pokémon · Revivir","Tous les PV du Pokémon choisi · Rappel si K.O.","Restaurar todos os PS de um Pokémon · Reviver","Gewähltes Pokémon vollständig heilen · Wiederbeleben","Все ОЗ выбранного покемона · Оживить")}
    var challengePPFull:String {t("선택한 포켓몬의 기술 4개 PP 최대 회복","Restore all move PP of one Pokémon","選んだ1匹の全技PPを全回復","Recuperar todos los PP de un Pokémon","Tous les PP du Pokémon choisi","Restaurar todos os PP de um Pokémon","Alle AP eines gewählten Pokémon auffüllen","Все ОД всех приёмов выбранного покемона")}
    func challengeBuffReward(_ kind:ChallengeBuffKind)->String {
        switch kind {
        case .attack:return t("팀 전체 공격 +1","Team Attack +1","全員の攻撃 +1","Equipo: Ataque +1","Équipe : Attaque +1","Equipe: Ataque +1","Team: Angriff +1","Команда: Атака +1")
        case .specialAttack:return t("팀 전체 특수공격 +1","Team Sp. Atk +1","全員の特攻 +1","Equipo: At. Esp. +1","Équipe : Atq. Spé. +1","Equipe: At. Esp. +1","Team: Sp.-Ang. +1","Команда: Сп. атака +1")
        case .speed:return t("팀 전체 스피드 +1","Team Speed +1","全員の素早さ +1","Equipo: Velocidad +1","Équipe : Vitesse +1","Equipe: Velocidade +1","Team: Initiative +1","Команда: Скорость +1")
        case .defense:return t("팀 전체 방어 +1","Team Defense +1","全員の防御 +1","Equipo: Defensa +1","Équipe : Défense +1","Equipe: Defesa +1","Team: Verteidigung +1","Команда: Защита +1")
        case .specialDefense:return t("팀 전체 특수방어 +1","Team Sp. Def +1","全員の特防 +1","Equipo: Def. Esp. +1","Équipe : Déf. Spé. +1","Equipe: Def. Esp. +1","Team: Sp.-Vert. +1","Команда: Сп. защита +1")
        case .power:return t("팀 전체 공격·특공 +1","Team Attack/Sp. Atk +1","全員の攻撃・特攻 +1","Equipo: Ataque/At. Esp. +1","Équipe : Attaque/Atq. Spé. +1","Equipe: Ataque/At. Esp. +1","Team: Angriff/Sp.-Ang. +1","Команда: Атака/Сп. атака +1")
        }
    }
    func challengeBuffRemaining(_ kind:ChallengeBuffKind,_ count:Int)->String {
        let suffix=t("남은 \(count)전","\(count) battles left","残り\(count)戦","\(count) combates restantes","Encore \(count) combats","Restam \(count) batalhas","Noch \(count) Kämpfe","Осталось боёв: \(count)")
        return "\(challengeBuffReward(kind)) · \(suffix)"
    }
    var challengeBuffDuration:String {t("다음 3전 지속 · 중복 적용","Lasts 3 battles · Stacks","次の3戦・重複可","Dura 3 combates · Acumulable","Dure 3 combats · Cumulable","Dura 3 batalhas · Acumulável","Gilt 3 Kämpfe · Stapelbar","На 3 боя · Складывается")}

    var challengeSecondGeneration:String {t("2세대","Gen II","第2世代","2.ª generación","2e génération","2ª geração","2. Generation","2-е поколение")}

    var challengeTestNextTrainer:String {t("다음 트레이너 (테스트)","Next trainer (test)","次のトレーナー（テスト）","Siguiente entrenador (prueba)","Dresseur suivant (test)","Próximo treinador (teste)","Nächster Trainer (Test)","Следующий тренер (тест)")}

    var challengeTestData:String {t("테스트 데이터 · 실제 보유 목록의 사본","Test data · Copy of your collection","テストデータ・所持一覧のコピー","Datos de prueba · Copia de tu colección","Données de test · Copie de la collection","Dados de teste · Cópia da coleção","Testdaten · Kopie deiner Sammlung","Тестовые данные · Копия коллекции")}

    var challengeShinyReward:String {t("챔피언 보상 · 이로치 변경","Champion reward · Shiny conversion","王者報酬・色違いに変更","Recompensa de campeón · Variocolor","Récompense du champion · Chromatique","Recompensa de campeão · Shiny","Champion-Belohnung · Schillernd","Награда чемпиона · Шайни")}
    var challengeShinyHint:String {t("졸업한 포켓몬 한 마리를 선택해 이로치로 변경하세요. 클리어마다 한 번 받을 수 있습니다.","Choose one graduated Pokémon to make Shiny. Claim once per completed challenge.","育成済みの1匹を色違いにできます。クリアごとに1回受け取れます。","Elige un Pokémon graduado para volverlo variocolor. Una vez por desafío completado.","Choisis un Pokémon élevé à rendre chromatique. Une récompense par défi terminé.","Escolha um Pokémon formado para torná-lo Shiny. Uma vez por desafio concluído.","Wähle ein fertig trainiertes Pokémon aus. Einmal pro abgeschlossenem Durchlauf.","Выберите одного выращенного покемона. Одна награда за прохождение.")}
    var challengeShinyApply:String {t("이로치로 변경하고 닫기","Make Shiny and close","色違いにして閉じる","Hacer variocolor y cerrar","Rendre chromatique et fermer","Tornar Shiny e fechar","Schillernd machen und schließen","Сделать шайни и закрыть")}
    var challengeShinyLater:String {t("나중에 받기","Claim later","あとで受け取る","Recibir después","Recevoir plus tard","Receber depois","Später abholen","Получить позже")}
    var challengeShinyEmpty:String {t("변경할 수 있는 졸업 포켓몬이 없습니다. 이미 이로치이거나 놓아준 포켓몬은 선택할 수 없습니다. 보상은 보관됩니다.","No eligible graduates. Shiny or released Pokémon cannot be selected. Your reward is saved.","対象がいません。色違いや逃がした個体は選べません。報酬は保存されます。","No hay candidatos. Los variocolor o liberados no se pueden elegir. La recompensa se conserva.","Aucun candidat. Les Pokémon chromatiques ou relâchés sont exclus. La récompense est conservée.","Nenhum candidato. Shiny ou liberados não podem ser escolhidos. A recompensa fica salva.","Keine passenden Pokémon. Schillernde und freigelassene sind ausgeschlossen. Die Belohnung bleibt gespeichert.","Нет подходящих покемонов. Шайни и отпущенные исключены. Награда сохранится.")}

    var challengeChampion:String {t("챌린지 챔피언","Challenge champion","チャレンジ王者","Campeón del desafío","Champion du défi","Campeão do desafio","Herausforderungs-Champion","Чемпион испытания")}
    var challengeClose:String {t("닫기","Close","閉じる","Cerrar","Fermer","Fechar","Schließen","Закрыть")}

    var challengeTestWin:String {t("즉시 승리 (테스트)","Instant win (test)","即勝利（テスト）","Victoria inmediata (prueba)","Victoire immédiate (test)","Vitória imediata (teste)","Sofortsieg (Test)","Мгновенная победа (тест)")}
    func challengeTrainerAppeared(_ name:String,encounter:String="")->String {
        let scalar=name.components(separatedBy:" (").first?.unicodeScalars.last?.value ?? 0
        let particle=(0xAC00...0xD7A3).contains(scalar) && (scalar-0xAC00)%28 != 0 ? "이":"가"
        switch encounter {
        case "red":
            return t("포켓몬 마스터 \(name)\(particle) 등장했다.","Pokémon Master \(name) appeared!","ポケモンマスターの\(name)が現れた！","¡Ha aparecido el Maestro Pokémon \(name)!","Le Maître Pokémon \(name) apparaît !","O Mestre Pokémon \(name) apareceu!","Pokémon-Meister \(name) erscheint!","Появляется мастер покемонов \(name)!")
        case "blue","lance2":
            return t("챔피언 \(name)\(particle) 등장했다.","Champion \(name) appeared!","チャンピオンの\(name)が現れた！","¡Ha aparecido el Campeón \(name)!","Le Maître \(name) apparaît !","O Campeão \(name) apareceu!","Champ \(name) erscheint!","Появляется чемпион \(name)!")
        case "lorelei","bruno1","agatha","lance1","will","koga2","bruno2","karen":
            return t("사천왕 \(name)\(particle) 등장했다.","Elite Four \(name) appeared!","四天王の\(name)が現れた！","¡Ha aparecido \(name) del Alto Mando!","\(name) du Conseil 4 apparaît !","\(name) da Elite dos Quatro apareceu!","Top-Vier-Mitglied \(name) erscheint!","Появляется \(name) из Элитной четвёрки!")
        default:break
        }
        return t("적 \(name)\(particle) 등장했다.","Enemy \(name) appeared!","敵の\(name)が現れた！","¡Ha aparecido \(name)!","\(name) apparaît !","\(name) apareceu!","Gegner \(name) erscheint!","Появляется противник \(name)!")
    }

    var challengeTitle:String {t("챌린지","Challenge","チャレンジ","Desafío","Défi","Desafio","Herausforderung","Испытание")}
    var challengeEntry:String {t("챌린지 도전","Enter challenge","チャレンジに挑む","Entrar al desafío","Commencer le défi","Entrar no desafio","Herausforderung starten","Начать испытание")}
    var challengeMode:String {t("싱글 · 6마리","Singles · 6 Pokémon","シングル・6匹","Individual · 6 Pokémon","Solo · 6 Pokémon","Individual · 6 Pokémon","Einzel · 6 Pokémon","Одиночный · 6 покемонов")}
    var challengeRules:String {t("6대6 싱글 · 27연전 · HP·PP 유지","6v6 singles · 27 battles · HP and PP carry over","6対6シングル・27連戦・HPとPPを引き継ぐ","Individuales 6 contra 6 · 27 combates · Conserva PS y PP","Solo 6 contre 6 · 27 combats · PV et PP conservés","Individual 6 contra 6 · 27 batalhas · PS e PP mantidos","6-gegen-6-Einzel · 27 Kämpfe · KP und AP bleiben erhalten","6 на 6 · 27 боёв · ОЗ и ОД сохраняются")}
    var challengeResume:String {t("이어하기","Continue","続きから","Continuar","Continuer","Continuar","Fortsetzen","Продолжить")}
    var challengeStart:String {t("시작","Start","開始","Empezar","Commencer","Iniciar","Starten","Начать")}
    var challengeNew:String {t("새 도전","New challenge","新しい挑戦","Nuevo desafío","Nouveau défi","Novo desafio","Neue Herausforderung","Новое испытание")}
    var challengeSaveExit:String {t("세이브 후 종료","Save and exit","セーブして終了","Guardar y salir","Sauvegarder et quitter","Salvar e sair","Speichern und beenden","Сохранить и выйти")}
    var challengeNext:String {t("다음","Next","次へ","Siguiente","Suivant","Próximo","Weiter","Далее")}
    var challengeReward:String {t("승리 보상 · 하나를 선택하세요","Victory reward · Choose one","勝利報酬・1つ選ぶ","Recompensa · Elige una","Récompense · Choisis-en une","Recompensa · Escolha uma","Siegesbelohnung · Eine wählen","Награда · Выберите одну")}
    var challengeHeal:String {t("선택한 포켓몬 HP 35% 회복·부활","Heal or revive one Pokémon by 35% max HP","1匹のHPを最大HPの35%回復・復活","Cura o revive a un Pokémon un 35% de PS máximos","Soigne ou ranime un Pokémon de 35% de ses PV max","Cura ou revive um Pokémon em 35% dos PS máximos","Ein Pokémon um 35% der maximalen KP heilen oder beleben","Восстановить покемону 35% макс. ОЗ или оживить")}
    var challengePP:String {t("선택한 기술 PP 3 회복","Restore 3 PP to one move","選んだ技のPPを3回復","Recupera 3 PP de un movimiento","Restaure 3 PP à une capacité","Restaura 3 PP de um golpe","3 AP einer Attacke auffüllen","Восстановить 3 ОД одного приёма")}
    var challengeReplace:String {t("선발 포켓몬 한 마리 교체","Replace one team member","チームの1匹を入れ替える","Sustituye un miembro del equipo","Remplace un membre de l’équipe","Substitui um membro da equipe","Ein Teammitglied austauschen","Заменить одного члена команды")}
    var challengeReplaceHint:String {t("교체된 개체는 이번 도전에 다시 출전할 수 없습니다. 남은 호환 도구는 이어받습니다.","A replaced individual cannot return this run. Compatible remaining gear transfers.","交代した個体は今回再出場できません。対応する残りの道具を引き継ぎます。","El Pokémon sustituido no puede volver en este desafío. Se transfiere su objeto compatible.","Le Pokémon remplacé ne peut plus revenir. Son objet compatible est transféré.","O Pokémon substituído não pode voltar neste desafio. O item compatível é transferido.","Ausgetauschte Pokémon können nicht zurückkehren. Passende verbleibende Items werden übertragen.","Заменённый покемон не сможет вернуться. Совместимый оставшийся предмет передаётся.")}
    var challengeOutgoing:String {t("교체할 포켓몬","Outgoing Pokémon","交代するポケモン","Pokémon que sale","Pokémon à remplacer","Pokémon que sai","Auszuwechselndes Pokémon","Кого заменить")}
    var challengeIncoming:String {t("새로 출전할 포켓몬","Incoming Pokémon","新しく出場するポケモン","Pokémon que entra","Nouveau Pokémon","Pokémon que entra","Neues Pokémon","Новый покемон")}
    var challengeApplyReward:String {t("보상 적용","Apply reward","報酬を適用","Aplicar recompensa","Appliquer la récompense","Aplicar recompensa","Belohnung anwenden","Получить награду")}
    var challengeRewardDone:String {t("보상이 저장되었습니다.","Reward saved.","報酬を保存しました。","Recompensa guardada.","Récompense sauvegardée.","Recompensa salva.","Belohnung gespeichert.","Награда сохранена.")}
    var challengeSkip:String {t("사용 가능한 보상 없음 · 계속","No available reward · Continue","利用できる報酬なし・続ける","Sin recompensas disponibles · Continuar","Aucune récompense disponible · Continuer","Sem recompensa disponível · Continuar","Keine Belohnung verfügbar · Weiter","Нет доступной награды · Продолжить")}
    var challengeCleared:String {t("챌린지 클리어!","Challenge cleared!","チャレンジクリア！","¡Desafío completado!","Défi terminé !","Desafio concluído!","Herausforderung geschafft!","Испытание пройдено!")}
    var challengeLost:String {t("도전 종료 · 새 도전은 처음부터 시작합니다.","Run ended · A new challenge starts from the beginning.","挑戦終了・次は最初からです。","Fin del intento · El siguiente empieza desde el principio.","Défi terminé · Le prochain repart du début.","Tentativa encerrada · A próxima começa do início.","Versuch beendet · Der nächste beginnt von vorne.","Попытка завершена · Новая начнётся с начала.")}
    var challengeSetupHint:String {t("선택한 순서대로 출전합니다. 첫 포켓몬이 선발입니다.","Your selection order is the team order. The first Pokémon leads.","選んだ順に並び、最初のポケモンが先発です。","El orden de selección es el del equipo. El primero abre el combate.","L’ordre de sélection est celui de l’équipe. Le premier commence.","A ordem de seleção define a equipe. O primeiro inicia a batalha.","Die Auswahl bestimmt die Reihenfolge. Das erste Pokémon beginnt.","Порядок выбора определяет команду. Первый покемон выходит первым.")}
    var challengeProblem:String {t("진행할 수 없습니다. 저장된 데이터는 유지됩니다. 다시 시도해 주세요.","Unable to continue. Saved data is preserved. Please try again.","進められません。保存データは保持されています。再試行してください。","No se puede continuar. Se conservan los datos. Vuelve a intentarlo.","Impossible de continuer. La sauvegarde est conservée. Réessaie.","Não foi possível continuar. Os dados salvos foram preservados. Tente novamente.","Fortsetzen nicht möglich. Gespeicherte Daten bleiben erhalten. Bitte erneut versuchen.","Не удалось продолжить. Сохранение не изменено. Попробуйте снова.")}
    var challengeSaved:String {t("도전이 저장되었습니다. 이어하기로 계속할 수 있습니다.","Challenge saved. Use Continue to resume.","保存しました。「続きから」で再開できます。","Desafío guardado. Usa Continuar para retomarlo.","Défi sauvegardé. Choisis Continuer pour reprendre.","Desafio salvo. Use Continuar para retomar.","Herausforderung gespeichert. Mit Fortsetzen weiterspielen.","Испытание сохранено. Выберите «Продолжить».")}
    func challengeRound(_ n:Int,_ total:Int)->String {t("제 \(n)전 / \(total)","Battle \(n) / \(total)","第\(n)戦 / \(total)","Combate \(n) / \(total)","Combat \(n) / \(total)","Batalha \(n) / \(total)","Kampf \(n) / \(total)","Бой \(n) / \(total)")}
}
