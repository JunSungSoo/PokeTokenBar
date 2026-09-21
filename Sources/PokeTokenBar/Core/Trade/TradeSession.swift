import Foundation

/// 교환 프로토콜 상태 기계 — 전송 계층과 무관하게 Offer→Accept→Commit 순서를 관리한다.
/// 실제 상태 반영(백업+적용)은 이 클래스가 하지 않는다 — `onReadyToCommit` 콜백을 받은 쪽
/// (CompanionStore 소비자)이 적용을 마친 뒤 `confirmLocalCommit()` 을 호출해야 세션이 완료된다.
@MainActor
final class TradeSession {
    private let transport: any TradeTransport
    /// 교환 신원(닉네임·코드)을 읽는 저장소 — UsageStore/CompanionStore 와 같은 주입 규약. 테스트가
    /// 격리 suite 를 넘기지 않으면 hello 전송만으로 실제 사용자 도메인에 tradeCode 가 생성된다.
    private let defaults: UserDefaults
    private let sessionID = UUID().uuidString

    private(set) var peerIdentity: (nickname: String, code: String)?
    private(set) var myOffer: TradeItem?
    private(set) var theirOffer: TradeItem?
    private var myAcceptSent = false
    /// `theirOffer` 와 같은 등급의 관측 가능한 세션 상태 — "상대 승인이 도착했는가" 는 커밋 가능 여부를
    /// 가르는 조건이라 밖에서 읽을 수 있어야 한다.
    private(set) var theirAcceptReceived = false
    private var committed = false
    private var localCommitAckSent = false
    private var remoteCommitAckReceived = false
    private var completed = false

    var onPeerIdentified: (((nickname: String, code: String)) -> Void)?
    var onOffersReady: ((_ mine: TradeItem, _ theirs: TradeItem) -> Void)?
    /// 상대가 제안을 거뒀다 — 심사 화면이 이미 없는 물건을 계속 보여주지 않게 알린다.
    var onOfferWithdrawn: (() -> Void)?
    var onReadyToCommit: ((_ received: TradeItem) -> Void)?
    var onRejected: ((String) -> Void)?
    var onDisconnected: (() -> Void)?
    var onCompleted: (() -> Void)?

    init(transport: any TradeTransport, defaults: UserDefaults = .standard) {
        self.transport = transport
        self.defaults = defaults
        transport.onConnected = { [weak self] in
            Task { @MainActor [weak self] in self?.sendHello() }
        }
        transport.onMessageReceived = { [weak self] message in
            Task { @MainActor [weak self] in self?.handle(message) }
        }
        transport.onDisconnected = { [weak self] in
            Task { @MainActor [weak self] in self?.onDisconnected?() }
        }
    }

    private func sendHello() {
        try? transport.send(.hello(nickname: TradeIdentity.nickname(defaults: defaults),
                                   code: TradeIdentity.code(defaults: defaults)))
    }

    func proposeOffer(_ item: TradeItem) {
        myOffer = item
        // 오퍼가 바뀌면 이전 심사 대상에 대한 Accept 는 양쪽 다 무효 — 내가 보낸 Accept 도, 상대가
        // 보낸 Accept 도 지금 이 새 쌍에 대한 동의가 아니었으므로 둘 다 지운다.
        invalidateAcceptsBeforeCommit()
        try? transport.send(.offer(item))
        notifyIfBothOffersReady()
    }

    func withdrawOffer() {
        myOffer = nil
        invalidateAcceptsBeforeCommit()
        try? transport.send(.offerWithdrawn)
    }

    func accept() {
        guard !myAcceptSent else { return }
        do {
            try transport.send(.accept)
            myAcceptSent = true
            commitIfBothAccepted()
        } catch {
            // 전송 실패 시 플래그를 세우지 않는다 — accept() 재시도가 가능한 상태로 남는다.
        }
    }

    func reject(reason: String) {
        try? transport.send(.reject(reason: reason))
        transport.disconnect()
    }

    /// `onReadyToCommit` 에서 실제 상태 반영(CompanionStore.applyTradeCommit)까지 마친 뒤 호출한다.
    func confirmLocalCommit() {
        do {
            try transport.send(.commitAck(nonce: sessionID))
            localCommitAckSent = true
            checkCompleted()
        } catch {
            // 전송 실패 시 completed 로 진행하지 않는다 — UI 는 커밋 중 상태로 남아 재연결/재시도 여지를 준다.
        }
    }

    func disconnect() {
        transport.disconnect()
    }

    private func handle(_ message: TradeMessage) {
        switch message {
        case .hello(let nickname, let code):
            peerIdentity = (nickname, code)
            onPeerIdentified?((nickname, code))
        case .offer(let item):
            theirOffer = item.sanitized()
            invalidateAcceptsBeforeCommit()
            notifyIfBothOffersReady()
        case .offerWithdrawn:
            theirOffer = nil
            invalidateAcceptsBeforeCommit()
            onOfferWithdrawn?()
        case .accept:
            theirAcceptReceived = true
            commitIfBothAccepted()
        case .reject(let reason):
            onRejected?(reason)
        case .commit:
            break   // 정보성 신호 — 양쪽이 Accept 교환 시점에 이미 독립적으로 commitIfBothAccepted 에 도달한다.
        case .commitAck:
            remoteCommitAckReceived = true
            checkCompleted()
        }
    }

    /// Accept 는 "지금 이 오퍼 쌍"에 대한 동의다 — 커밋 전이라면 어느 쪽 오퍼가 바뀌어도 두 Accept
    /// 플래그(내가 보낸 것, 상대에게서 받은 것) 모두 그 동의의 근거를 잃으므로 함께 지운다.
    private func invalidateAcceptsBeforeCommit() {
        guard !committed else { return }
        myAcceptSent = false
        theirAcceptReceived = false
    }

    private func notifyIfBothOffersReady() {
        guard let myOffer, let theirOffer else { return }
        onOffersReady?(myOffer, theirOffer)
    }

    private func commitIfBothAccepted() {
        guard myOffer != nil, myAcceptSent, theirAcceptReceived, !committed, let theirOffer else { return }
        committed = true
        try? transport.send(.commit(nonce: sessionID))
        onReadyToCommit?(theirOffer)
    }

    private func checkCompleted() {
        guard localCommitAckSent, remoteCommitAckReceived, !completed else { return }
        completed = true
        onCompleted?()
    }
}
