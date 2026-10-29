import AppKit
import SwiftUI
@testable import PokeTokenBar

private final class PreviewLink: BattleLink, @unchecked Sendable {
    var onPeerFound: (@Sendable (TradePeer) -> Void)?
    var onPeerLost: (@Sendable (String) -> Void)?
    var onConnected: (@Sendable () -> Void)?
    var onDisconnected: (@Sendable () -> Void)?
    var onDataReceived: (@Sendable (Data) -> Void)?
    weak var other: PreviewLink?
    var candidates: [TradePeer] = []
    var discoveryGroup: String?
    var routes: [String: PreviewLink] = [:]
    func startDiscovery() { candidates.filter{$0.discoveryGroup == discoveryGroup}.forEach { onPeerFound?($0) } }
    func stopDiscovery() {}
    func connect(to peer: TradePeer) throws {
        guard peer.discoveryGroup == discoveryGroup else { throw TradeTransportError.notConnected }
        if let route = routes[peer.id] { other = route; route.other = self }
        onConnected?();other?.onConnected?()
    }
    func sendData(_ data: Data) throws {
        let callback=other?.onDataReceived
        DispatchQueue.main.async { callback?(data) }
    }
    func disconnect() {}
}
private struct LoadoutPreviewDetails: PokemonDetailProviding {
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        if speciesID==6 {
            return PokemonDetails(speciesID:6,name:"charizard",height:17,weight:905,baseExperience:240,
                genderRate:1,types:["fire","flying"],
                baseStats:["hp":78,"attack":84,"defense":78,"special-attack":109,"special-defense":85,"speed":100],
                abilities:[.init(name:"blaze",slot:1,isHidden:false),.init(name:"solar-power",slot:3,isHidden:true)],
                moves:["flamethrower","air-slash","dragon-claw","protect","fly","fire-blast"].map {
                    .init(name:$0,learnMethods:[.init(method:"machine",level:0)])
                })
        }
        return PokemonDetails(speciesID: 79, name: "slowpoke", height: 12, weight: 360, baseExperience: 63,
            genderRate: 4, types: ["water", "psychic"],
            baseStats: ["hp":90,"attack":65,"defense":65,"special-attack":40,"special-defense":40,"speed":15],
            abilities: [.init(name:"oblivious",slot:1,isHidden:false),.init(name:"own-tempo",slot:2,isHidden:false),.init(name:"regenerator",slot:3,isHidden:true)],
            moves: ["tackle","growl","water-gun","confusion","psychic","surf","ice-beam"].map {
                PokemonMoveOption(name:$0,learnMethods:[.init(method:["surf","ice-beam"].contains($0) ? "machine" : "level-up",level:["surf","ice-beam"].contains($0) ? 0 : 1)])
            })
    }
}

