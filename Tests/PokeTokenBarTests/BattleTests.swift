import AVFoundation
import CryptoKit
import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private final class MemoryBattleLink: BattleLink, @unchecked Sendable {
    var onPeerFound: (@Sendable (TradePeer) -> Void)?
    var onPeerLost: (@Sendable (String) -> Void)?
    var onConnected: (@Sendable () -> Void)?
    var onDisconnected: (@Sendable () -> Void)?
    var onDataReceived: (@Sendable (Data) -> Void)?
    weak var other: MemoryBattleLink?
    var sent: [BattleWire] = []
    var starts = 0, stops = 0, pauses = 0
    func startDiscovery() { starts += 1 }
    func stopDiscovery() { stops += 1 }
    func pauseDiscovery() { pauses += 1 }
    func connect(to peer: TradePeer) throws { onConnected?(); other?.onConnected?() }
    func sendData(_ data: Data) throws {
        sent.append(try JSONDecoder().decode(BattleWire.self, from: data))
        let callback = other?.onDataReceived
        DispatchQueue.main.async { callback?(data) }
    }
    func disconnect() {}
}

@MainActor
final class BattleTests: XCTestCase {
    private var coordinators: [BattleCoordinator] = []
    private var paths: [URL] = []
    private var suites: [String] = []
    private func cleanup() {
        coordinators.forEach { $0.shutdown() }; coordinators = []
        paths.forEach { if FileManager.default.fileExists(atPath: $0.path) { try? FileManager.default.removeItem(at: $0) } }; paths = []
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }; suites = []
    }
    private func temporaryFile() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("battle-test-\(UUID()).json")
        paths.append(url); return url
    }
    private func defaults(code: String) throws -> UserDefaults {
        let suite = "BattleTests.\(UUID())"; suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(code, forKey: "tradeCode"); defaults.set(code, forKey: "tradeNickname")
        return defaults
    }
    func testMatchingContinuesPastFormerTimeoutAndStopsOnSelectionOrCancel() async throws {
        defer { cleanup() }
        let link = MemoryBattleLink()
        let battle = BattleCoordinator(defaults: try defaults(code: "AAAA"), history: BattleHistoryStore(url: temporaryFile()), linkFactory: { _, _ in link })
        coordinators.append(battle)
        battle.search()
        let first = TradePeer(id: "B", nickname: "B", code: "BBBB", discoveryGroup: "singles")
        let second = TradePeer(id: "C", nickname: "C", code: "CCCC", discoveryGroup: "singles")
        link.onPeerFound?(first); link.onPeerFound?(first)
        link.onPeerFound?(TradePeer(id: "busy", nickname: "busy", code: "DDDD", isAvailable: false, discoveryGroup: "singles"))
        try await wait { battle.peers.count == 1 }
        try await Task.sleep(for: .milliseconds(10_200))
        XCTAssertEqual(battle.phase, .searching)
        XCTAssertNil(battle.manualCode, "Search must not automatically switch to manual after ten seconds")
        XCTAssertEqual(link.starts, 1); XCTAssertEqual(link.pauses, 0); XCTAssertEqual(link.stops, 0)
        link.onPeerFound?(second)
        try await wait { battle.peers.count == 2 }
        link.onPeerLost?(second.id)
        try await wait { battle.peers.count == 1 }
        let staleFound = link.onPeerFound, staleConnected = link.onConnected, staleLost = link.onPeerLost
        battle.select(first)
        XCTAssertEqual(battle.phase, .connecting)
        XCTAssertEqual(link.pauses, 1)
        // A delegate callback already queued before stopping browsing must not alter the list.
        staleFound?(second); staleLost?(first.id)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(battle.peers.map(\.id), [first.id])
        battle.cancelLobby()
        XCTAssertEqual(battle.phase, .idle); XCTAssertTrue(battle.peers.isEmpty); XCTAssertNil(battle.selectedPeer)
        XCTAssertEqual(link.stops, 1)
        battle.search()
        staleFound?(second); staleConnected?()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(battle.phase, .searching); XCTAssertTrue(battle.peers.isEmpty)
        link.onPeerFound?(second)
        try await wait { battle.peers.count == 1 }
        battle.cancelLobby()
        XCTAssertEqual(link.stops, 2); XCTAssertTrue(battle.peers.isEmpty)
        XCTAssertFalse(link.sent.contains { $0.kind == "cancel" }, "An unpaired search must not send on an unconnected transport")
        XCTAssertNil(battle.error)
    }
    func testMatchingSelectionStopsDiscoveryForBothParticipants() async throws {
        defer { cleanup() }
        let (a, b, left, right) = try await connectedPair(mode: .singles)
        XCTAssertEqual(a.phase, .connected); XCTAssertEqual(b.phase, .connected)
        XCTAssertGreaterThanOrEqual(left.pauses, 1); XCTAssertEqual(right.pauses, 1)
        left.onPeerFound?(TradePeer(id: "C", nickname: "C", code: "CCCC", discoveryGroup: "singles"))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(a.peers.contains { $0.code == "CCCC" })
        a.cancelLobby()
        try await wait { b.phase == .idle }
        XCTAssertEqual(a.phase, .idle)
        XCTAssertTrue(left.sent.contains { $0.kind == "cancel" })
        XCTAssertEqual(left.stops, 1); XCTAssertEqual(right.stops, 1)
        XCTAssertEqual(left.starts, 1); XCTAssertEqual(right.starts, 1)
    }
    func testDifferentRequestedModesCannotCompleteHandshake() async throws {
        defer { cleanup() }
        let left=MemoryBattleLink(),right=MemoryBattleLink();left.other=right;right.other=left
        let a=BattleCoordinator(defaults:try defaults(code:"AAAA"),history:BattleHistoryStore(url:temporaryFile()),linkFactory:{_,_ in left})
        let b=BattleCoordinator(defaults:try defaults(code:"BBBB"),history:BattleHistoryStore(url:temporaryFile()),linkFactory:{_,_ in right})
        coordinators += [a,b];b.setMode(.doubles);a.search();b.search()
        // A direct/manual connection bypasses the discovery list entirely.
        left.onConnected?();right.onConnected?()
        try await Task.sleep(for:.milliseconds(150))
        XCTAssertNil(a.opponent);XCTAssertNil(b.opponent)
        XCTAssertEqual(a.mode,.singles);XCTAssertEqual(b.mode,.doubles)
        XCTAssertEqual(a.phase,.idle);XCTAssertEqual(b.phase,.idle)
        XCTAssertTrue(a.history.records.isEmpty);XCTAssertTrue(b.history.records.isEmpty)
    }
    func testMatchingListsOnlyRequestedModeAndRestartsWithoutOldCallbacks() async throws {
        defer { cleanup() }
        var links:[MemoryBattleLink]=[],requested:[BattleMode]=[]
        let battle=BattleCoordinator(defaults:try defaults(code:"AAAA"),history:BattleHistoryStore(url:temporaryFile()),linkFactory:{_,mode in
            let link=MemoryBattleLink();links.append(link);requested.append(mode);return link
        })
        coordinators.append(battle);battle.search()
        for mode in [BattleMode.singles,.doubles,.singles] {
            let old=links.last!,staleFound=old.onPeerFound,staleConnected=old.onConnected
            battle.setMode(mode)
            let link=links.last!
            if old !== link {
                XCTAssertEqual(old.stops,1);XCTAssertTrue(battle.peers.isEmpty)
                staleFound?(TradePeer(id:"stale",nickname:"stale",code:"CCCC",discoveryGroup:mode.rawValue));staleConnected?()
            }
            let same=TradePeer(id:"same",nickname:"same",code:"BBBB",discoveryGroup:mode.rawValue)
            link.onPeerFound?(same)
            link.onPeerFound?(TradePeer(id:"other",nickname:"other",code:"CCCC",discoveryGroup:mode == .singles ? "doubles":"singles"))
            link.onPeerFound?(TradePeer(id:"legacy",nickname:"legacy",code:"DDDD"))
            link.onPeerFound?(TradePeer(id:"unknown",nickname:"unknown",code:"EEEE",discoveryGroup:"unknown"))
            link.onPeerFound?(TradePeer(id:"busy",nickname:"busy",code:"FFFF",isAvailable:false,discoveryGroup:mode.rawValue))
            try await Task.sleep(for:.milliseconds(50))
            XCTAssertEqual(battle.phase,.searching);XCTAssertEqual(battle.peers,[same])
            link.onPeerFound?(TradePeer(id:"same",nickname:"same",code:"BBBB",discoveryGroup:mode == .singles ? "doubles":"singles"))
            try await wait { battle.peers.isEmpty }
            XCTAssertEqual(link.starts,1)
        }
        XCTAssertEqual(requested,[.singles,.doubles,.singles])
    }
    func testWrongModeAndLegacyRowsCannotBeSelected() async throws {
        defer { cleanup() }
        for mode in BattleMode.allCases {
            let link=MemoryBattleLink()
            let battle=BattleCoordinator(defaults:try defaults(code:"AAAA"),history:BattleHistoryStore(url:temporaryFile()),linkFactory:{_,_ in link})
            coordinators.append(battle);battle.setMode(mode);battle.search()
            for peer in [TradePeer(id:"other",nickname:"other",code:"BBBB",discoveryGroup:mode == .singles ? "doubles":"singles"),TradePeer(id:"old",nickname:"old",code:"CCCC"),TradePeer(id:"busy",nickname:"busy",code:"DDDD",isAvailable:false,discoveryGroup:mode.rawValue)] {
                battle.select(peer)
                XCTAssertEqual(battle.phase,.searching);XCTAssertNil(battle.selectedPeer);XCTAssertEqual(link.pauses,0)
            }
            battle.select(TradePeer(id:"valid",nickname:"valid",code:"EEEE",discoveryGroup:mode.rawValue))
            XCTAssertEqual(battle.phase,.connecting);XCTAssertEqual(link.pauses,1)
        }
    }
    func testMatchingHelloCarriesModeAndMatchedFormatCannotChange() async throws {
        defer { cleanup() }
        for mode in BattleMode.allCases {
            let (a,b,left,right)=try await connectedPair(mode:mode)
            XCTAssertEqual(left.sent.first{$0.kind=="hello"}?.mode,mode)
            XCTAssertEqual(right.sent.first{$0.kind=="hello"}?.mode,mode)
            XCTAssertFalse(a.canEditMode);XCTAssertFalse(b.canEditMode)
            let other:BattleMode=mode == .singles ? .doubles:.singles
            a.setMode(other);b.setMode(other)
            var oldModePacket=BattleWire(kind:"mode",matchID:[a.identity.nonce,b.identity.nonce].sorted().joined(separator:":"))
            oldModePacket.mode=other;oldModePacket.sequence=100
            right.onDataReceived?(try JSONEncoder().encode(oldModePacket))
            try await Task.sleep(for:.milliseconds(50))
            XCTAssertEqual(a.mode,mode);XCTAssertEqual(b.mode,mode)
            // The injected legacy packet deliberately advanced the receiver sequence.
            a.cancelLobby();b.cancelLobby()
            XCTAssertEqual(a.phase,.idle);XCTAssertEqual(b.phase,.idle)
            a.setMode(other);b.setMode(other)
            XCTAssertEqual(a.mode,other);XCTAssertEqual(b.mode,other)
        }
    }
    func testHelloWithoutRequestedModeIsRejected() async throws {
        defer { cleanup() }
        let link=MemoryBattleLink()
        let battle=BattleCoordinator(defaults:try defaults(code:"AAAA"),history:BattleHistoryStore(url:temporaryFile()),linkFactory:{_,_ in link})
        coordinators.append(battle);battle.search();link.onConnected?()
        try await wait { battle.phase == .connected }
        var hello=BattleWire(kind:"hello")
        hello.identity=BattleIdentity(nickname:"old",code:"BBBB",nonce:UUID().uuidString)
        link.onDataReceived?(try JSONEncoder().encode(hello))
        try await wait { battle.phase == .idle }
        XCTAssertNil(battle.opponent);XCTAssertEqual(battle.error,"Battle mode mismatch")
        for language in AppLanguage.allCases {XCTAssertNotEqual(L(language).battleUserError(battle.error!),battle.error)}
    }
    private func team(_ prefix: String, mode: BattleMode) -> [BattlePokemon] {
        (0..<mode.teamSize).map { i in
            BattlePokemon(id: "\(prefix)\(i)", speciesID: [26,181,310,101,587,618][i], species: ["Raichu","Ampharos","Manectric","Electrode","Emolga","Stunfisk"][i], displayName: "Pikachu",
                level: 37, ability: "static", nature: "hardy", gender: "M", shiny: false, form: nil,
                ivs: ["hp":17,"atk":17,"def":17,"spa":17,"spd":17,"spe":17],
                stats: ["hp":143,"atk":91,"def":87,"spa":96,"spd":89,"spe":107], moves: ["thunderbolt","protect","quick-attack","volt-switch"])
        }
    }
    private func wait(_ condition: () -> Bool, seconds: Double = 10, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition(), file: file, line: line)
        if !condition() { throw BattleFailure.invalidMessage }
    }
    private func connectedPair(mode: BattleMode, decisionTimeLimit: TimeInterval = 60) async throws -> (BattleCoordinator, BattleCoordinator, MemoryBattleLink, MemoryBattleLink) {
        guard FileManager.default.isExecutableFile(atPath: BattleEngineProcess.runtimeURL.path) else {
            throw XCTSkip("Run scripts/prepare-battle-engine.sh before the engine integration tests")
        }
        let left = MemoryBattleLink(), right = MemoryBattleLink()
        left.other = right; right.other = left
        let a = BattleCoordinator(defaults: try defaults(code: "AAAA"), history: BattleHistoryStore(url: temporaryFile()), decisionTimeLimit:decisionTimeLimit, linkFactory: { _, _ in left })
        let b = BattleCoordinator(defaults: try defaults(code: "BBBB"), history: BattleHistoryStore(url: temporaryFile()), decisionTimeLimit:decisionTimeLimit, linkFactory: { _, _ in right })
        coordinators += [a,b]
        a.setMode(mode); b.setMode(mode); a.search(); b.search()
        a.select(TradePeer(id: "BBBB", nickname: "BBBB", code: "BBBB", discoveryGroup: mode.rawValue))
        try await wait { a.opponent != nil && b.opponent != nil && b.mode == mode }
        left.onPeerFound?(TradePeer(id: "BBBB", nickname: "BBBB", code: "BBBB", discoveryGroup: mode.rawValue))
        right.onPeerFound?(TradePeer(id: "AAAA", nickname: "AAAA", code: "AAAA", discoveryGroup: mode.rawValue))
        return (a,b,left,right)
    }
    private func registerPair(_ a: BattleCoordinator, _ b: BattleCoordinator, _ own: [BattlePokemon], _ foe: [BattlePokemon]) async throws {
        a.register(team: own); b.register(team: foe)
        try await wait { a.canSelectLineup && b.canSelectLineup }
        XCTAssertFalse(a.isActive); XCTAssertFalse(b.isActive)
    }
    private func pair(mode: BattleMode, decisionTimeLimit: TimeInterval = 60) async throws -> (BattleCoordinator, BattleCoordinator, MemoryBattleLink, MemoryBattleLink) {
        let (a,b,left,right) = try await connectedPair(mode: mode,decisionTimeLimit:decisionTimeLimit)
        try await registerPair(a,b,team("a",mode:mode),team("b",mode:mode))
        a.ready(team: team("a", mode: mode))
        try await wait { b.remoteReady }
        XCTAssertFalse(a.isActive, "one participant's consent cannot start a match")
        b.ready(team: team("b", mode: mode))
        do { try await wait { a.frame != nil && b.frame != nil } }
        catch {
            XCTFail("Engine startup: A=\(a.error ?? "none") B=\(b.error ?? "none") phases=\(a.phase)/\(b.phase)")
            throw error
        }
        return (a,b,left,right)
    }
    private func chooseLeads(_ a: BattleCoordinator, _ b: BattleCoordinator) async throws {
        for c in [a,b] {
            let frame = try XCTUnwrap(c.frame)
            if frame.preview { c.choose(BattleDecision(decisionID: frame.decisionID, actions: [], order: Array(1...frame.own.count))) }
        }
        try await wait { a.frame?.preview == false && b.frame?.preview == false }
    }
    func testWeatherAndFieldStateReachBothClientsInSinglesAndDoubles() async throws {
        defer { cleanup() }
        for mode in BattleMode.allCases {
            func roster(_ prefix: String) -> [BattlePokemon] {
                team(prefix,mode:mode).enumerated().map { i, p in
                    BattlePokemon(id:p.id,speciesID:p.speciesID,species:p.species,displayName:p.displayName,level:p.level,
                        ability:p.ability,nature:p.nature,gender:p.gender,shiny:p.shiny,form:p.form,ivs:p.ivs,stats:p.stats,
                        moves:prefix == "a" && i == 0 ? ["sunny-day","gravity","reflect","tailwind"] : ["amnesia"])
                }
            }
            let (a,b,left,_) = try await connectedPair(mode:mode)
            try await registerPair(a,b,roster("a"),roster("b"))
            a.ready(team:roster("a")); try await wait { b.remoteReady }; b.ready(team:roster("b"))
            try await wait { a.frame != nil && b.frame != nil }
            for index in 1...4 {
                let old = a.frame!.turn
                for c in [a,b] {
                    let f = c.frame!
                    c.choose(BattleDecision(decisionID:f.decisionID,actions:f.slots.map { slot in
                        .init(kind:"move",index:c === a && slot.slot == 0 ? index : 1,target:0)
                    },order:[]))
                }
                try await wait { (a.frame?.turn ?? 0) > old && (b.frame?.turn ?? 0) > old }
                let own = try XCTUnwrap(a.frame?.field), foe = try XCTUnwrap(b.frame?.field)
                XCTAssertEqual(own.weather,"sunnyday")
                XCTAssertEqual(own.weather,foe.weather); XCTAssertEqual(own.conditions,foe.conditions)
                XCTAssertEqual(own.ownSide,foe.foeSide); XCTAssertEqual(own.foeSide,foe.ownSide)
                if index >= 2 { XCTAssertTrue(own.conditions.contains("gravity")) }
                if index >= 3 { XCTAssertTrue(own.ownSide.contains { $0.id == "reflect" }) }
                if index == 4 { XCTAssertTrue(own.ownSide.contains { $0.id == "tailwind" }) }
                XCTAssertEqual(left.sent.last(where:{ $0.kind == "frame" })?.frame?.field,foe)
                XCTAssertNil(a.error); XCTAssertNil(b.error)
            }
            a.shutdown(); b.shutdown()
        }
    }
    func testPublicRosterWireRejectsDuplicateRegistrationAndUnregisteredOrChangedReadyTeams() async throws {
        defer { cleanup() }
        for mode in BattleMode.allCases {
            for scenario in ["duplicate", "early", "changed", "reregister", "unregister"] {
                let (a,b,left,right) = try await connectedPair(mode: mode)
                let own = team("a", mode: mode), foe = team("b", mode: mode)
                if ["changed", "reregister", "unregister"].contains(scenario) { try await registerPair(a,b,own,foe) }
                var packet = BattleWire(kind: scenario == "unregister" ? "unregister" : ["duplicate", "reregister"].contains(scenario) ? "roster" : "ready")
                packet.matchID = [a.identity.nonce,b.identity.nonce].sorted().joined(separator:":")
                packet.sequence = 100; packet.mode = mode
                if scenario == "duplicate" {
                    var roster = foe.map(BattleRosterMember.init); roster[1] = roster[0]; packet.roster = roster
                } else if scenario == "reregister" {
                    packet.roster = foe.reversed().map(BattleRosterMember.init)
                } else { packet.team = scenario == "changed" ? team("unregistered", mode: mode) : foe }
                try right.sendData(JSONEncoder().encode(packet))
                try await wait { a.error != nil }
                XCTAssertFalse(a.remoteReady); XCTAssertFalse(a.isActive)
                if scenario == "duplicate" { XCTAssertTrue(a.opponentRoster.isEmpty) }
                if ["reregister", "unregister"].contains(scenario) {
                    XCTAssertEqual(a.opponentRoster, foe.map(BattleRosterMember.init), "Peer packets must not change a registered six")
                    XCTAssertEqual(a.registeredTeam, own)
                }
                a.shutdown(); b.shutdown()
            }
        }
    }
    func testDuplicateItemsAreBlockedAtRegistrationReadyAndIncomingConsent() async throws {
        defer{cleanup()}
        for mode in BattleMode.allCases {
            let (a,b,left,_)=try await connectedPair(mode:mode)
            var own=team("a",mode:mode),foe=team("b",mode:mode)
            own[0].item="Leftovers";own[5].item="leftovers"
            a.register(team:own)
            XCTAssertTrue(a.registeredTeam.isEmpty);XCTAssertEqual(a.error,"Duplicate held item")
            XCTAssertFalse(left.sent.contains{$0.kind=="roster"})
            own[5].item="lifeorb";foe[0].item="leftovers"
            try await registerPair(a,b,own,foe)
            var duplicate=own;duplicate[5].item="leftovers"
            a.ready(team:duplicate)
            XCTAssertFalse(a.localReady);XCTAssertFalse(left.sent.contains{$0.kind=="ready"})
            a.shutdown();b.shutdown()
            let (c,d,_,peer)=try await connectedPair(mode:mode)
            try await registerPair(c,d,own,foe)
            d.ready(team:foe);try await wait{c.remoteReady}
            XCTAssertNil(c.error)
            var incoming=try XCTUnwrap(peer.sent.last{$0.kind=="ready"})
            incoming.sequence += 1;var changed=foe;changed[5].item="leftovers";incoming.team=changed
            try peer.sendData(JSONEncoder().encode(incoming))
            try await wait{c.error != nil}
            XCTAssertFalse(c.isActive);XCTAssertNil(c.frame)
            XCTAssertEqual(L(.ko).battleUserError(c.error!),L(.ko).battleDuplicateItem)
            c.shutdown();d.shutdown()
        }
    }
    func testPublicSixMemberRegistrationPrecedesPrivateLineupConsentAndStaysLocked() async throws {
        defer { cleanup() }
        for mode in BattleMode.allCases {
            let (a,b,left,_) = try await connectedPair(mode: mode)
            let own = team("a", mode: mode), foe = team("b", mode: mode)
            a.ready(team: own)
            XCTAssertFalse(a.localReady); XCTAssertNil(a.frame)
            a.register(team: own)
            try await wait { b.opponentRoster.count == 6 }
            XCTAssertFalse(a.canSelectLineup); XCTAssertFalse(b.canSelectLineup)
            a.ready(team: own)
            XCTAssertFalse(a.localReady, "Own registration alone must not permit final lineup consent")
            XCTAssertFalse(left.sent.contains { $0.kind == "ready" })
            let packet = try XCTUnwrap(left.sent.last { $0.kind == "roster" })
            XCTAssertNil(packet.team)
            let json = try XCTUnwrap(String(data: JSONEncoder().encode(packet), encoding: .utf8))
            for key in ["stats", "ivs", "moves", "ability", "nature"] { XCTAssertFalse(json.contains("\"\(key)\""), key) }
            b.register(team: foe)
            try await wait { a.canSelectLineup && b.canSelectLineup }
            XCTAssertFalse(a.isActive); XCTAssertFalse(b.isActive)
            XCTAssertEqual(a.opponentRoster, foe.map(BattleRosterMember.init))
            a.ready(team: Array(own.reversed()))
            try await wait { b.remoteReady }
            XCTAssertFalse(b.isActive)
            XCTAssertEqual(b.opponentRoster, own.map(BattleRosterMember.init), "Final order must not mark or reorder the public preview")
            b.register(team: Array(foe.reversed()))
            XCTAssertEqual(b.registeredTeam, foe, "Registered six are immutable")
            XCTAssertTrue(b.remoteReady, "A rejected registration edit must not reset readiness")
            b.unready()
            try await wait { !a.localReady && !b.remoteReady }
            XCTAssertEqual(a.registeredTeam, own)
            XCTAssertEqual(a.opponentRoster, foe.map(BattleRosterMember.init))
            XCTAssertTrue(a.canSelectLineup)
            a.ready(team: Array(own.reversed())); try await wait { b.remoteReady }
            b.ready(team: foe)
            try await wait { a.frame != nil && b.frame != nil }
            XCTAssertEqual(a.frame?.own.map(\.id), Array(own.reversed().prefix(mode.battleSize)).map(\.id))
            a.surrender(); try await wait { b.outcome == "win" }
            a.shutdown(); b.shutdown()
        }
    }
    func testRegisteredSixCanSelectNonPrefixLineupsAndOnlySelectedMembersEnterBothClients() async throws {
        defer { cleanup() }
        for mode in BattleMode.allCases {
            let (a,b,_,_) = try await connectedPair(mode: mode)
            let rosterA = team("a", mode: mode), rosterB = team("b", mode: mode)
            let chosenA = Array(rosterA.reversed().prefix(mode.battleSize)).map(\.id)
            let chosenB = Array(rosterB.dropFirst().prefix(mode.battleSize)).map(\.id)
            func ordered(_ roster: [BattlePokemon], _ lineup: [String]) throws -> [BattlePokemon] {
                try BattleTeamBuilder.orderedRoster(roster.map(\.id), lineup: lineup, mode: mode).map { id in roster.first { $0.id == id }! }
            }
            try await registerPair(a,b,rosterA,rosterB)
            a.ready(team: try ordered(rosterA, chosenA)); try await wait { b.remoteReady }
            b.ready(team: try ordered(rosterB, chosenB)); try await wait { a.frame != nil && b.frame != nil }
            XCTAssertEqual(a.ownTeam.count, 6)
            XCTAssertEqual(a.frame?.own.map(\.id), chosenA)
            XCTAssertEqual(b.frame?.own.map(\.id), chosenB)
            XCTAssertEqual(a.frame?.own.filter(\.active).map(\.id), Array(chosenA.prefix(mode == .singles ? 1 : 2)))
            XCTAssertEqual(a.frame?.foe.count, mode == .singles ? 1 : 2)
            a.surrender(); try await wait { b.outcome == "win" }
            XCTAssertEqual(a.history.records.first?.team.map(\.id), chosenA)
            a.shutdown(); b.shutdown()
        }
    }
    func testBattleLineupOrderingRequiresExactlyThreeOrFourFromRegisteredSix() throws {
        let roster = (0..<6).map { "id\($0)" }
        for mode in BattleMode.allCases {
            let lineup = Array(roster.reversed().prefix(mode.battleSize))
            let ordered = try BattleTeamBuilder.orderedRoster(roster, lineup: lineup, mode: mode)
            XCTAssertEqual(Array(ordered.prefix(mode.battleSize)), lineup)
            XCTAssertEqual(Set(ordered), Set(roster))
            XCTAssertThrowsError(try BattleTeamBuilder.orderedRoster(roster, lineup: roster, mode: mode))
            XCTAssertThrowsError(try BattleTeamBuilder.orderedRoster(roster, lineup: Array(lineup.dropLast()), mode: mode))
            XCTAssertThrowsError(try BattleTeamBuilder.orderedRoster(roster, lineup: Array(repeating: roster[0], count: mode.battleSize), mode: mode))
            XCTAssertThrowsError(try BattleTeamBuilder.orderedRoster(roster, lineup: ["foreign"] + lineup.dropFirst(), mode: mode))
        }
    }
    func testSavedLoadoutReachesBringSixPickThreeSinglesMechanics() async throws {
        defer { cleanup() }
        try await verifySavedLoadoutInBattle(mode: .singles)
    }
    func testSavedLoadoutReachesBringSixPickFourDoublesMechanics() async throws {
        defer { cleanup() }
        try await verifySavedLoadoutInBattle(mode: .doubles)
    }
    private func verifySavedLoadoutInBattle(mode: BattleMode) async throws {
        let provider = SelectedLoadoutBattleDetails()
        func ownedStore(_ prefix: String, ids: [Int]) async throws -> CompanionStore {
            var state = CompanionState()
            for id in ids {
                let details = try await provider.pokemonDetails(speciesID: id)
                var profile = PokemonProfile.generate(seed: UInt64(id))
                profile.level = 50
                let ability = SelectedLoadoutBattleDetails.originalAbility[id]!
                let option = try XCTUnwrap(details.abilities.first { $0.name == ability })
                profile.abilityName = option.name; profile.abilitySlot = option.slot; profile.abilityIsHidden = option.isHidden
                profile.moves = [.init(name: "return", learnedAtLevel: 0), .init(name: "protect", learnedAtLevel: 0)]
                profile.enrich(with: details)
                state.dex.append(DexEntry(id: "\(prefix)-\(id)", baseID: id, finalID: id, chainOrder: [id], rarity: .common,
                                caughtAt: Date(), nature: .hardy, profile: profile))
            }
            let file = temporaryFile()
            try JSONEncoder().encode(state).write(to: file)
            let preferences = try defaults(code: prefix)
            let store = CompanionStore(detailProvider: provider, fileURL: file, defaults: preferences)
            for id in ids { await store.loadPokemonDetails(speciesID: id) }
            let moves = [130: "dragon-rage", 26: "tail-whip", 59: "flamethrower", 80: "amnesia", 134: "surf", 212: "bullet-punch"]
            let abilities = [130: "Moxie", 26: "Lightning Rod", 59: "Intimidate", 80: "Regenerator", 134: "Hydration", 212: "Technician"]
            for id in ids {
                // These are exactly the mutation APIs used by the collection menus.
                XCTAssertTrue(store.setPokemonMove(entryID: "\(prefix)-\(id)", slot: 0, name: moves[id]!))
                XCTAssertTrue(store.setPokemonAbility(entryID: "\(prefix)-\(id)", name: abilities[id]!))
            }
            if prefix == "a" {
                XCTAssertTrue(store.setPokemonMove(entryID: "a-130", slot: 1, name: "dragon-dance"))
                XCTAssertTrue(store.setPokemonMove(entryID: "a-130", slot: 2, name: "protect"))
                XCTAssertTrue(store.setPokemonMove(entryID: "a-130", slot: 3, name: "waterfall"))
            }
            let restored = CompanionStore(detailProvider: provider, fileURL: file, defaults: preferences)
            for id in ids { await restored.loadPokemonDetails(speciesID: id) }
            XCTAssertEqual(restored.state.dex.map(\.profile), store.state.dex.map(\.profile))
            XCTAssertTrue(restored.state.dex.allSatisfy { $0.profile?.hasCustomAbility == true && $0.profile?.hasCustomMoves == true })
            return restored
        }
        let storeA = try await ownedStore("a", ids: [130,26,59,80,134,212])
        let storeB = try await ownedStore("b", ids: [80,26,59,134,212,130])
        let savedA = storeA.state.dex.map(\.profile), savedB = storeB.state.dex.map(\.profile)
        let teamA = try await BattleTeamBuilder.build(ids: storeA.state.dex.map(\.id), entries: storeA.state.dex, mode: mode, language: .ko, provider: provider)
        let teamB = try await BattleTeamBuilder.build(ids: storeB.state.dex.map(\.id), entries: storeB.state.dex, mode: mode, language: .ko, provider: provider)
        for (entries, built) in [(storeA.state.dex, teamA), (storeB.state.dex, teamB)] {
            XCTAssertEqual(built.count, 6)
            for (entry, mon) in zip(entries, built) {
                let profile = try XCTUnwrap(entry.profile)
                XCTAssertEqual(mon.moves, profile.moves.map(\.name))
                XCTAssertEqual(BattleTextCatalog.key(mon.ability), BattleTextCatalog.key(profile.abilityName!))
                XCTAssertEqual(mon.level, profile.level); XCTAssertEqual(mon.nature, entry.nature!.rawValue)
            }
        }
        let (a,b,left,right) = try await connectedPair(mode: mode)
        try await registerPair(a,b,teamA,teamB)
        a.ready(team: teamA); try await wait { b.remoteReady }; b.ready(team: teamB)
        try await wait { a.frame != nil && b.frame != nil }
        XCTAssertEqual(left.sent.first { $0.kind == "ready" }?.team, teamA)
        XCTAssertEqual(right.sent.first { $0.kind == "ready" }?.team, teamB)
        XCTAssertEqual(a.frame?.own.count, mode.battleSize); XCTAssertEqual(b.frame?.own.count, mode.battleSize)
        XCTAssertEqual(a.frame?.own.filter(\.active).count, mode == .singles ? 1 : 2)
        XCTAssertEqual(a.frame?.preview, false)
        var seen = Set<String>()
        func verifyActiveMoves() throws {
            let frame = try XCTUnwrap(a.frame)
            for (slot, mon) in frame.own.filter(\.active).enumerated() {
                seen.insert(mon.id)
                let expected = try XCTUnwrap(teamA.first { $0.id == mon.id })
                XCTAssertEqual(frame.slots[slot].moves.compactMap(\.apiName), expected.moves)
                XCTAssertEqual(mon.stats, expected.stats, "Owned numeric stats must remain unchanged")
            }
        }
        func action(_ coordinator: BattleCoordinator, _ name: String) throws -> BattleAction {
            let move = try XCTUnwrap(coordinator.frame?.slots.first?.moves.first { $0.apiName == name })
            return BattleAction(kind: "move", index: move.index, target: move.targetRequired ? 1 : 0)
        }
        func round(_ primaryA: BattleAction, _ primaryB: BattleAction) async throws {
            let oldTurn = a.frame!.turn
            for (coordinator, primary) in [(a,primaryA),(b,primaryB)] {
                let frame = try XCTUnwrap(coordinator.frame)
                XCTAssertFalse(frame.waiting)
                let actions = try frame.slots.map { slot -> BattleAction in
                    if slot.slot == 0 { return primary }
                    let quiet = try XCTUnwrap(slot.moves.first { $0.apiName == "tail-whip" })
                    return BattleAction(kind: "move", index: quiet.index, target: 0)
                }
                coordinator.choose(BattleDecision(decisionID: frame.decisionID, actions: actions, order: []))
            }
            try await wait {
                !a.submitted && !b.submitted &&
                ((a.frame?.turn ?? 0) > oldTurn || b.frame?.slots.contains(where: \.mustSwitch) == true)
            }
            XCTAssertNil(a.error); XCTAssertNil(b.error)
        }
        func switchTo(_ coordinator: BattleCoordinator, id: String) throws -> BattleAction {
            let index = try XCTUnwrap(coordinator.frame?.own.firstIndex { $0.id == id })
            return BattleAction(kind: "switch", index: index + 1, target: 0)
        }
        try verifyActiveMoves()
        let initialDragonPP = try XCTUnwrap(a.frame?.slots[0].moves.first { $0.apiName == "dragon-rage" }?.pp)
        try await round(action(a,"dragon-dance"), action(b,"amnesia"))
        XCTAssertEqual(a.frame?.own.first { $0.id == "a-130" }?.boosts?["atk"], 1)
        XCTAssertEqual(a.frame?.own.first { $0.id == "a-130" }?.boosts?["spe"], 1)
        let slowbroMax = try XCTUnwrap(b.frame?.own.first { $0.id == "b-80" }?.maxHP)
        for _ in 0..<2 { try await round(action(a,"dragon-rage"), action(b,"amnesia")) }
        let damaged = try XCTUnwrap(b.frame?.own.first { $0.id == "b-80" }?.hp)
        XCTAssertEqual(slowbroMax - damaged, 80, "Selected Dragon Rage must actually deal 40 per use")
        XCTAssertEqual(a.frame?.slots[0].moves.first { $0.apiName == "dragon-rage" }?.pp, initialDragonPP - 2)
        try await round(action(a,"protect"), switchTo(b,id:"b-59"))
        XCTAssertEqual(b.frame?.own.first { $0.id == "b-80" }?.hp, min(slowbroMax, damaged + slowbroMax / 3), "Selected Regenerator must heal on switching out")
        XCTAssertTrue(BattleLogText.abilityChanges(b.frame!.log, language:.ko, ownPlayer:1).contains { $0.contains("재생력") && $0.contains(L(.ko).battleEvent("-heal")) })
        XCTAssertFalse(a.frame!.log.contains { $0.contains("ability: Regenerator") })
        XCTAssertEqual(a.frame?.own.first { $0.id == "a-130" }?.boosts?["atk"], 0, "Selected Intimidate must undo one Dragon Dance Attack stage")
        if mode == .doubles { XCTAssertEqual(a.frame?.own.first { $0.id == "a-26" }?.boosts?["atk"], -1) }
        let intimidation = BattleLogText.abilityChanges(a.frame!.log, language: .ko, ownPlayer: 0)
        XCTAssertTrue(intimidation.contains { $0.contains("위협") && $0.contains(L(.ko).battleStat("atk")) })
        try await round(action(a,"protect"), switchTo(b,id:"b-80"))
        for _ in 0..<10 {
            if b.frame?.own.first(where: { $0.id == "b-80" })?.fainted == true { break }
            try await round(action(a,"dragon-rage"), action(b,"amnesia"))
        }
        XCTAssertEqual(b.frame?.own.first { $0.id == "b-80" }?.fainted, true)
        XCTAssertEqual(a.frame?.own.first { $0.id == "a-130" }?.boosts?["atk"], 1, "Selected Moxie must raise Attack after the actual knockout")
        XCTAssertTrue(BattleLogText.abilityChanges(a.frame!.log, language: .ko, ownPlayer: 0).contains { $0.contains("자기과신") })
        // Resolve the actual knockout replacement, then verify each selected battle loadout in live move requests.
        let forced = try XCTUnwrap(b.frame)
        b.choose(BattleDecision(decisionID: forced.decisionID, actions: try forced.slots.map { $0.mustSwitch ? try switchTo(b,id:"b-59") : .pass }, order: []))
        try await wait { b.frame?.slots.contains(where: \.mustSwitch) == false && b.frame?.waiting == false && a.frame?.waiting == false }
        for mon in teamA.prefix(mode.battleSize) where !seen.contains(mon.id) {
            try await round(switchTo(a,id:mon.id), action(b,"protect"))
            try verifyActiveMoves()
        }
        XCTAssertEqual(seen, Set(teamA.prefix(mode.battleSize).map(\.id)))
        XCTAssertEqual(storeA.state.dex.map(\.profile), savedA)
        XCTAssertEqual(storeB.state.dex.map(\.profile), savedB)
        b.surrender()
        try await wait { a.outcome == "win" && b.outcome == "loss" }
        XCTAssertEqual(a.history.records.first?.team, Array(teamA.prefix(mode.battleSize)))
        XCTAssertEqual(b.history.records.first?.team, Array(teamB.prefix(mode.battleSize)))
    }
    func testSinglesAndDoublesAcrossTwoClientsKeepCurrentStatsAndResolveTurns() async throws {
        defer { cleanup() }
        for mode in BattleMode.allCases {
            let (a,b,left,_) = try await pair(mode: mode)
            XCTAssertEqual(a.frame?.own[0].stats, team("x",mode:mode)[0].stats)
            XCTAssertNil(b.frame?.foe.first?.stats)
            XCTAssertEqual(a.frame?.own.count, mode.battleSize)
            XCTAssertEqual(b.frame?.own.count, mode.battleSize)
            XCTAssertEqual(a.frame?.preview, false)
            XCTAssertEqual(a.frame?.own.filter(\.active).map(\.id), Array(team("a",mode:mode).prefix(mode == .singles ? 1 : 2)).map(\.id))
            XCTAssertFalse(a.frame?.log.contains { $0.hasPrefix("|poke|") } ?? true)
            try await chooseLeads(a,b)
            let active = mode == .singles ? 1 : 2
            XCTAssertEqual(a.frame?.own.filter(\.active).count, active)
            for c in [a,b] {
                let f = try XCTUnwrap(c.frame)
                c.choose(BattleDecision(decisionID: f.decisionID,
                    actions: (0..<active).map { BattleAction(kind: "move", index: 1, target: mode == .singles ? 0 : $0 + 1) }, order: []))
            }
            try await wait { (a.frame?.turn ?? 0) >= 2 && (b.frame?.turn ?? 0) >= 2 }
            XCTAssertFalse(left.sent.contains { $0.kind == "reveal" && $0.decision == nil })
            XCTAssertTrue(left.sent.contains { $0.kind == "revealRequest" })
            a.surrender()
            try await wait { a.outcome == "loss" && b.outcome == "win" }
            XCTAssertEqual(a.history.records.count, 1)
            XCTAssertEqual(b.history.records.count, 1)
            XCTAssertEqual(a.history.records[0].id, b.history.records[0].id)
            a.surrender(); XCTAssertEqual(a.history.records.count, 1)
            a.shutdown(); b.shutdown()
        }
    }
    func testReadinessCanCancelButRegisteredRosterAndModeStayLockedUntilLobbyEnds() async throws {
        defer { cleanup() }
        let (a,b,_,_) = try await connectedPair(mode: .doubles)
        a.setMode(.singles);b.setMode(.singles)
        XCTAssertEqual(a.mode,.doubles);XCTAssertEqual(b.mode,.doubles)
        XCTAssertFalse(a.canEditMode);XCTAssertFalse(b.canEditMode)
        try await registerPair(a,b,team("a",mode:.doubles),team("b",mode:.doubles))
        a.ready(team:team("a",mode:.doubles)); try await wait { b.remoteReady }
        a.unready(); try await wait { !b.remoteReady }
        XCTAssertFalse(a.canEditMode)
        a.setMode(.singles); b.setMode(.singles)
        XCTAssertEqual(a.mode,.doubles); XCTAssertEqual(b.mode,.doubles)
        XCTAssertEqual(a.registeredTeam.count,6); XCTAssertEqual(b.registeredTeam.count,6)
        a.cancelLobby(); try await wait { a.phase == .idle && b.phase == .idle }
        XCTAssertTrue(a.registeredTeam.isEmpty); XCTAssertTrue(b.registeredTeam.isEmpty)
        a.setMode(.singles); XCTAssertEqual(a.mode,.singles)
    }
    func testReconnectResendsCurrentStateWithoutReplayingDamageAndIgnoresOldFrames() async throws {
        defer { cleanup() }
        let (a,b,left,right) = try await pair(mode:.singles)
        try await chooseLeads(a,b)
        for c in [a,b] {
            let f = try XCTUnwrap(c.frame)
            c.choose(BattleDecision(decisionID:f.decisionID,actions:[BattleAction(kind:"move",index:1,target:0)],order:[]))
        }
        try await wait { a.frame?.turn == 2 && b.frame?.turn == 2 }
        let hp = a.frame?.own.first?.hp
        let otherHP = b.frame?.own.first?.hp
        // Equal-speed Thunderbolts can paralyze the second mover. Either side may be the damaged one.
        XCTAssertLessThan(min(try XCTUnwrap(hp),try XCTUnwrap(otherHP)),143,"the reconnect fixture must contain actual damage")
        let old = try XCTUnwrap(left.sent.first(where: { $0.kind == "frame" }))
        left.onDisconnected?(); right.onDisconnected?()
        try await wait { left.sent.contains { $0.kind == "resume" } && right.sent.contains { $0.kind == "resume" } }
        try await wait { a.phase == .playing && b.phase == .playing }
        XCTAssertEqual(a.frame?.own.first?.hp,hp)
        XCTAssertEqual(b.frame?.own.first?.hp,otherHP)
        let currentTurn = b.frame?.turn
        right.onDataReceived?(try JSONEncoder().encode(old))
        try await Task.sleep(for:.milliseconds(60))
        XCTAssertEqual(b.frame?.turn,currentTurn)
    }
    func testRematchUsesANewIDAndResetsTheDeadlineAndCommands() async throws {
        defer { cleanup() }
        let (a,b,left,_) = try await pair(mode:.singles)
        let delayedConnection = left.onConnected
        a.surrender();try await wait { b.outcome == "win" }
        let firstID=try XCTUnwrap(a.history.records.first?.id)
        delayedConnection?()
        try await Task.sleep(for:.milliseconds(50))
        XCTAssertEqual(a.phase,.ended,"late transport callbacks must not revive a finished match")
        a.search();b.search();a.select(TradePeer(id:"BBBB",nickname:"BBBB",code:"BBBB",discoveryGroup:"singles"))
        try await wait { a.opponent != nil && b.opponent != nil }
        try await registerPair(a,b,team("a",mode:.singles),team("b",mode:.singles))
        a.ready(team:team("a",mode:.singles));try await wait { b.remoteReady }
        b.ready(team:team("b",mode:.singles))
        try await wait { a.frame != nil && b.frame != nil }
        XCTAssertFalse(a.submitted);XCTAssertFalse(b.submitted)
        XCTAssertNotNil(a.decisionDeadline);XCTAssertNotNil(b.decisionDeadline)
        a.surrender();try await wait { b.history.records.count == 2 }
        XCTAssertEqual(a.history.records.count,2)
        XCTAssertNotEqual(firstID,a.history.records.last?.id)
    }
    func testHistoryRetriesFailedWritesWithoutDroppingTheResult() throws {
        defer { cleanup() }
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("battle-parent-\(UUID())")
        paths.append(parent)
        try Data("file blocks directory".utf8).write(to:parent)
        let history = BattleHistoryStore(url:parent.appendingPathComponent("history.json"))
        let record = BattleRecord(id:"retry",opponentCode:"B",opponentName:"B",mode:.singles,startedAt:Date(),endedAt:Date(),result:"win",reason:"completed",team:[],turns:2)
        history.append(record)
        XCTAssertNotNil(history.error); XCTAssertEqual(history.records.count,1)
        try FileManager.default.removeItem(at:parent)
        history.append(record)
        XCTAssertNil(history.error)
        XCTAssertEqual(BattleHistoryStore(url:parent.appendingPathComponent("history.json")).records.count,1)
    }
    func testWindowCloseCancelKeepsBattleAndConfirmAwardsOpponentVictory() async throws {
        defer { cleanup() }
        let (a,b,_,_) = try await pair(mode: .singles)
        let profileFile = temporaryFile()
        let store = CompanionStore(fileURL: profileFile, defaults: try defaults(code: "render"))
        store.setLanguage(.ko)
        let controller = BattleWindowController(battle: a, store: store, allowsAudio: false)
        controller.show()
        let window = try XCTUnwrap(controller.window)
        window.setFrameOrigin(NSPoint(x: -10000,y: -10000))
        XCTAssertFalse(controller.windowShouldClose(window))
        let first = try XCTUnwrap(window.attachedSheet)
        func buttonTitles(_ view: NSView) -> [String] {
            if let button = view as? NSButton { return [button.title] }
            return view.subviews.flatMap(buttonTitles)
        }
        let titles = buttonTitles(try XCTUnwrap(first.contentView))
        XCTAssertTrue(titles.contains("취소"))
        XCTAssertTrue(titles.contains("항복"))
        XCTAssertFalse(titles.contains("확인"))
        XCTAssertFalse(titles.contains("매칭 취소"))
        window.endSheet(first, returnCode: .alertSecondButtonReturn)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(a.isActive); XCTAssertNil(a.outcome)
        XCTAssertFalse(controller.windowShouldClose(window))
        let second = try XCTUnwrap(window.attachedSheet)
        window.endSheet(second, returnCode: .alertFirstButtonReturn)
        try await wait { a.outcome == "loss" && b.outcome == "win" }
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(a.history.records.first?.reason, "surrender")
        window.orderOut(nil)
    }
    func testProductionWindowReplaysDamageReplacementAndLastKnockoutBeforeShowingResult() async throws {
        defer { cleanup() }
        let (a,b,_,_) = try await connectedPair(mode: .singles)
        func roster(_ prefix: String, speed: Int) -> [BattlePokemon] {
            team(prefix, mode: .singles).map { p in
                BattlePokemon(id:p.id,speciesID:p.speciesID,species:p.species,displayName:p.displayName,
                    level:p.level,ability:p.ability,nature:p.nature,gender:p.gender,shiny:p.shiny,form:p.form,
                    ivs:p.ivs,stats:["hp":40,"atk":100,"def":100,"spa":100,"spd":100,"spe":speed],moves:["dragon-rage"])
            }
        }
        let own=roster("a",speed:200),foe=roster("b",speed:50)
        try await registerPair(a,b,own,foe)
        a.ready(team:own);b.ready(team:foe)
        try await wait { a.frame != nil && b.frame != nil }
        let store=CompanionStore(fileURL:temporaryFile(),defaults:try defaults(code:"action-timing"))
        let controller=BattleWindowController(battle:a,store:store,allowsAudio:false)
        controller.show()
        defer { controller.window?.orderOut(nil);controller.fieldWindow?.orderOut(nil);controller.statsWindow?.orderOut(nil) }
        try await Task.sleep(for:.milliseconds(150))
        for turn in 0..<3 {
            let previousID=a.frame!.decisionID
            for c in [a,b] {
                c.choose(BattleDecision(decisionID:c.frame!.decisionID,actions:[BattleAction(kind:"move",index:1,target:0)],order:[]))
            }
            try await wait { a.frame?.decisionID != previousID }
            XCTAssertTrue(a.presentation.pending)
            XCTAssertEqual(a.presentation.frame?.foe.first?.hp,100,"Production view must keep pre-hit HP while announcing/animating")
            XCTAssertFalse(a.presentation.frame!.ended)
            if turn == 2 { XCTAssertEqual(a.outcome,"win");XCTAssertFalse(a.presentation.frame!.ended,"Terminal authoritative state must wait for the last effect") }
            try await wait({ !a.presentation.pending },seconds:16)
            XCTAssertEqual(a.presentation.frame?.foe.first?.hp,0)
            if turn < 2 {
                let previousPokemon=a.presentation.frame!.foe[0].id
                XCTAssertTrue(b.frame!.slots[0].mustSwitch)
                let index=try XCTUnwrap(b.frame!.own.firstIndex { !$0.active && !$0.fainted })
                b.choose(BattleDecision(decisionID:b.frame!.decisionID,actions:[BattleAction(kind:"switch",index:index+1,target:0)],order:[]))
                try await wait { a.frame!.foe[0].id != previousPokemon }
                XCTAssertEqual(a.presentation.frame?.foe[0].id,previousPokemon,"Replacement cannot appear before its switch transition")
                try await wait({ !a.presentation.pending },seconds:8)
                XCTAssertNotEqual(a.presentation.frame?.foe[0].id,previousPokemon)
                XCTAssertEqual(a.presentation.frame?.foe[0].hp,100)
            }
        }
        XCTAssertTrue(a.presentation.frame!.ended)
        XCTAssertEqual(a.history.records.count,1);XCTAssertEqual(b.history.records.count,1)
    }
    func testReusedBattleWindowAppliesEachModesPreferredWidth() async throws {
        defer { cleanup() }
        let (a,b,_,_) = try await connectedPair(mode:.singles)
        let store = CompanionStore(fileURL:temporaryFile(),defaults:try defaults(code:"mode-width"))
        let controller = BattleWindowController(battle:a,store:store,allowsAudio:false)
        controller.show()
        let window = try XCTUnwrap(controller.window)
        defer { window.orderOut(nil);controller.fieldWindow?.orderOut(nil);controller.statsWindow?.orderOut(nil) }
        for mode in [BattleMode.singles,.doubles,.singles] {
            a.cancelLobby();try await wait { b.phase == .idle }
            a.setMode(mode);b.setMode(mode);a.search();b.search()
            a.select(TradePeer(id:"BBBB",nickname:"BBBB",code:"BBBB",discoveryGroup:mode.rawValue))
            try await wait { a.opponent != nil && b.opponent != nil && b.mode == mode }
            controller.show()
            try await wait { abs(window.contentRect(forFrameRect:window.frame).width-(mode == .doubles ? 680 : 660))<0.5 }
            XCTAssertTrue(controller.window === window)
            XCTAssertEqual(window.minSize.width,mode == .doubles ? 680 : 660)
        }
        controller.show()
        XCTAssertEqual(window.contentRect(forFrameRect:window.frame).width,660,accuracy:0.5)
    }

    func testBattleHeightFitsMeasuredCommandsWithoutExtraClearance() async throws {
        defer { cleanup() }
        for mode in [BattleMode.singles, .doubles] {
            let (a,_,_,_) = try await pair(mode: mode)
            for language in [AppLanguage.ko, .en] {
                for width: CGFloat in [BattleWindowLayout.preferredWidth(for: mode), 1000] {
                    let store = CompanionStore(fileURL: temporaryFile(), defaults: try defaults(code: "height"))
                    store.setLanguage(language)
                    let controller = BattleWindowController(battle: a, store: store, allowsAudio: false)
                    controller.show()
                    let window = try XCTUnwrap(controller.window)
                    defer {
                        window.orderOut(nil)
                        controller.fieldWindow?.orderOut(nil)
                        controller.statsWindow?.orderOut(nil)
                    }
                    window.setContentSize(NSSize(width: width, height: 700))
                    try await wait {
                        window.contentView?.layoutSubtreeIfNeeded()
                        guard let measurement = controller.contentMeasurement,
                              abs(measurement.content.width - width) < 1,
                              let clearance = measurement.commandClearance else { return false }
                        return abs(clearance) < 1 && abs(window.contentRect(forFrameRect: window.frame).height - measurement.content.height) <= 1.1
                    }
                    let measurement = try XCTUnwrap(controller.contentMeasurement)
                    XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, width, accuracy: 0.5, "Height fitting must preserve the existing width")
                    XCTAssertEqual(try XCTUnwrap(measurement.commandClearance), 0, accuracy: 0.5)
                    XCTAssertLessThan(window.frame.height, 850, "No fixed 960-point window or unmeasured empty space")
                    XCTAssertGreaterThan(try XCTUnwrap(measurement.commands).height, 150, "Both move rows and details must participate in measurement")
                    print("Battle content fit: \(mode) \(language) width=\(width) height=\(window.frame.height) gap=\(measurement.commandClearance ?? -1)")
                    window.setContentSize(NSSize(width: width, height: 1000))
                    try await wait {
                        abs(window.contentRect(forFrameRect: window.frame).height - measurement.content.height) <= 1.1
                    }
                    try await Task.sleep(for: .milliseconds(500))
                    XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, measurement.content.height, accuracy: 1.1, "Hosting must not re-expand the fitted window after layout settles")

                }
            }
        }
    }

    func testAuxiliaryCloseReopenDoesNotSurrenderAndMainCloseHidesAllWindows() async throws {
        defer { cleanup() }
        let (a,b,_,_) = try await pair(mode: .doubles)
        let store = CompanionStore(fileURL: temporaryFile(), defaults: try defaults(code: "panels"))
        let controller = BattleWindowController(battle: a, store: store, allowsAudio: false)
        controller.show()
        let main = try XCTUnwrap(controller.window)
        let field = try XCTUnwrap(controller.fieldWindow)
        let stats = try XCTUnwrap(controller.statsWindow)
        XCTAssertTrue(field.isVisible && stats.isVisible)
        field.performClose(nil)
        stats.performClose(nil)
        XCTAssertFalse(controller.auxiliaryState.fieldVisible)
        XCTAssertFalse(controller.auxiliaryState.statsVisible)
        XCTAssertFalse(field.isVisible || stats.isVisible)
        XCTAssertTrue(a.isActive && b.isActive)
        XCTAssertNil(main.attachedSheet, "Closing information windows must never ask to surrender")
        XCTAssertNil(a.outcome)
        controller.showAuxiliary(.field)
        controller.showAuxiliary(.stats)
        XCTAssertTrue(controller.fieldWindow === field && controller.statsWindow === stats)
        XCTAssertTrue(field.isVisible && stats.isVisible)
        XCTAssertTrue(controller.auxiliaryState.fieldVisible && controller.auxiliaryState.statsVisible)
        // Actual host view must have no enclosing scroll view around combat and commands.
        main.contentView?.layoutSubtreeIfNeeded()
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        let scrolls = scrollViews(try XCTUnwrap(main.contentView))
        XCTAssertTrue(scrolls.isEmpty, "Battle history/logs must not add a scrolling area to the combat window")
        XCTAssertFalse(controller.windowShouldClose(main))
        let sheet = try XCTUnwrap(main.attachedSheet)
        main.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        try await wait { a.outcome == "loss" && b.outcome == "win" }
        XCTAssertFalse(main.isVisible || field.isVisible || stats.isVisible)
    }

    func testHistoryPersistsDeduplicatesAndFiltersByOpponent() throws {
        defer { cleanup() }
        let url = temporaryFile()
        let history = BattleHistoryStore(url: url)
        let record = BattleRecord(id: "match1", opponentCode: "B", opponentName: "Opponent", mode: .singles,
            startedAt: Date(), endedAt: Date(), result: "loss", reason: "surrender", team: team("a",mode:.singles), turns: 2)
        history.append(record); history.append(record)
        let reloaded = BattleHistoryStore(url: url)
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.forOpponent("B").count, 1)
        XCTAssertTrue(reloaded.forOpponent("C").isEmpty)
        XCTAssertEqual(reloaded.records.first?.team.first?.stats["hp"], 143)
    }
    func testCorruptHistoryIsNotOverwritten() throws {
        defer { cleanup() }
        let url = temporaryFile(), original = Data("corrupt history".utf8)
        try original.write(to: url)
        let history = BattleHistoryStore(url: url)
        XCTAssertNotNil(history.error)
        history.append(BattleRecord(id: "m", opponentCode: "B", opponentName: "B", mode: .singles,
            startedAt: Date(), endedAt: Date(), result: "win", reason: "completed", team: [], turns: 1))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testCommitmentBindsDecisionNonceAndMatch() {
        let decision = BattleDecision(decisionID: "turn1", actions: [.pass], order: [])
        let digest = BattleCoordinator.digest(decision,nonce: "a",matchID: "m")
        XCTAssertNotEqual(digest,BattleCoordinator.digest(decision,nonce: "b",matchID: "m"))
        XCTAssertNotEqual(digest,BattleCoordinator.digest(decision,nonce: "a",matchID: "n"))
    }
    func testGoldSilverWildBattlePreservesSourceIntroAndLoopFrames() throws {
        let directory=BattleEngineProcess.sourceRoot
        let track=try BattleMusicTrack(directory:directory)
        XCTAssertEqual(track.intro.frameLength,1_038_645)
        XCTAssertEqual(track.loop.frameLength,1_612_668)
        XCTAssertEqual(track.intro.format.sampleRate,44_100)
        XCTAssertEqual(track.intro.format.channelCount,2)
        XCTAssertEqual(track.intro.format,track.loop.format)
        let expected = ["GoldSilverWildBattleIntro.wav":"3bbfb18ee4b5c0cc35db197b1c5449f3de2fa1dcd410ac61e04c8a2b24311fb7",
                        "GoldSilverWildBattleLoop.wav":"359e8c720f145879e7c472d13de1d8f40bc4e83052cfca3c852c3ecd44979f09"]
        for (name,hash) in expected {
            let url=directory.appendingPathComponent(name)
            XCTAssertGreaterThan(try AVAudioPlayer(contentsOf:url).duration,20)
            XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:url)).map { String(format:"%02x",$0) }.joined(),hash,
                           "The bundled sound must remain the verified archive recording, not a substitute")
        }
    }
    func testWildBattleSchedulingSkipsIntroOnEverySubsequentLoop() throws {
        let track=try BattleMusicTrack(directory:BattleEngineProcess.sourceRoot)
        let engine=AVAudioEngine(),node=AVAudioPlayerNode()
        engine.attach(node);engine.connect(node,to:engine.mainMixerNode,format:track.intro.format)
        let block: AVAudioFrameCount=4096
        try engine.enableManualRenderingMode(.offline,format:track.intro.format,maximumFrameCount:block)
        track.schedule(on:node)
        try engine.start();node.play()
        defer { node.stop();engine.stop() }
        let buffer=try XCTUnwrap(AVAudioPCMBuffer(pcmFormat:track.intro.format,frameCapacity:block))
        let intro=Int(track.intro.frameLength),loop=Int(track.loop.frameLength)
        var rendered=0, error: Float=0, count=0
        while rendered < intro + loop + 8192 {
            let status=try engine.renderOffline(block,to:buffer)
            XCTAssertEqual(status,.success)
            guard status == .success else { return }
            for i in 0..<Int(buffer.frameLength) {
                let frame=rendered+i
                // Check both joins and a later part of the repeated loop.
                guard (intro-128..<intro+128).contains(frame) || (intro+loop-128..<intro+loop+8192).contains(frame) else { continue }
                let source=frame < intro ? track.intro : track.loop
                let index=frame < intro ? frame : (frame-intro)%loop
                let actual=buffer.floatChannelData![0][i],expected=source.floatChannelData![0][index]
                error=max(error,abs(actual-expected));count+=1
            }
            rendered+=Int(buffer.frameLength)
        }
        XCTAssertGreaterThan(count,8000)
        XCTAssertLessThan(error,0.00001,"Offline output must match original PCM at intro→loop and loop→loop, without gaps or repeated intro")
    }
    func testDecisionTimeoutCountsGuestCommitBeforeHostRequestsReveal() {
        XCTAssertEqual(BattleCoordinator.decisionTimeoutWinner(waiting:[false,false],submitted:[1]),1)
        XCTAssertEqual(BattleCoordinator.decisionTimeoutWinner(waiting:[false,false],submitted:[0]),0)
        XCTAssertEqual(BattleCoordinator.decisionTimeoutWinner(waiting:[false,false],submitted:[]),-1)
        XCTAssertEqual(BattleCoordinator.decisionTimeoutWinner(waiting:[true,false],submitted:[]),0)
        XCTAssertEqual(BattleCoordinator.decisionTimeoutWinner(waiting:[false,true],submitted:[]),1)
    }
    func testTeamBuilderPreservesCurrentStatsMovesAndRejectsReleasedOrDuplicateIndividuals() async throws {
        let details = PokemonDetails(speciesID:25,name:"pikachu",height:4,weight:60,baseExperience:112,genderRate:4,
            types:["electric"],baseStats:["hp":35,"attack":55,"defense":40,"special-attack":50,"special-defense":50,"speed":90],
            abilities:[PokemonAbilityOption(name:"static",slot:1,isHidden:false)],moves:[])
        var profile = PokemonProfile.generate(seed:19)
        profile.level=37;profile.abilityName="static";profile.abilitySlot=1
        profile.moves=[PokemonKnownMove(name:"thunderbolt",learnedAtLevel:26)]
        let entries = (0..<6).map { i in DexEntry(id:"entry\(i)",baseID:[26,181,310,101,587,618][i],finalID:[26,181,310,101,587,618][i],chainOrder:[[26,181,310,101,587,618][i]],rarity:.common,
            caughtAt:Date(),nature:.timid,profile:profile) }
        let team = try await BattleTeamBuilder.build(ids:entries.reversed().map(\.id),entries:entries,mode:.singles,language:.en,
            provider:BattleDetailFixture(details:details))
        let expected=Dictionary(uniqueKeysWithValues:PokemonStatCalculator.stats(details:details,profile:profile,nature:.timid).map {
            (BattleTeamBuilder.statNames[$0.name]!, $0.value)
        })
        XCTAssertEqual(team.map(\.id), entries.reversed().map(\.id))
        XCTAssertEqual(team.count, 6)
        XCTAssertEqual(team[0].stats,expected)
        XCTAssertEqual(team[0].moves,["thunderbolt"])
        XCTAssertEqual(team[0].level,37)
        XCTAssertTrue(BattleTeamBuilder.isSpeciesEligible(351), "Weather forms remain eligible")
        XCTAssertFalse(BattleTeamBuilder.isSpeciesEligible(493))
        for mode in BattleMode.allCases {
            for form in PokemonForm.forms(speciesID:493) {
                let blocked = (0..<mode.teamSize).map { i in
                    DexEntry(id:"blocked\(i)",baseID:493,finalID:493,chainOrder:[493],rarity:.common,
                        caughtAt:Date(),nature:.timid,profile:profile,form:form)
                }
                do {
                    _ = try await BattleTeamBuilder.build(ids:blocked.map(\.id),entries:blocked,mode:mode,
                        language:.ko,provider:BattleDetailFixture(details:details))
                    XCTFail("Every item-dependent form must be rejected before loading details")
                } catch {
                    XCTAssertEqual(error.localizedDescription,L(.ko).battleItemTypeExcluded)
                }
            }
        }
        var released=entries;released[0].releasedAt=Date()
        do {
            _ = try await BattleTeamBuilder.build(ids:entries.map(\.id),entries:released,mode:.singles,language:.en,provider:BattleDetailFixture(details:details))
            XCTFail("released individuals must not be eligible")
        } catch { XCTAssertNotNil(error as? BattleFailure) }
        do {
            _ = try await BattleTeamBuilder.build(ids:["entry0","entry0","entry1"],entries:entries,mode:.singles,language:.en,provider:BattleDetailFixture(details:details))
            XCTFail("duplicate individuals must not be eligible")
        } catch { XCTAssertNotNil(error as? BattleFailure) }
    }
    func testSpeciesClauseRejectsSameSpeciesFormsAndKeepsSelectedIndividualRemovable() async throws {
        var profile = PokemonProfile.generate(seed:19)
        profile.level=37; profile.abilityName="pressure"
        profile.moves=[PokemonKnownMove(name:"psychic",learnedAtLevel:1)]
        for mode in BattleMode.allCases {
            let entries = (0..<mode.teamSize).map { i in
                DexEntry(id:"species\(i)",baseID:386,finalID:386,chainOrder:[386],rarity:.common,
                    caughtAt:Date(),profile:profile,form:PokemonForm(i == 0 ? "normal" : "attack"))
            }
            XCTAssertFalse(BattleTeamBuilder.hasSelectedSpecies(entries[0],selectedIDs:[entries[0].id],entries:entries))
            XCTAssertTrue(BattleTeamBuilder.hasSelectedSpecies(entries[1],selectedIDs:[entries[0].id],entries:entries))
            XCTAssertFalse(BattleTeamBuilder.hasSelectedSpecies(entries[1],selectedIDs:[],entries:entries))
            do {
                _ = try await BattleTeamBuilder.build(ids:entries.map(\.id),entries:entries,mode:mode,language:.ko)
                XCTFail("Different individuals/forms of the same species must be rejected before API access")
            } catch { XCTAssertEqual(error.localizedDescription,L(.ko).battleDuplicateSpecies) }
        }
        let (a,_,link,_) = try await connectedPair(mode:.singles)
        var roster=team("duplicate",mode:.singles); roster[1]=roster[0]
        a.ready(team:roster)
        XCTAssertFalse(a.localReady)
        XCTAssertFalse(link.sent.contains { $0.kind == "ready" })
        XCTAssertEqual(L(.ko).battleUserError(a.error ?? ""),L(.ko).battleDuplicateSpecies)
    }
    func testOnlyFinalGraduatedRecordsAppearAndBuilderRejectsEarlierStages() async throws {
        defer { cleanup() }
        var profile = PokemonProfile.generate(seed: 7)
        profile.level = 100
        profile.abilityName = "static"
        profile.moves = [.init(name: "thunderbolt", learnedAtLevel: 26)]
        let ids = [25,26,181,310,143,133,493]
        var entries = ids.map { id in
            DexEntry(id:"eligible-\(id)",baseID:id,finalID:id,chainOrder:[id],rarity:.common,caughtAt:Date(),profile:profile)
        }
        entries[4].releasedAt = Date()
        entries.append(DexEntry(id:"unresolved",baseID:143,finalID:143,chainOrder:[143],rarity:.common,caughtAt:nil))
        XCTAssertEqual(BattleTeamBuilder.storedCandidates(entries).map(\.finalID),[26,181,310,493])
        var saved = CompanionState()
        saved.dex = entries
        saved.active = MonState(baseID:26,pathIDs:[26],stageIndex:0,usedAtStage:0,rarity:.common,totalForms:1,profile:profile)
        let file = temporaryFile()
        try JSONEncoder().encode(saved).write(to:file)
        let store = CompanionStore(fileURL:file,defaults:try defaults(code:"stored-eligibility"))
        XCTAssertTrue(store.dexEntries.contains { store.isActiveDexEntry($0) })
        XCTAssertFalse(BattleTeamBuilder.storedCandidates(store.state.dex).contains { store.isActiveDexEntry($0) },
                       "Even a final-form level-100 Pokémon must graduate before selection")
        for id in [26,134,135,136,196,197,470,471,57,83,206,143,351] {
            XCTAssertTrue(BattleTeamBuilder.isFinalEvolution(id), "BW2 terminal species \(id)")
        }
        for id in [25,172,133,123,233,82,299] { XCTAssertFalse(BattleTeamBuilder.isFinalEvolution(id)) }
        for mode in BattleMode.allCases {
            let selected = [entries[0],entries[1],entries[2],entries[3]] + [entries[0],entries[1]].enumerated().map { i, entry in
                var copy = entry; copy.id = "extra-\(i)"; return copy
            }
            do {
                _ = try await BattleTeamBuilder.build(ids:selected.map(\.id),entries:entries,mode:mode,language:.ko,provider:RejectingBattleDetails())
                XCTFail("A truncated saved chain must not turn Pikachu into a terminal species")
            } catch { XCTAssertEqual(error.localizedDescription,L(.ko).battleFinalOnly) }
            let (a,_,_,_) = try await connectedPair(mode:mode)
            let invalid = [BattlePokemon(id:"unevolved",speciesID:25,species:"Pikachu",displayName:"Pikachu",level:100,ability:"Static",nature:"hardy",gender:"M",shiny:false,form:nil,ivs:[:],stats:[:],moves:["thunderbolt"])] + Array(team("valid",mode:mode).dropFirst())
            a.ready(team:invalid)
            XCTAssertFalse(a.localReady)
            XCTAssertEqual(L(.ko).battleUserError(a.error ?? ""),L(.ko).battleFinalOnly)
            let (receiver,_,_,sender) = try await connectedPair(mode:mode)
            var packet = BattleWire(kind:"ready")
            packet.matchID = [receiver.identity.nonce,try XCTUnwrap(receiver.opponent).nonce].sorted().joined(separator:":")
            packet.sequence = 100
            packet.mode = mode
            packet.team = invalid
            try sender.sendData(JSONEncoder().encode(packet))
            try await wait({ receiver.error != nil }, seconds: 1)
            XCTAssertFalse(receiver.remoteReady)
            XCTAssertFalse(receiver.isActive)
            XCTAssertEqual(L(.ko).battleUserError(receiver.error ?? ""),L(.ko).battleFinalOnly)
        }
    }
    func testFormIdentityMapsDefaultAPINamesToActualEngineForms() {
        XCTAssertEqual(BattleTeamBuilder.engineSpecies("shaymin-land",speciesID:492,form:PokemonForm("sky")),"Shaymin-sky")
        XCTAssertEqual(BattleTeamBuilder.engineSpecies("deoxys-normal",speciesID:386,form:PokemonForm("attack")),"Deoxys-attack")
    }
    func testBattleCatalogCoversEveryMoveAndSpeciesInEverySettingLanguage() {
        let catalog = BattleTextCatalog.shared
        XCTAssertEqual(catalog.species.count,649)
        XCTAssertGreaterThanOrEqual(catalog.moves.count,559)
        for language in AppLanguage.allCases {
            for (id,names) in catalog.species { XCTAssertFalse(names[language.rawValue,default:""].isEmpty,"\(language) species \(id)") }
            for (key,move) in catalog.moves {
                XCTAssertFalse(move.names[language.rawValue,default:""].isEmpty,"\(language) \(key)")
                XCTAssertFalse(move.descriptions[language.rawValue,default:""].isEmpty,"\(language) description \(key)")
                XCTAssertEqual(catalog.moveName(key,language:language),move.names[language.rawValue])
                XCTAssertEqual(catalog.description(key,language:language),move.descriptions[language.rawValue])
            }
        }
        XCTAssertEqual(catalog.speciesName(25,language:.ko),"피카츄")
        XCTAssertEqual(catalog.moveName("Thunderbolt",language:.ko),"10만볼트")
        XCTAssertEqual(catalog.typeName("Electric",language:.ko),"전기")
        XCTAssertTrue(catalog.description("thunderbolt",language:.ko).contains("마비"))
        XCTAssertFalse(catalog.description("thunderbolt",language:.ru).contains("chance"))
        XCTAssertEqual(catalog.moveName("unknown move",language:.ko),L(.ko).battleUnknownMove)
        XCTAssertEqual(catalog.pokemonName("p1a: Pikachu, L37, M",language:.ko),"피카츄")
        XCTAssertEqual(BattleLogText.describe("|move|p1a: Pikachu|Thunderbolt|p2a: Squirtle",language:.ko),"아군 피카츄 → 10만볼트")
        XCTAssertEqual(BattleLogText.describe("|-status|p1a: Pikachu|par",language:.ko),"아군 피카츄 · 마비")
        XCTAssertEqual(L(.ko).battleEffectiveness(0),"효과 없음 ×0")
        XCTAssertTrue(L(.ko).battleEffectiveness(4).contains("굉장"))
    }
    func testSpriteFeetIgnoreTransparentPaddingAndStandFivePointsAboveShadowCenter() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:96,pixelsHigh:96,
            bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        pixels.initialize(repeating:0,count:bitmap.bytesPerRow * bitmap.pixelsHigh)
        for y in 15..<70 { for x in 20..<60 {
            let offset = y * bitmap.bytesPerRow + x * 4
            pixels[offset] = 255; pixels[offset+3] = 255
        } }
        XCTAssertEqual(BattleSpriteGeometry.contentBounds(bitmap),CGRect(x:20,y:15,width:40,height:55))
        let image = NSImage(size:NSSize(width:96,height:96));image.addRepresentation(bitmap)
        let cropped = BattleSpriteGeometry.cropped(image)
        XCTAssertEqual(cropped.size,NSSize(width:40,height:55))
        for size: CGFloat in [100,128] {
            XCTAssertEqual(BattleSpriteGeometry.footInset - BattleSpriteGeometry.shadowHeight/2,5)
            let fitted = SpriteFit.size(for:cropped.size,box:BattleSpriteGeometry.imageBox(stageSize:size))
            XCTAssertEqual(fitted.width/fitted.height,40.0/55.0,accuracy:0.0001)
            XCTAssertEqual(fitted.height + BattleSpriteGeometry.footInset,size+5)
        }
    }
    func testBattleVolumePersistsIncludingSilenceAndUpdatesTheMixer() throws {
        defer { cleanup() }
        let storage = try defaults(code:"audio")
        let original = UserDefaults.standard.object(forKey:BattleAudioSettings.volumeKey) as? Double
        let settings = BattleAudioSettings(defaults:storage)
        XCTAssertEqual(settings.volume,0.35)
        let player = try BattleMusicPlayer(directory:BattleEngineProcess.sourceRoot,volume:settings.volume)
        settings.onVolumeChange = { player.volume = $0 }
        for value in [0.72,0,1,0.18] {
            settings.setVolume(value)
            XCTAssertEqual(player.volume,value,accuracy:0.00001)
            let restored = BattleAudioSettings(defaults:storage)
            XCTAssertEqual(restored.volume,value)
            let nextBattle = try BattleMusicPlayer(directory:BattleEngineProcess.sourceRoot,volume:restored.volume)
            XCTAssertEqual(nextBattle.volume,value,accuracy:0.00001)
        }
        XCTAssertEqual(UserDefaults.standard.object(forKey:BattleAudioSettings.volumeKey) as? Double,original)
        for (input,expected) in [(-1.0,0.0),(2,1),(.nan,0.35)] {
            settings.setVolume(input)
            XCTAssertEqual(settings.volume,expected)
        }
        storage.set(-0.5,forKey:BattleAudioSettings.volumeKey)
        XCTAssertEqual(BattleAudioSettings(defaults:storage).volume,0)
    }
    func testNativeSpriteFeetStayFivePointsAboveShadowWithDifferentPadding() async throws {
        defer { cleanup() }
        let pokemon = BattleCombatant(id:"sprite",speciesID:25,name:"Pikachu",level:37,shiny:false,
            active:true,form:nil,fainted:false,hp:100,maxHP:100,status:"",stats:nil)
        for rect in [CGRect(x:20,y:15,width:40,height:55),CGRect(x:10,y:50,width:70,height:20)] {
            for back in [false,true] {
                let directory = temporaryFile()
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:96,pixelsHigh:96,
                    bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
                let data = try XCTUnwrap(bitmap.bitmapData);data.initialize(repeating:0,count:bitmap.bytesPerRow*96)
                for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) {
                    let index=y*bitmap.bytesPerRow+x*4;data[index]=255;data[index+3]=255
                } }
                // A thin tail on opposite sides reproduces the front/back Pikachu bias.
                let tail = back ? 5..<Int(rect.minX) : Int(rect.maxX)..<92
                for y in Int(rect.midY)..<Int(rect.midY)+4 { for x in tail {
                    let index=y*bitmap.bytesPerRow+x*4;data[index]=255;data[index+3]=255
                } }
                let file=directory.appendingPathComponent(SpriteStore.cacheKey(speciesID:25,animated:false,shiny:false,back:back)+".png")
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:file)
                let view=NSHostingController(rootView:BattlePokemonStage(pokemon:pokemon,back:back,stageSize:128,spriteStore:SpriteStore(directory:directory),animated:false))
                let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:148,height:133),styleMask:[.borderless],backing:.buffered,defer:false)
                window.contentViewController=view;window.setContentSize(NSSize(width:148,height:133));window.orderFront(nil)
                try await Task.sleep(for:.milliseconds(150));view.view.layoutSubtreeIfNeeded()
                let rep=try XCTUnwrap(view.view.bitmapImageRepForCachingDisplay(in:view.view.bounds))
                view.view.cacheDisplay(in:view.view.bounds,to:rep)
                let cg = try XCTUnwrap(rep.cgImage)
                var rgba = [UInt8](repeating:0,count:cg.width*cg.height*4)
                let context = try XCTUnwrap(CGContext(data:&rgba,width:cg.width,height:cg.height,bitsPerComponent:8,
                    bytesPerRow:cg.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
                var bottom: Int?
                var top = cg.height
                for y in 0..<cg.height { for x in 0..<cg.width {
                    let offset=(y*cg.width+x)*4
                    if rgba[offset]>230 && rgba[offset+1]<26 && rgba[offset+2]<26 {
                        bottom=y; top = min(top,y)
                    }
                } }
                let lastPixel=try XCTUnwrap(bottom,"The cached fixture sprite must render")
                var mass: CGFloat = 0, moment: CGFloat = 0
                for y in (top+Int(CGFloat(lastPixel-top+1)*0.75))...lastPixel { for x in 0..<cg.width {
                    let offset=(y*cg.width+x)*4
                    if rgba[offset]>230 && rgba[offset+1]<26 && rgba[offset+2]<26 {
                        mass += 1; moment += CGFloat(x)+0.5
                    }
                } }
                let scale=CGFloat(rep.pixelsHigh)/view.view.bounds.height
                let bottomInset=CGFloat(rep.pixelsHigh-lastPixel-1)/scale
                XCTAssertEqual(bottomInset-BattleSpriteGeometry.shadowHeight/2,5,accuracy:1/scale)
                XCTAssertEqual(moment/mass/scale,view.view.bounds.midX,accuracy:1,
                    "The stance must center over the shadow despite an asymmetric tail")
                window.orderOut(nil)
            }
        }
    }
    func testBackSpritesUseSeparateCacheAndCorrectBWAssetPaths() {
        for shiny in [false,true] {
            let front = SpriteStore.cacheKey(speciesID:25,animated:false,shiny:shiny)
            let back = SpriteStore.cacheKey(speciesID:25,animated:false,shiny:shiny,back:true)
            XCTAssertNotEqual(front,back)
            XCTAssertEqual(SpriteStore.spriteURL(speciesID:25,animated:false,shiny:shiny,back:true).path,
                           "/PokeAPI/sprites/master/sprites/pokemon/back/" + (shiny ? "shiny/" : "") + "25.png")
        }
    }
    func testUnsubmittedActionLosesAtInjectedDeadline() async throws {
        defer { cleanup() }
        let (a,b,_,_) = try await pair(mode:.singles,decisionTimeLimit:1)
        try await chooseLeads(a,b)
        let frame=try XCTUnwrap(b.frame)
        b.choose(BattleDecision(decisionID:frame.decisionID,actions:[BattleAction(kind:"move",index:1,target:0)],order:[]))
        try await wait { a.outcome == "loss" && b.outcome == "win" }
        XCTAssertEqual(a.history.records.first?.reason,"timeout")
        XCTAssertEqual(a.frame?.own.first?.hp,143,"A timeout loss is independent of battle damage")
    }
    /// Opt-in visual harness: real engine/UI with isolated profiles and an in-memory opponent.
    func testInteractiveBattlePreview() async throws {
        guard ProcessInfo.processInfo.environment["PTB_BATTLE_LIVE_PREVIEW"] == "1" else {
            throw XCTSkip("Set PTB_BATTLE_LIVE_PREVIEW=1 to open the interactive battle window")
        }
        defer { cleanup() }
        let mode: BattleMode = ProcessInfo.processInfo.environment["PTB_BATTLE_PREVIEW_MODE"] == "doubles" ? .doubles : .singles
        let (a,b,_,_) = try await pair(mode:mode,decisionTimeLimit:1800)
        try await chooseLeads(a,b)
        let store = CompanionStore(fileURL:temporaryFile(),defaults:try defaults(code:"live-preview"))
        store.setLanguage(.ko)
        let controller = BattleWindowController(battle:a,store:store,allowsAudio:true)
        NSApplication.shared.setActivationPolicy(.regular)
        controller.show()
        XCTAssertTrue(controller.isMusicPlaying,"The live preview must start its audio player")
        let window = try XCTUnwrap(controller.window)
        window.title = "PokeTokenBar · " + (mode == .singles ? "싱글배틀" : "더블배틀") + " · BGM / 가상 상대 테스트"
        let output = URL(fileURLWithPath:"/private/tmp/ptb-live-battle-preview.png")
        let end = Date().addingTimeInterval(1800)
        while window.isVisible && Date() < end {
            // XCTest pumps CFRunLoop, but does not run NSApplication's native input event loop.
            while let event=NSApp.nextEvent(matching:.any,until:Date(),inMode:.default,dequeue:true) {
                NSApp.sendEvent(event)
            }
            NSApp.updateWindows()
            try await Task.sleep(for:.milliseconds(50))
            if b.phase == .playing, !b.submitted, let frame=b.frame, !frame.waiting, !frame.preview, !frame.ended {
                var used = Set<Int>()
                let actions: [BattleAction] = frame.slots.compactMap { slot in
                    if slot.canPass { return .pass }
                    if slot.mustSwitch {
                        guard let index=frame.own.indices.first(where:{ !frame.own[$0].active && !frame.own[$0].fainted && !used.contains($0) }) else { return nil }
                        used.insert(index)
                        return BattleAction(kind:"switch",index:index+1,target:0)
                    }
                    let attacks=slot.moves.filter { !$0.disabled && $0.pp > 0 && $0.category != "Status" }
                    guard let move=attacks.first ?? slot.moves.first(where:{ !$0.disabled && $0.pp > 0 }) else { return nil }
                    let target=move.targetRequired ? (move.targets.first(where: { $0.location > 0 })?.location ?? move.targets.first?.location ?? 0) : 0
                    return BattleAction(kind:"move",index:move.index,target:target)
                }
                if actions.count == frame.slots.count { b.choose(BattleDecision(decisionID:frame.decisionID,actions:actions,order:[])) }
            }
            let state: [String:Any] = ["turn":a.frame?.turn ?? 0,"submitted":a.submitted,
                "musicPlaying":controller.isMusicPlaying,"outcome":a.outcome ?? "",
                "ownHP":a.frame?.own.first?.hp ?? 0,"foeHP":a.frame?.foe.first?.hp ?? 0]
            try JSONSerialization.data(withJSONObject:state).write(to:URL(fileURLWithPath:"/private/tmp/ptb-live-battle-state.json"),options:.atomic)
            if let view=window.contentView, let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                view.cacheDisplay(in:view.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])?.write(to:output,options:.atomic)
            }
        }
        window.orderOut(nil)
    }
    func testNativeBattleRenders() async throws {
        defer { cleanup() }
        guard let directory = ProcessInfo.processInfo.environment["PTB_BATTLE_SCREENSHOT_DIR"] else { return }
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for mode in BattleMode.allCases {
            let (a,b,_,_) = try await pair(mode:mode)
            try await chooseLeads(a,b)
            let store = CompanionStore(fileURL: temporaryFile(),defaults:try defaults(code:"render"))
            let audioSettings = BattleAudioSettings(defaults:try defaults(code:"audio-render"))
            let host = NSHostingController(rootView:BattleView(battle:a,store:store,onSurrender:{},onMusic:{},onPlayMusic:{},audioSettings:audioSettings))
            let window = NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:1000,height:720),styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentViewController=host
            window.setContentSize(NSSize(width:1000,height:720));window.orderFront(nil)
            try await Task.sleep(for:.milliseconds(500));host.view.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
            host.view.cacheDisplay(in:host.view.bounds,to:rep)
            try XCTUnwrap(rep.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent("battle-\(mode.rawValue).png"))
            let inspectorRect = CGRect(x:rep.pixelsWide * 7 / 10,y:rep.pixelsHigh * 3 / 5,
                                       width:rep.pixelsWide / 4,height:rep.pixelsHigh / 4)
            let beforeCrop = try XCTUnwrap(rep.cgImage?.cropping(to:inspectorRect))
            let beforeInspector = try XCTUnwrap(NSBitmapImageRep(cgImage:beforeCrop).representation(using:.png,properties:[:]))
            for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with:type,location:NSPoint(x:100,y:mode == .singles ? 260 : 280),modifierFlags:[],
                    timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,
                    eventNumber:1,clickCount:1,pressure:1))
                window.sendEvent(event)
            }
            try await Task.sleep(for:.milliseconds(500));host.view.layoutSubtreeIfNeeded()
            XCTAssertFalse(a.submitted,"Inspecting a move must not submit a battle command")
            let selectedRep = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
            host.view.cacheDisplay(in:host.view.bounds,to:selectedRep)
            let afterCrop = try XCTUnwrap(selectedRep.cgImage?.cropping(to:inspectorRect))
            let afterInspector = try XCTUnwrap(NSBitmapImageRep(cgImage:afterCrop).representation(using:.png,properties:[:]))
            XCTAssertNotEqual(beforeInspector,afterInspector,"Clicking a move must populate the right inspector")
            try XCTUnwrap(selectedRep.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent("battle-selected-\(mode.rawValue).png"))
            let move = try XCTUnwrap(a.frame?.slots.first?.moves.first)
            let detailHost = NSHostingController(rootView:BattleMoveDetails(move:move,language:.ko).padding(12).frame(width:340).background(Color(nsColor:.windowBackgroundColor)))
            let detailWindow = NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:340,height:330),styleMask:[.borderless],backing:.buffered,defer:false)
            detailWindow.contentViewController=detailHost;detailWindow.setContentSize(NSSize(width:340,height:330));detailWindow.orderFront(nil)
            try await Task.sleep(for:.milliseconds(400));detailHost.view.layoutSubtreeIfNeeded()
            let detailRep = try XCTUnwrap(detailHost.view.bitmapImageRepForCachingDisplay(in:detailHost.view.bounds))
            detailHost.view.cacheDisplay(in:detailHost.view.bounds,to:detailRep)
            try XCTUnwrap(detailRep.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent("battle-move-details-\(mode.rawValue).png"))
            detailWindow.orderOut(nil)
            if mode == .singles {
                for language in AppLanguage.allCases {
                    let localized = NSHostingController(rootView:BattleMoveDetails(move:move,language:language).padding(12).frame(width:360).background(Color(nsColor:.windowBackgroundColor)))
                    let localizedWindow = NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:360,height:360),styleMask:[.borderless],backing:.buffered,defer:false)
                    localizedWindow.contentViewController=localized;localizedWindow.setContentSize(NSSize(width:360,height:360));localizedWindow.orderFront(nil)
                    try await Task.sleep(for:.milliseconds(50));localized.view.layoutSubtreeIfNeeded()
                    let localizedRep = try XCTUnwrap(localized.view.bitmapImageRepForCachingDisplay(in:localized.view.bounds))
                    localized.view.cacheDisplay(in:localized.view.bounds,to:localizedRep)
                    try XCTUnwrap(localizedRep.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent("battle-language-\(language.rawValue).png"))
                    localizedWindow.orderOut(nil)
                }
            }
            window.setContentSize(NSSize(width:800,height:598))
            try await Task.sleep(for:.milliseconds(650));host.view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(host.view.bounds.height,598.5,"The flexible root must fit the minimum content height")
            XCTAssertLessThanOrEqual(host.view.bounds.width,800.5,"The flexible root must fit the minimum content width")
            let compact = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
            host.view.cacheDisplay(in:host.view.bounds,to:compact)
            try XCTUnwrap(compact.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent("battle-\(mode.rawValue)-compact.png"))
            window.orderOut(nil)
            a.surrender(); try await wait { b.outcome == "win" }
            let nav = PopoverNavigation(); nav.tab = .battle
            let usage = UsageStore(providers:[],autoRefresh:false,defaults:try defaults(code:"usage"))
            let lobby = NSHostingController(rootView:PopoverView().environment(store).environment(usage)
                .environment(UpdateChecker()).environment(nav).environment(a)
                .background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.dark))
            let popup = NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:360,height:500),styleMask:[.borderless],backing:.buffered,defer:false)
            popup.appearance=NSAppearance(named:.darkAqua)
            popup.contentViewController=lobby;popup.orderFront(nil)
            try await Task.sleep(for:.milliseconds(150));lobby.view.layoutSubtreeIfNeeded()
            let image=try XCTUnwrap(lobby.view.bitmapImageRepForCachingDisplay(in:lobby.view.bounds))
            lobby.view.cacheDisplay(in:lobby.view.bounds,to:image)
            try XCTUnwrap(image.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent("battle-history-\(mode.rawValue).png"))
            popup.orderOut(nil);a.shutdown();b.shutdown()
        }
    }
    func testHeldItemAndMegaControlsFitProductionSinglesAndDoublesOffscreen() async throws {
        defer{cleanup()}
        for mode in BattleMode.allCases {
            let (a,b,left,_) = try await connectedPair(mode:mode)
            var own=team("a",mode:mode),foe=team("b",mode:mode)
            let items=["raichunitex","sitrusberry","lumberry","leftovers","lifeorb","focussash"]
            for i in own.indices {own[i].item=items[i];foe[i].item=i==0 ? "magnet":items[i]}
            try await registerPair(a,b,own,foe);a.ready(team:own);b.ready(team:foe)
            try await wait{a.frame != nil && b.frame != nil}
            XCTAssertEqual(left.sent.first{$0.kind=="ready"}?.team?.first?.item,"raichunitex")
            XCTAssertTrue(a.frame!.slots[0].canMegaEvo==true)
            // Layout a reopened mid-match window, after a real Protect turn; opening animation
            // timing is covered separately by entry/player tests, not by a half-loaded snapshot.
            for coordinator in [a,b] {
                coordinator.choose(BattleDecision(decisionID:coordinator.frame!.decisionID,actions:coordinator.frame!.slots.map{_ in BattleAction(kind:"move",index:2,target:0)},order:[]))
            }
            try await wait{a.frame!.turn==2 && b.frame!.turn==2}
            a.completePresentation();b.completePresentation()
            let store=CompanionStore(fileURL:temporaryFile(),defaults:try defaults(code:"item-layout"));store.setLanguage(.ko)
            var measurement:BattleContentMeasurement?
            let width=BattleWindowLayout.preferredWidth(for:mode)
            let host=NSHostingController(rootView:BattleView(battle:a,store:store,onSurrender:{},onMusic:{},onPlayMusic:{},allowsEffectsAudio:false,onLayout:{measurement=$0}).frame(width:width))
            let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:width,height:850),styleMask:[.borderless],backing:.buffered,defer:false)
            XCTAssertTrue(NSScreen.screens.allSatisfy{!$0.frame.intersects(window.frame)})
            window.contentViewController=host;window.orderFront(nil)
            defer{window.orderOut(nil);window.contentViewController=nil}
            try await wait{measurement != nil}
            let bounds=try XCTUnwrap(measurement)
            XCTAssertEqual(bounds.content.width,width,accuracy:1)
            XCTAssertLessThan(bounds.content.height,850)
            XCTAssertLessThanOrEqual(try XCTUnwrap(bounds.commands).maxY,try XCTUnwrap(bounds.footer).minY+1)
            let header=try XCTUnwrap(bounds.header),field=try XCTUnwrap(bounds.battlefield)
            let battlers=try XCTUnwrap(bounds.battlers),roster=try XCTUnwrap(bounds.roster),title=try XCTUnwrap(bounds.commandTitle)
            XCTAssertLessThanOrEqual(header.maxY,field.minY)
            XCTAssertGreaterThanOrEqual(battlers.minY,field.minY-0.5)
            XCTAssertLessThanOrEqual(battlers.maxY,field.maxY+0.5)
            XCTAssertLessThanOrEqual(field.maxY,roster.minY)
            XCTAssertLessThanOrEqual(roster.maxY,title.minY)
            window.setContentSize(NSSize(width:width,height:bounds.content.height));host.view.layoutSubtreeIfNeeded()
            if let bitmap=host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds){
                host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
                let file=URL(fileURLWithPath:"/tmp/ptb-held-battle-\(mode.rawValue).png")
                try bitmap.representation(using:.png,properties:[:])?.write(to:file)
            }
            a.shutdown();b.shutdown()
        }
    }

}

