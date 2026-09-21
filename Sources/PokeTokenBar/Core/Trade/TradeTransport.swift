import Foundation

/// 발견된 상대 후보 — 탐색 목록에 표시할 최소 정보.
struct TradePeer: Identifiable, Equatable, Sendable {
    let id: String
    let nickname: String
    let code: String
}

enum TradeTransportError: Error, Equatable {
    case notConnected
    case sendFailed
    case discoveryTimedOut
}

/// 교환 세션의 전송 계층 — 어떤 방식(Multipeer 자동 탐색/수동 TCP)으로 연결됐는지 `TradeSession` 은
/// 몰라도 된다. 콜백은 임의 스레드에서 호출될 수 있다 — MainActor 소비자(TradeSession)가 직접 hop 한다
/// (NetworkReachabilityMonitor.onReconnected 와 동일 관례).
protocol TradeTransport: AnyObject {
    var onPeerFound: (@Sendable (TradePeer) -> Void)? { get set }
    var onPeerLost: (@Sendable (String) -> Void)? { get set }
    var onConnected: (@Sendable () -> Void)? { get set }
    var onDisconnected: (@Sendable () -> Void)? { get set }
    var onMessageReceived: (@Sendable (TradeMessage) -> Void)? { get set }

    func startDiscovery()
    func stopDiscovery()
    func connect(to peer: TradePeer) throws
    func send(_ message: TradeMessage) throws
    func disconnect()
}
