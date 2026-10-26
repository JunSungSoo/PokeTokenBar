import Foundation
import CryptoKit

protocol BattleLink: AnyObject {
    var onPeerFound: (@Sendable (TradePeer) -> Void)? { get set }
    var onPeerLost: (@Sendable (String) -> Void)? { get set }
    var onConnected: (@Sendable () -> Void)? { get set }
    var onDisconnected: (@Sendable () -> Void)? { get set }
    var onDataReceived: (@Sendable (Data) -> Void)? { get set }
    func startDiscovery()
    func stopDiscovery()
    func pauseDiscovery()
    func startReconnectionDiscovery()
    func connect(to peer: TradePeer) throws
    func sendData(_ data: Data) throws
    func disconnect()
}
extension BattleLink {
    func pauseDiscovery() { stopDiscovery() }
    func startReconnectionDiscovery() { startDiscovery() }
}
extension MultipeerTradeTransport: BattleLink {}

struct BattleWire: Codable, Sendable {
    var sequence = 0
    var version = 1
    var revision = BattleEngineProcess.revision
    var kind: String
    var matchID: String? = nil
    var identity: BattleIdentity? = nil
    var mode: BattleMode? = nil
    var team: [BattlePokemon]? = nil
    var roster: [BattleRosterMember]? = nil
    var frame: BattleFrame? = nil
    var decision: BattleDecision? = nil
    var digest: String? = nil
    var nonce: String? = nil
    var reason: String? = nil
    var deadline: Date? = nil
    var winner: Int? = nil
}

@MainActor @Observable
final class BattleCoordinator {
    enum Phase { case idle, searching, connecting, connected, preparing, playing, reconnecting, ended }
    private(set) var phase: Phase = .idle
    private(set) var peers: [TradePeer] = []
    private(set) var selectedPeer: TradePeer?
    private(set) var opponent: BattleIdentity?
    let presentation = BattleScenePlayback()
    private(set) var frame: BattleFrame?
    private(set) var error: String?
    private(set) var localReady = false
    private(set) var remoteReady = false
    private(set) var submitted = false
    private(set) var outcome: String?
    private(set) var ownTeam: [BattlePokemon] = []
    private(set) var registeredTeam: [BattlePokemon] = []
    private(set) var opponentRoster: [BattleRosterMember] = []
    var canSelectLineup: Bool { registeredTeam.count == mode.teamSize && opponentRoster.count == mode.teamSize }
    private(set) var decisionDeadline: Date?
    private(set) var manualCode: String?
    private(set) var mode: BattleMode = .singles
    let history: BattleHistoryStore
    private(set) var identity: BattleIdentity
    var onBattleWindow: (() -> Void)?
    var onStopMusic: (() -> Void)?
    @ObservationIgnored private var transport: (any BattleLink)?
    @ObservationIgnored private let identityDefaults: UserDefaults
    @ObservationIgnored private let linkFactory: (BattleIdentity, BattleMode) -> any BattleLink
    @ObservationIgnored private var manual: ManualTradeTransport?
    @ObservationIgnored private var engine: BattleEngineProcess?
    @ObservationIgnored private var latestFrames: [BattleFrame] = []
    @ObservationIgnored private var peerTeam: [BattlePokemon] = []
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private var linkGeneration = UUID()
    @ObservationIgnored private var reconnectTimer: Task<Void, Never>?
    @ObservationIgnored private let decisionTimeLimit: TimeInterval
    @ObservationIgnored private var decisionTimer: Task<Void, Never>?
    @ObservationIgnored private var pending: BattleDecision?
    @ObservationIgnored private var pendingNonce: String?
    @ObservationIgnored private var commitments: [Int: String] = [:]
    @ObservationIgnored private var reveals: [Int: BattleDecision] = [:]
    @ObservationIgnored private var matchID = ""
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var endReason = "completed"
    @ObservationIgnored private var localPlayer = 0
    @ObservationIgnored private var sentSequence = 0
    @ObservationIgnored private var receivedSequence = 0
    @ObservationIgnored private var lastDecision = ""
    @ObservationIgnored private var timerKey = ""

