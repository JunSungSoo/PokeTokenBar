import Foundation

/// 교환 프로토콜 상태 기계 — 전송 계층과 무관하게 Offer→Accept→Commit 순서를 관리한다.
/// 실제 상태 반영(백업+적용)은 이 클래스가 하지 않는다 — `onReadyToCommit` 콜백을 받은 쪽
/// (CompanionStore 소비자)이 적용을 마친 뒤 `confirmLocalCommit()` 을 호출해야 세션이 완료된다.
@MainActor
final class TradeSession {
    private let transport: any TradeTransport
    private let sessionID = UUID().uuidString

    private(set) var peerIdentity: (nickname: String, code: String)?
    private(set) var myOffer: TradeItem?
    private(set) var theirOffer: TradeItem?
    private var myAcceptSent = false
    private var theirAcceptReceived = false
    private var committed = false
    private var localCommitAckSent = false
    private var remoteCommitAckReceived = false

    var onPeerIdentified: (((nickname: String, code: String)) -> Void)?
    var onOffersReady: ((_ mine: TradeItem, _ theirs: TradeItem) -> Void)?
    var onReadyToCommit: ((_ received: TradeItem) -> Void)?
    var onRejected: ((String) -> Void)?
    var onDisconnected: (() -> Void)?
    var onCompleted: (() -> Void)?

    init(transport: any TradeTransport) {
        self.transport = transport
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
        try? transport.send(.hello(nickname: TradeIdentity.nickname(), code: TradeIdentity.code()))
    }

    func proposeOffer(_ item: TradeItem) {
        myOffer = item
        try? transport.send(.offer(item))
        notifyIfBothOffersReady()
    }

    func withdrawOffer() {
        myOffer = nil
        try? transport.send(.offerWithdrawn)
    }

    func accept() {
        guard !myAcceptSent else { return }
        myAcceptSent = true
        try? transport.send(.accept)
        commitIfBothAccepted()
    }

    func reject(reason: String) {
        try? transport.send(.reject(reason: reason))
        transport.disconnect()
    }

    /// `onReadyToCommit` 에서 실제 상태 반영(CompanionStore.applyTradeCommit)까지 마친 뒤 호출한다.
    func confirmLocalCommit() {
        localCommitAckSent = true
        try? transport.send(.commitAck(nonce: sessionID))
        checkCompleted()
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
            notifyIfBothOffersReady()
        case .offerWithdrawn:
            theirOffer = nil
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

    private func notifyIfBothOffersReady() {
        guard let myOffer, let theirOffer else { return }
        onOffersReady?(myOffer, theirOffer)
    }

    private func commitIfBothAccepted() {
        guard myAcceptSent, theirAcceptReceived, !committed, let theirOffer else { return }
        committed = true
        try? transport.send(.commit(nonce: sessionID))
        onReadyToCommit?(theirOffer)
    }

    private func checkCompleted() {
        guard localCommitAckSent, remoteCommitAckReceived else { return }
        onCompleted?()
    }
}
