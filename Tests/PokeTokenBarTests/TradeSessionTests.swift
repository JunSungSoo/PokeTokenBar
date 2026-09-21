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

    /// 실제 트랜스포트 두 구현체 모두 끊는 쪽에도 onDisconnected 를 준다(MCSession 의 .notConnected,
    /// ManualTradeTransport.disconnect) — 상대에게만 알리던 이 스텁은 그만큼 현실과 달랐다.
    func disconnect() {
        guard let disconnectedPeer = peer else { return }
        peer = nil
        disconnectedPeer.peer = nil
        disconnectedPeer.onDisconnected?()
        onDisconnected?()
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
        var commitFiredA = false
        var commitFiredB = false
        sessionA.onCompleted = { completedCountA += 1 }
        sessionA.onReadyToCommit = { _ in commitFiredA = true }
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 2)))
        // 오퍼가 도착하기 전에 accept() 하면 늦게 온 .offer 가 그 accept 를 무효화해 커밋에 이르지 못한다 —
        // 그러면 이 테스트는 이름과 달리 "중복 ack" 경로를 밟지 않는다.
        let bothReady = await waitUntil { sessionA.theirOffer != nil && sessionB.theirOffer != nil }
        XCTAssertTrue(bothReady)
        sessionA.accept()
        sessionB.accept()
        let bothCommitted = await waitUntil { commitFiredA && commitFiredB }
        XCTAssertTrue(bothCommitted, "the duplicate-ack path is only reachable after a real commit")

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

    /// The shape `TradeView.onReadyToCommit` originally had: a callback the session stores, capturing
    /// the session strongly. That is a self-retain cycle, so dropping every outside reference leaks
    /// the session *and* the transport it owns — and the leaked callbacks keep firing into the view
    /// that let it go. Documented here because the leak is invisible at the call site.
    func testStronglySelfCapturingCallbackLeaksTheSession() {
        weak var leaked: TradeSession?
        do {
            let session = TradeSession(transport: InMemoryTradeTransport())
            leaked = session
            session.onCompleted = { _ = session.myOffer }
        }
        XCTAssertNotNil(leaked, "a strongly self-capturing callback keeps the session alive forever")

        leaked?.onCompleted = nil
        XCTAssertNil(leaked, "clearing the callback breaks the cycle")
    }

    /// Regression guard for the fix: capturing the session weakly lets it deallocate as soon as its
    /// owner drops it, which also releases the transport underneath.
    func testWeaklySelfCapturingCallbackDoesNotRetainTheSession() {
        weak var observed: TradeSession?
        do {
            let session = TradeSession(transport: InMemoryTradeTransport())
            observed = session
            session.onCompleted = { [weak session] in _ = session?.myOffer }
        }
        XCTAssertNil(observed, "weak capture must let the session deallocate once its owner drops it")
    }

    func testWithdrawnOfferNotifiesTheReviewingSide() async {
        // 상대가 제안을 거두면 심사 화면에 남은 스냅샷은 이미 없는 물건을 약속한다 — 그 화면의
        // 승인 버튼은 commitIfBothAccepted 의 theirOffer 가드에 걸려 아무 일도 하지 않는다.
        let (sessionA, sessionB) = makeConnectedSessions()
        var withdrawnSeenByB = false
        var commitFiredB = false
        sessionB.onOfferWithdrawn = { withdrawnSeenByB = true }
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 9)))
        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        let offerSeen = await waitUntil { sessionB.theirOffer != nil }
        XCTAssertTrue(offerSeen)

        sessionA.withdrawOffer()
        let withdrawn = await waitUntil { withdrawnSeenByB }
        XCTAssertTrue(withdrawn, "the reviewing side must be told the offer is gone")
        XCTAssertNil(sessionB.theirOffer)

        sessionB.accept()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(commitFiredB, "accepting a withdrawn offer must not commit")
    }

    func testWithdrawnOfferKeepsTheLocalOffer() async {
        // 상대가 거둬도 내가 낸 것은 그대로다 — 다시 고르게 만들면 승인 직전에 화면이 뒤로 밀린다.
        let (sessionA, sessionB) = makeConnectedSessions()
        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 9)))
        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        let offerSeen = await waitUntil { sessionB.theirOffer != nil }
        XCTAssertTrue(offerSeen)

        sessionA.withdrawOffer()
        let withdrawn = await waitUntil { sessionB.theirOffer == nil }
        XCTAssertTrue(withdrawn)
        XCTAssertNotNil(sessionB.myOffer)
    }

    func testDisconnectBeforeCommitNotifiesBothSidesAndCommitsNothing() async {
        // 명세의 테스트 전략이 요구하는 "중도 연결 끊김" 케이스 — 제안까지 오간 뒤 끊기면 어느 쪽도
        // 커밋에 이르지 않고, 양쪽이 끊김을 통보받아야 화면이 매달리지 않는다.
        let (sessionA, sessionB) = makeConnectedSessions()
        var disconnectedA = false
        var disconnectedB = false
        var commitFiredA = false
        var commitFiredB = false
        sessionA.onDisconnected = { disconnectedA = true }
        sessionB.onDisconnected = { disconnectedB = true }
        sessionA.onReadyToCommit = { _ in commitFiredA = true }
        sessionB.onReadyToCommit = { _ in commitFiredB = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 2)))
        let bothOffered = await waitUntil { sessionA.theirOffer != nil && sessionB.theirOffer != nil }
        XCTAssertTrue(bothOffered)

        sessionA.accept()   // A 는 승인까지 했지만 B 의 승인 전에 끊긴다
        sessionB.disconnect()

        let bothNotified = await waitUntil { disconnectedA && disconnectedB }
        XCTAssertTrue(bothNotified, "both sides must learn the connection is gone")
        XCTAssertFalse(commitFiredA)
        XCTAssertFalse(commitFiredB)
    }

    func testAcceptAfterDisconnectDoesNotCommit() async {
        // 끊긴 뒤 승인 버튼이 아직 화면에 남아 눌리는 경로 — send 가 실패해 myAcceptSent 가 서지 않으므로
        // 커밋에 이르면 안 된다(상대는 아무 것도 못 받았는데 내 세이브만 바뀌는 상황).
        let (sessionA, sessionB) = makeConnectedSessions()
        var commitFiredA = false
        sessionA.onReadyToCommit = { _ in commitFiredA = true }

        sessionA.proposeOffer(.dexEntry(sampleEntry(baseID: 1)))
        sessionB.proposeOffer(.dexEntry(sampleEntry(baseID: 2)))
        let bothOffered = await waitUntil { sessionA.theirOffer != nil && sessionB.theirOffer != nil }
        XCTAssertTrue(bothOffered)
        // 상대 승인이 **실제로 도착한 뒤에** 끊어야 이 테스트가 이름이 말하는 경로를 밟는다 —
        // 이미 참인 조건(theirOffer != nil)을 기다리면 승인이 안 왔어도 통과해, 커밋이 애초에 불가능해서
        // 통과한 것과 끊김 때문에 막힌 것을 구별하지 못한다.
        sessionB.accept()
        let theirAcceptArrived = await waitUntil { sessionA.theirAcceptReceived }
        XCTAssertTrue(theirAcceptArrived, "B's accept must reach A before the disconnect")

        // 이 시점 A 는 myOffer·theirOffer·theirAcceptReceived 를 모두 갖췄고 아직 커밋 전이다 —
        // 커밋을 막는 것은 오직 accept 전송 실패뿐이다.
        sessionA.disconnect()
        sessionA.accept()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(commitFiredA, "a failed accept send must not reach commit")
    }
}