    init(defaults: UserDefaults = .standard, history: BattleHistoryStore? = nil, decisionTimeLimit: TimeInterval = 60,
         linkFactory: @escaping (BattleIdentity, BattleMode) -> any BattleLink = { identity, mode in
             MultipeerTradeTransport(nickname: identity.nickname, code: identity.code, service: "ptb-battle", group: mode.rawValue)
         }) {
        self.decisionTimeLimit = decisionTimeLimit
        self.linkFactory = linkFactory
        self.identityDefaults = defaults
        identity = BattleIdentity(nickname: TradeIdentity.nickname(defaults: defaults),
                                  code: TradeIdentity.code(defaults: defaults), nonce: UUID().uuidString)
        self.history = history ?? BattleHistoryStore()
    }
    var isHost: Bool { localPlayer == 0 }
    var isActive: Bool { [.preparing, .playing, .reconnecting].contains(phase) }
    var canEditMode: Bool { (phase == .idle || phase == .searching) && !isActive && !localReady && !remoteReady && registeredTeam.isEmpty && opponentRoster.isEmpty && opponent == nil }

    func search() {
        guard !isActive else { return }
        releaseConnection()
        identity = BattleIdentity(nickname: TradeIdentity.nickname(defaults: identityDefaults), code: identity.code, nonce: UUID().uuidString)
        sentSequence = 0; receivedSequence = 0
        frame = nil; presentation.reset(); latestFrames = []; lastDecision = ""; timerKey = ""; matchID = ""
        pending = nil; pendingNonce = nil; commitments = [:]; reveals = [:]
        submitted = false; decisionDeadline = nil
        phase = .searching; peers = []; selectedPeer = nil; opponent = nil; error = nil
        localReady = false; remoteReady = false; ownTeam = []; peerTeam = []; outcome = nil
        registeredTeam = []; opponentRoster = []
        let link = linkFactory(identity,mode)
        transport = link
        let generation = linkGeneration
        link.onPeerFound = { [weak self] peer in Task { @MainActor [weak self] in
            guard let self, self.linkGeneration == generation else { return }; self.found(peer)
        } }
        link.onPeerLost = { [weak self] id in Task { @MainActor [weak self] in
            guard let self, self.linkGeneration == generation, self.phase == .searching || self.phase == .reconnecting else { return }
            self.peers.removeAll { $0.id == id }
        } }
        link.onConnected = { [weak self] in Task { @MainActor [weak self] in
            guard let self, self.linkGeneration == generation, self.transport != nil else { return }; self.connected()
        } }
        link.onDisconnected = { [weak self] in Task { @MainActor [weak self] in
            guard let self, self.linkGeneration == generation, self.transport != nil else { return }; self.disconnected()
        } }
        link.onDataReceived = { [weak self] data in Task { @MainActor [weak self] in
            guard let self, self.linkGeneration == generation, self.transport != nil else { return }; self.receive(data)
        } }
        link.startDiscovery()
    }

