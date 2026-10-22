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
    var routes: [String: PreviewLink] = [:]
    func startDiscovery() { candidates.forEach { onPeerFound?($0) } }
    func stopDiscovery() {}
    func connect(to peer: TradePeer) throws {
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
        PokemonDetails(speciesID: 79, name: "slowpoke", height: 12, weight: 360, baseExperience: 63,
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
    let left=PreviewLink(),right=PreviewLink()
    var matchingPeers: [BattleCoordinator] = []
    var matchingLinks: [PreviewLink] = []
    var suiteNames: [String] = []
    var directory: URL!
    var duelTeams: [String: [BattlePokemon]] = [:]
    let duelDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/codex-duel")
    func defaults(_ code: String) -> UserDefaults {
        let name="BattlePreview.\(UUID())";suiteNames.append(name)
        let defaults=UserDefaults(suiteName:name)!
        defaults.set(code,forKey:"tradeCode");defaults.set((CommandLine.arguments.contains("--versus-codex") || CommandLine.arguments.contains("--matching-duel")) ? (code == "AAAA" ? "플레이어" : "Codex") : code,forKey:"tradeNickname")
        return defaults
    }
    func team(_ prefix: String) -> [BattlePokemon] {
        if let random = duelTeams[prefix] { return random }
        let rogue=CommandLine.arguments.contains("--rogue-battle")
        let moves=[["psychic","surf","double-team","rest"],["thunderbolt","protect","volt-switch","flamethrower"],["secret-power","nature-power","sunny-day","power-split"],["ice-beam","reflect","swift","recover"]]
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
        let a = BattleCoordinator(defaults: defaults("AAAA"), history: BattleHistoryStore(url: directory.appendingPathComponent("a.json")), decisionTimeLimit:1800, linkFactory: { _ in self.left })
        battle = a
        let opponents:[String] = interactive ? ["Codex"] : ["지우", "이슬", "웅"]
        for (index, nickname) in opponents.enumerated() {
            let code = ["BBBB", "CCCC", "DDDD"][index]
            let link = PreviewLink()
            let preferences = defaults(code); preferences.set(nickname, forKey: "tradeNickname")
            let coordinator = BattleCoordinator(defaults: preferences, history: BattleHistoryStore(url: directory.appendingPathComponent("\(code).json")), decisionTimeLimit:1800, linkFactory: { _ in link })
            matchingLinks.append(link); matchingPeers.append(coordinator)
            left.candidates.append(TradePeer(id: code, nickname: nickname, code: code)); left.routes[code] = link
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
                            if peer.mode != a.mode{peer.setMode(a.mode)}
                            if peer.registeredTeam.isEmpty { peer.register(team:self.team("b")) }
                            if peer.canSelectLineup,!peer.localReady {peer.ready(team:peer.registeredTeam)}
                        }
                        if peer.phase == .playing,!peer.submitted,let frame=peer.frame,!frame.waiting,!frame.ended {
                            if frame.preview {
                                peer.choose(BattleDecision(decisionID:frame.decisionID,actions:[],order:Array(1...peer.mode.battleSize)))
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
                                    return BattleAction(kind:"move",index:move.index,target:move.targetRequired ? (move.targets.first?.location ?? 0):0)
                                }
                                if actions.count==frame.slots.count{peer.choose(BattleDecision(decisionID:frame.decisionID,actions:actions,order:[]))}
                            }
                        }
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
    func applicationDidFinishLaunching(_ notification: Notification) {
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
                    var profile = PokemonProfile.generate(seed: 7, instanceID: "preview-owned")
                    profile.level = 37
                    profile.enrich(with: try await LoadoutPreviewDetails().pokemonDetails(speciesID:79))
                    state.dex = [DexEntry(id: "preview-owned", baseID: 79, finalID: 79, chainOrder: [79], rarity: .common,
                        caughtAt: Date(), nature: .modest, profile: profile, names: [79:["ko":"야돈","en":"Slowpoke"]])]
                    try JSONEncoder().encode(state).write(to: file)
                    let store = CompanionStore(detailProvider: LoadoutPreviewDetails(), fileURL: file, defaults: defaults("loadout"))
                    await store.loadPokemonDetails(speciesID: 79)
                    let window = NSWindow(contentRect: NSRect(x:0,y:0,width:520,height:min(780,NSScreen.main!.visibleFrame.height-70)),
                        styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
                    window.title = "PokeTokenBar · 컬렉션 기술·특성 편집 테스트"
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
                let a=BattleCoordinator(defaults:defaults("AAAA"),history:BattleHistoryStore(url:directory.appendingPathComponent("a.json")),decisionTimeLimit:1800,linkFactory:{_ in self.left})
                let b=BattleCoordinator(defaults:defaults("BBBB"),history:BattleHistoryStore(url:directory.appendingPathComponent("b.json")),decisionTimeLimit:1800,linkFactory:{_ in self.right})
                battle=a;enemy=b
                a.search();b.search();a.select(TradePeer(id:"BBBB",nickname:"BBBB",code:"BBBB"))
                try await wait { a.opponent != nil && b.opponent != nil }
                if CommandLine.arguments.contains("--doubles") { a.setMode(.doubles);try await wait { b.mode == .doubles } }
                if CommandLine.arguments.contains("--lobby") {
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
                    let file = directory.appendingPathComponent("lobby.json")
                    try JSONEncoder().encode(state).write(to:file)
                    let store = CompanionStore(fileURL:file,defaults:defaults("lobby"))
                    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:480,height:470),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
                    window.title = "PokeTokenBar · 출전 선택 테스트 · 육성 완료 최종 진화체"
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
                let window=BattleWindowController(battle:a,store:store,allowsAudio:!CommandLine.arguments.contains("--narrow-preview") && !CommandLine.arguments.contains("--notices-demo"),audioDefaults:UserDefaults(suiteName:"dev.poketokenbar.battlepreview.audio")!);controller=window
                window.show();window.window?.title="PokeTokenBar · 실제 배틀 테스트 · PokéRogue / \(a.mode == .doubles ? "더블" : "싱글")"
                if CommandLine.arguments.contains("--narrow-preview"), let main = window.window {
                    let width = BattleWindowLayout.preferredWidth
                    main.setContentSize(NSSize(width: width, height: main.contentRect(forFrameRect: main.frame).height))
                    main.center()
                    main.title = "PokeTokenBar · 너비 비교 · \(a.mode == .singles ? "싱글 800px (−20%)" : "더블 800px (−20%)")"
                }
                if CommandLine.arguments.contains("--fields") { window.statsWindow?.makeKeyAndOrderFront(nil) }
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
                while window.window?.isVisible == true {
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
                            let quiet=CommandLine.arguments.contains("--rogue-battle") && frame.turn%3 != 0
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