@MainActor
private final class PreviewDelegate: NSObject, NSApplicationDelegate {
    var battle: BattleCoordinator?
    var enemy: BattleCoordinator?
    var controller: BattleWindowController?
    var comparisonWindow: NSWindow?
    var sizeWindows:[NSWindow]=[]
    let left=PreviewLink(),right=PreviewLink()
    var matchingPeers: [BattleCoordinator] = []
    var matchingLinks: [PreviewLink] = []
    var suiteNames: [String] = []
    var directory: URL!
    var preparingResult = false
    var duelTeams: [String: [BattlePokemon]] = [:]
    let duelDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/codex-duel")
    func defaults(_ code: String) -> UserDefaults {
        let name="BattlePreview.\(UUID())";suiteNames.append(name)
        let defaults=UserDefaults(suiteName:name)!
        defaults.set(code,forKey:"tradeCode");defaults.set((CommandLine.arguments.contains("--versus-codex") || CommandLine.arguments.contains("--matching-duel")) ? (code == "AAAA" ? "플레이어" : "Codex") : code,forKey:"tradeNickname")
        return defaults
    }
    func team(_ prefix: String) -> [BattlePokemon] {
        if CommandLine.arguments.contains("--fairy-preview") {
            let members: [(Int,String,String,[String])] = prefix == "a" ? [
                (282,"Gardevoir","Synchronize",["moonblast","dazzling-gleam","draining-kiss","misty-terrain"]),
                (303,"Mawile","Hyper Cutter",["play-rough","fairy-wind","baby-doll-eyes","iron-head"]),
                (547,"Whimsicott","Prankster",["moonblast","fairy-wind","dazzling-gleam","misty-terrain"]),
                (579,"Reuniclus","Magic Guard",["light-of-ruin","psychic","recover","protect"]),
                (26,"Raichu","Static",["thunderbolt"]),(9,"Blastoise","Torrent",["surf"])
            ] : [
                (235,"Smeargle","Own Tempo",["splash"]),(143,"Snorlax","Immunity",["splash"]),
                (242,"Blissey","Natural Cure",["splash"]),(151,"Mew","Synchronize",["splash"]),
                (9,"Blastoise","Torrent",["splash"]),(6,"Charizard","Blaze",["splash"])
            ]
            return members.enumerated().map { i,m in
                BattlePokemon(id:prefix+String(i),speciesID:m.0,species:m.1,displayName:"",level:100,
                    ability:m.2,nature:"hardy",gender:"F",shiny:false,form:nil,
                    ivs:["hp":31,"atk":31,"def":31,"spa":31,"spd":31,"spe":31],
                    stats:["hp":900,"atk":100,"def":300,"spa":100,"spd":300,"spe":100],moves:m.3)
            }
        }
        if CommandLine.arguments.contains("--mega-design-preview") {
            let members:[(Int,String,String,String)]=[
                prefix=="a" ? (6,"Charizard","Blaze","charizarditex"):(248,"Tyranitar","Sand Stream","tyranitarite"),
                (26,"Raichu","Static",""),(9,"Blastoise","Torrent",""),(3,"Venusaur","Overgrow",""),(94,"Gengar","Levitate",""),(143,"Snorlax","Immunity","")]
            return members.enumerated().map { i,m in
                BattlePokemon(id:prefix+String(i),speciesID:m.0,species:m.1,displayName:m.1,level:50,ability:m.2,nature:"hardy",gender:"M",shiny:false,form:nil,
                    ivs:["hp":17,"atk":17,"def":17,"spa":17,"spd":17,"spe":17],stats:["hp":500,"atk":100,"def":150,"spa":100,"spd":150,"spe":100],
                    moves:["protect","flamethrower","thunderbolt","dragonclaw"],item:m.3.isEmpty ? nil:m.3)
            }
        }
        if let random = duelTeams[prefix] { return random }
        if CommandLine.arguments.contains("--roster-preview") || CommandLine.arguments.contains("--item-preview") {
            let members:[(Int,String,String)]=prefix=="a" ? [(6,"Charizard","Blaze"),(26,"Raichu","Static"),(9,"Blastoise","Torrent"),(3,"Venusaur","Overgrow"),(94,"Gengar","Levitate"),(143,"Snorlax","Immunity")]:[(130,"Gyarados","Intimidate"),(260,"Swampert","Torrent"),(149,"Dragonite","Inner Focus"),(376,"Metagross","Clear Body"),(212,"Scizor","Technician"),(59,"Arcanine","Intimidate")]
            return members.enumerated().map { i,member in
                BattlePokemon(id:prefix+String(i),speciesID:member.0,species:member.1,displayName:member.1,level:50,
                    ability:member.2,nature:"hardy",gender:"M",shiny:false,form:nil,
                    ivs:["hp":17,"atk":17,"def":17,"spa":17,"spd":17,"spe":17],
                    stats:["hp":143,"atk":91,"def":87,"spa":96,"spd":89,"spe":107],moves:["tackle"])
            }
        }
        let rogue=CommandLine.arguments.contains("--rogue-battle")
        let moves=[["psychic","surf","double-team","rest"],["thunderbolt","protect","volt-switch","flamethrower"],["secret-power","nature-power","sunny-day","power-split"],["ice-beam","reflect","swift","recover"]]
        if prefix == "a", CommandLine.arguments.contains("--field-effects-pilot") {
            return [235,181,310,101,587,618].enumerated().map { i,id in
                BattlePokemon(id:prefix+String(i),speciesID:id,species:["Smeargle","Ampharos","Manectric","Electrode","Emolga","Stunfisk"][i],displayName:"",level:100,
                    ability:i==0 ? "Own Tempo":"Static",nature:"hardy",gender:"M",shiny:false,form:nil,
                    ivs:["hp":17,"atk":17,"def":17,"spa":17,"spd":17,"spe":17],stats:["hp":143,"atk":91,"def":87,"spa":96,"spd":89,"spe":107],
                    moves:i==0 ? ["rain-dance","trick-room","gravity","sunny-day"]:moves[i % moves.count])
            }
        }
        if CommandLine.arguments.contains("--fields") {
            let ids = prefix == "a" ? [235,272,59,80,134,212] : [186,143,26,59,134,212]
            let names = prefix == "a" ? ["Smeargle","Ludicolo","Arcanine","Slowbro","Vaporeon","Scizor"] : ["Politoed","Snorlax","Raichu","Arcanine","Vaporeon","Scizor"]
            let abilities = prefix == "a" ? ["Own Tempo","Swift Swim","Intimidate","Regenerator","Water Absorb","Technician"] : ["Drizzle","Immunity","Static","Intimidate","Water Absorb","Technician"]
            return (0..<6).map { i in
                BattlePokemon(id:prefix+String(i),speciesID:ids[i],species:names[i],displayName:names[i],level:50,
                    ability:abilities[i],nature:"hardy",gender:"M",shiny:false,form:nil,
                    ivs:["hp":17,"atk":17,"def":17,"spa":17,"spd":17,"spe":17],
                    stats:["hp":143,"atk":91,"def":87,"spa":96,"spd":89,"spe":107],
                    moves:prefix == "a" && i == 0 ? ["gravity","reflect","trick-room","tailwind"] : ["amnesia"])
            }
        }
        if CommandLine.arguments.contains("--abilities") {
            return (0..<6).map { i in
                BattlePokemon(id:prefix+String(i),speciesID:[130,26,181,143,587,618][i],species:["Gyarados","Raichu","Ampharos","Snorlax","Emolga","Stunfisk"][i],displayName:"",level:100,
                    ability:i == 0 ? (prefix == "a" ? "Moxie" : "Intimidate") : i == 3 ? "Immunity" : "Static",nature:"hardy",gender:"M",shiny:false,form:nil,
                    ivs:["hp":17,"atk":17,"def":17,"spa":17,"spd":17,"spe":17],stats:["hp":143,"atk":91,"def":87,"spa":96,"spd":89,"spe":107],
                    moves: prefix == "b" ? ["splash","tackle"] : i == 0 ? ["waterfall","ice-beam","dragon-dance","rest"] : moves[i % moves.count])
            }
        }
        return (0..<6).map { i in BattlePokemon(id:prefix+String(i),speciesID:[26,181,310,101,587,618][i],species:["Raichu","Ampharos","Manectric","Electrode","Emolga","Stunfisk"][i],displayName:"Pikachu",
            level:100,ability:"static",nature:"hardy",gender:"M",shiny:false,form:nil,
            ivs:["hp":17,"atk":17,"def":17,"spa":17,"spd":17,"spe":17],
            stats:["hp":143,"atk":91,"def":87,"spa":96,"spd":89,"spe":107],
            moves:rogue ? (prefix == "b" ? ["splash","tackle"] : moves[i % moves.count]) : (ProcessInfo.processInfo.environment["PTB_SHOWMOTION_PREVIEW"] == "1" || CommandLine.arguments.contains("--showmotion")) ?
                (prefix == "b" ? ["splash","growl"] : (i == 0 ? ["hydro-pump","swords-dance","shadow-ball","psychic"] : ["gunk-shot","will-o-wisp","protect","quick-attack"])) :
                ["thunderbolt","protect","quick-attack","volt-switch"]) }
    }
    func wait(_ condition: () -> Bool) async throws {
        let end=Date().addingTimeInterval(15)
        while !condition() && Date() < end { try await Task.sleep(for:.milliseconds(20)) }
        guard condition() else { throw NSError(domain:"BattlePreview",code:1) }
    }
    func showMatchingPreview() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-matching-preview-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let interactive=CommandLine.arguments.contains("--matching-duel")
        let a = BattleCoordinator(defaults: defaults("AAAA"), history: BattleHistoryStore(url: directory.appendingPathComponent("a.json")), decisionTimeLimit:1800, linkFactory: { _,mode in self.left.discoveryGroup=mode.rawValue;return self.left })
        battle = a
        let opponents:[String] = interactive ? ["Codex"] : ["지우", "이슬", "웅"]
        for (index, nickname) in opponents.enumerated() {
            let code = ["BBBB", "CCCC", "DDDD"][index]
            let link = PreviewLink()
            let preferences = defaults(code); preferences.set(nickname, forKey: "tradeNickname")
            let coordinator = BattleCoordinator(defaults: preferences, history: BattleHistoryStore(url: directory.appendingPathComponent("\(code).json")), decisionTimeLimit:1800, linkFactory: { _,mode in link.discoveryGroup=mode.rawValue;return link })
            matchingLinks.append(link); matchingPeers.append(coordinator)
            let mode:BattleMode=index == 2 ? .doubles:.singles
            coordinator.setMode(mode)
            left.candidates.append(TradePeer(id: code, nickname: nickname, code: code, discoveryGroup:mode.rawValue)); left.routes[code] = link
            coordinator.search()
        }
        var state = CompanionState(); state.language = .ko
        state.dex = (interactive ? [26,6,9,3,94,143]:[26,181,310,128,587,618]).map { id in
            var profile = PokemonProfile.generate(seed: UInt64(id)); profile.level = interactive ? 50:100
            if interactive {
                let moves:[Int:[String]]=[26:["thunderbolt","quick-attack","protect","volt-switch"],6:["flamethrower","air-slash","dragon-claw","roost"],9:["surf","ice-beam","protect","aqua-tail"],3:["energy-ball","sludge-bomb","sleep-powder","synthesis"],94:["shadow-ball","psychic","thunderbolt","hypnosis"],143:["body-slam","crunch","rest","earthquake"]]
                profile.moves=(moves[id] ?? ["tackle"]).map{.init(name:$0,learnedAtLevel:1)}
            }
            return DexEntry(id: "preview-\(id)", baseID: id, finalID: id, chainOrder: [id], rarity: .common, caughtAt: Date(), profile: profile)
        }
        if interactive,CommandLine.arguments.contains("--use-owned-roster") {
            let original=try JSONDecoder().decode(CompanionState.self,from:Data(contentsOf:CompanionStore.defaultURL()))
            state.dex=original.dex;state.language=original.language
            if CommandLine.arguments.contains("--no-items") {
                for index in state.dex.indices {state.dex[index].battleDefaultItem=nil}
                UserDefaults.standard.removeObject(forKey:"battlePokemonHeldItems.v1")
            }
            let originalPreferences=UserDefaults(suiteName:"io.github.chattymin.poketokenbar")!
            for key in ["battlePokemonHeldItems.v1","battleHeldItemUsage.v1"] {
                if key == "battlePokemonHeldItems.v1",CommandLine.arguments.contains("--no-items") {continue}
                if let value=originalPreferences.object(forKey:key) {UserDefaults.standard.set(value,forKey:key)}
            }
            print("Loaded owned collection into isolated duel copy: \(state.dex.filter{!$0.isReleased}.count) graduates")
        }
        let file = directory.appendingPathComponent("lobby.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(fileURL: file, defaults: defaults("lobby"))
        if CommandLine.arguments.contains("--check-registration") {
            Task { @MainActor in
                do {
                    let registered=try await BattleTeamBuilder.build(ids:state.dex.map(\.id),entries:state.dex,mode:.singles,language:.ko)
                    print("Registration check passed: \(registered.count)")
                }catch { print("Registration check failed: \(error)") }
                NSApp.terminate(nil)
            }
        }
        let window = NSWindow(contentRect: NSRect(x:0,y:0,width:480,height:470), styleMask:[.titled,.closable,.miniaturizable], backing:.buffered, defer:false)
        window.title = interactive ? "PokeTokenBar · 플레이어 vs Codex · 매칭부터 배틀" : "PokeTokenBar · 매칭 요청 화면 테스트 · 샘플 상대"
        if CommandLine.arguments.contains("--use-owned-roster") {window.title="PokeTokenBar · 실제 컬렉션 vs Codex · 싱글배틀"}
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: BattleLobbyView(store: store, battle: a).frame(width:480,height:470))
        comparisonWindow = window
        if interactive {
            let data=try Data(contentsOf:duelDirectory.appendingPathComponent("teams.json"))
            duelTeams=try JSONDecoder().decode([String:[BattlePokemon]].self,from:data)
            let battleWindow=BattleWindowController(battle:a,store:store,audioDefaults:UserDefaults(suiteName:"dev.poketokenbar.battlepreview.audio")!)
            controller=battleWindow
            Task { @MainActor in
                while window.isVisible {
                    if let peer=self.matchingPeers.first(where:{$0.opponent != nil}) {
                        self.enemy=peer
                        if peer.phase == .connected {
                            if peer.registeredTeam.isEmpty { peer.register(team:self.team("b")) }
                            if peer.canSelectLineup,!peer.localReady {
                                if CommandLine.arguments.contains("--manual-codex") {
                                    let command=duelDirectory.appendingPathComponent("lineup.json")
                                    if let data=try? Data(contentsOf:command),let ids=try? JSONDecoder().decode([String].self,from:data),
                                       ids.count==peer.mode.battleSize,Set(ids).count==ids.count,
                                       ids.allSatisfy({id in peer.registeredTeam.contains{$0.id==id}}) {
                                        let ordered=ids.compactMap{id in peer.registeredTeam.first{$0.id==id}}+peer.registeredTeam.filter{!ids.contains($0.id)}
                                        try? FileManager.default.removeItem(at:command)
                                        peer.ready(team:ordered)
                                    }
                                } else {peer.ready(team:peer.registeredTeam)}
                            }
                        }
                        if peer.phase == .playing,!peer.submitted,let frame=peer.frame,!frame.waiting,!frame.ended {
                            if frame.preview {
                                peer.choose(BattleDecision(decisionID:frame.decisionID,actions:[],order:Array(1...peer.mode.battleSize)))
                            }else if CommandLine.arguments.contains("--manual-codex") {
                                let command=duelDirectory.appendingPathComponent("command.json")
                                if let data=try? Data(contentsOf:command) {
                                    try? FileManager.default.removeItem(at:command)
                                    if let decision=try? JSONDecoder().decode(BattleDecision.self,from:data),decision.decisionID==frame.decisionID {
                                        peer.choose(decision)
                                    }
                                }
                            }else{
                                var used=Set<Int>()
                                let actions:[BattleAction]=frame.slots.compactMap { slot in
                                    if slot.canPass{return .pass}
                                    if slot.mustSwitch {
                                        guard let i=frame.own.indices.first(where:{!frame.own[$0].active && !frame.own[$0].fainted && !used.contains($0)}) else{return nil}
                                        used.insert(i);return BattleAction(kind:"switch",index:i+1,target:0)
                                    }
                                    let moves=slot.moves.filter{!$0.disabled && $0.pp>0}
                                    guard !moves.isEmpty else{return nil}
                                    let move=moves[(max(0,frame.turn-1)+slot.slot)%moves.count]
                                    return BattleAction(kind:"move",index:move.index,target:move.targetRequired ? (move.targets.first?.location ?? 0):0,mega:CommandLine.arguments.contains("--mega-test") && slot.slot==0 && slot.canMegaEvo==true ? true:nil)
                                }
                                if actions.count==frame.slots.count{peer.choose(BattleDecision(decisionID:frame.decisionID,actions:actions,order:[]))}
                            }
                        }
                    }
                    if CommandLine.arguments.contains("--manual-codex"),let peer=self.enemy {
                        var snapshot:[String:Any]=["phase":String(describing:peer.phase),"submitted":peer.submitted,"localReady":peer.localReady,"canSelectLineup":peer.canSelectLineup,"outcome":peer.outcome ?? "","error":peer.error ?? ""]
                        if let frame=peer.frame {snapshot["frame"]=try? JSONSerialization.jsonObject(with:JSONEncoder().encode(frame))}
                        snapshot["opponentRoster"]=try? JSONSerialization.jsonObject(with:JSONEncoder().encode(peer.opponentRoster))
                        snapshot["team"]=try? JSONSerialization.jsonObject(with:JSONEncoder().encode(peer.registeredTeam))
                        if let data=try? JSONSerialization.data(withJSONObject:snapshot) {try? data.write(to:duelDirectory.appendingPathComponent("state.json"),options:.atomic)}
                    }
                    try? await Task.sleep(for:.milliseconds(100))
                }
            }
        }
        a.search()
        if let index=CommandLine.arguments.firstIndex(of:"--resume-registration"),CommandLine.arguments.indices.contains(index+1) {
            let species=CommandLine.arguments[index+1].split(separator:",").compactMap{Int($0)}
            Task { @MainActor in
                do {
                    a.select(left.candidates[0]);try await wait{a.opponent != nil}
                    let ids=species.compactMap{id in store.state.dex.first{$0.finalID==id}?.id}
                    let restored=try await BattleTeamBuilder.build(ids:ids,entries:store.state.dex,mode:a.mode,language:store.language)
                    a.register(team:restored)
                }catch{print("Restored registration failed: \(error)")}
            }
        }
        if CommandLine.arguments.contains("--public-preview") {
            Task { @MainActor in
                do {
                    a.select(left.candidates[0]); try await wait { a.opponent != nil && matchingPeers.contains { $0.phase == .connected && $0.opponent != nil } }
                    let peer = matchingPeers.first { $0.phase == .connected && $0.opponent != nil }!
                    a.register(team: team("a")); peer.register(team: team("b"))
                } catch { print("Roster preview: \(error)") }
            }
        }
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func showResultPreview(win: Bool) {
        guard !preparingResult else { return }
        preparingResult = true
        Task { @MainActor in
            defer { preparingResult = false }
            do {
                controller?.window?.performClose(nil)
                battle?.shutdown();enemy?.shutdown()
                let folder=directory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let ownLink=PreviewLink(),foeLink=PreviewLink()
                ownLink.other=foeLink;foeLink.other=ownLink
                let a=BattleCoordinator(defaults:defaults("AAAA"),history:BattleHistoryStore(url:folder.appendingPathComponent("a.json")),decisionTimeLimit:1800,linkFactory:{_,mode in ownLink.discoveryGroup=mode.rawValue;return ownLink})
                let b=BattleCoordinator(defaults:defaults("BBBB"),history:BattleHistoryStore(url:folder.appendingPathComponent("b.json")),decisionTimeLimit:1800,linkFactory:{_,mode in foeLink.discoveryGroup=mode.rawValue;return foeLink})
                battle=a;enemy=b
                a.search();b.search();a.select(TradePeer(id:"BBBB",nickname:"상대",code:"BBBB",discoveryGroup:a.mode.rawValue))
                try await wait { a.opponent != nil && b.opponent != nil }
                a.register(team:team("a"));b.register(team:team("b"))
                try await wait { a.canSelectLineup && b.canSelectLineup }
                a.ready(team:team("a"));try await wait { b.remoteReady };b.ready(team:team("b"))
                try await wait { a.frame != nil && b.frame != nil }
                for side in [a,b] where side.frame?.preview == true {
                    side.choose(BattleDecision(decisionID:side.frame!.decisionID,actions:[],order:Array(1...side.mode.teamSize)))
                }
                try await wait { a.frame?.preview == false && b.frame?.preview == false }
                a.completePresentation();b.completePresentation()
                if win { b.surrender() } else { a.surrender() }
                try await wait { a.outcome != nil && b.outcome != nil }
                let store=CompanionStore(fileURL:folder.appendingPathComponent("profile.json"),defaults:defaults("preview"));store.setLanguage(.ko)
                let window=BattleWindowController(battle:a,store:store,audioDefaults:UserDefaults(suiteName:"dev.poketokenbar.battlepreview.audio")!)
                controller=window
                window.auxiliaryState.fieldVisible=false;window.auxiliaryState.statsVisible=false
                window.show()
                window.window?.title=win ? "PokeTokenBar · 승리 음원·종료 버튼 테스트" : "PokeTokenBar · 패배 음원·종료 버튼 테스트"
            } catch { print("Result preview: \(error)") }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--result-audio-preview") {
            directory=FileManager.default.temporaryDirectory.appendingPathComponent("ptb-result-preview-\(UUID())")
            try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let panel=NSWindow(contentRect:NSRect(x:0,y:0,width:380,height:166),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
            panel.isReleasedWhenClosed=false
            panel.title="PokeTokenBar · 승패 음원 테스트 선택"
            panel.contentViewController=NSHostingController(rootView:VStack(spacing:14) {
                Text("승리·패배 음원 / 종료 버튼").font(.headline)
                Text("결과창 하단의 종료 또는 X로 닫을 수 있습니다.\n다시 듣고 싶으면 아래에서 결과를 선택하세요.").font(.caption)
                HStack {
                    Button("승리 화면 열기") { [weak self] in self?.showResultPreview(win:true) }
                    Button("패배 화면 열기") { [weak self] in self?.showResultPreview(win:false) }
                    Button("테스트 종료") { NSApp.terminate(nil) }
                }
            }.padding(18))
            comparisonWindow=panel
            if let screen=NSScreen.main?.visibleFrame { panel.setFrameOrigin(NSPoint(x:screen.minX+20,y:screen.maxY-205)) }
            panel.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            showResultPreview(win:true)
            return
        }
        if CommandLine.arguments.contains("--size-preview") {
            let screen=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
            for mode in [CommandLine.arguments.contains("--doubles") ? BattleMode.doubles:.singles] {
                let host=NSHostingController(rootView:PokemonSizeComparison(mode:mode,spriteStore:SpriteStore(directory:Bundle.main.resourceURL!.appendingPathComponent("PokeRogueSizeGIFs"))))
                let window=NSWindow(contentViewController:host)
                window.styleMask=[.titled,.closable,.miniaturizable]
                window.title="PokeTokenBar · \(CommandLine.arguments.contains("--cry-preview") ? "등장·교체 울음소리 테스트" : CommandLine.arguments.contains("--status-preview") ? "상태이상 연출 테스트" : CommandLine.arguments.contains("--background-preview") ? "배경 연출":"PokéRogue 크기 비교") · \(mode == .singles ? "싱글 660px":"더블 680px")"
                window.isReleasedWhenClosed=false
                let width:CGFloat=mode == .singles ? 660:680
                let fit=host.view.fittingSize
                window.setContentSize(NSSize(width:width,height:max(430,fit.height)))
                window.setFrameOrigin(NSPoint(x:mode == .singles ? screen.minX+8:screen.maxX-width-8,y:screen.maxY-window.frame.height-24))
                sizeWindows.append(window);window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps:true);return
        }
        if CommandLine.arguments.contains("--matchmaking") || CommandLine.arguments.contains("--matching-duel") {
            do { try showMatchingPreview() } catch { print("Matching preview: \(error)"); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--loadout") {
            Task { @MainActor in
                do {
                    directory = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-loadout-preview-\(UUID())")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let file = directory.appendingPathComponent("profile.json")
                    var state = CompanionState()
                    state.language = .ko
                    let collectionBattle=CommandLine.arguments.contains("--collection-battle-preview")
                    let speciesID=collectionBattle ? 6:79
                    var profile = PokemonProfile.generate(seed: 7, instanceID: "preview-owned")
                    profile.level = collectionBattle ? 100:37
                    profile.enrich(with: try await LoadoutPreviewDetails().pokemonDetails(speciesID:speciesID))
                    state.dex = [DexEntry(id: "preview-owned", baseID:speciesID, finalID:speciesID, chainOrder:[speciesID], rarity: .common,
                        caughtAt: Date(), nature: .modest, profile: profile, names:[speciesID:collectionBattle ? ["ko":"리자몽","en":"Charizard"]:["ko":"야돈","en":"Slowpoke"]])]
                    if collectionBattle {state.dex[0].battleDefaultItem="charizarditex"}
                    try JSONEncoder().encode(state).write(to: file)
                    let store = CompanionStore(detailProvider: LoadoutPreviewDetails(), fileURL: file, defaults: defaults("loadout"))
                    await store.loadPokemonDetails(speciesID:speciesID)
                    let window = NSWindow(contentRect: NSRect(x:0,y:0,width:520,height:min(780,NSScreen.main!.visibleFrame.height-70)),
                        styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
                    window.title = collectionBattle ? "PokeTokenBar · 컬렉션 기본 도구·메가진화 정보 테스트":"PokeTokenBar · 컬렉션 기술·특성 편집 테스트"
                    window.isReleasedWhenClosed = false
                    window.contentViewController = NSHostingController(rootView: PokemonDetailView(store: store, species: store.dexSpecies[0], onBack: {}).frame(width:520,height:min(780,NSScreen.main!.visibleFrame.height-70)))
                    comparisonWindow = window
                    window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
                } catch { print("Loadout preview: \(error)");NSApp.terminate(nil) }
            }
            return
        }
        if CommandLine.arguments.contains("--faithful-pikachu") {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1120,height:650),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
            window.title="PokeTokenBar · 피카츄 PokéRogue 원본 비교"
            window.isReleasedWhenClosed=false
            window.contentViewController=NSHostingController(rootView:PokeRogueFaithfulComparison())
            window.center();comparisonWindow=window;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            return
        }
        if CommandLine.arguments.contains("--pokerogue") {
            do {
                let catalog=try PokeRoguePreviewCatalog(directory:Bundle.main.resourceURL!.appendingPathComponent("PokeRoguePreview"))
                let available=NSScreen.main?.visibleFrame.size ?? NSSize(width:1440,height:900)
                let scale=min(1,min((available.width-48)/1206,(available.height-80)/610))
                let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1206*scale,height:610*scale),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
                window.title="PokeTokenBar · PokéRogue 배경·움직임 테스트"
                window.isReleasedWhenClosed=false
                let moveIndex=CommandLine.arguments.firstIndex(of:"--move")
                let move=moveIndex.flatMap { CommandLine.arguments.indices.contains($0+1) ? CommandLine.arguments[$0+1] : nil } ?? "surf"
                window.contentViewController=NSHostingController(rootView:PokeRogueEffectComparison(catalog:catalog,initialMove:move)
                    .scaleEffect(scale,anchor:.topLeading).frame(width:1206*scale,height:610*scale,alignment:.topLeading))
                window.setContentSize(NSSize(width:1206*scale,height:610*scale))
                window.center();comparisonWindow=window;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            } catch { print("PokéRogue preview: \(error)");NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--compare-pikachu") {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1230,height:570),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
            window.title="PokeTokenBar · 피카츄 이펙트 비교"
            window.isReleasedWhenClosed=false
            window.contentViewController=NSHostingController(rootView:PikachuEffectComparison())
            window.center();comparisonWindow=window
            window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            return
        }
        Task { @MainActor in
            do {
                directory=FileManager.default.temporaryDirectory.appendingPathComponent("ptb-preview-\(UUID())")
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                if CommandLine.arguments.contains("--versus-codex") {
                    duelTeams = try JSONDecoder().decode([String: [BattlePokemon]].self, from: Data(contentsOf: duelDirectory.appendingPathComponent("teams.json")))
                    guard duelTeams["a"]?.count == 6, duelTeams["b"]?.count == 6 else { throw BattleFailure.invalidMessage }
                }
                left.other=right;right.other=left
                let a=BattleCoordinator(defaults:defaults("AAAA"),history:BattleHistoryStore(url:directory.appendingPathComponent("a.json")),decisionTimeLimit:1800,linkFactory:{_,mode in self.left.discoveryGroup=mode.rawValue;return self.left})
                let b=BattleCoordinator(defaults:defaults("BBBB"),history:BattleHistoryStore(url:directory.appendingPathComponent("b.json")),decisionTimeLimit:1800,linkFactory:{_,mode in self.right.discoveryGroup=mode.rawValue;return self.right})
                battle=a;enemy=b
                if CommandLine.arguments.contains("--doubles") { a.setMode(.doubles);b.setMode(.doubles) }
                a.search();b.search();a.select(TradePeer(id:"BBBB",nickname:"BBBB",code:"BBBB",discoveryGroup:a.mode.rawValue))
                try await wait { a.opponent != nil && b.opponent != nil }
                if CommandLine.arguments.contains("--lobby") || CommandLine.arguments.contains("--roster-preview") || CommandLine.arguments.contains("--item-preview") {
                    var state = CompanionState()
                    state.language = .ko
                    state.dex = [26,25,181,310,143,128,587,618].map { id in
                        var profile = PokemonProfile.generate(seed:UInt64(id))
                        profile.level = id == 25 ? 37 : 100
                        profile.abilityName = id == 128 ? "Intimidate" : id == 143 ? "Immunity" : "Static"
                        profile.moves = [.init(name:"thunderbolt",learnedAtLevel:26)]
                        return DexEntry(id:"preview-stored-\(id)",baseID:id,finalID:id,chainOrder:[id],rarity:.common,
                            caughtAt:Date(),profile:profile,releasedAt:id == 143 ? Date() : nil)
                    }
                    var active = PokemonProfile.generate(seed:134);active.level = 100
                    state.active = MonState(baseID:134,pathIDs:[134],stageIndex:0,usedAtStage:0,rarity:.common,totalForms:1,profile:active)
                    if CommandLine.arguments.contains("--roster-preview") || CommandLine.arguments.contains("--item-preview") {
                        state.dex=team("a").map { pokemon in
                            var profile=PokemonProfile.generate(seed:UInt64(pokemon.speciesID));profile.level=50
                            profile.abilityName=pokemon.ability;profile.abilitySlot=1
                            profile.moves=pokemon.moves.map{.init(name:$0,learnedAtLevel:1)}
                            return DexEntry(id:pokemon.id,baseID:pokemon.speciesID,finalID:pokemon.speciesID,chainOrder:[pokemon.speciesID],rarity:.common,caughtAt:Date(),profile:profile)
                        }
                        if !CommandLine.arguments.contains("--item-preview") {
                            a.register(team:team("a"));b.register(team:team("b"))
                            try await wait { a.canSelectLineup && b.canSelectLineup }
                        }
                    }
                    let file = directory.appendingPathComponent("lobby.json")
                    try JSONEncoder().encode(state).write(to:file)
                    let store = CompanionStore(fileURL:file,defaults:defaults("lobby"))
                    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:470),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
                    window.title = CommandLine.arguments.contains("--item-preview") ? "PokeTokenBar · 6마리 등록 · 도구 선택 테스트" : CommandLine.arguments.contains("--roster-preview") ? "PokeTokenBar · 타입·상성 선발 테스트 · 싱글 3마리":"PokeTokenBar · 출전 선택 테스트 · 육성 완료 최종 진화체"
                    window.isReleasedWhenClosed = false
                    window.contentViewController = NSHostingController(rootView:BattleLobbyView(store:store,battle:a).frame(width:480,height:470))
                    comparisonWindow = window
                    window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
                    return
                }
                a.register(team:team("a"));b.register(team:team("b"));try await wait { a.canSelectLineup && b.canSelectLineup }
                a.ready(team:team("a"));try await wait { b.remoteReady };b.ready(team:team("b"))
                try await wait { a.frame != nil && b.frame != nil }
                for side in [a,b] where side.frame?.preview == true { let frame=side.frame!;side.choose(BattleDecision(decisionID:frame.decisionID,actions:[],order:Array(1...side.mode.teamSize))) }
                try await wait { a.frame?.preview == false && b.frame?.preview == false }
                if CommandLine.arguments.contains("--mega-design-preview"), !CommandLine.arguments.contains("--mega-effect-preview") {
                    for c in [a,b] {
                        let f=c.frame!
                        c.choose(BattleDecision(decisionID:f.decisionID,actions:[.init(kind:"move",index:1,target:0,mega:true)],order:[]))
                    }
                    try await wait { a.frame?.turn==2 && b.frame?.turn==2 }
                    guard a.frame?.own[0].mega==true,b.frame?.own[0].mega==true else{throw BattleFailure.invalidMessage}
                    a.completePresentation();b.completePresentation()
                }
                if CommandLine.arguments.contains("--fields") {
                    for index in 1...3 {
                        let old = a.frame!.turn
                        for c in [a,b] {
                            let f = c.frame!
                            c.choose(BattleDecision(decisionID:f.decisionID,actions:f.slots.map { slot in
                                .init(kind:"move",index:c === a && slot.slot == 0 ? index : 1,target:0)
                            },order:[]))
                        }
                        try await wait { (a.frame?.turn ?? 0) > old && (b.frame?.turn ?? 0) > old }
                    }
                }
                let store=CompanionStore(fileURL:directory.appendingPathComponent("profile.json"),defaults:defaults("preview"));store.setLanguage(.ko)
                let window=BattleWindowController(battle:a,store:store,allowsAudio:!CommandLine.arguments.contains("--muted") && !CommandLine.arguments.contains("--narrow-preview") && !CommandLine.arguments.contains("--notices-demo"),audioDefaults:UserDefaults(suiteName:"dev.poketokenbar.battlepreview.audio")!);controller=window
                window.show();window.window?.title="PokeTokenBar · 실제 배틀 테스트 · PokéRogue / \(a.mode == .doubles ? "더블" : "싱글")"
                if CommandLine.arguments.contains("--fairy-preview") { window.window?.title="PokeTokenBar · 페어리 기술·원본 이펙트 · 싱글 · 음소거" }
                if CommandLine.arguments.contains("--mega-design-preview") {window.window?.title=CommandLine.arguments.contains("--mega-effect-preview") ? "PokeTokenBar · 메가진화 연출·크기 테스트 · 싱글":"PokeTokenBar · PokéRogue 메가진화 디자인 · 싱글"}
                if CommandLine.arguments.contains("--hp-preview") {
                    window.window?.title="PokeTokenBar · 타격 후 HP 감소 테스트 · 싱글 660px"
                }
                if CommandLine.arguments.contains("--narrow-preview"), let main = window.window {
                    let width = BattleWindowLayout.preferredWidth(for: a.mode)
                    main.setContentSize(NSSize(width: width, height: main.contentRect(forFrameRect: main.frame).height))
                    main.center()
                    main.title = "PokeTokenBar · 너비 비교 · \(a.mode == .singles ? "싱글 \(Int(width))px" : "더블 \(Int(width))px")"
                }
                if CommandLine.arguments.contains("--fields") { window.statsWindow?.makeKeyAndOrderFront(nil) }
                if CommandLine.arguments.contains("--field-effects-pilot") {
                    window.window?.title = "PokeTokenBar · 날씨·필드 원본 연출 테스트"
                }
                if CommandLine.arguments.contains("--versus-codex") {
                    window.window?.title = "PokeTokenBar · 플레이어 vs Codex · 랜덤 6마리 등록 · 3마리 싱글"
                }
                if CommandLine.arguments.contains("--notices-demo") {
                    window.window?.title = "PokeTokenBar · 기술·특성 알림 검증 · 별도 싱글"
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(6))
                        if a.phase == .playing, !a.submitted, let f = a.frame, !f.waiting {
                            a.choose(BattleDecision(decisionID:f.decisionID,actions:[BattleAction(kind:"move",index:3,target:0)],order:[]))
                        }
                    }
                }
                var entryDemoAt=Date().addingTimeInterval(16)
                var entryDemoCount=0
                if CommandLine.arguments.contains("--entry-demo") {
                    window.window?.title="PokeTokenBar · 등장·회수 테스트 · \(a.mode == .singles ? "싱글 660px":"더블 680px")"
                }
                while window.window?.isVisible == true {
                    if CommandLine.arguments.contains("--entry-demo"),entryDemoCount<2,Date()>entryDemoAt,
                       a.phase == .playing,!a.submitted,!a.presentation.pending,let f=a.frame,!f.waiting {
                        let bench=f.own.firstIndex{!$0.active && !$0.fainted}
                        if let bench {
                            a.choose(BattleDecision(decisionID:f.decisionID,actions:f.slots.map{ slot in
                                slot.slot==0 ? BattleAction(kind:"switch",index:bench+1,target:0):BattleAction(kind:"move",index:1,target:1)
                            },order:[]))
                            entryDemoCount+=1;entryDemoAt=Date().addingTimeInterval(16)
                        }
                    }
                    if CommandLine.arguments.contains("--versus-codex") {
                        if b.phase == .playing, !b.submitted, let frame = b.frame, !frame.waiting, !frame.ended {
                            let command = duelDirectory.appendingPathComponent("command.json")
                            if let data = try? Data(contentsOf: command) {
                                try? FileManager.default.removeItem(at: command)
                                if let decision = try? JSONDecoder().decode(BattleDecision.self, from: data), decision.decisionID == frame.decisionID {
                                    b.choose(decision)
                                }
                            }
                        }
                        var opponentState: [String: Any] = ["phase":String(describing:b.phase),"submitted":b.submitted,"outcome":b.outcome ?? "","error":b.error ?? ""]
                        if let frame = b.frame { opponentState["frame"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) }
                        opponentState["team"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b.ownTeam))
                        try JSONSerialization.data(withJSONObject: opponentState).write(to:duelDirectory.appendingPathComponent("state.json"),options:.atomic)
                    }
                    if !CommandLine.arguments.contains("--versus-codex"), b.phase == .playing, !b.submitted, let frame=b.frame, !frame.waiting, !frame.preview, !frame.ended {
                        var used=Set<Int>()
                        let actions: [BattleAction] = frame.slots.compactMap { slot in
                            if slot.canPass { return .pass }
                            if slot.mustSwitch {
                                guard let i=frame.own.indices.first(where:{ !frame.own[$0].active && !frame.own[$0].fainted && !used.contains($0) }) else { return nil }
                                used.insert(i);return BattleAction(kind:"switch",index:i+1,target:0)
                            }
                            if CommandLine.arguments.contains("--mega-effect-preview"),let move=slot.moves.first(where:{$0.apiName=="protect" && !$0.disabled && $0.pp>0}) {
                                return BattleAction(kind:"move",index:move.index,target:0,mega:slot.canMegaEvo==true ? true:nil)
                            }
                            let quiet=CommandLine.arguments.contains("--fairy-preview") || (CommandLine.arguments.contains("--rogue-battle") && frame.turn%3 != 0)
                            guard let move=(quiet ? slot.moves.first(where:{$0.apiName == "splash"}) : slot.moves.first(where:{ !$0.disabled && $0.pp > 0 && $0.category != "Status" })) ?? slot.moves.first(where:{ !$0.disabled && $0.pp > 0 }) else { return nil }
                            return BattleAction(kind:"move",index:move.index,target:move.targetRequired ? (move.targets.first?.location ?? 0) : 0)
                        }
                        if actions.count == frame.slots.count { b.choose(BattleDecision(decisionID:frame.decisionID,actions:actions,order:[])) }
                    }
                    let state: [String:Any] = ["turn":a.frame?.turn ?? 0,"ownHP":a.frame?.own.first?.hp ?? 0,"foeHP":a.frame?.foe.first?.hp ?? 0,"musicPlaying":window.isMusicPlaying,"musicVolume":window.audioSettings.volume,"outcome":a.outcome ?? ""]
                    var audioState = state
                    audioState["musicOutputVolume"] = window.musicOutputVolume
                    audioState["windowHeight"] = window.window?.frame.height
                    audioState["windowWidth"] = window.window?.frame.width
                    audioState["measuredWidth"] = window.contentMeasurement?.content.width
                    audioState["minimumHeight"] = window.window?.minSize.height
                    audioState["contentHeight"] = window.contentMeasurement?.content.height
                    audioState["commandClearance"] = window.contentMeasurement?.commandClearance

                    audioState["effects"] = a.frame?.effects?.suffix(4).map { $0.moveID ?? $0.move }
                    let statePath = a.mode == .doubles ? "/private/tmp/ptb-live-battle-doubles.json" : "/private/tmp/ptb-live-battle-state.json"
                    try JSONSerialization.data(withJSONObject:audioState).write(to:URL(fileURLWithPath:statePath),options:.atomic)
                    try await Task.sleep(for:.milliseconds(100))
                }
                NSApp.terminate(nil)
            } catch { print("Battle preview: \(error)");NSApp.terminate(nil) }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        battle?.shutdown();enemy?.shutdown();matchingPeers.forEach { $0.shutdown() }
        suiteNames.forEach { UserDefaults.standard.removePersistentDomain(forName:$0) }
        if let directory { try? FileManager.default.removeItem(at:directory) }
    }
}
@MainActor private var previewDelegate: PreviewDelegate?
@MainActor @_cdecl("previewmain")
func previewmain() -> Int32 {
    let app=NSApplication.shared
    let delegate=PreviewDelegate();previewDelegate=delegate;app.delegate=delegate
    app.setActivationPolicy(.regular);app.run();return 0
}