    private func found(_ peer: TradePeer) {
        guard phase == .searching || phase == .reconnecting else { return }
        guard peer.discoveryGroup == mode.rawValue else { peers.removeAll { $0.id == peer.id };return }
        if phase == .searching && !peer.isAvailable { peers.removeAll { $0.id == peer.id }; return }
        guard peer.code != identity.code || peer.nickname != identity.nickname else { return }
        peers.removeAll { $0.id == peer.id }; peers.append(peer)
    }
    func select(_ peer: TradePeer) {
        guard phase == .searching, opponent == nil, peer.isAvailable, peer.discoveryGroup == mode.rawValue else { return }
        selectedPeer = peer
        if !peers.contains(where: { $0.id == peer.id }) { peers.append(peer) }
        phase = .connecting
        do {
            try transport?.connect(to: peer)
            transport?.pauseDiscovery()
        } catch {
            releaseConnection(); phase = .idle; selectedPeer = nil; peers = []
            self.error = error.localizedDescription
        }
    }
    func enableManualConnection() {
        guard phase == .searching else { return }; prepareManual()
    }
    private func prepareManual() {
        guard manual == nil else { return }
        let link = ManualTradeTransport(); manual = link
        let generation = linkGeneration
        link.onConnected = { [weak self] in Task { @MainActor [weak self] in
            guard let self, self.linkGeneration == generation, self.manual != nil else { return }; self.connected(manual: true)
        } }
        link.onDisconnected = { [weak self] in Task { @MainActor [weak self] in
            guard let self, self.linkGeneration == generation, self.manual != nil else { return }; self.disconnected()
        } }
        link.onDataReceived = { [weak self] data in Task { @MainActor [weak self] in
            guard let self, self.linkGeneration == generation, self.manual != nil else { return }; self.receive(data)
        } }
        link.startListening { [weak self] code in Task { @MainActor [weak self] in
            guard let self, self.linkGeneration == generation, self.manual != nil else { return }; self.manualCode = code
        } }
    }
    func connectManual(_ code: String) {
        guard phase == .searching || phase == .reconnecting else { return }
        if manual == nil { prepareManual() }
        do {
            try manual?.connectManually(code: code)
            if phase == .searching { phase = .connecting }
            transport?.pauseDiscovery()
        } catch { self.error = error.localizedDescription }
    }
    private func connected(manual isManual: Bool = false) {
        guard phase == .searching || phase == .connecting || phase == .reconnecting else { return }
        transport?.pauseDiscovery()
        if isManual {
            transport?.onDisconnected = nil; transport?.disconnect(); transport = nil
        } else {
            manual?.onDisconnected = nil; manual?.disconnect(); manual = nil; manualCode = nil
        }
        if phase == .reconnecting {
            var resume = wire("resume"); resume.identity = identity; send(resume)
            return
        }
        phase = .connected
        var message = BattleWire(kind: "hello"); message.identity = identity; message.mode = mode
        send(message)
    }
    private func receive(_ data: Data) {
        guard data.count <= TCPFrameBuffer.maxFrameLength else { return }
        do {
            let message = try JSONDecoder().decode(BattleWire.self, from: data)
            guard message.version == 1, message.revision == BattleEngineProcess.revision else { throw BattleFailure.invalidMessage }
            if message.kind == "hello" {
                guard let peer = message.identity, peer.code.count <= 80, peer.nickname.count <= 100, peer.nonce.count <= 80,
                      UUID(uuidString: peer.nonce) != nil, !peer.code.isEmpty,
                      peer != identity, phase == .connected, opponent == nil else { return }
                guard message.mode == mode else { cancelLobby(); error = "Battle mode mismatch"; return }
                receivedSequence = message.sequence
                opponent = peer
                localPlayer = (identity.code + identity.nonce) < (peer.code + peer.nonce) ? 0 : 1
                matchID = [identity.nonce, peer.nonce].sorted().joined(separator: ":")
                selectedPeer = TradePeer(id: peer.nonce, nickname: peer.nickname, code: peer.code, discoveryGroup: mode.rawValue)
                return
            }
            guard opponent != nil, message.matchID == matchID, message.sequence > receivedSequence else { return }
            receivedSequence = message.sequence
            switch message.kind {
            case "resume":
                guard message.identity == opponent, phase == .reconnecting else { return }
                timeout?.cancel(); phase = .playing; submitted = false; pending = nil; pendingNonce = nil
                commitments = [:]; reveals = [:]
                if isHost, !latestFrames.isEmpty { timerKey = ""; engineFrames(latestFrames) }

            case "timeout":
                guard !isHost, isActive, let winner = message.winner, (-1...1).contains(winner) else { return }
                finish(winner: winner, reason: "timeout")
            case "abort":
                error = message.reason; finish(winner: -1, reason: "engineFailure")
            case "roster":
                guard phase == .connected, message.mode == mode, let roster = message.roster,
                      roster.count == mode.teamSize, Set(roster.map(\.id)).count == roster.count,
                      Set(roster.map(\.speciesID)).count == roster.count,
                      roster.allSatisfy({ BattleTeamBuilder.isFinalEvolution($0.speciesID) && BattleTeamBuilder.isSpeciesEligible($0.speciesID) && (5...100).contains($0.level) }) else { throw BattleFailure.invalidMessage }
                guard opponentRoster.isEmpty else { throw BattleFailure.invalidMessage }
                clearReady(resetRegistration: false); opponentRoster = roster
            case "unregister":
                throw BattleFailure.invalidMessage
            case "ready":
                if let team=message.team,BattleHeldItems.hasDuplicates(team){throw BattleFailure.invalidTeam("Duplicate held item")}
                guard phase == .connected, message.mode == mode, let team = message.team,
                      team.count == mode.teamSize, Set(team.map(\.id)).count == team.count else { throw BattleFailure.invalidMessage }
                guard team.allSatisfy({ BattleTeamBuilder.isFinalEvolution($0.speciesID) }) else {
                    throw BattleFailure.invalidTeam("Fully evolved Pokémon required")
                }
                guard canSelectLineup, team.allSatisfy({ pokemon in opponentRoster.contains(BattleRosterMember(pokemon)) }) else { throw BattleFailure.invalidMessage }
                peerTeam = team; remoteReady = true; beginIfReady()
            case "unready":
                guard phase == .connected else { return }; clearReady(resetRegistration: false)
            case "frame":
                guard !isHost, isActive, let next = message.frame, next.revision == BattleEngineProcess.revision else { return }
                decisionDeadline = message.deadline
                apply(next)
            case "commit":
                guard isHost, phase == .playing, let digest = message.digest, digest.count == 64,
                      message.reason == latestFrames[safe: 1]?.decisionID else { return }
                commitments[1] = digest; requestRevealsIfReady()
            case "revealRequest":
                guard !isHost, phase == .playing, let pending, message.reason == pending.decisionID,
                      let nonce = pendingNonce else { return }
                var reply = wire("reveal"); reply.decision = pending; reply.nonce = nonce; send(reply)
            case "reveal":
                guard isHost, phase == .playing, let decision = message.decision, let nonce = message.nonce,
                      nonce.count <= 100, commitments[1] == Self.digest(decision, nonce: nonce, matchID: matchID) else { throw BattleFailure.invalidMessage }
                reveals[1] = decision; resolveIfReady()
            case "surrender":
                guard isActive else { return }
                finish(winner: localPlayer, reason: "surrender")
                send(wire("surrenderAck"))
            case "surrenderAck":
                if phase == .ended { timeout?.cancel(); releaseConnection() }
            case "cancel":
                guard !isActive else { return }; cancelLobby()
            case "error":
                submitted = false; pending = nil; pendingNonce = nil
                error = String((message.reason ?? "Battle error").prefix(500))
                if phase == .preparing { phase = .connected; clearReady(resetRegistration: false) }
            default: break
            }
        } catch { self.error = error.localizedDescription }
    }
    func setMode(_ value: BattleMode) {
        guard canEditMode, mode != value else { return }
        mode = value; clearReady()
        if phase == .searching { search() }
    }
    func register(team: [BattlePokemon]) {
        guard !BattleHeldItems.hasDuplicates(team) else{error="Duplicate held item";return}
        guard phase == .connected, opponent != nil, registeredTeam.isEmpty, team.count == mode.teamSize,
              Set(team.map(\.id)).count == team.count, Set(team.map(\.speciesID)).count == team.count,
              team.allSatisfy({ BattleTeamBuilder.isFinalEvolution($0.speciesID) && BattleTeamBuilder.isSpeciesEligible($0.speciesID) }) else { return }
        clearReady(resetRegistration: false); registeredTeam = team; error = nil
        var message = wire("roster"); message.mode = mode; message.roster = team.map(BattleRosterMember.init); send(message)
    }
    func ready(team: [BattlePokemon]) {
        guard !BattleHeldItems.hasDuplicates(team) else{error="Duplicate held item";return}
        guard phase == .connected, opponent != nil, team.count == mode.teamSize else { return }
        guard team.allSatisfy({ BattleTeamBuilder.isFinalEvolution($0.speciesID) }) else {
            error = "Fully evolved Pokémon required"; return
        }
        guard Set(team.map(\.speciesID)).count == team.count else {
            error = "Duplicate species"; return
        }
        guard canSelectLineup, Set(team.map(\.id)) == Set(registeredTeam.map(\.id)),
              team.allSatisfy({ registeredTeam.contains($0) }) else {
            error = "Invalid battle lineup"; return
        }
        ownTeam = team; localReady = true; error = nil
        var message = wire("ready"); message.mode = mode; message.team = team; send(message)
        beginIfReady()
    }
    func unready() {
        guard phase == .connected else { return }
        clearReady(resetRegistration: false); send(wire("unready"))
    }
    private func clearReady(resetRegistration: Bool = true) {
        localReady = false; remoteReady = false; ownTeam = []; peerTeam = []
        if resetRegistration { registeredTeam = []; opponentRoster = [] }
    }
    private func beginIfReady() {
        guard localReady, remoteReady, phase == .connected else { return }
        phase = .preparing; startedAt = Date(); outcome = nil; frame = nil; presentation.reset(); submitted = false
        onBattleWindow?()
        if isHost {
            do {
                let engine = BattleEngineProcess(); self.engine = engine
                try engine.start(mode: mode, teams: [ownTeam, peerTeam])
                engine.onFrames = { [weak self] frames in self?.engineFrames(frames) }
                engine.onFailure = { [weak self] reason in self?.engineFailed(reason) }
                engine.onExit = { [weak self] reason in self?.abort(reason) }
            } catch { engineFailed(error.localizedDescription) }
        }
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.phase == .preparing else { return }
            self.engineFailed("The battle engine did not start. Try again.")
        }
    }
    private func abort(_ reason: String) {
        error = reason
        var message = wire("abort"); message.reason = reason; send(message)
        finish(winner: -1, reason: "engineFailure")
    }
    private func engineFailed(_ reason: String) {
        error = reason
        var message = wire("error"); message.reason = reason; send(message)
        if phase == .preparing {
            phase = .connected; clearReady(resetRegistration: false); engine?.stop(); engine = nil; onStopMusic?()
        } else if phase == .playing {
            // A rejected choice is retryable; keep the engine and refresh both legal requests.
            submitted = false; pending = nil; pendingNonce = nil; commitments = [:]; reveals = [:]
            if !latestFrames.isEmpty { timerKey = ""; engineFrames(latestFrames) }
        }
    }
    private func engineFrames(_ frames: [BattleFrame]) {
        guard frames.count == 2, isActive else { return }
        latestFrames = frames
        armDecisionTimer()
        apply(frames[0])
        var message = wire("frame"); message.frame = frames[1]; message.deadline = decisionDeadline; send(message)
    }
    private func armDecisionTimer() {
        guard isHost, latestFrames.count == 2, !latestFrames[0].ended else { return }
        let key = latestFrames.map(\.decisionID).joined(separator: "/")
        guard key != timerKey else { return }
        timerKey = key; decisionTimer?.cancel()
        let previousID = (frame?.logOffset ?? 0) + (frame?.log.count ?? 0) - 1
        let playbackAllowance = frame == nil ? 0 : latestFrames.enumerated().map { player, next in
            BattlePresentationEvents(frame: next, language: .en, ownPlayer: player).events
                .filter { $0.id > previousID }.reduce(0.0) { total,event in
                    total + max(BattleEffectsLayer.presentationDuration(event),PokeRogueOriginalCatalog.shared.estimatedDuration(event))
                }
        }.max() ?? 0
        let seconds = decisionTimeLimit + playbackAllowance
        decisionDeadline = Date().addingTimeInterval(seconds)
        decisionTimer = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.phase == .playing, self.timerKey == key else { return }
            let winner = Self.decisionTimeoutWinner(waiting: self.latestFrames.map(\.waiting),
                                                   submitted: Set(self.commitments.keys))
            var message = self.wire("timeout"); message.winner = winner; self.send(message)
            self.finish(winner: winner, reason: "timeout")
        }
    }
    static func decisionTimeoutWinner(waiting: [Bool], submitted: Set<Int>) -> Int {
        let missing = waiting.indices.filter { !waiting[$0] && !submitted.contains($0) }
        return missing.count == 1 ? 1 - missing[0] : -1
    }
    private func apply(_ next: BattleFrame) {
        timeout?.cancel(); phase = .playing
        presentation.accept(next)
        frame = next
        if lastDecision != next.decisionID {
            lastDecision = next.decisionID; submitted = false; pending = nil; pendingNonce = nil
            commitments = [:]; reveals = [:]
        }
        if next.ended { finish(winner: next.winner ?? -1, reason: endReason) }
    }
    func completePresentation() {
        presentation.finish()
        if outcome != nil { onStopMusic?() }
    }
    func choose(_ decision: BattleDecision) {
        guard phase == .playing, !submitted, frame?.decisionID == decision.decisionID,
              frame?.waiting == false else { return }
        error = nil; submitted = true; pending = decision; pendingNonce = UUID().uuidString
        let digest = Self.digest(decision, nonce: pendingNonce!, matchID: matchID)
        if isHost {
            commitments[0] = digest; reveals[0] = decision; requestRevealsIfReady()
        } else {
            var message = wire("commit"); message.digest = digest; message.reason = decision.decisionID; send(message)
        }
        // A forced replacement can request a command from just one player.
        if isHost, latestFrames[safe: 1]?.waiting == true { resolveIfReady() }
    }
    private func requestRevealsIfReady() {
        let hostWaits = latestFrames[safe: 0]?.waiting == true
        if commitments[1] != nil, commitments[0] != nil || hostWaits {
            var message = wire("revealRequest"); message.reason = latestFrames[safe: 1]?.decisionID; send(message)
        }
    }
    private func resolveIfReady() {
        guard isHost, latestFrames.count == 2 else { return }
        for player in 0...1 where !latestFrames[player].waiting {
            guard reveals[player] != nil else { return }
        }
        decisionTimer?.cancel()
        let choices = reveals
        commitments = [:]; reveals = [:]
        do {
            for player in 0...1 {
                if let choice = choices[player] { try engine?.choose(player: player, decision: choice) }
            }
        } catch { engineFailed(error.localizedDescription) }
    }
    static func digest(_ decision: BattleDecision, nonce: String, matchID: String) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(decision)) ?? Data()
        return SHA256.hash(data: Data((matchID + ":" + nonce + ":").utf8) + data).map { String(format: "%02x", $0) }.joined()
    }
    func surrender() {
        guard isActive else { return }
        send(wire("surrender"))
        finish(winner: 1 - localPlayer, reason: "surrender")
        // Keep the reliable channel alive long enough for the opponent to persist the result.
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }; self?.releaseConnection()
        }
    }
    private func finish(winner: Int, reason: String) {
        guard phase != .ended else { return }
        outcome = winner == -1 ? (reason == "completed" ? "draw" : "interrupted") : winner == localPlayer ? "win" : "loss"
        phase = .ended; submitted = true
        if reason != "completed" { presentation.finish() }
        if !presentation.pending { onStopMusic?() }
        timeout?.cancel(); decisionTimer?.cancel(); decisionDeadline = nil
        if let opponent {
            history.append(BattleRecord(id: matchID, opponentCode: opponent.code, opponentName: opponent.nickname,
                mode: mode, startedAt: startedAt, endedAt: Date(), result: outcome!, reason: reason,
                team: Array(ownTeam.prefix(mode.battleSize)), turns: frame?.turn ?? 0))
        }
        engine?.stop(); engine = nil
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.releaseConnection()
        }
    }
    private func disconnected() {
        guard phase != .ended, phase != .idle, phase != .searching else { return }
        if isActive {
            phase = .reconnecting; onStopMusic?(); decisionTimer?.cancel(); decisionDeadline = nil
            transport?.startReconnectionDiscovery()
            reconnectTimer?.cancel()
            reconnectTimer = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.phase == .reconnecting else { return }
                    if self.isHost, let peer = self.peers.first(where: { $0.code == self.opponent?.code }) {
                        try? self.transport?.connect(to: peer)
                    }
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                }
            }
            timeout?.cancel()
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.phase == .reconnecting else { return }
                self.finish(winner: -1, reason: "disconnected")
            }
        } else {
            releaseConnection(); phase = .idle; clearReady(); opponent = nil; selectedPeer = nil; peers = []
            error = "The opponent disconnected."
        }
    }
    func cancelLobby() {
        guard !isActive else { return }
        if opponent != nil { send(wire("cancel")) }
        releaseConnection(); phase = .idle; clearReady(); opponent = nil; selectedPeer = nil; peers = []; error = nil
    }
    func shutdown() { if isActive { surrender() }; releaseConnection(); engine?.stop(); engine = nil }
    private func wire(_ kind: String) -> BattleWire { BattleWire(kind: kind, matchID: matchID) }
    private func send(_ message: BattleWire) {
        do {
            sentSequence += 1
            var outbound = message; outbound.sequence = sentSequence
            let data = try JSONEncoder().encode(outbound)
            if let manual { try manual.sendData(data) }
            else if let transport { try transport.sendData(data) }
        } catch { self.error = error.localizedDescription }
    }
    private func releaseConnection() {
        timeout?.cancel(); timeout = nil
        decisionTimer?.cancel(); decisionTimer = nil
        reconnectTimer?.cancel(); reconnectTimer = nil
        linkGeneration = UUID()
        transport?.onPeerFound = nil; transport?.onPeerLost = nil
        transport?.onDisconnected = nil; transport?.onDataReceived = nil; transport?.onConnected = nil
        transport?.stopDiscovery(); transport?.disconnect(); transport = nil
        manual?.onDisconnected = nil; manual?.onDataReceived = nil; manual?.onConnected = nil
        manual?.disconnect(); manual = nil; manualCode = nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
