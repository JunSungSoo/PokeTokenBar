import XCTest
@testable import PokeTokenBar

// MARK: 스텁 (이 파일 전용)

/// 실제 네트워크 없이 두 TradeSession 을 직접 연결하는 가짜 트랜스포트.
private final class InMemoryTradeTransport: TradeTransport, @unchecked Sendable {
    var onPeerFound: (@Sendable (TradePeer) -> Void)?
    var onPeerLost: (@Sendable (String) -> Void)?
    var onConnected: (@Sendable () -> Void)?
    var onDisconnected: (@Sendable () -> Void)?
    var onMessageReceived: (@Sendable (TradeMessage) -> Void)?
    weak var peer: InMemoryTradeTransport?

    func startDiscovery() {}
    func stopDiscovery() {}
    func connect(to peer: TradePeer) throws {}

    func send(_ message: TradeMessage) throws {
        guard let peer else { throw TradeTransportError.notConnected }
        peer.onMessageReceived?(message)
    }

    func disconnect() {
        let disconnectedPeer = peer
        peer = nil
        disconnectedPeer?.onDisconnected?()
    }
}

/// 폴링 조건이 참이 될 때까지 대기 — Task { @MainActor in ... } 로 비동기 전달되는 콜백 검증용.
@MainActor
private func waitUntil(timeout: TimeInterval = 1, _ condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return condition()
}

@MainActor
private func makeConnectedSessions() -> (TradeSession, TradeSession) {
    let transportA = InMemoryTradeTransport()
    let transportB = InMemoryTradeTransport()
    transportA.peer = transportB
    transportB.peer = transportA
    let sessionA = TradeSession(transport: transportA)
    let sessionB = TradeSession(transport: transportB)
    transportA.onConnected?()
    transportB.onConnected?()
    return (sessionA, sessionB)
}

private func sampleEntry(baseID: Int) -> DexEntry {
    DexEntry(baseID: baseID, finalID: baseID, chainOrder: [baseID], rarity: .common, caughtAt: Date())
}

@MainActor
final class TradeSessionTests: XCTestCase {
    func testMutualOfferAndAcceptLeadsToCompletion() async {
        let (sessionA, sessionB) = makeConnectedSessions()
        var receivedByA: TradeItem?
        var receivedByB: TradeItem?
        var completedA = false
        var completedB = false
        sessionA.onReadyToCommit = { receivedByA = $0 }
        sessionB.onReadyToCommit = { receivedByB = $0 }
        sessionA.onCompleted = { completedA = true }
        sessionB.onCompleted = { completedB = true }

        let entryA = sampleEntry(baseID: 1)
        let entryB = sampleEntry(baseID: 4)
        sessionA.proposeOffer(.dexEntry(entryA))
        sessionB.proposeOffer(.dexEntry(entryB))
        sessionA.accept()
        sessionB.accept()

        let readyToCommit = await waitUntil { receivedByA != nil && receivedByB != nil }
        XCTAssertTrue(readyToCommit, "both sides should reach onReadyToCommit")

        guard case .dexEntry(let gotByA) = receivedByA else { return XCTFail("A should receive B's offer") }
        guard case .dexEntry(let gotByB) = receivedByB else { return XCTFail("B should receive A's offer") }
        XCTAssertEqual(gotByA.id, entryB.id)
        XCTAssertEqual(gotByB.id, entryA.id)

        sessionA.confirmLocalCommit()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(completedA)   // 상대 commitAck 아직 안 옴
        sessionB.confirmLocalCommit()
        let bothCompleted = await waitUntil { completedA && completedB }
        XCTAssertTrue(bothCompleted)
    }

    func testRejectStopsSessionBeforeCommit() async {
        let (sessionA, sessionB) = makeConnectedSessions()
        var rejectedReason: String?
        var commitFired = false
        sessionA.onRejected = { rejectedReason = $0 }
        sessionA.onReadyToCommit = { _ in commitFired = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionA.accept()
        sessionB.reject(reason: "마음이 바뀜")

        let rejected = await waitUntil { rejectedReason != nil }
        XCTAssertTrue(rejected)
        XCTAssertEqual(rejectedReason, "마음이 바뀜")
        XCTAssertFalse(commitFired)
    }

    func testAcceptWithoutBothOffersDoesNotCommit() async {
        let (sessionA, sessionB) = makeConnectedSessions()
        var commitFired = false
        sessionA.onReadyToCommit = { _ in commitFired = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionA.accept()
        sessionB.accept()   // B 는 자기 Offer 를 아직 안 보냄

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(commitFired)
    }

    func testPeerIdentifiedFiresFromHelloExchangedOnConnect() async {
        // sessionB must stay alive until its deferred onConnected Task runs and sends
        // its hello — discarding it into `_` would let ARC free it (and its transport)
        // before that Task fires, so A would never receive B's hello.
        let (sessionA, sessionB) = makeConnectedSessions()
        let identified = await waitUntil { sessionA.peerIdentity != nil }
        XCTAssertTrue(identified)
        _ = sessionB
    }
}
