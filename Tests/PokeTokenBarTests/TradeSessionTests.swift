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
        // 실제 accept 는 오퍼가 실제로 도착한 뒤 눌리므로(async 전달), 두 오퍼가 다 도착할 때까지
        // 기다린다 — 그러지 않으면 늦게 도착한 .offer 처리가 이미 보낸 accept 를 무효화해 버린다.
        let bothOffersArrived = await waitUntil { sessionA.theirOffer != nil && sessionB.theirOffer != nil }
        XCTAssertTrue(bothOffersArrived)
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
        // 양쪽 다 Offer 를 냈고 A 는 Accept 까지 눌렀지만, B 가 Accept 대신 Reject 를 보내면
        // 커밋이 가능했을 상황에서도 어느 쪽도 커밋에 이르면 안 된다.
        let (sessionA, sessionB) = makeConnectedSessions()
        var rejectedReason: String?
        var commitFiredA = false
        var commitFiredB = false
        sessionA.onRejected = { rejectedReason = $0 }
        sessionA.onReadyToCommit = { _ in commitFiredA = true }
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 2)))
        let bothOffered = await waitUntil { sessionA.theirOffer != nil && sessionB.theirOffer != nil }
        XCTAssertTrue(bothOffered, "both offers should have been exchanged before reject")

        sessionA.accept()
        sessionB.reject(reason: "마음이 바뀜")

        let rejected = await waitUntil { rejectedReason != nil }
        XCTAssertTrue(rejected)
        XCTAssertEqual(rejectedReason, "마음이 바뀜")
        XCTAssertFalse(commitFiredA)
        XCTAssertFalse(commitFiredB)
    }

    func testAcceptWithoutBothOffersDoesNotCommit() async {
        // onReadyToCommit 을 양쪽 모두에 걸어야 한다 — B 가 Offer 없이 Accept 만 보냈을 때
        // B 쪽에서 (자기 Offer 없이) 커밋이 발화하는 결함은 A 쪽만 관찰하면 가려진다.
        let (sessionA, sessionB) = makeConnectedSessions()
        var commitFiredA = false
        var commitFiredB = false
        sessionA.onReadyToCommit = { _ in commitFiredA = true }
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionA.accept()
        sessionB.accept()   // B 는 자기 Offer 를 아직 안 보냄

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(commitFiredA)
        XCTAssertFalse(commitFiredB)
    }

    func testOfferChangeAfterAcceptInvalidatesStaleAccept() async {
        // A offers X, B accepts X, then A withdraws X and offers Y. B's earlier Accept was
        // consent to X, not Y — it must not silently carry over and let B commit into
        // receiving something it never agreed to.
        let (sessionA, sessionB) = makeConnectedSessions()
        var commitFiredB = false
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 9)))
        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))   // X
        let firstOfferSeen = await waitUntil {
            if case .dexEntry(let entry) = sessionB.theirOffer { return entry.baseID == 1 }
            return false
        }
        XCTAssertTrue(firstOfferSeen)

        sessionB.accept()

        sessionA.withdrawOffer()
        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 2)))   // Y
        let secondOfferSeen = await waitUntil {
            if case .dexEntry(let entry) = sessionB.theirOffer { return entry.baseID == 2 }
            return false
        }
        XCTAssertTrue(secondOfferSeen)

        sessionA.accept()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(commitFiredB, "B's stale accept of X must not carry over to Y")
    }

    func testDuplicateCommitAckDoesNotRefireCompletion() async {
        let (sessionA, sessionB) = makeConnectedSessions()
        var completedCountA = 0
        sessionA.onCompleted = { completedCountA += 1 }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 2)))
        sessionA.accept()
        sessionB.accept()
        let bothReady = await waitUntil { sessionA.theirOffer != nil && sessionB.theirOffer != nil }
        XCTAssertTrue(bothReady)

        sessionA.confirmLocalCommit()
        sessionB.confirmLocalCommit()
        let completedOnce = await waitUntil { completedCountA == 1 }
        XCTAssertTrue(completedOnce)

        // 중복 commitAck 시뮬레이션 — B 가 ack 를 다시 보내도 A 의 완료는 재발화되면 안 된다.
        sessionB.confirmLocalCommit()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(completedCountA, 1, "duplicate commitAck must not refire onCompleted")
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