private struct BattleDetailFixture: PokemonDetailProviding {
    let details: PokemonDetails
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID:speciesID,name:[25:"pikachu",26:"raichu",172:"pichu",181:"ampharos",310:"manectric",101:"electrode",587:"emolga",618:"stunfisk"][speciesID] ?? details.name,
            height:details.height,weight:details.weight,baseExperience:details.baseExperience,genderRate:details.genderRate,
            types:details.types,baseStats:details.baseStats,abilities:details.abilities,moves:details.moves)
    }
}

private struct RejectingBattleDetails: PokemonDetailProviding {
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        throw BattleFailure.invalidTeam("Unexpected metadata load before eligibility validation")
    }
}

private struct SelectedLoadoutBattleDetails: PokemonDetailProviding {
    static let originalAbility = [130:"Intimidate",26:"Static",59:"Flash Fire",80:"Own Tempo",134:"Water Absorb",212:"Swarm"]
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        let names = [130:"gyarados",26:"raichu",59:"arcanine",80:"slowbro",134:"vaporeon",212:"scizor"]
        let stats = [130:[95,125,79,60,100,81],26:[60,90,55,90,80,110],59:[90,110,80,100,80,95],80:[95,75,110,100,80,30],134:[130,65,60,110,95,65],212:[70,130,100,55,80,65]]
        let moves = [130:["dragon-rage","dragon-dance","waterfall"],26:["tail-whip"],59:["flamethrower"],80:["amnesia"],134:["surf"],212:["bullet-punch"]]
        let name = try XCTUnwrap(names[speciesID])
        return PokemonDetails(speciesID:speciesID,name:name,height:10,weight:100,baseExperience:100,genderRate:4,
            types:[130:["water","flying"],26:["electric"],59:["fire"],80:["water","psychic"],134:["water"],212:["bug","steel"]][speciesID]!,baseStats:Dictionary(uniqueKeysWithValues:zip(["hp","attack","defense","special-attack","special-defense","speed"],stats[speciesID]!)),
            abilities:PokemonLoadout.abilities[name]!,moves:(["return","protect"] + moves[speciesID]!).map {
                .init(name:$0,learnMethods:[.init(method:["dragon-rage","dragon-dance","tail-whip","amnesia","bullet-punch"].contains($0) ? "level-up" : "machine",level:["dragon-rage":23,"dragon-dance":44,"tail-whip":1,"amnesia":43,"bullet-punch":1][$0] ?? 0)])
            })
    }
}
